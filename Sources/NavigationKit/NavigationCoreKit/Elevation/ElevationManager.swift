//
//  ElevationManager.swift
//  NavigationKit
//
//  Created by mille on 2025/12/5.
//

import Foundation
import Combine

/**
 海拔计算配置结构体，用于控制平滑程度、噪声阈值等参数。
 
 - Important: 所有单位均使用国际标准单位（SI），海拔单位为“米”，距离单位为“米”。
 */
public struct ElevationConfig {
    
    /// 低通滤波系数，范围建议在 0.0 ~ 1.0 之间，越小越平滑、越慢。
    public let smoothingFactor: Double
    
    /// 判定为有效爬升/下降的最小海拔变化阈值（米），小于该值视为噪声。
    public let noiseThreshold: Double
    
    /// 计算坡度时的最小水平距离阈值（米），防止除以极小的数导致不稳定。
    public let minimumGradientDistance: Double
    
    /**
     初始化配置。
     
     - parameter smoothingFactor: 低通滤波系数，默认 `0.2`。
     - parameter noiseThreshold: 噪声阈值（米），默认 `0.5`。
     - parameter minimumGradientDistance: 最小坡度计算距离（米），默认 `1.0`。
     */
    public init(
        smoothingFactor: Double = 0.2,
        noiseThreshold: Double = 0.5,
        minimumGradientDistance: Double = 1.0
    ) {
        self.smoothingFactor = smoothingFactor
        self.noiseThreshold = noiseThreshold
        self.minimumGradientDistance = minimumGradientDistance
    }
    
    /// 默认配置，适用于一般公路驾驶 / 骑行场景。
    public static let `default`: ElevationConfig = .init()
}

/**
 海拔管理器，负责基于原始海拔数据计算：
 
 1. 平滑海拔（滤波后）
 2. 累计爬升 / 累计下降
 3. 当前坡度（gradient，单位：百分比 %）
 
 - Important: 本类只处理“算法逻辑”，不主动访问硬件或 CoreLocation。
   上层可以通过 `bindAltitudePublisher(_:horizontalDistanceProvider:)` 或手动调用
   `processAltitudeSample(rawAltitude:horizontalDistance:)` 进行数据输入。
 */
public final class ElevationManager: ObservableObject {
    
    /// 平滑后的当前海拔（米）
    @Published public private(set) var smoothedAltitude: Double = 0
    
    /// 当前坡度（百分比 %，正值为上坡，负值为下坡）
    @Published public private(set) var gradient: Double = 0
    
    /// 累计爬升（米）
    @Published public private(set) var elevationGain: Double = 0
    
    /// 累计下降（米）
    @Published public private(set) var elevationLoss: Double = 0
    
    /// 配置参数
    private let config: ElevationConfig
    
    /// 最近一次平滑后的海拔
    private var lastAltitude: Double?
    
    /// 统计信息
    private var statistics: ElevationStatistics = .init()
    
    /// 内部订阅集合
    private var subscriptions: Set<AnyCancellable> = .init()
    
    /**
     使用指定配置初始化 `ElevationManager`。
     
     - parameter config: 高度计算相关配置，默认使用 `ElevationConfig.default`。
     */
    public init(config: ElevationConfig = .default) {
        self.config = config
    }
    
    deinit {
        subscriptions.forEach { $0.cancel() }
    }
    
    /**
     绑定一个海拔数据流（Publisher），并通过回调提供水平距离，用于计算坡度。
     
     - Important: 该方法不会假设数据来源，可以对接 `CoreLocationKit`、
       轨迹回放、文件导入等各种来源。
     
     - parameter publisher: 任意发出 `Double` 类型海拔值（单位：米）的 Publisher。
     - parameter horizontalDistanceProvider: 一个回调，用于根据上一点和当前点提供水平距离（米）。
       若返回 `nil` 或距离无效，则本次不计算坡度，仅更新海拔与爬升统计。
     
     # 使用示例
     ```swift
     elevationManager.bindAltitudePublisher(
         CoreLocationKit.shared.altitudePublisher.map(Double.init)
     ) { _, _ in
         // 这里可以结合自己的距离计算逻辑
         return 5.0 // 单位：米
     }
     ```
     
     - parameter previousAltitude: 上一次平滑后的海拔（米），无历史数据时为 `nil`。
     - parameter newAltitude: 本次传入的原始海拔（米）。
     */
    public func bindAltitudePublisher<P>(
        _ publisher: P,
        horizontalDistanceProvider: @escaping (_ previousAltitude: Double?, _ newAltitude: Double) -> Double?
    ) where P: Publisher, P.Output == Double, P.Failure == Never {
        publisher
            .sink { [weak self] rawAltitude in
                guard let self else { return }
                let distance = horizontalDistanceProvider(self.lastAltitude, rawAltitude)
                self.processAltitudeSample(rawAltitude: rawAltitude,
                                           horizontalDistance: distance)
            }
            .store(in: &subscriptions)
    }
    
    /**
     处理一条新的海拔样本数据。
     
     - Important: 该方法是 `ElevationManager` 的核心，负责：
       1. 使用 `ElevationFilter` 进行低通滤波；
       2. 使用 `ElevationStatistics` 更新累计爬升/下降；
       3. 使用 `GradientCalculator` 计算当前坡度。
     
     - parameter rawAltitude: 原始海拔（单位：米）。
     - parameter horizontalDistance: 与上一点之间的水平距离（单位：米），
       若为 `nil` 或小于配置中的 `minimumGradientDistance`，则本次不更新坡度。
     */
    public func processAltitudeSample(
        rawAltitude: Double,
        horizontalDistance: Double?
    ) {
        // 1. 低通滤波
        let previous = lastAltitude
        let filtered = ElevationFilter.lowPassFilter(
            previousValue: previous,
            newValue: rawAltitude,
            alpha: config.smoothingFactor
        )
        smoothedAltitude = filtered
        
        // 2. 更新统计
        if let last = previous {
            let delta = filtered - last
            
            statistics.update(
                currentAltitude: filtered,
                deltaAltitude: delta,
                noiseThreshold: config.noiseThreshold
            )
            
            elevationGain = statistics.totalAscent
            elevationLoss = statistics.totalDescent
            
            // 3. 计算坡度
            if let distance = horizontalDistance {
                gradient = GradientCalculator.computeGradient(
                    deltaAltitude: delta,
                    horizontalDistance: distance,
                    minimumDistance: config.minimumGradientDistance
                )
            } else {
                gradient = 0
            }
        } else {
            // 第一次样本，用当前值初始化统计
            statistics.reset(withInitialAltitude: filtered)
            elevationGain = statistics.totalAscent
            elevationLoss = statistics.totalDescent
            gradient = 0
        }
        
        lastAltitude = filtered
        NavigationCoreKit.debugLog("alt=\(rawAltitude), filtered=\(filtered), gain=\(elevationGain), loss=\(elevationLoss), gradient=\(gradient)")
    }
    /**
     重置海拔管理器的内部状态，包括平滑海拔、累计爬升/下降、坡度等统计信息。

     - Important:
       调用本方法会 **清空所有已计算的数据**，并使 `ElevationManager` 回到“初始状态”，
       相当于刚创建对象时的状态。适用于以下场景：
       - 开始新的记录 Session（骑行 / 路线跟踪 / 导航）
       - 用户主动点击“重置统计”
       - 停止默认海拔管道后准备重新开始

     - Attention:
       本方法不会停止任何正在进行的 Publisher 订阅。
       如果你使用的是 `NavigationKit.startDefaultElevationPipeline()` 搭建的默认数据管道，
       请在调用本方法前务必使用 `NavigationKit.stopElevationPipeline()` 停止管道，否则
       订阅仍在运行，会立即推入新的样本并重建统计数据。

     - Bug:
       若在 `processAltitudeSample` 正在执行时（即高频调用中）并发调用本方法，可能导致
       统计状态瞬间出现不一致。建议在管道停止后或在安全的线程环境中调用。

     - Warning:
       调用本方法后，`lastAltitude` 会被清空，在下一次处理样本时将视为“第一次输入”，
       不会计算坡度、累计爬升或累计下降，直到至少有两个有效样本为止。

     - Remark:
       若你想要“保留累计爬升，但更新平滑海拔”，则**不要调用 reset()**，而应考虑
       在外层加自定义逻辑，而不是清空全部状态。

     - Note:
       `ElevationStatistics.reset(withInitialAltitude:)` 会将统计器内部的总爬升、总下降、
       历史峰值等全部恢复到初始值。

     - Precondition:
       `ElevationManager` 当前实例即将开始新的海拔数据流，或你希望丢弃之前所有统计。

     - Postcondition:
       以下值将被重置为初始状态：
       - `smoothedAltitude = 0`
       - `gradient = 0`
       - `elevationGain = 0`
       - `elevationLoss = 0`
       - `lastAltitude = nil`
       - `statistics` 清空并等待下一次输入重新初始化

     # 使用示例
     ```swift
     // 停止管道
     NavigationKit.stopElevationPipeline()

     // 重置状态
     NavigationKit.elevationManager.reset()

     // 再次开始新的记录
     NavigationKit.startDefaultElevationPipeline()
     */
    public func reset() {
        smoothedAltitude = 0
        gradient = 0
        elevationGain = 0
        elevationLoss = 0
        lastAltitude = nil
        statistics.reset(withInitialAltitude: nil)
    }
}
