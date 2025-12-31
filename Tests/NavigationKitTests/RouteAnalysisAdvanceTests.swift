//
//  RouteAnalysisAdvanceTests.swift
//  NavigationKit
//
//  Created by mille on 2025/12/31.
//

import XCTest
@testable import NavigationCoreKit

class RouteAnalysisAdvanceTests: XCTestCase {
    
    // 基准时间，方便累加
    private let referenceDate = Date(timeIntervalSince1970: 1735622400) // 2025-12-31 00:00:00

    // MARK: - Helpers

    /**
     * 辅助方法：构造 GeoPoint
     * 修正：time 显式累加到基准 Date 上
     */
    private func makePoint(lat: Double = 30.0, lon: Double = 120.0, alt: Double = 10, offset: TimeInterval, speed: Double? = nil) -> GeoPoint {
        GeoPoint(
            latitude: lat,
            longitude: lon,
            altitude: alt,
            timestamp: referenceDate.addingTimeInterval(offset),
            speed: speed,
            course: nil
        )
    }

    // MARK: - 1. 物理合理性：陡坡与下坡分类
    func testRationality_SteepDownhill() {
        let analyzer = SegmentAnalyzer()
        let startPoint = makePoint(alt: 100, offset: 0)
        // 经度增加 0.001 度在纬度 30° 约等于 96.5 米（Haversine 计算）
        let endPoint = makePoint(lon: 120.001, alt: 85, offset: 10)
        
        let segments = analyzer.process(endPoint, last: startPoint, segments: [])
        guard let segment = segments.first else { XCTFail("未生成 Segment"); return }
        
        // 验证坡度数值：(85-100) / 96.5 * 100 ≈ -15.5%
        // 注意：你之前的逻辑是 * 100，所以这里断言也要对应
        XCTAssertTrue(segment.gradient < -10, "坡度应该小于 -10%")
        XCTAssertEqual(segment.slopeType, .downhill)
    }

    // MARK: - 2. 信号清洗合理性：隧道跳点屏蔽
    func testRationality_TunnelDriftRejection() {
        // 注入配置：144km/h 以上的点视为异常
        let cleaner = TrackCleaner(maximumReasonableSpeed: 40, maximumAltitudeJump: 50, minimumTimeInterval: 0.5)
        
        let p1 = makePoint(lat: 30.0, lon: 120.0, offset: 0)
        let pDrift = makePoint(lat: 31.0, lon: 121.0, offset: 1) // 1秒瞬移上百公里
        let p3 = makePoint(lat: 30.0001, lon: 120.0001, offset: 2)
        
        let accepted1 = cleaner.process(p1, last: nil)
        let accepted2 = cleaner.process(pDrift, last: accepted1)
        
        // 当 pDrift 被判定为无效返回 nil 时，下一个点的比较对象应该是上一个“有效点”
        let accepted3 = cleaner.process(p3, last: accepted1)
        
        XCTAssertNotNil(accepted1)
        XCTAssertNil(accepted2, "瞬移跳点必须被拦截")
        XCTAssertNotNil(accepted3, "回到正常轨迹的点应该被接受")
    }

    // MARK: - 3. 综合逻辑链测试：爬坡行程汇总
    /**
     * 场景：模拟一段 30 秒的连续爬坡
     * 验证：Summary 里的总爬升、平均速度是否符合逻辑
     */
    func testRationality_UphillJourneySummary() {
        let engine = TrackEngine()
        engine.start()
        
        // 10m/s 对应的纬度步进约为 0.00009
        let step = 0.0000899 // 对应纬度 30 度附近约 10 米
        
        for i in 0...30 {
            let p = makePoint(
                lat: 30.0 + Double(i) * step,
                alt: 100.0 + Double(i) * 1.0,
                offset: TimeInterval(i),
                speed: 10
            )
            engine.append(p)
        }
        
        engine.finish()
        let summary = engine.summary
        
        // 验证爬升：30步，每步1米，总爬升30
        XCTAssertEqual(summary.totalElevationGain, 30.0, accuracy: 0.1)
        
        // 现在平均速度应该能落在 10.0 +/- 1.0 的范围内了
        // 实际上它会非常接近 10.0
        XCTAssertEqual(summary.averageSpeed, 10.0, accuracy: 1.0)
        
        XCTAssertEqual(summary.maxAltitude, 130.0)
    }
    
    // MARK: - 3. 完整骑行过程
    
    /**
     * 场景：一次完整的通勤骑行
     * 1. 正常出发 (10s)
     * 2. 隧道丢信号 + 严重漂移点 (5s) -> 考验 TrackCleaner
     * 3. 红灯停滞 (20s) -> 考验 StopDetector & movingTime 统计
     * 4. 爬坡冲刺 (10s) -> 考验 ElevationGain & Gradient
     */
    func testRationality_ComplexUrbanRide() {
        let engine = TrackEngine()
        // 假设配置：15秒判定停车，0.5m/s 判定移动
        engine.start()
        
        var currentTime: TimeInterval = 0
        
        // 1. 正常出发：匀速移动
        for i in 0..<10 {
            currentTime = Double(i)
            let p = makePoint(lat: 30.0 + Double(i) * 0.0001, offset: currentTime, speed: 5)
            engine.append(p)
        }
        
        // 2. 模拟隧道漂移：产生一个经纬度极度离谱的点
        currentTime += 1
        let driftPoint = makePoint(lat: 31.0, lon: 121.0, offset: currentTime, speed: 100)
        engine.append(driftPoint)
        
        // 3. 模拟等红灯：速度极低，但位置有轻微 GPS 抖动
        for i in 0..<20 {
            currentTime += 1
            let p = makePoint(
                lat: 30.001 + Double.random(in: -0.000001...0.000001),
                offset: currentTime,
                speed: 0.2 // 低于 0.5 阈值，应视为 stoppedTime
            )
            engine.append(p)
        }
        
        // 4. 爬坡冲刺：高度上升
        for i in 0..<10 {
            currentTime += 1
            let p = makePoint(
                lat: 30.001 + Double(i) * 0.0001,
                alt: 10 + Double(i) * 2, // 爬升 18 米
                offset: currentTime,
                speed: 8
            )
            engine.append(p)
        }
        
        engine.finish()
        let summary = engine.summary
        
        // --- 合理性断言 ---
        
        // 验证：跳点是否被 Cleaner 踢出去了？
        // 如果 driftPoint 没被踢，pointCount 会多一个，或者 totalDistance 会变成几百公里
        XCTAssertLessThan(summary.totalDistance, 5000, "总距离不应包含漂移点的数千公里")
        
        // 验证：海拔增量是否准确？ (预计 18m)
        XCTAssertEqual(summary.totalElevationGain, 18.0, accuracy: 0.5)
        
        // 验证：停车检测
        XCTAssertEqual(engine.stops.count, 1, "红灯应该产生一个停车事件")
        
        // 验证：移动时间
        // 10s (出发) + 10s (冲刺) = 20s 左右。
        // 如果不处理 0.2m/s 的硬编码，这里会变成 40s，那平均速度就废了。
        XCTAssertEqual(summary.movingTime, 20.0, accuracy: 2.0)
        
        print("🎬 最终报告：距离 \(summary.totalDistance)m, 爬升 \(summary.totalElevationGain)m, 停车时长 \(summary.stoppedTime)s")
    }
}
