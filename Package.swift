// swift-tools-version:5.9
// AstroCore: ephemeris, frames, body catalogue and simulation clock. No UIKit/SceneKit, so the
// same module can back a later visionOS target. The iOS app itself is generated from project.yml.
import PackageDescription

let package = Package(
    name: "AstroCore",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [.library(name: "AstroCore", targets: ["AstroCore"])],
    targets: [
        .target(name: "AstroCore", path: "Sources/AstroCore"),
        .testTarget(name: "AstroCoreTests", dependencies: ["AstroCore"], path: "Tests/AstroCoreTests"),
    ]
)
