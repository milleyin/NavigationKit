//
//  GeoDistance.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//


import Foundation

/**
 `GeoDistance` 提供基础的地理距离与方向计算。

 - Important:
   本模块只负责**数学与地理计算**，不涉及轨迹语义、不关心时间、速度或业务规则。
   所有方法均为 **纯函数（Pure Function）**，无状态、可单测、可复用。

 - Note:
   当前实现基于球体地球模型（Haversine），
   对于徒步 / 骑行 / 驾驶等场景精度完全足够。
 */
public enum GeoDistance {

    // MARK: - Constants

    /// 地球平均半径（米）
    private static let earthRadius: Double = 6_371_000

    // MARK: - Distance

    /**
     使用 Haversine 公式计算两点间的大圆距离。

     - Parameters:
       - a: 起点
       - b: 终点
     - Returns: 距离（单位：米）
     */
    public static func haversine(from a: GeoPoint, to b: GeoPoint) -> Double {

        let lat1 = degreesToRadians(a.latitude)
        let lon1 = degreesToRadians(a.longitude)
        let lat2 = degreesToRadians(b.latitude)
        let lon2 = degreesToRadians(b.longitude)

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2)
              * sin(dLon / 2) * sin(dLon / 2)

        return 2 * earthRadius * asin(min(1.0, sqrt(h)))
    }

    // MARK: - Bearing

    /**
     计算从起点指向终点的方位角（Bearing）。

     - Parameters:
       - a: 起点
       - b: 终点
     - Returns:
       方位角（单位：度，范围 0° ~ 360°，正北为 0°，顺时针）
     */
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {

        let lat1 = degreesToRadians(a.latitude)
        let lat2 = degreesToRadians(b.latitude)
        let dLon = degreesToRadians(b.longitude - a.longitude)

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2)
              - sin(lat1) * cos(lat2) * cos(dLon)

        let radians = atan2(y, x)
        let degrees = radiansToDegrees(radians)

        return fmod((degrees + 360), 360)
    }

    // MARK: - Helpers

    @inline(__always)
    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    @inline(__always)
    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }
}
