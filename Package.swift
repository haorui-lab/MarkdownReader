// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownReader",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "MarkdownReader",
            targets: ["MarkdownReader"]
        ),
        .executable(
            name: "MarkdownReaderQL",
            targets: ["MarkdownReaderQL"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-markdown.git",
            from: "0.5.0"
        )
    ],
    targets: [
        // Shared library — rendering logic, theme, localization
        .target(
            name: "MarkdownReaderKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MarkdownReaderKit"
        ),
        // Main application
        .executableTarget(
            name: "MarkdownReader",
            dependencies: [
                "MarkdownReaderKit",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MarkdownReader",
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        ),
        // Quick Look Preview Extension
        .executableTarget(
            name: "MarkdownReaderQL",
            dependencies: [
                "MarkdownReaderKit"
            ],
            path: "Sources/MarkdownReaderQL"
        )
    ]
)
