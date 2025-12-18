//
//  SegmentAnalyzer.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//


import Foundation

/**
 `SegmentAnalyzer` 负责将连续的 `GeoPoint` 转换为 `RouteSegment`。

 - Important:
   本模块只做「点 → 段」的**确定性计算**：
   - 距离
   - 时间
   - 平均速度
   - 海拔变化
   - 坡度
   - 坡段类型（上坡 / 下坡 / 平路）

 - Note:
   不做段合并、不做统计、不做业务判断，
   所有“更高级”的语义由上层模块负责。
 */
public final class SegmentAnalyzer {

    // MARK: - Configuration

    /// 坡度判定阈值（百分比 %）
    /// |gradient| <= threshold → flat
    private let slopeThreshold: Double = 1.0

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /**
     处理一个新的轨迹点，生成对应的 `RouteSegment`（如可行）。

     - Parameters:
       - point: 当前轨迹点
       - last: 上一个已接受的轨迹点
       - segments: 现有的段落数组
     - Returns: 更新后的段落数组
     */
    public func process(
        _ point: GeoPoint,
        last: GeoPoint?,
        segments: [RouteSegment]
    ) -> [RouteSegment] {

        guard let last = last else {
            return segments
        }

        // 1️⃣ 时间差
        let time = point.timestamp.timeIntervalSince(last.timestamp)
        guard time > 0 else {
            return segments
        }

        // 2️⃣ 距离（米）
        let distance = GeoDistance.haversine(from: last, to: point)
        guard distance > 0 else {
            return segments
        }

        // 3️⃣ 平均速度（m/s）
        let averageSpeed = distance / time

        // 4️⃣ 海拔变化
        let elevationDelta = point.altitude - last.altitude

        // 5️⃣ 坡度（%）
        let gradient = (distance > 0)
            ? (elevationDelta / distance) * 100.0
            : 0.0

        // 6️⃣ 坡段类型
        let slopeType: RouteSegment.SlopeType
        if gradient > slopeThreshold {
            slopeType = .uphill
        } else if gradient < -slopeThreshold {
            slopeType = .downhill
        } else {
            slopeType = .flat
        }

        let segment = RouteSegment(
            start: last,
            end: point,
            distance: distance,
            elevationDelta: elevationDelta,
            time: time,
            averageSpeed: averageSpeed,
            gradient: gradient,
            slopeType: slopeType
        )

        return segments + [segment]
    }

    // MARK: - Reset

    public func reset() {
        // 当前实现无内部状态
    }
}
