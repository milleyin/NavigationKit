// The Swift Programming Language
// https://docs.swift.org/swift-book

//
//  LocationRepository.swift
//  Traveller
//
//  Created by Mille Yin on 2024/11/30.
//

import Foundation
import CoreLocation
import Combine

public final class CoreLocationKit: NSObject {
    
    /// 自訂錯誤類型。
    public enum LocationError: Swift.Error {
        /// 當前位置不可用。
        case locationUnavailable
        /// 反向地理編碼失敗。
        case geoEncodingFailed(Swift.Error)
        /// 沒有找到對應的地址。
        case noAddressFound
    }
    ///單例
    public static let shared: CoreLocationKit = .init()
    
    /// 定位座標的發布者。
    public var locationPublisher: AnyPublisher<CLLocation?, Never> {
        self.locationSubject.eraseToAnyPublisher()
    }
    
    /// 當前的定位座標。
    public var currentLocation: CLLocation? {
        self.locationSubject.value
    }
    
    /// 授權狀態的發布者。
    public var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus?, Never> {
        self.authorizationStatusSubject.eraseToAnyPublisher()
    }
    
    /// 當前的授權狀態。
    public var currentAuthorizationStatus: CLAuthorizationStatus? {
        self.authorizationStatusSubject.value
    }
    
    /// 方向的發布者。
    public var headingPublisher: AnyPublisher<CLHeading?, Never> {
        self.headingSubject.eraseToAnyPublisher()
    }
    
    /// 當前的方向。
    public var currentHeading: CLHeading? {
        self.headingSubject.value
    }
    
    /// 定位錯誤的發布者。
    public var errorPublisher: Swift.Error? {
        self.errorSubject.value
    }
    
    /// 反向地理編碼(取得地址)的發布者。
    public var addressPublisher: AnyPublisher<String, Swift.Error> {
        
        // 確認當前位置是否存在。
        guard let location = self.currentLocation else {
            return Fail(error: LocationError.locationUnavailable).eraseToAnyPublisher()
        }
        
        // 進行反向地理編碼。
        return Future { promise in
            let geoEncoder: CLGeocoder = .init()
            geoEncoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error: Swift.Error {
                    // 如果發生錯誤，則返回錯誤。
                    promise(.failure(LocationError.geoEncodingFailed(error)))
                } else if let placemark: CLPlacemark = placemarks?.first {
                    // 如果找到地標，組合地址字符串並返回。
                    let address: String = [
                        placemark.thoroughfare,
                        placemark.subThoroughfare,
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.postalCode,
                        placemark.country].compactMap { $0 }.joined(separator: ", ")
                    promise(.success(address))
                } else {
                    // 如果沒有找到地標，則返回錯誤。
                    promise(.failure(LocationError.noAddressFound))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    /// CLLocationManager 的實例，用於管理定位服務。
    private let locationManager: CLLocationManager = .init()
    
    /// 定位座標的訂閱對象。
    lazy private var locationSubject: CurrentValueSubject<CLLocation?, Never> = {
        .init(nil)
    }()
    
    /// 授權狀態的訂閱對象。
    lazy private var authorizationStatusSubject: CurrentValueSubject<CLAuthorizationStatus?, Never> = {
        .init(nil)
    }()
    
    /// 方向的訂閱對象。
    lazy private var headingSubject: CurrentValueSubject<CLHeading?, Never> = {
        .init(nil)
    }()
    
    /// 定位錯誤的訂閱對象。
    lazy private var errorSubject: CurrentValueSubject<Swift.Error?, Never> = {
        .init(nil)
    }()
    
    public override init() {
        super.init()
        // 設定定位管理器的參數並開始定位。
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = 35
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
        self.locationManager.startUpdatingHeading()
        self.locationManager.delegate = self
    }
    
    /**
     設定是否允許背景位置更新

     - parameter allowed: 是否允許背景位置更新
     */
    public func allowBackgroundLocationUpdates(_ allowed: Bool) {
        self.locationManager.allowsBackgroundLocationUpdates = allowed
    }
}

// MARK: - CLLocationManager Protocol

extension CoreLocationKit: CLLocationManagerDelegate {
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        self.errorSubject.send(error)
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorizationStatusSubject.send(status)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.locationSubject.send(locations.last)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.headingSubject.send(newHeading)
    }
}
