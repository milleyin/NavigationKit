//
//  File.swift
//  NavigationKit
//
//  Created by mille on 2025/12/6.
//

import XCTest
import Combine
@testable import NavigationCoreKit

final class SpeedManagerTests: XCTestCase {
    
    private var subscriptions = Set<AnyCancellable>()
    private var manager: SpeedManager!
    
    override func setUp() {
        super.setUp()
        manager = SpeedManager(smoothingAlpha: 0.2, deadZoneThreshold: 1.0)
    }
    
    override func tearDown() {
        subscriptions.removeAll()
        manager = nil
        super.tearDown()
    }
    
    
    // MARK: - 1️⃣ 测试原始速度（m/s） → km/h 转换是否正确
    
    func testLowPassFilteringSingleSample() {
        let exp = expectation(description: "低通滤波是否正确")

        // m/s = 10 → 36 km/h → 低通后 ≈ 7.2
        let input = Just(10.0).eraseToAnyPublisher()

        manager.bindSpeedPublisher(input)

        manager.$speedKmh
            .dropFirst()
            .sink { speed in
                XCTAssertEqual(speed, 7.2, accuracy: 0.01)
                exp.fulfill()
            }
            .store(in: &subscriptions)

        wait(for: [exp], timeout: 1)
    }
    
    
    // MARK: - 2️⃣ 测试低通滤波（平滑处理）
    
    func testLowPassFiltering() {
        let exp = expectation(description: "低通滤波是否正确")
        
        // 输入速度：第一次 0 m/s，第二次 10 m/s
        // km/h = 0 → 36
        // 低通公式: filtered = prev + α * (new - prev)
        // prev = 0, new = 36, α = 0.2 → 7.2 km/h
        
        let publisher = [0.0, 10.0].publisher
        
        manager.bindSpeedPublisher(publisher.eraseToAnyPublisher())
        
        manager.$speedKmh
            .dropFirst(2) // 跳过初始值0 和第一次低通计算
            .sink { speed in
                XCTAssertEqual(speed, 7.2, accuracy: 0.1)
                exp.fulfill()
            }
            .store(in: &subscriptions)
        
        wait(for: [exp], timeout: 1)
    }
    
    
    // MARK: - 3️⃣ 测试死区处理（低速视为 0）
    
    func testDeadZoneFilter() {
        let exp = expectation(description: "低速死区是否正确工作")
        
        let publisher = Just(0.2).eraseToAnyPublisher() // m/s → 0.72 km/h < 1.0 阈值
        
        manager.bindSpeedPublisher(publisher)
        
        manager.$speedKmh
            .dropFirst()
            .sink { speed in
                XCTAssertEqual(speed, 0.0, accuracy: 0.01)
                exp.fulfill()
            }
            .store(in: &subscriptions)
        
        wait(for: [exp], timeout: 1)
    }
    
    
    // MARK: - 4️⃣ 测试多次速度变化是否有平滑趋势（不跳变）
    
    func testSpeedSmoothingBehavior() {
        let exp = expectation(description: "多次速度输入是否平滑变化")
        
        let inputs = [0.0, 5.0, 10.0, 15.0].publisher // 单位 m/s
        
        var outputs: [Double] = []
        
        manager.$speedKmh
            .dropFirst()
            .sink { speed in
                outputs.append(speed)
                if outputs.count == 4 {
                    exp.fulfill()
                }
            }
            .store(in: &subscriptions)
        
        manager.bindSpeedPublisher(inputs.eraseToAnyPublisher())
        
        wait(for: [exp], timeout: 2)
        
        // 检查是否递增且没有发生跳变
        XCTAssertTrue(outputs[0] <= outputs[1])
        XCTAssertTrue(outputs[1] <= outputs[2])
        XCTAssertTrue(outputs[2] <= outputs[3])
    }
    
    
    // MARK: - 5️⃣ 测试 reset 是否清零
    
    func testReset() {
        manager.reset()
        XCTAssertEqual(manager.speedKmh, 0)
    }
}
