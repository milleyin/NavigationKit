//
//  CoreLocationKitTests.swift
//  
//
//  Created by Mille Yin on 2025/2/15.
//

import XCTest
import CoreLocation
import Combine
@testable import CoreLocationKit

final class CoreLocationKitTests: XCTestCase {
    
    private var subscriptions = Set<AnyCancellable>()
    
    override func setUpWithError() throws {
        super.setUp()
        CoreLocationKit.shared.requestCurrentLocation() // 启动定位
        
    }
    
    override func tearDownWithError() throws {
        subscriptions.removeAll()
    }
    
    /// ✅ 测试授权状态变化
    func testAuthorizationStatusUpdates() {
        let expectation = expectation(description: "等待授权状态更新")
        
        CoreLocationKit.shared.authorizationStatusPublisher
            .sink { status in
#if os(iOS)
                XCTAssertTrue(
                    status == .authorizedWhenInUse ||
                    status == .authorizedAlways ||
                    status == .denied ||
                    status == .restricted ||
                    status == .notDetermined
                )
#elseif os(macOS)
                XCTAssertTrue(
                    status == .authorizedAlways ||
                    status == .denied ||
                    status == .restricted ||
                    status == .notDetermined
                )
#endif
                
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        CoreLocationKit.shared.requestCurrentLocation()
        
        wait(for: [expectation], timeout: 5)
    }
    
    /// ✅ 测试单次获取位置
    func testRequestCurrentLocation() {
        let expectation = expectation(description: "等待位置更新")
        
        CoreLocationKit.shared.locationPublisher
            .compactMap { $0 }
            .sink { location in
                XCTAssertNotNil(location)
                print("获取到位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        CoreLocationKit.shared.requestCurrentLocation()
        
        wait(for: [expectation], timeout: 10)
    }
    
    /// ✅ 测试持续位置更新
    func testContinuousLocationUpdates() {
        let expectation = expectation(description: "等待位置更新推送")
        
        let cancellable = CoreLocationKit.shared.locationPublisher
            .compactMap { $0 }
            .first()
            .sink { location in
                XCTAssertNotNil(location)
                print("位置更新: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                expectation.fulfill()
            }
        
        wait(for: [expectation], timeout: 10)
    }
    
    /// ✅ 测试 headingPublisher 初始值行为（不依赖真实传感器）
    func testHeadingPublisherInitialValueIsNil() {
        let expectation = expectation(description: "订阅 headingPublisher 得到初始值")
        
        CoreLocationKit.shared.headingPublisher
            .sink { heading in
                // 初始值应该是 nil（CurrentValueSubject(nil)）
                XCTAssertNil(heading, "初始 heading 应为 nil")
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        wait(for: [expectation], timeout: 1)
    }
    
    /// ✅ 测试后台定位控制
    func testBackgroundLocationUpdates() {
        // 检查当前授权状态
        let status = CoreLocationKit.shared.currentAuthorizationStatus
        
        guard status == .authorizedAlways else {
            print("⚠️ 无法测试后台定位：当前授权状态为 \(status)，需要 `Always` 权限")
            return
        }
        
        CoreLocationKit.shared.allowBackgroundLocationUpdates(true)
        XCTAssertTrue(CoreLocationKit.shared.locationManager.allowsBackgroundLocationUpdates)
        
        CoreLocationKit.shared.allowBackgroundLocationUpdates(false)
        XCTAssertFalse(CoreLocationKit.shared.locationManager.allowsBackgroundLocationUpdates)
    }
    
    /// ✅ 测试反向地理编码
    func testReverseGeocoding() {
        let expectation = expectation(description: "等待地址解析完成")
        
        CoreLocationKit.shared.addressPublisher
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("地址解析失败: \(error.localizedDescription)")
                }
            }, receiveValue: { address in
                XCTAssertFalse(address.isEmpty)
                print("解析成功: \(address)")
                expectation.fulfill()
            })
            .store(in: &subscriptions)
        
        wait(for: [expectation], timeout: 10)
    }
    
    /// ✅ 测试 speedPublisher 是否正确收到速度更新
    func testSpeedPublisherReceivesCorrectSpeed() {
        let expectation = expectation(description: "等待速度更新")
        
        let kit = CoreLocationKit.shared
        
        // 订阅速度变化
        kit.speedPublisher
            .dropFirst()   // 避免初始 0 立刻触发
            .sink { speed in
                XCTAssertEqual(speed, 10.0, accuracy: 0.01)
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        // 构造模拟坐标点（速度 10 m/s）
        let mockLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 10.0,       // ⚡ 关键：模拟速度
            timestamp: Date()
        )
        
        // 手动触发 delegate
        kit.locationManager(kit.locationManager, didUpdateLocations: [mockLocation])
        
        wait(for: [expectation], timeout: 1)
    }
    
    /// 测试 altitudePublisher 是否收到正确海拔
    func testAltitudePublisherReceivesAltitude() {
        let expectation = expectation(description: "等待海拔更新")
        
        let kit = CoreLocationKit.shared
        
        // 订阅海拔变化
        kit.altitudePublisher
            .dropFirst() // 跳过默认值 0
            .sink { altitude in
                XCTAssertEqual(altitude, 123.45, accuracy: 0.01)
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        // 构造模拟定位点（海拔 123.45 米）
        let mockLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
            altitude: 123.45,           // ⭐ 关键：模拟海拔
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 0,
            timestamp: Date()
        )
        
        // 触发 delegate，让 CoreLocationKit 接收到这个模拟点
        kit.locationManager(kit.locationManager,
                            didUpdateLocations: [mockLocation])
        
        wait(for: [expectation], timeout: 1)
    }
}




