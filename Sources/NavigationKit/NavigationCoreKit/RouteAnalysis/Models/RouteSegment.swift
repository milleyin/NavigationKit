//
//  RouteSegment.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `RouteSegment` 表示轨迹中由两个连续点构成的**最小分析单元**。

 每个 `RouteSegment` 仅描述：
 - 两点之间的几何关系（距离 / 海拔差）
 - 两点之间的时间关系（时间差 / 速度）
 - 派生的坡度、移动特征等“段落属性”

 - Important:
   `RouteSegment` 不参与任何计算逻辑，
   它只是 **TrackEngine / SegmentAnalyzer** 等算法模块的“结果承载结构”。
   所有算法写在外面，使模型保持完全不可变（immutable）。

 - Note:
   所有数值均采用 SI 单位：
   - 距离：米
   - 时间：秒
   - 速度：米/秒
   - 坡度：百分比（%）
 */
public struct RouteSegment: Sendable {

    // MARK: - 基础字段（输入）

    /// 段落起点
    public let start: GeoPoint

    /// 段落终点
    public let end: GeoPoint

    // MARK: - 纯几何计算结果（由 TrackEngine / SegmentAnalyzer 填充）

    /// 水平距离（单位：米）
    public let distance: Double

    /// 海拔变化（end.altitude - start.altitude)
    public let elevationDelta: Double

    // MARK: - 时间 & 速度分析

    /// 本段时间（单位：秒）
    public let time: Double

    /**
     平均速度（米/秒）。

     - Important:
       这是由两点时间与距离计算的“平均速度”，
       与 GeoPoint.speed（原生设备值）不同。
     */
    public let averageSpeed: Double

    // MARK: - 坡度分析（Gradient）

    /**
     坡度百分比（%）：
     `(elevationDelta / distance) * 100`

     - Note:
       若 `distance` < 最小阈值，应由上层算法设为 `0` 或 `nil`。
     */
    public let gradient: Double

    // MARK: - 状态分类（上坡 / 下坡 / 平路）

    /**
     由 SlopeClassifier 分类的坡段类型。
     
     - `.uphill`     (正坡)
     - `.downhill`   (负坡)
     - `.flat`       (接近 0%)
     */
    public let slopeType: SlopeType

    /// 坡度分类枚举
    public enum SlopeType: Sendable {
        case uphill
        case downhill
        case flat
    }

    // MARK: - 初始化（由 TrackEngine 构建）

    /**
     初始化一个 `RouteSegment`。

     - Parameters:
       - start: 起点
       - end: 终点
       - distance: 水平距离（米）
       - elevationDelta: 海拔变化（米）
       - time: 用时（秒）
       - averageSpeed: 两点平均速度（米/秒）
       - gradient: 坡度百分比（%）
       - slopeType: 坡段分类
     */
    public init(start: GeoPoint, end: GeoPoint, distance: Double, elevationDelta: Double, time: Double, averageSpeed: Double, gradient: Double, slopeType: SlopeType) {
        self.start = start
        self.end = end
        self.distance = distance
        self.elevationDelta = elevationDelta
        self.time = time
        self.averageSpeed = averageSpeed
        self.gradient = gradient
        self.slopeType = slopeType
    }
}
