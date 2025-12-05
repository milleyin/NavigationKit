// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NavigationKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "NavigationKit",
            targets: ["NavigationKit"]
        ),
    ],
    dependencies: [],
    targets: [

        // MARK: - API 层（暴露给外界）
        .target(
            name: "NavigationKit",
            dependencies: [
                "CoreLocationKit",
                "AppleMapKit",
                "NavigationCoreKit"
            ],
            path: "Sources/NavigationKit",
            sources: ["NavigationKit.swift"]
        ),

        // MARK: - 数据源层（原始传感器）
        .target(
            name: "CoreLocationKit",
            dependencies: [],
            path: "Sources/NavigationKit/CoreLocationKit"
        ),

        // MARK: - 地图层
        .target(
            name: "AppleMapKit",
            dependencies: [],
            path: "Sources/NavigationKit/AppleMapKit"
        ),

        // MARK: - 算法层（Elevation）
        .target(
            name: "NavigationCoreKit",
            dependencies: [],
            path: "Sources/NavigationKit/NavigationCoreKit"
        ),

        // MARK: - 测试
        .testTarget(
            name: "NavigationKitTests",
            dependencies: [
                "NavigationKit",
                "CoreLocationKit",
                "NavigationCoreKit"
            ],
            path: "Tests/NavigationKitTests"
        )
    ]
)
