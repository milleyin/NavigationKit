//
//  SpeedManager.swift
//  NavigationKit
//
//  Created by mille on 2025/12/6.
//

import Foundation
import Combine

/**
 SpeedManager 提供统一的速度计算逻辑，包括：
 
 1. 原始速度（m/s）的清洗
 2. 单位转换（km/h）
 3. 低通滤波（平滑速度）
 4. 死区处理（防抖）
 
 - Important:
   不直接依赖 CoreLocation，可通过任意 `Publisher<Double>` 输入速度数据。
   上层可绑定 CoreLocationKit.rawSpeedPublisher 或轨迹回放等来源。
 */
public final class SpeedManager: ObservableObject {

    /// 处理后的最终速度（单位：km/h）
    @Published public private(set) var speedKmh: Double = 0

    /// 内部订阅集合
    private var subscriptions: Set<AnyCancellable> = .init()

    /// 滤波缓存
    private var lastFilteredValue: Double = 0

    /// 滤波参数
    private let smoothingAlpha: Double
    private let deadZoneThreshold: Double

    public init(
        smoothingAlpha: Double = 0.2,
        deadZoneThreshold: Double = 1.0
    ) {
        self.smoothingAlpha = smoothingAlpha
        self.deadZoneThreshold = deadZoneThreshold
    }

    /**
     绑定一个速度 Publisher（单位必须为 m/s）。
     
     - Important: 这是 SpeedManager 的主输入管线。
     - parameter publisher: 任意发出 `Double`（m/s）的 Publisher。
     */
    public func bindSpeedPublisher<P>(_ publisher: P)
        where P: Publisher, P.Output == Double, P.Failure == Never
    {
        publisher
            // 1. 负值清洗
            .map { SpeedFilter.sanitize($0) }
            // 2. 单位转换 m/s → km/h
            .map { SpeedFilter.toKmh($0) }
            // 3. 低通滤波
            .map { [weak self] newValue -> Double in
                guard let self else { return newValue }
                let filtered = SpeedFilter.lowPass(
                    previous: self.lastFilteredValue,
                    new: newValue,
                    alpha: smoothingAlpha
                )
                self.lastFilteredValue = filtered
                return filtered
            }
            // 4. 死区处理（静止抖动）
            .map { SpeedFilter.deadZone($0, threshold: self.deadZoneThreshold) }
            // 5. 更新 UI
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.speedKmh = value
            }
            .store(in: &subscriptions)
    }

    /// 重置所有缓存与输出（用于停止或重启速度管线）
    public func reset() {
        lastFilteredValue = 0
        speedKmh = 0
    }
}
