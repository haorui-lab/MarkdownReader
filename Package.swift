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
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-markdown.git",
            from: "0.5.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "MarkdownReader",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MarkdownReader",
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        )
    ]
)
