//
//  TrackCleaner.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//


import Foundation

/**
 `TrackCleaner` 负责对原始轨迹点（`GeoPoint`）进行**基础清洗**。

 - Important:
   本模块只做「是否可信」判断，不做平滑、不做统计、不做业务分析。
   它的职责是：**把明显错误的数据点移除**，让后续算法建立在“干净输入”之上。

 - Design:
   - 支持两种使用方式：
     1) `process(_:last:)`：实时流式清洗（适合 TrackEngine append）
     2) `clean(_:)`：批量清洗（适合 GPX/文件导入/回放）
   - 不依赖 CoreLocationKit / AppleMapKit
   - 不关心 UI/线程/实时与否
 */
public final class TrackCleaner {

    // MARK: - Parameters (Injected)

    /// 合理的最大速度（m/s），超过视为异常跳点
    private let maximumReasonableSpeed: Double

    /// 最大允许的单次海拔突变（米）
    private let maximumAltitudeJump: Double

    /// 最小时间间隔（秒），小于该值的点将被视为重复/异常
    private let minimumTimeInterval: TimeInterval

    // MARK: - Init

    /**
     初始化 `TrackCleaner`。

     - Important:
       这里不再定义 `TrackCleaner.Config`，避免与 `TrackEngine.Config` 职责重叠。
       所有策略参数统一由上层（例如 TrackEngine）注入。

     - Parameters:
       - maximumReasonableSpeed: 最大合理速度（m/s）
       - maximumAltitudeJump: 最大单次海拔跳变（米）
       - minimumTimeInterval: 最小时间间隔（秒）
     */
    public init(maximumReasonableSpeed: Double, maximumAltitudeJump: Double, minimumTimeInterval: TimeInterval) {
        self.maximumReasonableSpeed = maximumReasonableSpeed
        self.maximumAltitudeJump = maximumAltitudeJump
        self.minimumTimeInterval = minimumTimeInterval
    }

    // MARK: - Public API (Streaming)

    /**
     清洗一个点（实时流式入口）。

     - Important:
       这个方法用于 **TrackEngine 实时 append** 场景：
       你给我“当前点”和“上一个已接受的点”，我决定收不收。

     - Parameters:
       - point: 当前输入点
       - last: 上一个已接受点（可为 nil）

     - Returns:
       - `GeoPoint`：接受该点
       - `nil`：丢弃该点
     */
    public func process(_ point: GeoPoint, last: GeoPoint?) -> GeoPoint? {

        // 1) 基础合法性
        guard isValidCoordinate(point) else { return nil }

        // 第一个点永远接受
        guard let last = last else { return point }

        // 2) 时间检查：倒退 / 过密
        let dt = point.timestamp.timeIntervalSince(last.timestamp)
        if dt <= 0 { return nil }
        if dt < minimumTimeInterval { return nil }

        // 3) 海拔突变检查
        let altitudeJump = abs(point.altitude - last.altitude)
        if altitudeJump > maximumAltitudeJump { return nil }

        // 4) 速度异常检查：优先用点自带 speed，否则用两点估算
        let speed: Double = {
            if let s = point.speed, s.isFinite, s >= 0 {
                return s
            }
            let distance = GeoDistance.haversine(from: last, to: point)
            return distance / dt
        }()

        guard speed.isFinite else { return nil }
        if speed > maximumReasonableSpeed { return nil }

        return point
    }

    // MARK: - Public API (Batch)

    /**
     清洗一段轨迹点（批量入口）。

     - Important:
       适用于 GPX/KML/历史轨迹回放/导入：
       该方法会**先按时间排序**，再逐点调用 `process(_:last:)` 清洗。

     - Parameter points: 原始轨迹点数组（可无序）
     - Returns:
       - cleaned: 清洗后的轨迹点（按时间升序）
       - droppedCount: 被丢弃的点数量
     */
    public func clean(_ points: [GeoPoint]) -> (cleaned: [GeoPoint], droppedCount: Int) {
        guard points.count > 1 else {
            return (points, 0)
        }

        // 1) 时间排序
        let sorted = points.sorted { $0.timestamp < $1.timestamp }

        var cleaned: [GeoPoint] = []
        var dropped = 0

        for p in sorted {
            if let accepted = process(p, last: cleaned.last) {
                cleaned.append(accepted)
            } else {
                dropped += 1
            }
        }

        return (cleaned, dropped)
    }

    /**
     重置内部状态。

     - Note:
       当前版本 TrackCleaner 本身是“无状态”的（last 由上层传入），
       该方法是为了保持模块接口一致性，方便未来扩展（例如窗口缓存）。
     */
    public func reset() {
        // no-op
    }
}

// MARK: - Internal Helpers

private extension TrackCleaner {

    /// 经纬度/海拔是否为有限值，并且范围合理
    func isValidCoordinate(_ point: GeoPoint) -> Bool {
        guard point.latitude.isFinite,
              point.longitude.isFinite,
              point.altitude.isFinite else {
            return false
        }

        return abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }
}
