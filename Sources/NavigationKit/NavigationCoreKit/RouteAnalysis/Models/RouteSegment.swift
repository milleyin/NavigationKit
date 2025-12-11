//
//  RouteSegment.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

public struct RouteSegment {
    public let start: GeoPoint
    public let end: GeoPoint
    /// 水平距离（米）
    public let distance: Double
    /// 爬升（正值）
    public let altitudeGain: Double
    /// 下降（正值）
    public let altitudeLoss: Double
    /// 时间差（秒）
    public let time: TimeInterval
    /// 平均速度（m/s）
    public let speed: Double
    /// 坡度（%）
    public let gradient: Double
    /// 停车点判断
    public let isMoving: Bool
}
