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
   本模块是 **“点 → 段”** 的唯一入口，
   不负责整体统计、不做清洗、不依赖外部状态。
 */
public final class SegmentAnalyzer {

    /// 最小可计算距离（米），小于该值认为是噪声段
    private let minimumDistance: Double = 0.5

    public init() {}

    /// 重置接口（当前无内部状态，预留）
    public func reset() {}

    /**
     处理一个新的轨迹点，生成新的段落（如有）。

     - Parameters:
       - current: 当前点
       - last: 上一个已接受的点
       - segments: 当前已有段落数组
     - Returns: 更新后的段落数组
     */
    public func process(
        _ current: GeoPoint,
        last: GeoPoint?,
        segments: [RouteSegment]
    ) -> [RouteSegment] {

        guard let last = last else {
            return segments
        }

        let deltaTime = current.timestamp.timeIntervalSince(last.timestamp)
        guard deltaTime > 0 else {
            return segments
        }

        // 1️⃣ 距离
        let distance = GeoDistance.haversine(from: last, to: current)
        guard distance.isFinite, distance >= minimumDistance else {
            return segments
        }

        // 2️⃣ 海拔变化
        let elevationDelta = current.altitude - last.altitude

        // 3️⃣ 平均速度
        let averageSpeed = distance / deltaTime

        // 4️⃣ 坡度（百分比）
        let gradient: Double = {
            guard distance > 0 else { return 0 }
            return (elevationDelta / distance) * 100
        }()

        // 5️⃣ 坡段分类（接入 SlopeClassifier）
        let slopeType = SlopeClassifier.classify(gradient: gradient)

        let segment = RouteSegment(
            start: last,
            end: current,
            distance: distance,
            elevationDelta: elevationDelta,
            time: deltaTime,
            averageSpeed: averageSpeed,
            gradient: gradient,
            slopeType: slopeType
        )

        var updated = segments
        updated.append(segment)
        return updated
    }
}
