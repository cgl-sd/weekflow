// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Weekflow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Weekflow", targets: ["Weekflow"])],
    targets: [
        .executableTarget(name: "Weekflow"),
        .testTarget(name: "WeekflowTests", dependencies: ["Weekflow"])
    ]
)
