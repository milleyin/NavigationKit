//
//  GradientCalculator.swift
//  NavigationKit
//
//  Created by mille on 2025/12/5.
//

import Foundation

/**
 坡度计算工具，用于根据海拔变化和水平距离计算坡度（百分比 %）。
 
 - Important: 所有单位均为“米”，返回值为百分比，如 `10.0` 表示 10% 坡度。
 */
public enum GradientCalculator {
    
    /**
     计算坡度（Gradient）。
     
     公式：`gradient = (Δ海拔 / 水平距离) × 100%`
     
     - Important: 当水平距离小于 `minimumDistance` 时，将返回 `0`，避免数值不稳定。
     
     - parameter deltaAltitude: 海拔变化量（米），正值为上升，负值为下降。
     - parameter horizontalDistance: 水平距离（米）。
     - parameter minimumDistance: 最小有效距离（米），默认为 `1.0`。
     
     - Returns: 坡度百分比（正值上坡，负值下坡）。
     */
    public static func computeGradient(
        deltaAltitude: Double,
        horizontalDistance: Double,
        minimumDistance: Double = 1.0
    ) -> Double {
        guard horizontalDistance > minimumDistance else {
            return 0
        }
        
        return (deltaAltitude / horizontalDistance) * 100.0
    }
}
