//
//  NavigationKit.swift
//  NavigationKit
//
//  Created by Mille Yin on 2025/2/17.
//

import Foundation
import Combine
import CoreLocation
import CoreLocationKit
import NavigationCoreKit

public enum NavigationKit {
    /// NavigationKit 版本号
    public static let version: String = "1.4.0(2025034)"
}

//MARK: - Elevation
extension NavigationKit {
    /// 全局 Elevation 管理器
    public static let elevationManager = ElevationManager()
    
    private static var subscriptions: Set<AnyCancellable> = .init()
    private static var lastLocation: CLLocation?
    private static var isElevationPipelineStarted = false
    
    /**
         启动默认的海拔计算数据管道，将 `CoreLocationKit` 的位置数据自动接入 `ElevationManager`。
         
         - Important: 此方法为**幂等**设计，多次调用仅第一次生效，后续调用将被忽略，不会重复建立订阅。
         - Attention: 该默认管道基于 `CoreLocationKit.shared.locationPublisher` 提供的位置数据，
           使用 `CLLocation.distance(from:)` 计算相邻两点间的水平距离，以用于坡度与累计爬升/下降的计算。
         - Bug: 如果上层在未正确配置定位权限或未启用定位服务的情况下调用本方法，
           可能导致 `locationPublisher` 长时间无数据推送，从而无法更新海拔相关统计。
         - Warning: 本方法**不会**主动请求定位权限或启动硬件，仅建立对 `locationPublisher` 的订阅；
           上层仍需确保 `CoreLocationKit` 已按需初始化并具有有效的定位权限。
         - Requires: 需要在工程中集成 `CoreLocationKit` 与 `NavigationCoreKit`，并保证
           `CoreLocationKit.shared.locationPublisher` 能够稳定推送 `CLLocation` 数据。
         - Remark: 该方法适用于“快速接入”的场景，例如公路导航、骑行记录等，不需要自行管理
           海拔处理管线的应用。
         - Note: 若对水平距离计算有更高精度要求（如基于轨迹纠偏、地图匹配等），
           建议**不要使用本默认管道**，而是在上层自行调用
           `ElevationManager.processAltitudeSample(rawAltitude:horizontalDistance:)` 进行更精细控制。
         - Precondition: `CoreLocationKit.shared` 已完成初始化，且应用的 Info.plist 中已配置
           必要的定位权限字段（如 `NSLocationWhenInUseUsageDescription` 等）。
         - Postcondition: 成功调用后，`ElevationManager` 将随位置更新自动计算：
           - 平滑海拔（`smoothedAltitude`）
           - 累计爬升（`elevationGain`）
           - 累计下降（`elevationLoss`）
           - 当前坡度（`gradient`，单位：百分比 %）
         
         # 使用示例
         ```swift
         // 在 App 启动或导航功能初始化时调用一次
         NavigationKit.startDefaultElevationPipeline()
         
         // 在 ViewModel 中订阅计算结果
         NavigationKit.elevationManager.$elevationGain
             .receive(on: RunLoop.main)
             .sink { gain in
                 print("当前累计爬升：\(gain) m")
             }
             .store(in: &subscriptions)
         ```
         
         - parameter 无: 本方法不接受任何参数，内部直接使用 `CoreLocationKit.shared.locationPublisher`。
         - Returns: 无返回值。
         - Throws: 不抛出错误，所有异常情况通过日志或上层状态观察处理。
         */
    public static func startDefaultElevationPipeline() {
        guard isElevationPipelineStarted == false else { return }
        isElevationPipelineStarted = true
        
        CoreLocationKit.shared.locationPublisher
            .compactMap { $0 }
            .sink { location in
                let altitude = location.altitude
                
                let distance: Double? = {
                    guard let last = lastLocation else { return nil }
                    let d = last.distance(from: location)
                    return d > 0 ? d : nil
                }()
                
                lastLocation = location
                
                elevationManager.processAltitudeSample(
                    rawAltitude: altitude,
                    horizontalDistance: distance
                )
            }
            .store(in: &subscriptions)
    }
    
    /**
         停止默认的海拔计算数据管道，并重置相关内部状态。
         
         - Important: 调用本方法后，`NavigationKit` 将不再从 `CoreLocationKit` 接收位置更新，
           默认海拔管道被完全关闭，直到再次调用 `startDefaultElevationPipeline()`。
         - Attention: 本方法会调用 `ElevationManager.reset()`（需要在 `ElevationManager` 中提供实现），
           用于清空平滑海拔、累计爬升/下降、坡度等内部统计，适合在“结束一次记录”或“重置状态”
           的场景中使用。
         - Bug: 若上层在仍需使用默认海拔管道时误调用本方法，将导致后续不再更新海拔与坡度数据，
           需要重新调用 `startDefaultElevationPipeline()` 以恢复。
         - Warning: 本方法会将 `subscriptions` 清空，意味着所有通过
           `startDefaultElevationPipeline()` 建立的内部订阅都会被释放，无法恢复先前的状态。
         - Requires: 应在确定当前不再需要默认海拔管道（例如停止轨迹记录、退出导航模式）时调用。
         - Remark: 该方法不会影响上层自行构建的其它订阅逻辑，仅作用于
           `NavigationKit` 内部维护的默认 Elevation 管道。
         - Note:
           - 如果你希望在不同“记录 Session”之间重用同一个 `ElevationManager` 实例，
             推荐在每次开始新 Session 前调用一次 `stopElevationPipeline()`，
             然后再调用 `startDefaultElevationPipeline()`，以保证统计数据干净。
           - 如果你不希望在停止时清空历史统计，可在自定义版本中移除对 `reset()` 的调用。
         - Precondition: `startDefaultElevationPipeline()` 曾被调用且当前处于已启动状态；
           否则本方法将安静返回，不做任何操作。
         - Postcondition:
           - 默认海拔数据管道被完全停止；
           - 内部订阅集合 `subscriptions` 被清空；
           - `lastLocation` 被重置为 `nil`；
           - `isElevationPipelineStarted` 被重置为 `false`；
           - `elevationManager` 的内部统计算法状态被 `reset()` 清空（取决于你的实现）。
         
         # 使用示例
         ```swift
         // 结束一次骑行 / 导航记录时：
         NavigationKit.stopElevationPipeline()
         
         // 再次开始新一段记录：
         NavigationKit.startDefaultElevationPipeline()
         ```
         
         - parameter 无: 本方法不接受任何参数。
         - Returns: 无返回值。
         - Throws: 不抛出错误。
         */
    public static func stopElevationPipeline() {
        guard isElevationPipelineStarted else { return }
        
        // 停止订阅
        subscriptions.removeAll()
        
        // 清除状态
        lastLocation = nil
        isElevationPipelineStarted = false
        
        // 重置 elevationManager（如果你希望 stop 就清零数据）
        elevationManager.reset()  // 我等下告诉你怎么搓 reset()
        
        print("Elevation pipeline stopped.")
    }
}

// MARK: - Speed
extension NavigationKit {

    /// 全局 SpeedManager
    public static let speedManager = SpeedManager()

    private static var speedSubscriptions: Set<AnyCancellable> = .init()
    private static var isSpeedPipelineRunning = false

    /**
     启动默认速度管线，自动将 CoreLocationKit 的原始速度（m/s）
     → 清洗 → 转换 → 滤波 → 死区处理 → speedKmh 输出。
     
     - Important: 调用一次即可，重复调用会被忽略。
     */
    public static func startDefaultSpeedPipeline() {
        guard isSpeedPipelineRunning == false else { return }
        isSpeedPipelineRunning = true

        CoreLocationKit.shared.speedPublisher
            .sink { rawSpeedMs in
                speedManager.bindSpeedPublisher(
                    Just(rawSpeedMs).eraseToAnyPublisher()
                )
            }
            .store(in: &speedSubscriptions)
    }

    /**
     停止速度管线，清理订阅并重置 SpeedManager 状态。
     */
    public static func stopSpeedPipeline() {
        guard isSpeedPipelineRunning else { return }

        speedSubscriptions.removeAll()
        speedManager.reset()
        isSpeedPipelineRunning = false

        print("Speed pipeline stopped.")
    }
}
