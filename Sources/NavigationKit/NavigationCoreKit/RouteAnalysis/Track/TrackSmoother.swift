//
//  TrackSmoother.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `TrackSmoother` 负责对**已通过清洗的轨迹点**进行平滑处理。

 - Important:
   本模块 **不会丢弃任何点**，也不会改变时间顺序；
   仅对数值字段进行 **低通滤波 (Low-pass Filter)**，降低 GPS 抖动对后续分析的影响。

 - Design Principles:
   - 输入一个点，输出一个点（1-in-1-out）
   - 实现了指数加权移动平均 (EMA) 算法
   - 解决了航向角 (Course) 的 0-360 度环绕平滑问题
 */
public final class TrackSmoother {

    // MARK: - Config

    /**
     平滑配置。

     - Parameter alpha:
       平滑系数（0 ~ 1）。
       - `alpha = 1.0`: 不平滑（完全使用新值）
       - `alpha = 0.1`: 强平滑（新值权重低，响应慢，轨迹非常圆滑）
       - 推荐值: 0.1 ~ 0.3
     */
    public struct Config: Sendable, Equatable {

        public var alpha: Double

        public init(alpha: Double = 0.2) {
            self.alpha = min(max(alpha, 0.0), 1.0)
        }
    }

    // MARK: - Properties

    private let config: Config

    // MARK: - Init

    public init(config: Config) {
        self.config = config
    }

    // MARK: - Lifecycle

    /**
     重置内部状态。

     - Note:
       当前版本为**无内部缓存实现**（依赖外部传入 last 点），
       该方法为未来扩展（如引入 Kalman 滤波或内部 Buffer）预留。
     */
    public func reset() {
        // v1 无状态，无需处理
    }

    // MARK: - Processing

    /**
     对单个轨迹点进行平滑处理。

     - Parameters:
       - point: 当前输入点（已通过 TrackCleaner）
       - last: 上一个“已接受”且“已平滑”的轨迹点

     - Returns:
       平滑后的 `GeoPoint`
     */
    public func process(_ point: GeoPoint, last: GeoPoint?) -> GeoPoint {

        // 如果没有上一个点，或者配置为不平滑 (alpha >= 1)，直接返回原点
        guard let last = last, config.alpha < 1.0 else {
            return point
        }

        let a = config.alpha

        // 1. 线性平滑：适用于经纬度、海拔、速度
        // 公式：Previous + alpha * (Current - Previous)
        func smoothLinear(_ current: Double, _ previous: Double) -> Double {
            return previous + a * (current - previous)
        }
        
        // 2. 角度平滑：适用于航向角 (0~360)
        // 解决 359° -> 1° 平滑成 180° 的错误，应平滑为 0° 附近
        func smoothAngle(_ current: Double, _ previous: Double) -> Double {
            var diff = current - previous
            // 将差值限制在 -180 ~ 180 之间，寻找最短旋转方向
            while diff < -180 { diff += 360 }
            while diff > 180  { diff -= 360 }
            
            let result = previous + a * diff
            
            // 归一化结果到 0 ~ 360
            return (result.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }

        // --- 执行平滑 ---

        let latitude  = smoothLinear(point.latitude,  last.latitude)
        let longitude = smoothLinear(point.longitude, last.longitude)
        let altitude  = smoothLinear(point.altitude,  last.altitude)

        let speed: Double?
        if let cur = point.speed, let prev = last.speed {
            speed = smoothLinear(cur, prev)
        } else {
            speed = point.speed
        }

        let course: Double?
        if let cur = point.course, let prev = last.course {
            // 使用角度专用平滑算法
            course = smoothAngle(cur, prev)
        } else {
            course = point.course
        }

        return GeoPoint(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: point.timestamp, // 时间戳永远保持原始值，不平滑
            speed: speed,
            course: course
        )
    }
}
