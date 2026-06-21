// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ditto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Ditto", targets: ["Ditto"])
    ],
    targets: [
        .executableTarget(
            name: "Ditto",
            dependencies: []
        )
    ]
)
