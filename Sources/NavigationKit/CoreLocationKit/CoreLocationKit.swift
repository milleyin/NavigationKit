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
#if os(iOS)
import UIKit
#endif

public final class CoreLocationKit: NSObject, ObservableObject, CLLocationManagerDelegate {
    
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
        
        #if os(iOS)
        // iOS: 继续使用静态方法
        authorizationStatusSubject.send(CLLocationManager.authorizationStatus())
        
        if CLLocationManager.authorizationStatus() == .notDetermined {
            DispatchQueue.main.async {
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
        
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        #elseif os(macOS)
        // macOS: 必须用实例属性
        authorizationStatusSubject.send(locationManager.authorizationStatus)
        
        if locationManager.authorizationStatus == .notDetermined {
            DispatchQueue.main.async {
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
        
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        #endif
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
    
    /// 速度发布者（单位：m/s）
    public var speedPublisher: AnyPublisher<CLLocationSpeed, Never> {
        speedSubject.eraseToAnyPublisher()
    }
    /// 海拔高度发布者（单位：米）
    public var altitudePublisher: AnyPublisher<CLLocationDistance, Never> {
        altitudeSubject.eraseToAnyPublisher()
    }

    /// 当前方向数据
    public var currentHeading: CLHeading? {
        headingSubject.value
    }
    /// 当前海拔（米）
    public var currentAltitude: CLLocationDistance {
        altitudeSubject.value
    }
    /// 位置错误发布者
    public var errorPublisher: AnyPublisher<Swift.Error?, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    
    /// 位置订阅对象
    private let locationSubject = CurrentValueSubject<CLLocation?, Never>(nil)
    /**
    进行中的单次定位请求。
       requestCurrentLocation(timeout:)` 每次创建一个 `SingleLocationRequest` 并暂存于此，以在请求存续期间维持强引用（否则 delegate 回调不触发）；请求终结后自动移除。
    */
    private var pendingSingleRequests = Set<SingleLocationRequest>()
    
    /// 授权状态订阅对象（默认值 `notDetermined`，防止 `nil`）
    private let authorizationStatusSubject: CurrentValueSubject<CLAuthorizationStatus, Never> = {
        #if os(iOS)
        return CurrentValueSubject(CLLocationManager.authorizationStatus())
        #elseif os(macOS)
        return CurrentValueSubject(CLLocationManager().authorizationStatus)
        #endif
    }()
    /// 内部长期订阅容器：持有「授权状态驱动持续更新启停」等跟随单例生命周期的订阅
    private var subscriptions = Set<AnyCancellable>()
    /// 方向订阅对象
    private let headingSubject = CurrentValueSubject<CLHeading?, Never>(nil)
    /// 速度订阅对象（m/s）
    private let speedSubject = CurrentValueSubject<CLLocationSpeed, Never>(0)
    /// 内部海拔订阅对象
    private let altitudeSubject = CurrentValueSubject<CLLocationDistance, Never>(0)
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
        
        #if os(iOS)
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            restartUpdatingLocation()
        }
        #elseif os(macOS)
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways {
            restartUpdatingLocation()
        }
        #endif
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
        
        #if os(iOS)
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
        }
        
        #elseif os(macOS)
        if status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
        #endif
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lastLocation = locations.last else {
            print("⚠️ `didUpdateLocations` 收到空位置数组，可能是 CoreLocation 异常行为")
            return
        }
        print("✅ 成功获取位置: \(lastLocation.coordinate.latitude), \(lastLocation.coordinate.longitude)")
        locationSubject.send(lastLocation)
        
        // 原生速度（m/s）
        let rawSpeed = lastLocation.speed >= 0 ? lastLocation.speed : 0
        speedSubject.send(rawSpeed)
        
        // 海拔（米）
        altitudeSubject.send(lastLocation.altitude)
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
     
     主动触发定位硬件获取**一个新的**位置，与「读取缓存快照」（`currentLocation`）和「持续订阅」（`locationPublisher`）是三种不同语义，互不替代。
     
     实现要点：
     - **授权状态异步**：不在调用瞬间硬读授权状态（进程启动有「空窗期」，瞬时读会得到假 `notDetermined`），而是订阅授权状态、等其「就绪」（非 `notDetermined`）后再决策；尚未决定时先经收敛入口触发授权请求。已授权时因 `CurrentValueSubject` 重放当前值而零额外等待。
     - 使用一个**独立的** `CLLocationManager`（封装在 `SingleLocationRequest` 内）执行本次请求，与主实例的持续定位完全隔离，不会干扰正在订阅 `locationPublisher` 的使用者。
     - 取得首个有效位置后立即停止该独立 manager，信守「取一次、省电」的语义。
     - 不自动重试。
     
     - Parameter timeout: 超时时限（秒），默认 10。涵盖「等待授权就绪」与「单次定位测量」——任一阶段超时均以 `LocationError.timeout` 失败。常态（已授权）下等待就绪近乎瞬时，timeout 实际作用于测量阶段。
     - Returns: 发出**单个** `CLLocation` 后立即完成的 publisher；失败时发出错误。
     - Note: 是否重试由调用方决定——可对返回值施加 `.retry(_:)`。SDK 不内置重试。
     - Note: 若只需「此刻的缓存位置、可能为 nil」，应改用 `currentLocation` 属性，零等待零耗电；若需持续跟踪，应订阅 `locationPublisher`。
     - Example:
        ```swift
            CoreLocationKit.shared.requestCurrentLocation()
                .sink { completion in
                    if case .failure(let error) = completion { print(error) }
                } receiveValue: { location in
                    print("取得位置: \(location)")
                }
                .store(in: &subscriptions)
        ```
     */
    public func requestCurrentLocation(timeout: TimeInterval = 10) -> AnyPublisher<CLLocation, Swift.Error> {
        // 步骤1：服务总开关无空窗期，可瞬时判断；关闭则直接失败，不必进入等待
        guard CLLocationManager.locationServicesEnabled() else {
            return Fail(error: LocationError.locationServicesDisabled).eraseToAnyPublisher()
        }
        
        // 步骤2：尚未决定授权时经收敛入口发起授权请求；已决定则为 no-op
        requestAuthorizationIfNeeded()
        
        // 步骤3~5：订阅授权状态，等其「就绪」（非 notDetermined）后再决策。
        // 不再瞬时读 status —— 授权状态是异步的，启动空窗期内瞬时读会得到假 notDetermined。
        // authorizationStatusSubject 是 CurrentValueSubject，订阅即重放当前值：已授权时当前值即真值，
        // filter 立即放行、零额外等待；空窗期当前值为 notDetermined，被滤掉，待 didChangeAuthorization 送真值后再放行。
        return authorizationStatusPublisher
            .filter { $0 != .notDetermined }
            .first()
            .setFailureType(to: Swift.Error.self)            // Never → Error，以承接下方 timeout 与 flatMap 的错误流
            .timeout(
                .seconds(timeout),
                scheduler: DispatchQueue.main,
                customError: { LocationError.timeout }        // 等就绪超时：回调迟迟不到则失败，不无限挂起
            )
            .flatMap { [weak self] status -> AnyPublisher<CLLocation, Swift.Error> in
                guard let self = self else {
                    return Fail(error: LocationError.locationUnavailable).eraseToAnyPublisher()
                }
                // 服务总开关已在步骤1校验，此处仅判授权白名单（denied / restricted → permissionDenied）
                if let blocker = Self.validatePreconditions(servicesEnabled: true, status: status) {
                    return Fail(error: blocker).eraseToAnyPublisher()
                }
                // 就绪且在白名单 → 发起单次定位；测量阶段超时由 SingleLocationRequest 内部计时负责
                return self.makeSingleLocationRequest(timeout: timeout)
            }
            .eraseToAnyPublisher()
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
#if os(iOS)
        guard CLLocationManager.authorizationStatus() == .authorizedAlways else {
            print("⚠️ 请启用 `Always` 授权，以允许后台更新位置")
            return
        }
        
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            print("⚠️ 设备禁用了后台刷新，后台定位功能可能无法生效")
            return
        }
        
        locationManager.allowsBackgroundLocationUpdates = allowed
        locationManager.pausesLocationUpdatesAutomatically = !allowed
        
        if allowed {
            print("后台定位已启用")
        } else {
            print("后台定位已关闭")
        }
#else
        print("⚠️ macOS 不支持后台定位更新功能")
#endif
    }
}

//MARK: - 前置条件校验
extension CoreLocationKit {
    /**
     校验发起定位请求的前置条件（纯函数）。
     
     不读取任何系统状态，仅依据传入的参数做判定，因此结果完全确定、可独立单元测试，并被 `requestCurrentLocation(timeout:)`、`currentLocationReadiness()` 共用，确保「授权白名单」只在此处定义一份，不会在多处各写一份而走样。
     
     - Parameters:
     - servicesEnabled: 设备定位服务总开关是否开启。
     - status: 当前定位授权状态。
     - Returns: 不满足前置条件时返回对应的 `LocationError`；满足则返回 `nil`（可放行）。
     - Note: 授权白名单是**平台相关**的——iOS 接受 `.authorizedWhenInUse` 与 `.authorizedAlways`；macOS 无 `.authorizedWhenInUse` 这一 case，仅接受 `.authorizedAlways`。
     */
    static func validatePreconditions(servicesEnabled: Bool, status: CLAuthorizationStatus) -> LocationError? {
        guard servicesEnabled else { return .locationServicesDisabled }
        
        // 授权白名单按平台区分：.authorizedWhenInUse 是 iOS 专属 case，macOS SDK 中不存在
#if os(iOS)
        let isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
#elseif os(macOS)
        let isAuthorized = (status == .authorizedAlways)
#endif
        
        guard isAuthorized else { return .permissionDenied }
        return nil
    }
    
    /**
     查询当前是否满足发起定位请求的条件。
     
     读取系统实时的服务开关与授权状态，内部复用纯函数 `validatePreconditions(servicesEnabled:status:)`。供应用层在发起定位前做预检——例如据返回的错误提示用户「去开启定位服务」或「去授权」。
     
     - Returns: 满足条件返回 `nil`；否则返回阻碍发起的具体 `LocationError`。
     - Note: 仅做「能否发起」的判定，不触发任何定位请求。
     */
    public func currentLocationReadiness() -> LocationError? {
#if os(iOS)
        let status = CLLocationManager.authorizationStatus()
#elseif os(macOS)
        let status = locationManager.authorizationStatus
#endif
        return Self.validatePreconditions(
            servicesEnabled: CLLocationManager.locationServicesEnabled(),
            status: status
        )
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
    
    /**
     在授权状态尚未决定（`notDetermined`）时发起一次定位授权请求。
     
     - Note: 判断依据取自 `currentAuthorizationStatus`（即 `authorizationStatusSubject` 当前值）
     - Note: 可安全重复调用——系统对已决定授权的 App 会忽略重复的 `requestWhenInUseAuthorization()`（不弹框、无副作用）；仅在 `notDetermined` 时正常弹出授权框。
     - Important: `requestWhenInUseAuthorization()` 要求在主线程调用，故派发至主队列。
     */
    private func requestAuthorizationIfNeeded() {
        // 仅在「尚未决定」时请求；已授权 / 已拒绝状态下无需打扰
        guard currentAuthorizationStatus == .notDetermined else { return }
        // requestWhenInUseAuthorization 要求主线程调用
        DispatchQueue.main.async {
            self.locationManager.requestWhenInUseAuthorization()
        }
    }
    
    /**
     创建并发起一次独立的单次定位请求，桥接为 Combine publisher。
     
     封装 `SingleLocationRequest` 的生命周期：请求存续期间由 `pendingSingleRequests` 维持强引用，终结后自动解除。仅由 `requestCurrentLocation(timeout:)` 在授权就绪后调用。
     
     - Parameter timeout: 单次测量的超时时限（秒），透传给 `SingleLocationRequest` 内部计时。
     - Returns: 发出单个 `CLLocation` 后完成的 publisher；失败时发出错误。
     */
    private func makeSingleLocationRequest(timeout: TimeInterval) -> AnyPublisher<CLLocation, Swift.Error> {
        Future<CLLocation, Swift.Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(LocationError.locationUnavailable))
                return
            }
            let request = SingleLocationRequest(
                desiredAccuracy: self.locationManager.desiredAccuracy,
                timeout: timeout,
                completion: { result in
                    promise(result)
                },
                onFinish: { [weak self] finished in
                    // 终结时由 SingleLocationRequest 回传自身，据此解除持有——
                    // 不再用外部 var 捕获，从根上消除「实例 → onFinish → 捕获变量 → 实例」的自持有环
                    self?.pendingSingleRequests.remove(finished)
                }
            )
            // 请求存续期间维持强引用，否则方法返回后实例释放、delegate 回调永不触发
            self.pendingSingleRequests.insert(request)
        }
        .eraseToAnyPublisher()
    }
}

//MARK: - 类型定义
extension CoreLocationKit {
    /// 自定义错误类型
    public enum LocationError: Swift.Error, LocalizedError {
        case locationUnavailable
        //定位服务未启用
        case locationServicesDisabled
        //用户未授权定位
        case permissionDenied
        case geoEncodingFailed(originalError: Swift.Error)
        case noAddressFound
        /// 单次定位请求在指定时限内未取得位置
        case timeout

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
            case .timeout:
                return "单次定位请求超时，未能在限定时间内取得位置。"
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
            case .timeout:
                return "定位环境可能暂时不佳（如室内或无网络定位）。可稍后重试，或改用持续订阅 locationPublisher"
            }
        }
    }
}

// MARK: - 单次定位请求
 
/**
 一次性定位请求的执行器。
 
 用于支撑 `CoreLocationKit.requestCurrentLocation(timeout:)` 的「请求一次」语义。每次单次请求都创建一个独立实例，持有自己**独立的** `CLLocationManager`，与 `CoreLocationKit` 主实例的持续定位（`locationPublisher` 背后的 manager）完全隔离。
 
 - Important: 采用独立 manager 的根本原因——单次请求拿到位置后需要 `stop`，若复用主 manager 的 `stopUpdatingLocation()`，会**误停主实例的持续更新**，掐断其它正在订阅 `locationPublisher` 的使用者。独立实例彻底规避此冲突。
 - Important: 本类必须在请求存续期间被强引用持有（由 `CoreLocationKit` 用集合持有），否则方法返回后实例即释放，`CLLocationManagerDelegate` 回调永不触发。请求终结（成功 / 失败 / 超时）后通过 `onFinish` 回调通知持有者解除持有。
 - Note: macOS 上单次 `requestLocation()` 在弱定位环境下常直接回 `locationUnknown` 而放弃，故此处统一采用 `startUpdatingLocation()` 持续测量、**取得首个有效位置后立即停止**的策略，既信守「取一次」的省电语义，又比 `requestLocation()` 更稳。
 - Warning: 不在此处重试。重试与否属调用方的业务策略 —— 调用方可对返回的 publisher 施加 `.retry(_:)`。SDK 只负责「请求一次，给结果或给错误」。
 */
private final class SingleLocationRequest: NSObject, CLLocationManagerDelegate {
 
    /// 本次请求独享的定位管理器，与主实例隔离
    private let manager = CLLocationManager()
    
    /// 结果回调：成功传出位置，失败传出错误。仅会被调用一次
    private let completion: (Result<CLLocation, Swift.Error>) -> Void
 
    /// 请求终结后回调，把「本次请求实例自身」交还持有者以便精确解除强引用（避免实例泄漏）
    private let onFinish: (SingleLocationRequest) -> Void
 
    /// 超时计时器；取得结果或失败时取消
    private var timeoutTimer: Timer?
 
    /// 防止结果回调被多次触发（首个位置、超时、失败之间存在竞态）
    private var hasCompleted = false
 
    /**
     创建并立即发起一次定位请求。
 
     - Parameters:
       - desiredAccuracy: 期望精度，沿用主实例的精度设置以保持一致。
       - timeout: 超时时限（秒）。超时后以 `LocationError.timeout` 失败，不重试。
       - completion: 唯一结果回调（成功位置 / 失败错误）。
       - onFinish: 请求终结后调用，回传本实例自身，供持有者精确解除强引用。
     */
    init(desiredAccuracy: CLLocationAccuracy, timeout: TimeInterval, completion: @escaping (Result<CLLocation, Swift.Error>) -> Void, onFinish: @escaping (SingleLocationRequest) -> Void) {
        self.completion = completion
        self.onFinish = onFinish
        super.init()
 
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
 
        // 启动持续测量；取得首个有效位置后在 didUpdateLocations 内立即停止
        manager.startUpdatingLocation()
 
        // 启动超时计时器：到时仍无结果则以 timeout 失败
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.finish(.failure(CoreLocationKit.LocationError.timeout))
        }
    }
 
    /**
     终结本次请求：停止定位、取消计时、回调结果、通知持有者解除持有。
 
     - Parameter result: 本次请求的最终结果。
     - Note: 通过 `hasCompleted` 保证整个生命周期内只终结一次。
     */
    private func finish(_ result: Result<CLLocation, Swift.Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
 
        manager.stopUpdatingLocation()   // 仅停止本实例的独立 manager，不影响主实例
        timeoutTimer?.invalidate()
        timeoutTimer = nil
 
        completion(result)
        onFinish(self)
    }
 
    // MARK: CLLocationManagerDelegate
 
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 取首个有效位置即终结（满足「取一次」语义）
        guard let location = locations.first else { return }
        finish(.success(location))
    }
 
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        // locationUnknown 表示「暂时未知、系统仍会重试」——单次语义下不等待，交由超时统一兜底
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        finish(.failure(error))
    }
}
