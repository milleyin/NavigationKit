//
//  File.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//


import Foundation

/**
 `StopDetector` 用于从轨迹点中识别“停车事件”。

 判定规则（首版）：
 - 当速度 <= `stopSpeedThreshold` 时，进入“可能停车”状态
 - 当速度 >  `stopSpeedThreshold` 时，结束停车
 - 只有持续时间 >= `stopMinimumDuration` 才会被认定为有效停车

 - Important:
   本模块只识别 **时间区间**，不负责业务语义（如“休息点 / 红绿灯 / 拍照”）。
 */
public final class StopDetector {

    // MARK: - Dependencies

    private let speedThreshold: Double
    private let minimumDuration: TimeInterval

    // MARK: - Internal State

    /// 当前停车开始点（若不在停车中则为 nil）
    private var pendingStart: GeoPoint?

    // MARK: - Init

    /**
     初始化 StopDetector。

     - Parameters:
       - speedThreshold: 停车速度阈值（m/s）
       - minimumDuration: 最小停车持续时间（秒）
     */
    public init(
        speedThreshold: Double,
        minimumDuration: TimeInterval
    ) {
        self.speedThreshold = speedThreshold
        self.minimumDuration = minimumDuration
    }

    // MARK: - Public API

    /**
     处理一个轨迹点，更新停车状态。

     - Parameters:
       - point: 当前轨迹点
       - last: 上一个轨迹点
       - stops: 当前已识别的停车事件
     - Returns: 更新后的停车事件数组
     */
    public func process(
        _ point: GeoPoint,
        last: GeoPoint?,
        stops: [TrackEngine.StopEvent]
    ) -> [TrackEngine.StopEvent] {

        let speed = max(0, point.speed ?? 0)

        // 1️⃣ 低速 → 可能停车
        if speed <= speedThreshold {
            if pendingStart == nil {
                pendingStart = point
            }
            return stops
        }

        // 2️⃣ 高速 → 结束停车
        if let start = pendingStart {
            let end = point
            let duration = end.timestamp.timeIntervalSince(start.timestamp)

            pendingStart = nil

            if duration >= minimumDuration {
                let event = TrackEngine.StopEvent(start: start, end: end)
                return stops + [event]
            }
        }

        return stops
    }

    /**
     在轨迹结束时调用，用于收尾未关闭的停车事件。
     */
    public func finish(stops: [TrackEngine.StopEvent], lastPoint: GeoPoint?) -> [TrackEngine.StopEvent] {
        guard let start = pendingStart, let end = lastPoint else {
            return stops
        }

        pendingStart = nil

        let duration = end.timestamp.timeIntervalSince(start.timestamp)
        guard duration >= minimumDuration else {
            return stops
        }

        return stops + [TrackEngine.StopEvent(start: start, end: end)]
    }

    // MARK: - Reset

    /**
     重置内部状态。
     */
    public func reset() {
        pendingStart = nil
    }
}
