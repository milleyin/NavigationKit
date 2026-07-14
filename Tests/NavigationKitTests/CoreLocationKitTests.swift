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
            .sink { location in
                if abs(location.coordinate.latitude - 31.23) < 0.0001 {
                    expectation.fulfill()
                }
            }
            .store(in: &subscriptions)

        kit.handleDidUpdateLocations([mock])
        wait(for: [expectation], timeout: 1)
    }

    /**
     连续多次注入位置，currentLocation 应反映最新一次注入的值，而非停留在第一次——
     验证 locationSubject 是普通的「最新值覆盖」语义，不是仅记录首次的机制。此前测试
     只注入过一次，这条「后一次覆盖前一次」的基本行为从未被验证过。
     */
    func testDidUpdateLocations_multipleInjections_currentLocationReflectsLatest() {
        let kit = CoreLocationKit.shared
        let first = CLLocation(latitude: 10.0, longitude: 10.0)
        let second = CLLocation(latitude: 20.0, longitude: 20.0)

        kit.handleDidUpdateLocations([first])
        XCTAssertEqual(kit.currentLocation?.coordinate.latitude ?? 0, 10.0, accuracy: 0.0001)

        kit.handleDidUpdateLocations([second])
        XCTAssertEqual(kit.currentLocation?.coordinate.latitude ?? 0, 20.0, accuracy: 0.0001,
                       "第二次注入后应反映最新值，而非停留在第一次")
    }

    /**
     空位置数组不应更新 currentLocation、也不应崩溃——验证
     `guard let lastLocation = locations.last else { ...; return }` 这条防御分支
     被正确触发，且不会用空数组污染已有快照。
     */
    func testDidUpdateLocations_emptyArray_doesNotCrashAndDoesNotOverwriteSnapshot() {
        let kit = CoreLocationKit.shared
        let mock = CLLocation(latitude: 33.0, longitude: 44.0)
        kit.handleDidUpdateLocations([mock])
        XCTAssertEqual(kit.currentLocation?.coordinate.latitude ?? 0, 33.0, accuracy: 0.0001)

        // 空数组注入：不应崩溃，且不应覆盖已有快照
        kit.handleDidUpdateLocations([])
        XCTAssertEqual(kit.currentLocation?.coordinate.latitude ?? 0, 33.0, accuracy: 0.0001,
                       "空数组不应清空或改变已有快照")
    }

    /**
     两个独立订阅者同时订阅 locationPublisher()，同一次注入应被两者都收到——
     验证 A1 的订阅驱动机制支持多订阅者，不是只服务单一订阅者的隐含假设。
     此前所有 locationPublisher 相关测试都只用单订阅者，多订阅场景从未覆盖过。
     */
    func testLocationPublisher_multipleSubscribers_allReceiveSameInjectedValue() {
        let kit = CoreLocationKit.shared
        let expectationA = expectation(description: "订阅者A收到位置")
        let expectationB = expectation(description: "订阅者B收到位置")
        let mock = CLLocation(latitude: 12.34, longitude: 56.78)

        kit.locationPublisher()
            .compactMap { $0 }
            .sink { location in
                if abs(location.coordinate.latitude - 12.34) < 0.0001 {
                    expectationA.fulfill()
                }
            }
            .store(in: &subscriptions)

        kit.locationPublisher()
            .compactMap { $0 }
            .sink { location in
                if abs(location.coordinate.latitude - 12.34) < 0.0001 {
                    expectationB.fulfill()
                }
            }
            .store(in: &subscriptions)

        kit.handleDidUpdateLocations([mock])
        wait(for: [expectationA, expectationB], timeout: 1)
    }

    // MARK: - didChangeAuthorization 数据流（此前完全空白，补齐与 didUpdateLocations 对称的覆盖）

    /**
     手动以 mock 状态触发 didChangeAuthorization，验证 currentAuthorizationStatus 快照
     与 authorizationStatusPublisher 流均反映新值。与 didUpdateLocations 侧「快照 + 流」
     的验证是同一模式，补齐授权这一侧此前从未测过的空白。
     */
    func testDidChangeAuthorization_updatesCurrentStatusAndPublishesViaStream() {
        let kit = CoreLocationKit.shared
        let expectation = expectation(description: "authorizationStatusPublisher 推送新状态")

        kit.authorizationStatusPublisher
            .sink { status in
                if status == .denied {
                    expectation.fulfill()
                }
            }
            .store(in: &subscriptions)

        kit.handleDidChangeAuthorization(.denied)

        XCTAssertEqual(kit.currentAuthorizationStatus, .denied)
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Publisher 初始值契约

    #if os(iOS)
    /**
     headingPublisher 初始值应为 nil（CurrentValueSubject(nil)）。
     纯属初始状态契约，不依赖真实传感器。
     - Note: headingPublisher() 本身仅 iOS 可用（v1.7.0 起整体包进 #if os(iOS)），
       此测试随之仅在 iOS 编译目标下存在；macOS 目标下这个方法不存在，无需也无法测试。
     - Note: `CLHeading` 没有可供测试代码直接使用的公开构造器（与 `CLLocation` 不同），
       故本测试套件无法像 `didUpdateLocations` 那样注入一个非 nil 的 mock heading 值来
       验证「推送」行为——这里只能验证初始状态契约，`headingPublisher()` 是否真的在真机
       磁力计数据到来时正确推送，留给真机集成测试覆盖。
     */
    func testHeadingPublisher_initialValueIsNil() {
        let expectation = expectation(description: "headingPublisher 初始值")
        CoreLocationKit.shared.headingPublisher()
            .first()
            .sink { heading in
                // 注：CLHeading 无法被测试代码构造注入，本套件中 headingSubject 永远不会
                // 收到非 nil 值，故此断言不受其它测试执行顺序影响，恒定安全。
                XCTAssertNil(heading, "初始 heading 应为 nil")
                expectation.fulfill()
            }
            .store(in: &subscriptions)
        wait(for: [expectation], timeout: 1)
    }

    /**
     两个独立订阅者同时订阅 headingPublisher()，初始值均应为 nil——验证多订阅场景下
     每个订阅者都能独立收到当前值重放、互不干扰（对称于 locationPublisher 的多订阅者测试）。
     由于 CLHeading 无法被 mock 构造（见上一测试的说明），无法测试「多订阅者收到同一个
     非 nil 推送值」，退而覆盖「多订阅者各自正确收到初始重放」这一层，仍是此前完全
     没有覆盖过的场景。
     */
    func testHeadingPublisher_multipleSubscribers_bothReceiveInitialNil() {
        let expectationA = expectation(description: "订阅者A收到初始nil")
        let expectationB = expectation(description: "订阅者B收到初始nil")

        CoreLocationKit.shared.headingPublisher()
            .first()
            .sink { heading in
                XCTAssertNil(heading)
                expectationA.fulfill()
            }
            .store(in: &subscriptions)

        CoreLocationKit.shared.headingPublisher()
            .first()
            .sink { heading in
                XCTAssertNil(heading)
                expectationB.fulfill()
            }
            .store(in: &subscriptions)

        wait(for: [expectationA, expectationB], timeout: 1)
    }
    #endif
}
