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
    public static let version: String = "1.1.0(20250232)"
    
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
    
    public enum RouteAnalysis {
        /**
         快速轨迹分析：输入轨迹点，返回统计摘要（RouteSummary）。
         - Parameters:
           - points: 轨迹点数组，建议已按时间正序排列
           - config: 分析配置，默认 cycling 方案
         - Returns: RouteSummary 结果
         ```swift
         Example：
         let summary = NavigationCoreKit.RouteAnalysis.analyze(points: points)
         print(summary.averageSpeed)
         ```
         */
        public static func analyze(points: [GeoPoint], config: TrackEngine.Config = .cycling) -> RouteSummary {
            let engine = TrackEngine(config: config)
            engine.process(points)
            engine.finish()
            return engine.summary
        }

        /**
         详细轨迹分析：输入轨迹点，返回 summary、分段、停车等全部结果。
         - Parameters:
           - points: 轨迹点数组
           - config: 分析配置
         - Returns: AnalysisResult（包含 summary, segments, stops）
         
         ```swift
         Example：
         let detail = NavigationCoreKit.RouteAnalysis.analyzeDetail(points: points)
         print(detail.summary.totalTime)
         print(detail.segments.count)
         ```
         */
        public static func analyzeDetail(points: [GeoPoint], config: TrackEngine.Config = .cycling) -> AnalysisResult {
            let engine = TrackEngine(config: config)
            engine.process(points)
            engine.finish()
            return AnalysisResult(summary: engine.summary, segments: engine.segments, stops: engine.stops)
        }
    }
}
/**
 RouteAnalysis 全量结果。
 */
public struct AnalysisResult: Sendable {
    public let summary: RouteSummary
    public let segments: [RouteSegment]
    public let stops: [TrackEngine.StopEvent]
    public init(summary: RouteSummary, segments: [RouteSegment], stops: [TrackEngine.StopEvent]) {
        self.summary = summary
        self.segments = segments
        self.stops = stops
    }
}

