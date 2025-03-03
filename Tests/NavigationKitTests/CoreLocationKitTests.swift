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
                XCTAssertTrue(status == .authorizedWhenInUse || status == .authorizedAlways || status == .denied || status == .notDetermined)
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
    
    /// ✅ 测试方向（Heading）数据
    func testHeadingUpdates() {
        let expectation = expectation(description: "等待方向数据更新")

        CoreLocationKit.shared.headingPublisher
            .dropFirst()
            .sink { heading in
                XCTAssertNotNil(heading)
                print("方向数据: \(heading?.trueHeading ?? 0)°")
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        
        wait(for: [expectation], timeout: 10)
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
}




