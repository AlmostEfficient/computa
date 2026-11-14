// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Computa", platforms: [.macOS(.v15)], products: [.executable(name: "Computa", targets: ["Computa"])], targets: [
    .target(name: "CaptureRing"),
    .executableTarget(name: "Computa", dependencies: ["CaptureRing"]),
    .testTarget(name: "ComputaTests", dependencies: ["Computa", "CaptureRing"])
])
