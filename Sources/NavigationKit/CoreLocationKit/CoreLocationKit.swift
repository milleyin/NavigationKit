// The Swift Programming Language
// https://docs.swift.org/swift-book

//
//  CoreLocationKit.swift
//  Traveller
//
//  Created by Mille Yin on 2024/11/30.
//

import Foundation
import CoreLocation
import Combine
import UIKit

public final class CoreLocationKit: NSObject, CLLocationManagerDelegate {
    
    /// 单例
    public static let shared = CoreLocationKit()
    
    /**
     初始化 `CoreLocationKit` 单例，统一管理 `CoreLocation` 相关的定位服务。
     
     - Important: 该类为单例模式，不能手动初始化，必须通过 `CoreLocationKit.shared` 访问。
     - Attention: 仅在 `shared` 访问时初始化，所有定位服务在 `init` 时即开启。
     - Bug: 在 iOS 14 及以上，`requestWhenInUseAuthorization()` 可能需要在主线程调用，否则可能无效。
     - Warning: 请确保在 `Info.plist` 文件中添加 `NSLocationWhenInUseUsageDescription` 或 `NSLocationAlwaysUsageDescription`，否则 `requestWhenInUseAuthorization()` 将导致崩溃。
     - Requires: 适用于 `iOS 13.0+`，需要 `CoreLocation` 框架支持。
     - Remark: `desiredAccuracy` 影响耗电量，`distanceFilter` 影响更新频率，合理设置可优化性能。
     - Note: `distanceFilter = kCLDistanceFilterNone` 表示始终触发 `didUpdateLocations`，不建议长期使用。
     - Precondition: 必须确保 `locationServicesEnabled()` 返回 `true`，否则 `requestLocation()` 无效。
     - Postcondition: 在初始化完成后，将立即请求授权并开始定位。
     
     # 使用示例
     ```swift
     let locationKit = CoreLocationKit.shared
     locationKit.setLocationAccuracy(.nearestTenMeters, distanceFilter: 10)
     ```
     
     - parameter accuracy: 定位精度，默认为 `kCLLocationAccuracyBest`，建议根据业务需求调整。
     - parameter distanceFilter: 触发 `didUpdateLocations` 事件的最小移动距离，默认 `35` 米，适用于一般导航需求。
     */
    private init(accuracy: CLLocationAccuracy = kCLLocationAccuracyBest,
                 distanceFilter: CLLocationDistance = 35) {
        locationManager = CLLocationManager()
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = accuracy
        locationManager.distanceFilter = distanceFilter
        
        // ✅ 立即同步授权状态
        authorizationStatusSubject.send(CLLocationManager.authorizationStatus())
        
        // 请求定位授权
        if CLLocationManager.authorizationStatus() == .notDetermined {
            DispatchQueue.main.async {
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
        
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
    }
    
    
    
    /**
     `CLLocationManager` 实例，管理设备的定位服务。
     
     - Important: 该对象是 `CoreLocationKit` 的核心组件，负责所有的 GPS 数据更新和权限管理。
     - Warning: 请确保 `Info.plist` 文件中已正确配置 `NSLocationWhenInUseUsageDescription` 或 `NSLocationAlwaysUsageDescription`，否则调用 `requestLocation()` 可能导致崩溃。
     - Note: `CLLocationManager` 需要在主线程使用，否则部分 API 可能无法正常工作。
     */
    public let locationManager: CLLocationManager
    
    /**
     发布设备当前位置的 `Combine` 订阅者。
     
     - Important: 该 `Publisher` 会持续推送最新的位置信息。
     - Returns: `CLLocation?`，如果设备尚未提供位置信息，则返回 `nil`。
     - Note: 订阅该 `Publisher` 后，将接收 `CLLocationManager` 解析出的最新位置信息。
     - Example:
     ```swift
     locationKit.locationPublisher
     .sink { location in
     print("当前位置: \(String(describing: location))")
     }
     ```
     */
    public var locationPublisher: AnyPublisher<CLLocation?, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    /**
     获取当前设备的最新位置信息。
     
     - Important: 该属性 **仅返回最新缓存的位置数据**，不会主动触发新的定位请求。
     - Returns: `CLLocation?`，如果设备尚未提供位置信息，则返回 `nil`。
     - Note: 若希望主动请求最新位置，请使用 `requestCurrentLocation()` 方法。
     */
    public var currentLocation: CLLocation? {
        locationSubject.value
    }
    
    
    /// 授权状态发布者
    public var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }
    
    /// 当前授权状态
    public var currentAuthorizationStatus: CLAuthorizationStatus {
        authorizationStatusSubject.value
    }
    
    /// 方向数据发布者
    public var headingPublisher: AnyPublisher<CLHeading?, Never> {
        headingSubject.eraseToAnyPublisher()
    }
    
    /// 当前方向数据
    public var currentHeading: CLHeading? {
        headingSubject.value
    }
    
    /// 位置错误发布者
    public var errorPublisher: AnyPublisher<Swift.Error?, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    
    /// 位置订阅对象
    private let locationSubject = CurrentValueSubject<CLLocation?, Never>(nil)
    
    /// 授权状态订阅对象（默认值 `notDetermined`，防止 `nil`）
    private let authorizationStatusSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(
        CLLocationManager.authorizationStatus()
    )
    
    /// 方向订阅对象
    private let headingSubject = CurrentValueSubject<CLHeading?, Never>(nil)
    
    /// 错误信息订阅对象
    private let errorSubject = CurrentValueSubject<Swift.Error?, Never>(nil)
    
    /**
     允许开发者修改定位精度和距离过滤器
     
     - parameter accuracy: 定位精度（默认值 `kCLLocationAccuracyBest`）
     - parameter distance: 触发 `didUpdateLocations` 事件的最小移动距离（默认值 `35` 米）
     */
    public func setLocationAccuracy(_ accuracy: CLLocationAccuracy = kCLLocationAccuracyBest,
                                    distanceFilter distance: CLLocationDistance = 35) {
        locationManager.desiredAccuracy = accuracy
        locationManager.distanceFilter = distance
        
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            restartUpdatingLocation()
        }
    }
    
    
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationKit {
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        guard let clError = error as? CLError else {
            errorSubject.send(error)
            return
        }

        switch clError.code {
        case .locationUnknown:
            print("位置暂时不可用，等待系统自动重试")
        case .denied:
            errorSubject.send(LocationError.permissionDenied)
            print("⚠️ 用户拒绝了位置权限")
        case .network:
            errorSubject.send(LocationError.locationUnavailable)
            print("⚠️ 位置获取失败，可能是网络问题")
        case .headingFailure:
            print("⚠️ 方向数据不可用，可能是磁场干扰")
        default:
            errorSubject.send(error)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatusSubject.send(status)
        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lastLocation = locations.last else {
            print("⚠️ `didUpdateLocations` 收到空位置数组，可能是 CoreLocation 异常行为")
            return
        }
        locationSubject.send(lastLocation)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headingSubject.send(newHeading)
    }
}


//MARK: - 外部方法函数

extension CoreLocationKit {
    /**
     提供基于当前位置的反向地理编码（地址解析）功能，并通过 `Publisher` 返回地址字符串。
     
     - Important: 该 `Publisher` 仅在 `currentLocation` 可用时执行，
       若 `currentLocation == nil`，则直接返回 `LocationError.locationUnavailable`。
     - Attention: 反向地理编码是异步操作，调用 `addressPublisher` 不会立即返回地址，
       需要订阅 `Publisher` 以获取解析结果。
     - Warning: `CLGeocoder` 在短时间内调用过多次可能会被系统限制，影响解析功能。
     - Note: 返回的地址字符串格式如下：`街道, 门牌号, 城市, 省份, 邮政编码, 国家`。
     
     # 使用示例
     ```swift
     CoreLocationKit.shared.addressPublisher
         .sink(receiveCompletion: { completion in
             if case .failure(let error) = completion {
                 print("地址解析失败: \(error)")
             }
         }, receiveValue: { address in
             print("当前位置地址: \(address)")
         })
         .store(in: &subscriptions)
     ```
     
     - Returns: `AnyPublisher<String, Swift.Error>`，返回解析出的地址字符串，或错误。
     - Throws: `LocationError.locationUnavailable` 若 `currentLocation` 不可用。
     - Throws: `LocationError.geoEncodingFailed` 若 `CLGeocoder` 解析失败。
     - Throws: `LocationError.noAddressFound` 若未能找到匹配的地址。
     */
    public var addressPublisher: AnyPublisher<String, Swift.Error> {
        guard let location = currentLocation else {
            return Fail(error: LocationError.locationUnavailable).eraseToAnyPublisher()
        }
        
        return Future { promise in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    return promise(.failure(LocationError.geoEncodingFailed(originalError: error)))
                }
                guard let placemark = placemarks?.first else {
                    return promise(.failure(LocationError.noAddressFound))
                }
                
                let address = [
                    placemark.thoroughfare,
                    placemark.subThoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                
                promise(.success(address))
            }
        }
        .eraseToAnyPublisher()
    }
    
    /**
     请求一次当前位置。
     
     - Important: 该方法每次调用仅返回一个位置信息，适用于 **单次获取用户位置** 的场景。
     - Precondition: 设备定位服务必须已启用 (`CLLocationManager.locationServicesEnabled()` 返回 `true`)，否则不会触发回调。
     - Postcondition: 如果请求成功，`locationManager(_:didUpdateLocations:)` 将接收到最新的位置数据。
     - Throws: `LocationError.locationUnavailable` 如果定位服务未启用。
     - Example:
     ```swift
     CoreLocationKit.shared.requestCurrentLocation()
     ```
     */
    public func requestCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            errorSubject.send(LocationError.locationServicesDisabled)
            print("⚠️ 定位服务未启用，请在系统设置中打开")
            return
        }

        guard currentAuthorizationStatus == .authorizedWhenInUse || currentAuthorizationStatus == .authorizedAlways else {
            errorSubject.send(LocationError.permissionDenied)
            print("⚠️ 当前没有定位权限，无法执行 requestLocation()")
            return
        }

        locationManager.requestLocation()
    }
    
    /**
     设置是否允许后台位置更新。
     
     - Important: 仅当应用拥有 **`authorizedAlways`** 权限时才可启用后台定位。
     若当前授权状态不是 `authorizedAlways`，则不会修改 `allowsBackgroundLocationUpdates`，
     并会打印警告信息。
     - Attention: 启用后台定位可能会显著增加电量消耗，应仅在必要时使用。
     - Warning: 若未在 `Info.plist` 添加 `UIBackgroundModes` -> `location`，
     即使设置 `allowsBackgroundLocationUpdates = true`，后台定位仍不会生效。
     - Note:
     - iOS 13+ 需要用户在系统设置中 **手动开启** `Always Allow`。
     - 后台定位适用于 **步行导航、车辆跟踪、健身应用** 等场景。
     
     # 使用示例
     ```swift
     CoreLocationKit.shared.allowBackgroundLocationUpdates(true)
     ```
     
     - parameter allowed: 是否允许后台定位，`true` 开启，`false` 关闭。
     */
    public func allowBackgroundLocationUpdates(_ allowed: Bool) {
        guard currentAuthorizationStatus == .authorizedAlways else {
            print("⚠️ 请启用 `always` 授权，以允许后台更新位置")
            return
        }
        
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            print("⚠️ 设备禁用了后台刷新，后台定位功能可能无法生效")
            return
        }
        
        locationManager.allowsBackgroundLocationUpdates = allowed
        locationManager.pausesLocationUpdatesAutomatically = !allowed
        
        if allowed {
            print("✅ 后台定位已启用")
        } else {
            print("⏹️ 后台定位已关闭")
        }
    }

}

//MARK: - 内部方法
extension CoreLocationKit {
    ///重新获取定位数据
    private func restartUpdatingLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            print("⚠️ 定位服务未启用，无法重启 `startUpdatingLocation()`")
            return
        }
        locationManager.stopUpdatingLocation()
        locationManager.startUpdatingLocation()

        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        } else {
            print("⚠️ 设备不支持方向数据，跳过 `startUpdatingHeading()`")
        }
    }
}

//MARK: - 类型定义
extension CoreLocationKit {
    /// 自定义错误类型
    public enum LocationError: Swift.Error, LocalizedError {
        case locationUnavailable
        case locationServicesDisabled  // ✅ 定位服务未启用
        case permissionDenied          // ✅ 用户未授权定位
        case geoEncodingFailed(originalError: Swift.Error)
        case noAddressFound

        public var errorDescription: String? {
            switch self {
            case .locationUnavailable:
                return "当前位置信息不可用，请检查设备的定位权限或网络状态。"
            case .locationServicesDisabled:
                return "设备定位服务已关闭，请在系统设置中启用 GPS。"
            case .permissionDenied:
                return "应用没有访问位置信息的权限，请在设置中允许定位。"
            case .geoEncodingFailed(let originalError):
                return "反向地理编码失败: \(originalError.localizedDescription)"
            case .noAddressFound:
                return "未找到匹配的地址信息。"
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .locationUnavailable:
                return "请确保 GPS 已启用，并检查 App 的定位权限。"
            case .locationServicesDisabled:
                return "请打开系统的定位服务 (设置 -> 隐私 -> 定位服务)。"
            case .permissionDenied:
                return "请在 (设置 -> 隐私 -> 定位服务 -> 你的 App) 里启用访问权限。"
            case .geoEncodingFailed:
                return "请检查网络连接，并尝试重新请求。"
            case .noAddressFound:
                return "可能是偏远地区，尝试移动到其他位置。"
            }
        }
    }
}
