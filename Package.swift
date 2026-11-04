// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickPlan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlueprintCore", targets: ["BlueprintCore"]),
        .executable(name: "QuickPlan", targets: ["QuickPlan"])
    ],
    targets: [
        .target(name: "BlueprintCore"),
        .executableTarget(name: "QuickPlan", dependencies: ["BlueprintCore"]),
        .testTarget(name: "BlueprintCoreTests", dependencies: ["BlueprintCore"]),
        .testTarget(name: "QuickPlanTests", dependencies: ["QuickPlan", "BlueprintCore"])
    ]
)
