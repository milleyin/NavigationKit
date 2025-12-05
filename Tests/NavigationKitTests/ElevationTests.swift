//
//  ElevationTests.swift
//  NavigationKitTests
//
//  Created by Mille Yin on 2025/2/24.
//

import XCTest
@testable import NavigationCoreKit

final class ElevationTests: XCTestCase {
    
    /// 通用配置：低通滤波 α = 1，表示不平滑，便于验证原始值
    private let config = ElevationConfig(
        smoothingFactor: 1.0,
        noiseThreshold: 0.5,
        minimumGradientDistance: 1.0
    )
    
    /**
     测试：基本海拔处理流程（平滑 + 统计 + 坡度）
     */
    func testElevationBasicFlow() {
        
        let manager = ElevationManager(config: config)
        
        // 输入样本：海拔每次上升 2 米，水平距离固定 10 米
        let samples: [(alt: Double, distance: Double?)] = [
            (100, nil),   // 第一点，无坡度
            (102, 10),    // 上升 2m → 坡度 = 20%
            (104, 10),    // 上升 2m → 坡度 = 20%
            (106, 10)     // 上升 2m → 坡度 = 20%
        ]
        
        for s in samples {
            manager.processAltitudeSample(
                rawAltitude: s.alt,
                horizontalDistance: s.distance
            )
        }
        
        XCTAssertEqual(manager.smoothedAltitude, 106, accuracy: 0.001)
        XCTAssertEqual(manager.elevationGain, 6.0, accuracy: 0.001)
        XCTAssertEqual(manager.elevationLoss, 0.0, accuracy: 0.001)
        XCTAssertEqual(manager.gradient, 20.0, accuracy: 0.001)
    }
    
    /**
     测试：噪声过滤（noiseThreshold）
     小于噪声阈值的海拔变化不应计入累计爬升
     */
    func testNoiseFiltering() {
        let manager = ElevationManager(config: config)
        
        manager.processAltitudeSample(rawAltitude: 100, horizontalDistance: nil)
        manager.processAltitudeSample(rawAltitude: 100.3, horizontalDistance: 5)
        manager.processAltitudeSample(rawAltitude: 100.4, horizontalDistance: 5)
        
        // noiseThreshold = 0.5 → 全部视为噪声
        XCTAssertEqual(manager.elevationGain, 0.0, accuracy: 0.001)
        XCTAssertEqual(manager.elevationLoss, 0.0, accuracy: 0.001)
    }
    
    /**
     测试：累计爬升与下降统计
     */
    func testAscentAndDescent() {
        let manager = ElevationManager(config: config)
        
        let samples: [Double] = [100, 103, 101, 105, 103]
        
        for (idx, alt) in samples.enumerated() {
            let dist = idx == 0 ? nil : 10.0
            manager.processAltitudeSample(rawAltitude: alt, horizontalDistance: dist)
        }
        
        // 爬升贡献：100→103 (+3), 101→105 (+4)
        XCTAssertEqual(manager.elevationGain, 7.0, accuracy: 0.001)
        
        // 下降贡献：103→101 (-2), 105→103 (-2)
        XCTAssertEqual(manager.elevationLoss, 4.0, accuracy: 0.001)
    }
    
    /**
     测试：坡度计算正确性
     Δ海拔 = 5m, 距离=50m → 坡度 = 10%
     */
    func testGradientCalculation() {
        let g = GradientCalculator.computeGradient(
            deltaAltitude: 5,
            horizontalDistance: 50,
            minimumDistance: 1.0
        )
        
        XCTAssertEqual(g, 10.0, accuracy: 0.001)
    }
    
    /**
     测试：低通滤波效果（ElevationFilter）
     */
    func testLowPassFilter() {
        // α=0.5 → 新值 = prev + 0.5*(new-prev)
        let v = ElevationFilter.lowPassFilter(
            previousValue: 100,
            newValue: 110,
            alpha: 0.5
        )
        
        XCTAssertEqual(v, 105.0, accuracy: 0.001)
    }
    
    /**
     测试：ElevationStatistics min/max/ascent/descent 逻辑
     */
    func testStatistics() {
        var stats = ElevationStatistics()
        
        stats.reset(withInitialAltitude: 100)
        stats.update(currentAltitude: 103, deltaAltitude: 3, noiseThreshold: 0.5)
        stats.update(currentAltitude: 101, deltaAltitude: -2, noiseThreshold: 0.5)
        stats.update(currentAltitude: 106, deltaAltitude: 5, noiseThreshold: 0.5)
        
        XCTAssertEqual(stats.totalAscent, 8.0, accuracy: 0.001)
        XCTAssertEqual(stats.totalDescent, 2.0, accuracy: 0.001)
        XCTAssertEqual(stats.minimumAltitude, 100)
        XCTAssertEqual(stats.maximumAltitude, 106)
    }
}
