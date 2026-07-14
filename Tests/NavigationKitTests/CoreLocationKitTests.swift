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

    override func tearDownWithError() throws {
        subscriptions.removeAll()
    }

    // MARK: - validatePreconditions（纯函数，前置条件判定）

    /**
     服务关闭时，无论授权如何，都应判定为 locationServicesDisabled。
     服务开关优先级高于授权状态。
     */
    func testValidatePreconditions_servicesDisabled_returnsServicesDisabled() {
        // .authorizedWhenInUse 是 iOS 专属，macOS 输入列表不含该 case
        #if os(iOS)
        let statuses: [CLAuthorizationStatus] = [.notDetermined, .denied, .restricted, .authorizedAlways, .authorizedWhenInUse]
        #elseif os(macOS)
        let statuses: [CLAuthorizationStatus] = [.notDetermined, .denied, .restricted, .authorizedAlways]
        #endif
        for status in statuses {
            let result = CoreLocationKit.validatePreconditions(servicesEnabled: false, status: status)
            guard case .locationServicesDisabled = result else {
                XCTFail("服务关闭 + 授权\(status.rawValue) 应返回 locationServicesDisabled，实际为 \(String(describing: result))")
                continue
            }
        }
    }

    /**
     服务开启但已拒绝 / 受限（denied / restricted）时，应判定为 permissionDenied。
     */
    func testValidatePreconditions_servicesEnabledButDeniedOrRestricted_returnsPermissionDenied() {
        let blocked: [CLAuthorizationStatus] = [.denied, .restricted]
        for status in blocked {
            let result = CoreLocationKit.validatePreconditions(servicesEnabled: true, status: status)
            guard case .permissionDenied = result else {
                XCTFail("服务开启 + 授权\(status.rawValue) 应返回 permissionDenied，实际为 \(String(describing: result))")
                continue
            }
        }
    }

    /**
     服务开启但授权尚未决定（notDetermined）时，应判定为 permissionNotDetermined，
     而非 permissionDenied——「尚未决定」与「已拒绝」语义不同（方案 1.5）。
     */
    func testValidatePreconditions_servicesEnabledButNotDetermined_returnsNotDetermined() {
        let result = CoreLocationKit.validatePreconditions(servicesEnabled: true, status: .notDetermined)
        guard case .permissionNotDetermined = result else {
            XCTFail("服务开启 + notDetermined 应返回 permissionNotDetermined，实际为 \(String(describing: result))")
            return
        }
    }

    /**
     服务开启且已授权时，应放行（返回 nil）。
     这是「授权白名单」的正向验证——防止再次出现授权判定收窄的 bug。
     白名单平台相关：iOS 含 whenInUse / always，macOS 仅 always。
     */
    func testValidatePreconditions_servicesEnabledAndAuthorized_returnsNil() {
#if os(iOS)
        let authorized: [CLAuthorizationStatus] = [.authorizedWhenInUse, .authorizedAlways]
#elseif os(macOS)
        let authorized: [CLAuthorizationStatus] = [.authorizedAlways]
#endif
        for status in authorized {
            let result = CoreLocationKit.validatePreconditions(servicesEnabled: true, status: status)
            XCTAssertNil(result,
                         "服务开启 + 授权\(status.rawValue) 应放行（返回 nil），实际为 \(String(describing: result))")
        }
    }

    // MARK: - LocationError（错误类型契约）

    /**
     所有 LocationError case 的 errorDescription 与 recoverySuggestion 均应非空，
     保证向用户呈现时不出现空文案。
     */
    func testLocationError_allCasesHaveDescriptions() {
        let dummy = NSError(domain: "test", code: -1)
        let cases: [CoreLocationKit.LocationError] = [
            .locationUnavailable,
            .locationServicesDisabled,
            .permissionDenied,
            .permissionNotDetermined,
            .geoEncodingFailed(originalError: dummy),
            .noAddressFound,
            .timeout
        ]
        for error in cases {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                           "\(error) 的 errorDescription 不应为空")
            XCTAssertFalse(error.recoverySuggestion?.isEmpty ?? true,
                           "\(error) 的 recoverySuggestion 不应为空")
        }
    }

    /**
     timeout 是本次重构新增的 case，单独确认其文案存在且语义正确。
     */
    func testLocationError_timeoutHasMeaningfulDescription() {
        let error = CoreLocationKit.LocationError.timeout
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("超时") ?? false,
                      "timeout 的描述应体现「超时」语义")
    }

    /**
     geoEncodingFailed 带的关联 originalError，应被正确编入 errorDescription 文案中，
     而不只是笼统提示——验证关联值真正被使用，不是摆设。
     */
    func testLocationError_geoEncodingFailed_includesOriginalErrorDescription() {
        let originalError = NSError(
            domain: "TestGeocodeDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "网络超时"]
        )
        let error = CoreLocationKit.LocationError.geoEncodingFailed(originalError: originalError)

        XCTAssertTrue(error.errorDescription?.contains("网络超时") ?? false,
                      "geoEncodingFailed 的描述应包含原始错误的具体信息，而非仅笼统提示")
    }

    // MARK: - didUpdateLocations 数据流（主实例 delegate，mock 触发，不依赖真实定位）

    /**
     手动以 mock 位置触发 didUpdateLocations，验证 currentLocation 快照被更新。
     不依赖真实定位——直接调用 internal delegate 处理方法注入数据。
     */
    func testDidUpdateLocations_updatesCurrentLocationSnapshot() {
        let kit = CoreLocationKit.shared
        let mock = CLLocation(latitude: 25.0, longitude: 121.0)

        kit.handleDidUpdateLocations([mock])

        XCTAssertEqual(kit.currentLocation?.coordinate.latitude ?? 0, 25.0, accuracy: 0.0001)
        XCTAssertEqual(kit.currentLocation?.coordinate.longitude ?? 0, 121.0, accuracy: 0.0001)
    }

    /**
     locationPublisher 应推送 didUpdateLocations 注入的位置。
     */
    func testDidUpdateLocations_publishesViaLocationPublisher() {
        let kit = CoreLocationKit.shared
        let expectation = expectation(description: "locationPublisher 推送注入的位置")
        let mock = CLLocation(latitude: 31.23, longitude: 121.47)
        
        kit.locationPublisher()
            .compactMap { $0 }
            .dropFirst(0)
            .sink { location in
                if abs(location.coordinate.latitude - 31.23) < 0.0001 {
                    expectation.fulfill()
                }
            }
            .store(in: &subscriptions)
        
        kit.handleDidUpdateLocations([mock])
        wait(for: [expectation], timeout: 1)
    }

//    /**
//     速度派生：speed >= 0 时 speedPublisher 应推送该速度值。
//     沿用既有 mock 触发范式，验证派生计算逻辑。
//     */
//    func testDidUpdateLocations_publishesSpeed() {
//        let kit = CoreLocationKit.shared
//        let expectation = expectation(description: "等待速度更新")
//
//        kit.speedPublisher
//            .dropFirst()
//            .sink { speed in
//                XCTAssertEqual(speed, 10.0, accuracy: 0.01)
//                expectation.fulfill()
//            }
//            .store(in: &subscriptions)
//
//        let mock = CLLocation(
//            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
//            altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
//            course: 0, speed: 10.0, timestamp: Date()
//        )
//        kit.handleDidUpdateLocations([mock])
//        wait(for: [expectation], timeout: 1)
//    }

//    /**
//     速度派生：speed < 0（无效）时应归零。
//     验证 `rawSpeed = speed >= 0 ? speed : 0` 这条逻辑。
//     */
//    func testDidUpdateLocations_negativeSpeedClampedToZero() {
//        let kit = CoreLocationKit.shared
//        // 先注入一个正速度，使后续负速度能形成可观测的变化
//        let warmUp = CLLocation(
//            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
//            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
//            course: 0, speed: 5.0, timestamp: Date()
//        )
//        kit.handleDidUpdateLocations([warmUp])
//
//        let expectation = expectation(description: "负速度应归零")
//        kit.speedPublisher
//            .dropFirst()
//            .sink { speed in
//                XCTAssertEqual(speed, 0.0, accuracy: 0.01, "无效负速度应被归零")
//                expectation.fulfill()
//            }
//            .store(in: &subscriptions)
//
//        let invalid = CLLocation(
//            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
//            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
//            course: 0, speed: -1.0, timestamp: Date()
//        )
//        kit.handleDidUpdateLocations([invalid])
//        wait(for: [expectation], timeout: 1)
//    }
//
//    /**
//     海拔派生：altitudePublisher 应推送注入位置的海拔。
//     */
//    func testDidUpdateLocations_publishesAltitude() {
//        let kit = CoreLocationKit.shared
//        let expectation = expectation(description: "等待海拔更新")
//
//        kit.altitudePublisher
//            .dropFirst()
//            .sink { altitude in
//                XCTAssertEqual(altitude, 123.45, accuracy: 0.01)
//                expectation.fulfill()
//            }
//            .store(in: &subscriptions)
//
//        let mock = CLLocation(
//            coordinate: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
//            altitude: 123.45, horizontalAccuracy: 5, verticalAccuracy: 5,
//            course: 0, speed: 0, timestamp: Date()
//        )
//        kit.handleDidUpdateLocations([mock])
//        wait(for: [expectation], timeout: 1)
//    }

    // MARK: - Publisher 初始值契约

    #if os(iOS)
        /**
         headingPublisher 初始值应为 nil（CurrentValueSubject(nil)）。
         纯属初始状态契约，不依赖真实传感器。
         - Note: headingPublisher() 本身仅 iOS 可用（v1.7.0 起整体包进 #if os(iOS)），
           此测试随之仅在 iOS 编译目标下存在；macOS 目标下这个方法不存在，无需也无法测试。
         */
        func testHeadingPublisher_initialValueIsNil() {
            let expectation = expectation(description: "headingPublisher 初始值")
            CoreLocationKit.shared.headingPublisher()
                .first()
                .sink { heading in
                    // 注：若此前测试已注入过 heading，此断言可能受单例状态影响；
                    // heading 在本套件中无注入路径，故初始仍应为 nil。
                    XCTAssertNil(heading, "初始 heading 应为 nil")
                    expectation.fulfill()
                }
                .store(in: &subscriptions)
            wait(for: [expectation], timeout: 1)
        }
    #endif
}
