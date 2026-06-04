import AppKit
import CoreGraphics

// Usage: swift generate-icons.swift <source.png> <output_dir>
let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: swift generate-icons.swift <source.png> <output_dir>\n", stderr)
    exit(1)
}

let sourcePath = args[1]
let outputDir = args[2]

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    fputs("Error: Cannot load image from \(sourcePath)\n", stderr)
    exit(2)
}

// Convert NSImage to CGImage
guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Error: Cannot create CGImage\n", stderr)
    exit(3)
}

let width = cgImage.width
let height = cgImage.height
print("Source image: \(width)x\(height)")

// Step 1: Find the bounding box of non-white pixels
// White = RGB all > 240 (with some tolerance for near-white)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let pixelsWide = width
let pixelsHigh = height

guard let context = CGContext(
    data: nil,
    width: pixelsWide,
    height: pixelsHigh,
    bitsPerComponent: 8,
    bytesPerRow: pixelsWide * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Error: Cannot create bitmap context\n", stderr)
    exit(4)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))

guard let data = context.data else {
    fputs("Error: Cannot get bitmap data\n", stderr)
    exit(5)
}

let buffer = data.bindMemory(to: UInt8.self, capacity: pixelsWide * pixelsHigh * 4)

var minX = pixelsWide
var minY = pixelsHigh
var maxX = 0
var maxY = 0

let whiteThreshold: UInt8 = 245 // Pixels with RGB all above this are considered "white"

for y in 0..<pixelsHigh {
    for x in 0..<pixelsWide {
        let offset = (y * pixelsWide + x) * 4
        let r = buffer[offset]
        let g = buffer[offset + 1]
        let b = buffer[offset + 2]
        let a = buffer[offset + 3]

        // If pixel is not white (or is transparent, skip transparent)
        let isWhite = r >= whiteThreshold && g >= whiteThreshold && b >= whiteThreshold
        let isVisible = a > 10 // not fully transparent

        if isVisible && !isWhite {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
}

print("Non-white bounding box: (\(minX), \(minY)) - (\(maxX), \(maxY))")

if minX >= maxX || minY >= maxY {
    fputs("Error: Could not find non-white content in image\n", stderr)
    exit(6)
}

// Add a minimal margin (1% of content size) — macOS applies its own squircle mask,
// so we want the subject to fill as much of the canvas as possible.
let contentWidth = maxX - minX + 1
let contentHeight = maxY - minY + 1
let marginX = Int(Double(contentWidth) * 0.01)
let marginY = Int(Double(contentHeight) * 0.01)

minX = max(0, minX - marginX)
minY = max(0, minY - marginY)
maxX = min(pixelsWide - 1, maxX + marginX)
maxY = min(pixelsHigh - 1, maxY + marginY)

print("With margin: (\(minX), \(minY)) - (\(maxX), \(maxY))")

// Step 2: Crop the image to the bounding box
let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let croppedImage = cgImage.cropping(to: cropRect) else {
    fputs("Error: Cannot crop image\n", stderr)
    exit(7)
}

// Step 3: Use the cropped image directly — keep white background.
// macOS fills transparent areas with gray, which looks bad.
// Keeping the white background gives a clean white icon that macOS
// clips to its squircle shape automatically.
let finalImage = croppedImage

// Step 4: Generate all required icon sizes
let iconSizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// Create output directory
let fileManager = FileManager.default
if !fileManager.fileExists(atPath: outputDir) {
    try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
}

for icon in iconSizes {
    let targetSize = icon.size

    // Create a new context at target size with opaque white background
    // (no transparency — avoids macOS gray background on transparent areas)
    guard let resizeContext = CGContext(
        data: nil,
        width: targetSize,
        height: targetSize,
        bitsPerComponent: 8,
        bytesPerRow: targetSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fputs("Error: Cannot create resize context for \(icon.name)\n", stderr)
        continue
    }

    // Fill with white background first
    resizeContext.setFillColor(CGColor.white)
    resizeContext.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

    // Draw the final image scaled to fill the entire canvas.
    // No padding — macOS applies its own squircle (rounded rectangle) mask automatically.
    resizeContext.interpolationQuality = .high
    resizeContext.draw(finalImage, in: CGRect(x: 0, y: 0, width: Double(targetSize), height: Double(targetSize)))

    guard let resizedImage = resizeContext.makeImage() else {
        fputs("Error: Cannot create resized image for \(icon.name)\n", stderr)
        continue
    }

    // Convert to NSImage and save as PNG
    let nsImage = NSImage(cgImage: resizedImage, size: NSSize(width: targetSize, height: targetSize))
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fputs("Error: Cannot create PNG data for \(icon.name)\n", stderr)
        continue
    }

    let outputPath = "\(outputDir)/\(icon.name).png"
    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("✅ Generated \(icon.name).png (\(targetSize)x\(targetSize))")
    } catch {
        fputs("Error: Cannot write \(outputPath): \(error)\n", stderr)
    }
}

print("\n🎉 All icons generated in \(outputDir)")
