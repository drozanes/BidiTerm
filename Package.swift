// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BidiTerm",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BidiTerm", targets: ["BidiTerm"])
    ],
    targets: [
        .executableTarget(
            name: "BidiTerm",
            path: "Sources/BidiTerm"
        )
    ]
)
