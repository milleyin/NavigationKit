//
//  SegmentAnalyzer.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `SegmentAnalyzer` 负责将连续的轨迹点转换为 `RouteSegment`。

 - Important:
   本模块是 **“点 → 段”** 的唯一入口。
   它负责计算两点间的几何关系（距离、坡度等），但不负责维护整个轨迹的段落列表。
   为了性能考虑，本模块设计为 **无状态（Stateless）** 或 **轻量级状态**，
   每次调用仅返回最新生成的段落。

 - Optimization:
   v2.0 改动：`process` 方法不再接收或返回整个 `segments` 数组，而是返回单个 `RouteSegment?`，
   以避免 O(N) 的数组拷贝和遍历开销。
 */
public final class SegmentAnalyzer {

    // MARK: - Configuration

    /// 最小可计算距离（米）。
    /// 两点间距离小于该值时，将被视为“原地抖动”或“无效移动”，不生成 Segment。
    private let minimumDistance: Double = 0.5

    /// 计算坡度的最小距离阈值（米）。
    ///
    /// - Why:
    ///   在极短距离内（例如 0.5m），气压计的微小波动（例如 0.4m）会导致坡度计算出现极端异常值（0.4/0.5 = 80% 坡度）。
    ///   通过设置此阈值，强制要求只有在水平距离足够长时，才计算有效坡度。
    private let minimumGradientDistance: Double = 10.0

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /**
     重置分析器状态。

     - Note:
       当前版本的 `SegmentAnalyzer` 是无状态的（Stateless），此方法主要用于保持接口一致性。
       如果未来版本引入了“多点缓冲坡度计算”或“滑动窗口”，此方法将用于清空缓冲区。
     */
    public func reset() {
        // v1.0 无内部状态，无需操作
        // v2.0 预留位置
    }

    /**
     处理一个新的轨迹点，尝试生成一个新的段落。

     - Important:
       这是一个纯计算方法。它不会修改任何内部状态，也不持有历史数据。

     - Parameters:
       - current: 当前采样点（必须是经过 Cleaner/Smoother 处理后的有效点）
       - last: 上一个已接受的采样点（若无则传 nil）
     
     - Returns:
       - `RouteSegment`: 如果两点满足生成段落的条件（距离 > 阈值等），返回新生成的段落。
       - `nil`: 如果两点距离过近或时间倒退，不生成段落。
     */
    public func process(_ current: GeoPoint, last: GeoPoint?) -> RouteSegment? {

        // 1. 基础校验：必须有上一个点
        guard let last = last else {
            return nil
        }

        // 2. 时间校验：时间必须正向流动
        let deltaTime = current.timestamp.timeIntervalSince(last.timestamp)
        guard deltaTime > 0 else {
            return nil
        }

        // 3. 距离校验：过滤微小抖动
        let distance = GeoDistance.haversine(from: last, to: current)
        guard distance.isFinite, distance >= minimumDistance else {
            return nil
        }

        // 4. 计算基础属性
        let elevationDelta = current.altitude - last.altitude
        let averageSpeed = distance / deltaTime

        // 5. 计算坡度（带防抖逻辑）
        // 优化：只有当水平距离超过阈值（如 10m）时才计算坡度，防止短距离噪音导致坡度爆炸
        let gradient: Double = {
            guard distance >= minimumGradientDistance else {
                return 0.0 // 距离太短，视为平路，避免噪点
            }
            return (elevationDelta / distance) * 100.0
        }()

        // 6. 坡度分类
        let slopeType = SlopeClassifier.classify(gradient: gradient)

        // 7. 构造并返回结果
        return RouteSegment(
            start: last,
            end: current,
            distance: distance,
            elevationDelta: elevationDelta,
            time: deltaTime,
            averageSpeed: averageSpeed,
            gradient: gradient,
            slopeType: slopeType
        )
    }
}
