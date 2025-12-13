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

    /// 判定“有效轨迹”的最小点数
    private let minimumValidPointCount: Int = 2

    public init() {}

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
    public func process(
        _ current: GeoPoint,
        last: GeoPoint?,
        summary: RouteSummary
    ) -> RouteSummary {

        // MARK: - 点数
        let newPointCount = summary.pointCount + 1

        // MARK: - 起点 / 终点
        let startPoint = summary.startPoint ?? current
        let endPoint = current

        // MARK: - 时间统计
        var totalTime = summary.totalTime
        var movingTime = summary.movingTime
        var stoppedTime = summary.stoppedTime

        if let last = last {
            let deltaTime = current.timestamp.timeIntervalSince(last.timestamp)
            if deltaTime > 0 {
                totalTime += deltaTime

                let speed = max(current.speed ?? 0, 0)
                if speed > 0.5 {   // 0.5 m/s 作为“移动阈值”（≈ 1.8 km/h）
                    movingTime += deltaTime
                } else {
                    stoppedTime += deltaTime
                }
            }
        }

        // MARK: - 距离统计
        var totalDistance = summary.totalDistance

        if let last = last {
            let distance = GeoDistance.distance(from: last, to: current)
            if distance.isFinite && distance > 0 {
                totalDistance += distance
            }
        }

        // MARK: - 速度统计
        let currentSpeed = max(current.speed ?? 0, 0)
        let maxSpeed = max(summary.maxSpeed, currentSpeed)

        let averageSpeed: Double = {
            guard movingTime > 0 else { return 0 }
            return totalDistance / movingTime
        }()

        // MARK: - 有效性判断
        let isValid = newPointCount >= minimumValidPointCount && totalDistance > 0

        return RouteSummary(
            isValid: isValid,
            pointCount: newPointCount,
            segmentCount: summary.segmentCount, // 后续由 SegmentAnalyzer 填
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
