// swift-tools-version: 5.9
// 这个文件用于定义 `NavigationKit` 的 Swift Package 结构
// `swift-tools-version` 指定了最低支持的 Swift 版本

import PackageDescription  // 引入 Swift Package 描述框架

let package = Package(
    // 📌 1. **包的名称**
    name: "NavigationKit",  // 这个 Swift Package 的名称
    
    // 📌 2. **支持的平台**
    platforms: [
        .iOS(.v13),   // 最低支持 iOS 13（SwiftUI、Combine 可用）
        .macOS(.v11)  // 最低支持 macOS 11（支持 SwiftUI + CoreLocation）
    ],
    
    // 📌 3. **定义产物（可被外部使用的库）**
    products: [
        .library(
            name: "NavigationKit",  // 这个库的名称
            targets: ["NavigationKit"]  // 这个库依赖的目标（`NavigationKit` 目标）
        ),
    ],
    
    // 📌 4. **依赖项（当前没有额外依赖）**
    dependencies: [],
    
    // 📌 5. **目标（Targets）**
    // `targets` 定义了当前 Package 的所有模块
    targets: [
        // ✅ **NavigationKit 目标**
        .target(
            name: "NavigationKit",  // 主要 SDK 入口
            dependencies: [
                "CoreLocationKit",  // 依赖 CoreLocationKit（定位功能）
                "AppleMapKit"       // 依赖 AppleMapKit（地图功能）
            ],
            path: "Sources/NavigationKit",  // 代码路径
            sources: ["NavigationKit.swift"]  // 指定 NavigationKit.swift 作为主入口
        ),
        
        // ✅ **CoreLocationKit 目标（负责定位功能）**
        .target(
            name: "CoreLocationKit",  // 负责 CoreLocation 相关功能
            dependencies: [],
            path: "Sources/NavigationKit/CoreLocationKit"
        ),
        
        // ✅ **AppleMapKit 目标（负责地图功能）**
        .target(
            name: "AppleMapKit",  // 负责地图 `MKMapView` 相关功能
            dependencies: [],
            path: "Sources/NavigationKit/AppleMapKit"
        ),
        
        // ✅ **测试目标**
        .testTarget(
            name: "NavigationKitTests",  // 测试 `NavigationKit`
            dependencies: ["NavigationKit"],  // 依赖 `NavigationKit`
            path: "Tests/NavigationKitTests"
        )
    ]
)
