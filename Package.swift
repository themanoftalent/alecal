// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AleCal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AleCal", targets: ["AleCal"])
    ],
    targets: [
        .executableTarget(
            name: "AleCal",
            path: "Sources"
        )
    ]
)
