// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlertClashIP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AlertClashIPApp", targets: ["AlertClashIPApp"])
    ],
    targets: [
        .executableTarget(
            name: "AlertClashIPApp"
        ),
        .testTarget(
            name: "AlertClashIPAppTests",
            dependencies: ["AlertClashIPApp"]
        )
    ]
)
