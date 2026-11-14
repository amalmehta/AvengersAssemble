// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AvengersAssemble",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AvengersAssemble", targets: ["AvengersAssemble"]),
        .library(name: "AvengersAssembleCore", targets: ["AvengersAssembleCore"]),
    ],
    targets: [
        .target(name: "AvengersAssembleCore"),
        .executableTarget(name: "AvengersAssemble", dependencies: ["AvengersAssembleCore"]),
        .testTarget(name: "AvengersAssembleCoreTests", dependencies: ["AvengersAssembleCore"]),
    ]
)
