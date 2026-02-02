//
//  TrackAnalyzer.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `TrackAnalyzer` 用于对轨迹点序列进行**整体统计分析**。

 - Important:
   该类 **不持有任何状态**，所有统计结果都通过 `RouteSummary` 返回。
   每次 `process` 调用都基于「上一次 summary + 新点」生成新的 summary。

 - Design:
   GeoPoint → TrackAnalyzer → RouteSummary
 */
public final class TrackAnalyzer {
    
    /// 定义 Config 结构体
    public struct Config: Sendable, Equatable {
        /// 判定移动的最小速度阈值（m/s），低于此值计入静止时间
        public var movingSpeedThreshold: Double = 0.5
        
        public init() {}
    }

    /// 判定“有效轨迹”的最小点数
    private let minimumValidPointCount: Int = 2
    
    /// 判定移动的最小速度阈值（m/s），低于此值计入静止时间
    private let movingSpeedThreshold: Double
    
    /// 新增：便利构造器，接收 Config
    public convenience init(config: Config) {
        self.init(movingSpeedThreshold: config.movingSpeedThreshold)
    }

    public init(movingSpeedThreshold: Double = 0.5) {
            self.movingSpeedThreshold = movingSpeedThreshold
        }

    /// 重置接口（预留，当前无内部状态）
    public func reset() {}

    /**
     处理一个新的轨迹点，返回更新后的 `RouteSummary`。
     
     - Parameters:
       - current: 当前采样点
       - last: 上一个已接受的采样点（若无则为 `nil`）
       - summary: 上一次的轨迹统计结果
     
     - Returns: 新的 `RouteSummary`
     */
    public func process(_ current: GeoPoint, last: GeoPoint?, summary: RouteSummary) -> RouteSummary {

        // 点数
        let newPointCount = summary.pointCount + 1

        // 起点 / 终点
        let startPoint = summary.startPoint ?? current
        let endPoint = current

        // 时间统计
        var totalTime = summary.totalTime
        var movingTime = summary.movingTime
        var stoppedTime = summary.stoppedTime
        
        // 距离统计
        var totalDistance = summary.totalDistance
        
        // 速度统计
        var maxSpeed = summary.maxSpeed

        if let last = last {
            let deltaTime = current.timestamp.timeIntervalSince(last.timestamp)
            if deltaTime > 0 {
                totalTime += deltaTime

                // 1) 先计算距离（可能需要用于速度推断和距离累加）
                let distance = GeoDistance.distance(from: last, to: current)
                
                // 2) 确定速度：优先使用 GPS 速度，否则基于位移推断
                let speed: Double
                if let reportedSpeed = current.speed, reportedSpeed >= 0 {
                    speed = reportedSpeed
                } else {
                    // 后台模式常见：speed 为 nil 或 -1，基于位移推断
                    // 确保距离有效，避免 NaN/Inf 传播
                    speed = (distance.isFinite && distance >= 0) ? (distance / deltaTime) : 0
                }

                // 3) 更新最大速度
                maxSpeed = max(maxSpeed, speed)
                
                // 4) 判定移动/静止
                if speed > movingSpeedThreshold {
                    movingTime += deltaTime
                    
                    // 只有移动时才累加距离，过滤静止时的 GPS 漂移
                    if distance.isFinite && distance > 0 {
                        totalDistance += distance
                    }
                } else {
                    stoppedTime += deltaTime
                }
            }
        }

        let averageSpeed: Double = {
            guard movingTime > 0 else { return 0 }
            return totalDistance / movingTime
        }()

        // 有效性判断
        let isValid = newPointCount >= minimumValidPointCount && totalDistance > 0

        return RouteSummary(
            isValid: isValid,
            pointCount: newPointCount,
            segmentCount: summary.segmentCount,
            totalDistance: totalDistance,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            totalTime: totalTime,
            movingTime: movingTime,
            stoppedTime: stoppedTime,
            totalElevationGain: summary.totalElevationGain,
            totalElevationLoss: summary.totalElevationLoss,
            maxAltitude: summary.maxAltitude,
            minAltitude: summary.minAltitude,
            maxGradient: summary.maxGradient,
            minGradient: summary.minGradient,
            startPoint: startPoint,
            endPoint: endPoint,
            metadata: summary.metadata
        )
    }
}
