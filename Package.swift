// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LocalCopilot",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LocalCopilotCore", targets: ["LocalCopilotCore"]), .executable(name: "LocalCopilotProbe", targets: ["LocalCopilotProbe"])],
    dependencies: [.package(path: "Vendor/argmax-oss-swift"), .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7")],
    targets: [
        .target(name: "LocalCopilotCore", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift"), .product(name: "FluidAudio", package: "FluidAudio")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "LocalCopilotProbe", dependencies: ["LocalCopilotCore"]),
        .testTarget(name: "LocalCopilotCoreTests", dependencies: ["LocalCopilotCore"])
    ]
)
