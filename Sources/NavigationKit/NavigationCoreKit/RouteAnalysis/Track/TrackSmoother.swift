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
   仅对数值字段进行低通滤波，降低 GPS 抖动对后续分析的影响。

 - Design Principles:
   - 输入一个点，输出一个点（1-in-1-out）
   - 不做合法性判断（Cleaner 已负责）
   - 不引入业务语义（Analyzer / Segment 才关心）
 */
public final class TrackSmoother {

    // MARK: - Config

    /**
     平滑配置。

     - Parameter alpha:
       平滑系数（0 ~ 1）。
       - 越小 → 越平滑（响应慢）
       - 越大 → 越灵敏（接近原始数据）
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
       当前版本为**无内部缓存实现**，
       该方法为未来扩展（如多阶滤波）预留。
     */
    public func reset() {
        // v1 无状态，无需处理
    }

    // MARK: - Processing

    /**
     对单个轨迹点进行平滑处理。

     - Parameters:
       - point: 当前输入点（已通过 TrackCleaner）
       - last: 上一个“已接受”的轨迹点

     - Returns:
       平滑后的 `GeoPoint`
     */
    public func process(_ point: GeoPoint, last: GeoPoint?) -> GeoPoint {

        guard let last = last, config.alpha < 1 else {
            // 第一个点 or alpha == 1：直接返回原始点
            return point
        }

        let a = config.alpha

        func smooth(_ current: Double, _ previous: Double) -> Double {
            previous + a * (current - previous)
        }

        let latitude  = smooth(point.latitude,  last.latitude)
        let longitude = smooth(point.longitude, last.longitude)
        let altitude  = smooth(point.altitude,  last.altitude)

        let speed: Double?
        if let cur = point.speed, let prev = last.speed {
            speed = smooth(cur, prev)
        } else {
            speed = point.speed
        }

        let course: Double?
        if let cur = point.course, let prev = last.course {
            // 航向角暂不做环绕处理（V1 保守处理）
            course = smooth(cur, prev)
        } else {
            course = point.course
        }

        return GeoPoint(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: point.timestamp,
            speed: speed,
            course: course
        )
    }
}
