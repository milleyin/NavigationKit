//
//  ElevationStatistics.swift
//  NavigationKit
//
//  Created by mille on 2025/12/5.
//

import Foundation

/**
 海拔相关统计信息，包含：
 
 - 累计爬升（totalAscent）
 - 累计下降（totalDescent）
 - 最低海拔（minimumAltitude）
 - 最高海拔（maximumAltitude）
 
 - Important: 本结构体为“值类型”，适合作为状态承载，由上层管理生命周期。
 */
public struct ElevationStatistics {
    
    /// 累计爬升（米）
    public private(set) var totalAscent: Double = 0
    
    /// 累计下降（米）
    public private(set) var totalDescent: Double = 0
    
    /// 最低海拔（米）
    public private(set) var minimumAltitude: Double?
    
    /// 最高海拔（米）
    public private(set) var maximumAltitude: Double?
    
    /// 最近一次记录的海拔（米）
    public private(set) var lastAltitude: Double?
    
    /**
     初始化一个空的统计结构。
     */
    public init() {}
    
    /**
     使用指定海拔重置统计信息。
     
     - parameter altitude: 初始海拔值（米），若为 `nil`，则所有统计重置为空。
     */
    public mutating func reset(withInitialAltitude altitude: Double?) {
        totalAscent = 0
        totalDescent = 0
        minimumAltitude = altitude
        maximumAltitude = altitude
        lastAltitude = altitude
    }
    
    /**
     使用新的海拔数据更新统计信息。
     
     - Important: 该方法不会进行滤波，调用方应传入已经平滑后的海拔值。
     
     - parameter currentAltitude: 当前海拔（米）。
     - parameter deltaAltitude: 相对上一点的海拔变化（米），正值表示上升，负值表示下降。
     - parameter noiseThreshold: 噪声阈值（米），绝对值小于该阈值的变化将被忽略，不计入累计爬升/下降。
     */
    public mutating func update(
        currentAltitude: Double,
        deltaAltitude: Double,
        noiseThreshold: Double
    ) {
        // 更新 min / max
        if let minAlt = minimumAltitude {
            minimumAltitude = min(minAlt, currentAltitude)
        } else {
            minimumAltitude = currentAltitude
        }
        
        if let maxAlt = maximumAltitude {
            maximumAltitude = max(maxAlt, currentAltitude)
        } else {
            maximumAltitude = currentAltitude
        }
        
        // 根据阈值过滤噪声
        if deltaAltitude > noiseThreshold {
            totalAscent += deltaAltitude
        } else if deltaAltitude < -noiseThreshold {
            totalDescent += abs(deltaAltitude)
        }
        
        lastAltitude = currentAltitude
    }
}
