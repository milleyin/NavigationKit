//
//  NavigationCoreKit.swift
//  NavigationKit
//
//  Created by mille on 2025/12/5.
//

import Foundation

/**
 `NavigationCoreKit` 提供导航相关的核心算法能力，包括海拔、坡度、距离、路线分析等。
 
 - Important: 本模块不直接依赖 UI 层，仅关注“数据计算与算法逻辑”。
 - Note: 建议在应用启动时根据需要配置 `isDebugLoggingEnabled`，便于排查问题。
 */
public enum NavigationCoreKit {
    
    /// NavigationCoreKit 当前版本号
    public static let version: String = "1.0.0(20250224)"
    
    /// 是否开启调试日志输出
    public static var isDebugLoggingEnabled: Bool = false
    
    /**
     内部调试日志输出方法。
     
     - parameter message: 日志内容，使用自动闭包以避免不必要的字符串拼接开销。
     */
    static func debugLog(_ message: @autoclosure () -> String) {
        guard isDebugLoggingEnabled else { return }
        print("[NavigationCoreKit] \(message())")
    }
}
