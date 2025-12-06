//
//  SpeedFilter.swift
//  NavigationKit
//
//  Created by mille on 2025/12/6.
//

import Foundation

/**
 提供速度相关的基础算法，包括：
 - 负值清洗（sanitize）
 - 单位转换（m/s → km/h）
 - 低通滤波（low-pass filter）
 - 死区处理（用于低速抖动）
 
 本模块不依赖 CoreLocation，可用于任意速度数据源。
 */
public enum SpeedFilter {

    /**
     清洗速度数据，确保不出现负值（GPS 在静止或漂移时可能出现 -1）。
     
     - parameter raw: 原始速度（m/s）
     - returns: 清洗后的速度（m/s）
     */
    public static func sanitize(_ raw: Double) -> Double {
        return max(raw, 0)
    }

    /**
     将速度从 m/s 转换为 km/h。
     - parameter ms: 米每秒
     - returns: 千米每小时
     */
    public static func toKmh(_ ms: Double) -> Double {
        return ms * 3.6
    }

    /**
     简单低通滤波算法，使速度变化更平滑。
     
     - parameter previous: 上一次滤波值
     - parameter new: 新的输入值
     - parameter alpha: 滤波系数，0~1（越小越平滑）
     */
    public static func lowPass(previous: Double, new: Double, alpha: Double = 0.2) -> Double {
        return previous + alpha * (new - previous)
    }

    /**
     对低速进行死区处理，减少抖动。
     
     - parameter value: 输入速度（km/h）
     - parameter threshold: 小于此速度视为 0 km/h
     */
    public static func deadZone(_ value: Double, threshold: Double = 1.0) -> Double {
        return value < threshold ? 0 : value
    }
}
