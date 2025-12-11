//
//  RouteSummary.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `RouteSummary` 是对整个轨迹（Track）的最终统计结果。

 - Important:
   本结构体**只存结果，不做计算**，所有数值由 `TrackAnalyzer` 或其他算法模块填充。
   
 - Note:
   单位全为 SI 国际标准单位：
   - 距离：米（m）
   - 时间：秒（s）
   - 速度：米/秒（m/s）
   - 坡度：百分比（%）
   - 海拔：米（m）

 - Usage:
   用在 UI、数据库、行程记录、本地文件存储、远端同步、统计图表等所有呈现层。
 */
public struct RouteSummary: Sendable {

    // MARK: - 基础数据（总览）

    /// 轨迹是否有效（例如点数过少会标记为 invalid）
    public let isValid: Bool

    /// 点的数量
    public let pointCount: Int

    /// 段落数量（RouteSegment 个数）
    public let segmentCount: Int

    // MARK: - 距离统计

    /// 总距离（米）
    public let totalDistance: Double

    /// 平均速度（基于总距离／移动时间，单位：米/秒）
    public let averageSpeed: Double

    /// 最大速度（米/秒）
    public let maxSpeed: Double

    // MARK: - 时间统计

    /// 总用时（秒）
    public let totalTime: Double

    /// 移动时间（速度 > 阈值 时累计）
    public let movingTime: Double

    /// 停止时间（速度 < 阈值 时累计）
    public let stoppedTime: Double

    // MARK: - 海拔统计（复用 ElevationManager 的逻辑结果）

    /// 总爬升（米）
    public let totalElevationGain: Double

    /// 总下降（米）
    public let totalElevationLoss: Double

    /// 最高点（米）
    public let maxAltitude: Double

    /// 最低点（米）
    public let minAltitude: Double

    // MARK: - 坡度统计

    /// 最大坡度（百分比 %）
    public let maxGradient: Double

    /// 最陡下坡（百分比 %）
    public let minGradient: Double

    // MARK: - 起点、终点

    public let startPoint: GeoPoint?
    public let endPoint: GeoPoint?

    // MARK: - 自定义摘要（未来可扩展）

    /// 例如 “最难爬坡段落”、“本次路线评分”等
    public let metadata: [String: String]

    // MARK: - 初始化

    public init(
        isValid: Bool,
        pointCount: Int,
        segmentCount: Int,
        totalDistance: Double,
        averageSpeed: Double,
        maxSpeed: Double,
        totalTime: Double,
        movingTime: Double,
        stoppedTime: Double,
        totalElevationGain: Double,
        totalElevationLoss: Double,
        maxAltitude: Double,
        minAltitude: Double,
        maxGradient: Double,
        minGradient: Double,
        startPoint: GeoPoint?,
        endPoint: GeoPoint?,
        metadata: [String : String] = [:]
    ) {
        self.isValid = isValid
        self.pointCount = pointCount
        self.segmentCount = segmentCount
        self.totalDistance = totalDistance
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.totalTime = totalTime
        self.movingTime = movingTime
        self.stoppedTime = stoppedTime
        self.totalElevationGain = totalElevationGain
        self.totalElevationLoss = totalElevationLoss
        self.maxAltitude = maxAltitude
        self.minAltitude = minAltitude
        self.maxGradient = maxGradient
        self.minGradient = minGradient
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.metadata = metadata
    }
}
