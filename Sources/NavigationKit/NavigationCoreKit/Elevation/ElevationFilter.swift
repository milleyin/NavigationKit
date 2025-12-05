//
//  ElevationFilter.swift
//  NavigationKit
//
//  Created by mille on 2025/12/5.
//

import Foundation

/**
 海拔滤波工具，提供简易的一阶低通滤波器。
 
 - Important: 本工具为纯算法模块，不持有任何状态。
 */
public enum ElevationFilter {
    
    /**
     一阶低通滤波（Exponential Moving Average）。
     
     公式：
     `filtered = previous + α * (new - previous)`
     
     - parameter previousValue: 上一次平滑后的值，若为 `nil` 则直接返回 `newValue`。
     - parameter newValue: 本次原始输入值。
     - parameter alpha: 滤波系数，范围建议在 `0.0 ... 1.0`。越小越平滑，越大越接近原始值。
     
     - Returns: 滤波后的新值。
     */
    public static func lowPassFilter(
        previousValue: Double?,
        newValue: Double,
        alpha: Double
    ) -> Double {
        let clampedAlpha = max(0.0, min(alpha, 1.0))
        
        guard let previous = previousValue else {
            return newValue
        }
        
        return previous + clampedAlpha * (newValue - previous)
    }
}
