// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SetuIOS",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SetuIOSCore", targets: ["SetuIOSCore"]),
        .executable(name: "SetuIOSApp", targets: ["SetuIOSApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .binaryTarget(name: "SetuPixivTransport", path: "Native/PixivTransport/build/SetuPixivTransport.xcframework"),
        .target(
            name: "SetuIOSCore",
            dependencies: ["SetuPixivTransport", "ZIPFoundation"],
            path: "Sources/SetuIOSCore"
        ),
        .executableTarget(
            name: "SetuIOSApp",
            dependencies: ["SetuIOSCore"],
            path: "Sources/SetuIOSApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SetuIOSAppTests",
            dependencies: ["SetuIOSCore", "SetuIOSApp"],
            path: "Tests/SetuIOSAppTests"
        ),
    ]
)
