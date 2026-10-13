// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuiteOfAgents",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SuiteOfAgents", targets: ["SuiteOfAgents"]),
        .library(name: "SuiteCore", targets: ["SuiteCore"]),
    ],
    targets: [
        .target(name: "SuiteCore"),
        .executableTarget(name: "SuiteOfAgents", dependencies: ["SuiteCore"]),
        .testTarget(name: "SuiteCoreTests", dependencies: ["SuiteCore"]),
    ]
)
