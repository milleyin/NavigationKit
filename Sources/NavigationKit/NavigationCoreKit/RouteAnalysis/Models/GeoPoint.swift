//
//  GeoPoint.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation
import CoreLocation

/**
 轨迹系统中的**最小基础单位**：地理点（GPS 样本点）。

 `GeoPoint` 不包含任何经过算法处理的内容（如平滑海拔、滤波速度等），
 它仅代表设备原始状态下的“一次定位采样”。

 - Important:
   该结构体应当保持 **纯数据模型（POD）** 的性质，不包含逻辑、不依赖业务环境。
   所有算法与分析模块（如 TrackEngine / SegmentAnalyzer）均应基于此模型构建。

 - Note:
   `speed` 与 `course` 是可选字段，因为某些数据源（如 GPX 文件、KML
   或某些低功耗定位）可能不提供这两个值。
 */
public struct GeoPoint: Sendable, Equatable {

    // MARK: - 基本地理信息
    
    /// 纬度（单位：十进制度）
    public let latitude: Double
    
    /// 经度（单位：十进制度）
    public let longitude: Double
    
    /// 海拔高度（单位：米）
    public let altitude: Double
    
    /// 时间戳（采样时间）
    public let timestamp: Date

    // MARK: - 可选的设备数据（若无则为 nil）

    /**
     原生速度（单位：米/秒）。
     
     - Important:
       速度值来自系统定位框架（如 CoreLocation），非分析后速度。
       若无速度信息，值为 `nil`。
     */
    public let speed: Double?

    /**
     航向角（0° ~ 360°，单位：度）。
     
     - Important:
       表示设备当时的指向方向，而不是移动方向。
       某些数据源可能缺失该字段。
     */
    public let course: Double?

    // MARK: - 初始化
    
    /**
     使用指定字段创建一个 `GeoPoint`。

     - Parameters:
       - latitude: 纬度（十进制度）
       - longitude: 经度（十进制度）
       - altitude: 海拔高度（米）
       - timestamp: 采样时间
       - speed: 可选的原生速度（米/秒）
       - course: 可选的航向角（度）
     */
    public init(latitude: Double, longitude: Double, altitude: Double, timestamp: Date, speed: Double? = nil, course: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.speed = speed
        self.course = course
    }

    // MARK: - 便利初始化（从 CoreLocation 构造）
    
    /**
     从 `CLLocation` 直接构建 `GeoPoint`。

     - Important:
       这是模型层允许的少数便利方法之一，
       但依然保持“原始数据入 → GeoPoint → 算法”的设计原则。
     */
    public init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp
        self.speed = location.speed >= 0 ? location.speed : nil // CoreLocation 负值代表无速度
        self.course = location.course >= 0 ? location.course : nil
    }
}
