import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: seticon <icon.icns> <file>\n", stderr)
    exit(1)
}

let iconPath = args[1]
let targetPath = args[2]

guard let image = NSImage(contentsOfFile: iconPath) else {
    fputs("Error: Cannot load icon from \(iconPath)\n", stderr)
    exit(2)
}

guard NSWorkspace.shared.setIcon(image, forFile: targetPath) else {
    fputs("Error: Failed to set icon on \(targetPath)\n", stderr)
    exit(3)
}
