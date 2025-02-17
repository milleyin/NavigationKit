// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NavigationKit",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(
            name: "NavigationKit",
            targets: ["NavigationKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NavigationKit",
            dependencies: ["CoreLocationKit", "AppleMapKit"],
            path: "Sources/NavigationKit",
            sources: ["NavigationKit.swift"]
        ),
        
        // CoreLocationKit 模块
        .target(
            name: "CoreLocationKit",
            dependencies: [],
            path: "Sources/NavigationKit/CoreLocationKit"
        ),
        
        // AppleMapKit 模块
        .target(
            name: "AppleMapKit",
            dependencies: [],
            path: "Sources/NavigationKit/AppleMapKit"
        ),
        
        // 测试目标
        .testTarget(
            name: "NavigationKitTests",
            dependencies: ["NavigationKit"],
            path: "Tests/NavigationKitTests"
        )
    ]
)
