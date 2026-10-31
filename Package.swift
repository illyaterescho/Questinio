// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LocalCopilot",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LocalCopilotCore", targets: ["LocalCopilotCore"]), .executable(name: "LocalCopilotProbe", targets: ["LocalCopilotProbe"])],
    dependencies: [.package(path: "Vendor/argmax-oss-swift")],
    targets: [
        .target(name: "LocalCopilotCore", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "LocalCopilotProbe", dependencies: ["LocalCopilotCore"]),
        .testTarget(name: "LocalCopilotCoreTests", dependencies: ["LocalCopilotCore"])
    ]
)
