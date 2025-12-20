//
//  SlopeClassifier.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//


import Foundation

/**
 `SlopeClassifier` 用于根据坡度值对路段进行简单分类。

 - Important:
   本模块只做“数值 → 类型”的映射，
   不关心 GeoPoint、不计算坡度、不涉及轨迹上下文。
 */
public enum SlopeClassifier {

    /// 判定为平路的坡度阈值（百分比）
    private static let flatThreshold: Double = 1.0

    /**
     根据坡度百分比返回坡段类型。
     
     - Parameter gradient: 坡度百分比（%）
     */
    public static func classify(gradient: Double) -> RouteSegment.SlopeType {
        if gradient > flatThreshold {
            return .uphill
        } else if gradient < -flatThreshold {
            return .downhill
        } else {
            return .flat
        }
    }
}
