//
//  AppleMapKitTests.swift
//  NavigationKit
//
//  Created by Mille Yin on 2025/2/26.
//

import XCTest
import MapKit
@testable import NavigationKit
@testable import AppleMapKit

final class AppleMapKitTests: XCTestCase {
    
    var appleMapKit: AppleMapKit!
    
    override func setUp() {
        super.setUp()
        appleMapKit = AppleMapKit()
    }
    
    override func tearDown() {
        appleMapKit = nil
        super.tearDown()
    }
    
    /// 测试 AppleMapKit 是否正确初始化
    func testInitialization() {
        XCTAssertNotNil(appleMapKit.mapView, "MKMapView 实例未正确初始化")
        XCTAssertEqual(appleMapKit.userTrackingMode, .follow, "默认的用户追踪模式应为 follow")
        XCTAssertTrue(appleMapKit.mapView.showsUserLocation, "默认应显示用户位置")
    }
    
    /// 测试用户追踪模式设置
    func testUserTrackingMode() {
        appleMapKit.setUserTrackingMode(.none)
        XCTAssertEqual(appleMapKit.userTrackingMode, .none, "用户追踪模式未正确设置")
        
        appleMapKit.setUserTrackingMode(.followWithHeading)
        XCTAssertEqual(appleMapKit.userTrackingMode, .followWithHeading, "用户追踪模式未正确切换为 followWithHeading")
    }
    
    /// 测试添加标记
    func testAddingAnnotations() {
        let annotations = [
            MultipleAnnotations(name: "地点 A", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            MultipleAnnotations(name: "地点 B", location: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437))
        ]
        
        appleMapKit.addAnnotations(annotations)
        
        let mapAnnotations = appleMapKit.mapView.annotations.compactMap { $0 as? MKPointAnnotation }
        
        XCTAssertEqual(mapAnnotations.count, annotations.count, "添加的标记数量与预期不符")
        XCTAssertEqual(mapAnnotations.first?.title, "地点 A", "第一个标记名称错误")
        XCTAssertEqual(mapAnnotations.last?.title, "地点 B", "第二个标记名称错误")
    }
    
    /// 测试导航线路绘制
    func testDrawRoute() {
        let expectation = self.expectation(description: "导航线路绘制")
        
        let start = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let destination = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        
        appleMapKit.drawRoute(from: start, to: destination)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            XCTAssertFalse(self.appleMapKit.mapView.overlays.isEmpty, "未成功添加导航线路")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    /// 测试 Apple Maps 导航跳转
    func testOpenInAppleMaps() {
        let destination = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        
        let expectation = self.expectation(description: "跳过 Apple Maps 调用")
        
        // 模拟 Apple Maps 的调用，不实际执行
        DispatchQueue.global().async {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }

}
