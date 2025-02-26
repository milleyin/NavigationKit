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

public final class CoreLocationKit: NSObject, CLLocationManagerDelegate {
    
    /// 自定义错误类型
    public enum LocationError: Swift.Error {
        /// 当前位置信息不可用
        case locationUnavailable
        /// 反向地理编码失败
        case geoEncodingFailed(Swift.Error)
        /// 没有找到匹配的地址
        case noAddressFound
    }
    
    /// 单例
    public static let shared = CoreLocationKit()
    
    /// `CLLocationManager` 实例（管理定位服务）
    public let locationManager: CLLocationManager
    
    /// 位置发布者
    public var locationPublisher: AnyPublisher<CLLocation?, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    /**
     请求一次当前位置，call一次，只会传一个值
     */
    public func requestCurrentLocation() {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.stopUpdatingLocation() // 停止持续更新，避免 `requestLocation()` 影响
            locationManager.requestLocation()
        }
    }

    
    /// 当前定位，持续发送定位数据
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
    
    /// 反向地理编码（获取地址）发布者
    public var addressPublisher: AnyPublisher<String, Swift.Error> {
        guard let location = currentLocation else {
            return Fail(error: LocationError.locationUnavailable).eraseToAnyPublisher()
        }
        
        return Future { promise in
            let geoCoder = CLGeocoder()
            geoCoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    promise(.failure(LocationError.geoEncodingFailed(error)))
                } else if let placemark = placemarks?.first {
                    let address = [
                        placemark.thoroughfare,
                        placemark.subThoroughfare,
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.postalCode,
                        placemark.country
                    ].compactMap { $0 }.joined(separator: ", ")
                    promise(.success(address))
                } else {
                    promise(.failure(LocationError.noAddressFound))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// 位置订阅对象
    private let locationSubject = CurrentValueSubject<CLLocation?, Never>(nil)
    
    /// 授权状态订阅对象（默认值 `notDetermined`，防止 `nil`）
//    private let authorizationStatusSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)
    private let authorizationStatusSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(
        CLLocationManager.authorizationStatus()
    )
    
    /// 方向订阅对象
    private let headingSubject = CurrentValueSubject<CLHeading?, Never>(nil)
    
    /// 错误信息订阅对象
    private let errorSubject = CurrentValueSubject<Swift.Error?, Never>(nil)
    
    /// 初始化方法
    public override init() {
        locationManager = CLLocationManager()
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 35
        
        // ✅ 立即同步授权状态
        authorizationStatusSubject.send(CLLocationManager.authorizationStatus())
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    /**
     设置是否允许后台位置更新
     
     - parameter allowed: 是否允许后台定位
     */
    public func allowBackgroundLocationUpdates(_ allowed: Bool) {
        locationManager.allowsBackgroundLocationUpdates = allowed
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationKit {
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        let clError = error as? CLError
        if clError?.code == .locationUnknown {
            print("位置暂时不可用，等待系统自动重试")
            return
        }
        errorSubject.send(error)
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatusSubject.send(status)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationSubject.send(locations.last)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headingSubject.send(newHeading)
    }
}

