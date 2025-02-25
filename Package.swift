// swift-tools-version: 5.9
// 这个文件用于定义 `NavigationKit` 的 Swift Package 结构
// `swift-tools-version` 指定了最低支持的 Swift 版本

import PackageDescription

let package = Package(
    name: "NavigationKit",  // 这个 Swift Package 的名称
    
    platforms: [
        .iOS(.v13),   // 最低支持 iOS 13（SwiftUI、Combine 可用）
        .macOS(.v11)  // 最低支持 macOS 11（支持 SwiftUI + CoreLocation）
    ],
    
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
            dependencies: [
                "CoreLocationKit",  // 依赖 CoreLocationKit（定位功能）
                "AppleMapKit"       // 依赖 AppleMapKit（地图功能）
            ],
            path: "Sources/NavigationKit",
            sources: ["NavigationKit.swift"]  // 指定 NavigationKit.swift 作为主入口
        ),
        
        .target(
            name: "CoreLocationKit",  // 负责 CoreLocation 相关功能
            dependencies: [],
            path: "Sources/NavigationKit/CoreLocationKit"
        ),
        
        .target(
            name: "AppleMapKit",  // 负责地图 `MKMapView` 相关功能
            dependencies: [],
            path: "Sources/NavigationKit/AppleMapKit"
        ),
        
        .testTarget(
            name: "NavigationKitTests",  // 测试 `NavigationKit`
            dependencies: ["NavigationKit"],  // 依赖 `NavigationKit`
            path: "Tests/NavigationKitTests"
        )
    ]
)
