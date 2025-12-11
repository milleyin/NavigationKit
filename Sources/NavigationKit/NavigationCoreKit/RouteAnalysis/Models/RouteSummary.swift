//
//  RouteSummary.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

public struct RouteSummary {
    /// 总距离
    public let totalDistance: Double
    /// 总时间
    public let totalDuration: TimeInterval
    /// 移动时间
    public let movingTime: TimeInterval
    /// 停车总时间
    public let stoppedTime: TimeInterval
    /// 平均速度
    public let avgSpeed: Double
    /// 最大速度
    public let maxSpeed: Double
    /// 最大坡度
    public let maxGradient: Double
    /// 总爬升
    public let totalElevationGain: Double
    /// 总下降
    public let totalElevationLoss: Double
    /// 分段数量
    public let segmentCount: Int
}
