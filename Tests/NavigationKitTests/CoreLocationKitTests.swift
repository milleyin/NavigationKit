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
    
    var coreLocationKit: CoreLocationKit!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        coreLocationKit = CoreLocationKit.shared
        cancellables = []
    }
    
    override func tearDown() {
        coreLocationKit = nil
        cancellables = nil
        super.tearDown()
    }
    
    /// 测试 CoreLocationKit 是否正确初始化
    func testInitialization() {
        XCTAssertNotNil(coreLocationKit, "CoreLocationKit 实例未正确初始化")
        XCTAssertNotNil(coreLocationKit.locationManager, "locationManager 应该存在")
    }
    
    /// 测试获取授权状态（防止多次调用 fulfill）
    func testAuthorizationStatus() {
        let expectation = self.expectation(description: "监听授权状态")
        expectation.assertForOverFulfill = false  // ✅ 防止多次 fulfill 抛出异常

        coreLocationKit.authorizationStatusPublisher
            .removeDuplicates()  // ✅ 避免多次触发
            .sink { status in
                if status != .notDetermined {  // ✅ 仅当状态改变时触发 fulfill
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        coreLocationKit.locationManager.delegate?.locationManager?(
            coreLocationKit.locationManager,
            didChangeAuthorization: .authorizedWhenInUse
        )

        waitForExpectations(timeout: 2, handler: nil)
    }
    
    /// 测试定位更新
    func testLocationUpdate() {
        let expectation = self.expectation(description: "监听位置更新")

        coreLocationKit.locationPublisher
            .compactMap { $0 }
            .sink { location in
                XCTAssertEqual(location.coordinate.latitude, 37.7749, "纬度错误")
                XCTAssertEqual(location.coordinate.longitude, -122.4194, "经度错误")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let testLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        coreLocationKit.locationManager.delegate?.locationManager?(
            coreLocationKit.locationManager,
            didUpdateLocations: [testLocation]
        )

        waitForExpectations(timeout: 2, handler: nil)
    }

}





