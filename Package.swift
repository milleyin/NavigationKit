// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NavigationKit",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "NavigationKit",
            targets: ["NavigationKit"]  // 这是最终的库目标
        ),
    ],
    dependencies: [],
    targets: [
        // 这里定义了 NavigationKit 模块，包括它的子模块
        .target(
            name: "NavigationKit",
            dependencies: ["CoreLocationKit", "AppleMapKit"],  // 引入子模块
            path: "Sources/NavigationKit"
        ),
        
        // 子模块 CoreLocationKit
        .target(
            name: "CoreLocationKit",
            dependencies: [],
            path: "Sources/NavigationKit/CoreLocationKit"
        ),
        
        // 子模块 MapKit
        .target(
            name: "MapKit",
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
