// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "T2PCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "T2PCore", targets: ["T2PCore"])],
    targets: [
        .target(name: "T2PCore", resources: [.copy("Resources/rules.js")]),
        .testTarget(name: "T2PCoreTests", dependencies: ["T2PCore"], resources: [.copy("Fixtures")]),
    ]
)
