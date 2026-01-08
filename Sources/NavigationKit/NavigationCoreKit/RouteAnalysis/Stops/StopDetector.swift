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
    public init(speedThreshold: Double, minimumDuration: TimeInterval) {
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
    public func process(_ point: GeoPoint, last: GeoPoint?, stops: [TrackEngine.StopEvent]) -> [TrackEngine.StopEvent] {

        let speed = max(0, point.speed ?? 0)

        // 低速 → 可能停车
        if speed <= speedThreshold {
            if pendingStart == nil {
                pendingStart = point
            }
            return stops
        }

        // 高速 → 结束停车
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

// MARK: - Configuration Extension

extension StopDetector {
    
    /**
     `StopDetector` 的配置参数结构体。
     
     用于定义“什么是停车”的判别标准。
     核心逻辑是基于 **速度** 和 **持续时间** 的双重阈值过滤。
     */
    public struct Config: Sendable, Equatable {
        
        /// 停车判定的速度阈值（米/秒）。
        ///
        /// 当瞬时速度低于此值时，状态机进入“可能停车”状态。
        /// - Default: `0.277...` (即 1 km/h)
        /// - Note: 建议设置一个很小但非零的值，以容忍 GPS 在静止时的微小漂移。
        public var speedThreshold: Double = 0.277_777_777_8 // 1 km/h
        
        /// 判定为有效停车的最小持续时间（秒）。
        ///
        /// 只有当低速状态持续时间超过此值时，才会生成一个 `StopEvent`。
        /// - Default: `15.0` 秒
        /// - Purpose: 用于过滤掉短暂的交通停滞（如等红绿灯、避让行人），只记录有意义的驻留（如休息、补给）。
        public var minDuration: TimeInterval = 15
        
        /// 使用默认值初始化配置。
        public init() {}
    }
    
    /**
     使用配置对象初始化 `StopDetector`（便利构造器）。
     
     - Parameter config: 包含停车判定策略的配置对象。
     */
    public convenience init(config: Config) {
        self.init(
            speedThreshold: config.speedThreshold,
            minimumDuration: config.minDuration
        )
    }
}
