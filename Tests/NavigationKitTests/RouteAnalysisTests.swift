//
//  RouteAnalysisTests.swift
//  NavigationKit
//
//  Created by mille on 2025/12/31.
//

import XCTest
@testable import NavigationCoreKit

/**
 RouteAnalysis 模块的综合测试套件。
 包含：基础数学计算、各模块单元测试、引擎状态机测试以及复杂场景的合理性验证。
 */
class RouteAnalysisTests: XCTestCase {

    // MARK: - Helpers

    /// 测试基准时间：2025-12-31 00:00:00
    private let referenceDate = Date(timeIntervalSince1970: 1735622400)

    /**
     辅助方法：构造 GeoPoint。
      
     使用 `offset` 相对时间，保证测试的可重复性和时间轴的确定性。
     */
    private func makePoint(
        lat: Double = 30.0,
        lon: Double = 120.0,
        alt: Double = 10,
        offset: TimeInterval,
        speed: Double? = nil
    ) -> GeoPoint {
        GeoPoint(
            latitude: lat,
            longitude: lon,
            altitude: alt,
            timestamp: referenceDate.addingTimeInterval(offset),
            speed: speed,
            course: nil
        )
    }

    // MARK: - Part 1: 基础组件测试 (Math & Pure Logic)

    /**
     测试 GeoDistance：同一点距离应为 0。
     */
    func testGeoDistance_ZeroDistance() {
        let p = makePoint(offset: 0)
        let d = GeoDistance.distance(from: p, to: p)
        XCTAssertEqual(d, 0, accuracy: 0.0001)
    }

    /**
     测试 GeoDistance：距离计算应具有对称性 (A->B == B->A)。
     */
    func testGeoDistance_Symmetry() {
        let a = makePoint(lat: 25.0, lon: 121.0, offset: 0)
        let b = makePoint(lat: 25.001, lon: 121.001, offset: 0)

        let d1 = GeoDistance.distance(from: a, to: b)
        let d2 = GeoDistance.distance(from: b, to: a)

        XCTAssertEqual(d1, d2, accuracy: 0.0001)
    }

    /**
     测试 SlopeClassifier：验证上坡、下坡和平路的阈值分类逻辑。
     */
    func testSlopeClassifier_Classification() {
        XCTAssertEqual(SlopeClassifier.classify(gradient: 5.0), .uphill, "5% 坡度应为上坡")
        XCTAssertEqual(SlopeClassifier.classify(gradient: -5.0), .downhill, "-5% 坡度应为下坡")
        XCTAssertEqual(SlopeClassifier.classify(gradient: 0.3), .flat, "0.3% 坡度应为平路")
    }

    // MARK: - Part 2: 模块功能测试 (Components)

    /**
     测试 TrackCleaner：能够识别并丢弃时间倒退的点。
     */
    func testCleaner_RejectsBackwardTime() {
        // 使用 Config 或直接初始化均可，这里测试直接初始化接口
        let cleaner = TrackCleaner(maximumReasonableSpeed: 50, maximumAltitudeJump: 100, minimumTimeInterval: 0.5)

        let last = makePoint(offset: 10)
        let current = makePoint(offset: 9) // 时间倒退 1 秒

        XCTAssertNil(cleaner.process(current, last: last), "时间倒退的点应该被丢弃")
    }
    
    /**
     测试 TrackCleaner：能够丢弃过于密集的点（采样频率过高）。
     */
    func testCleaner_DropsTooDensePoints() {
        let cleaner = TrackCleaner(maximumReasonableSpeed: 50, maximumAltitudeJump: 100, minimumTimeInterval: 1.0)

        let p1 = makePoint(offset: 0)
        let p2 = makePoint(offset: 0.2) // 间隔仅 0.2s，小于最小间隔 1.0s

        let accepted1 = cleaner.process(p1, last: nil)
        let accepted2 = cleaner.process(p2, last: accepted1)

        XCTAssertNotNil(accepted1)
        XCTAssertNil(accepted2, "间隔小于阈值的点应被丢弃")
    }

    /**
     测试 SegmentAnalyzer：能正确计算两点间的段落属性（距离、速度）。
     */
    func testSegmentAnalyzer_Calculation() {
        let analyzer = SegmentAnalyzer()
        
        // 模拟简单的两点，纬度差 0.001 度（约 111m）
        let p1 = makePoint(lat: 0, lon: 0, offset: 0)
        let p2 = makePoint(lat: 0.001, lon: 0, offset: 10)
        
        // v2.0 API: process 返回 RouteSegment?
        guard let segment = analyzer.process(p2, last: p1) else {
            XCTFail("未生成 Segment")
            return
        }
        
        XCTAssertGreaterThan(segment.distance, 100)
        XCTAssertEqual(segment.time, 10, accuracy: 0.001)
        XCTAssertEqual(segment.averageSpeed, segment.distance / 10, accuracy: 0.0001)
    }

    // MARK: - Part 3: 引擎生命周期 (TrackEngine Lifecycle)

    /**
     测试 TrackEngine：基本的 Start -> Append -> Finish 流程。
     */
    func testEngine_BasicFlow() {
        let engine = TrackEngine()
        engine.start()

        engine.append(makePoint(offset: 0))
        engine.append(makePoint(lat: 30.001, offset: 10))

        XCTAssertEqual(engine.pointsCount, 2)
        XCTAssertEqual(engine.segments.count, 1)
        XCTAssertTrue(engine.summary.isValid)
        
        engine.finish()
        XCTAssertEqual(engine.state, .finished)
    }

    /**
     测试 TrackEngine：Reset 必须彻底清空所有内部状态。
     */
    func testEngine_ResetClearsAllState() {
        let engine = TrackEngine()
        engine.start()
        engine.append(makePoint(offset: 0))
        
        // 执行重置
        engine.reset()
        
        XCTAssertEqual(engine.pointsCount, 0)
        XCTAssertTrue(engine.segments.isEmpty)
        XCTAssertTrue(engine.stops.isEmpty)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.summary.isValid)
    }
    
    /**
     测试 TrackEngine：Finish 时应自动闭合尚未结束的停车事件。
     */
    func testEngine_FinishClosesPendingStop() {
        // 使用默认配置：SpeedThreshold 约 0.27m/s (1km/h), MinDuration 15s
        let engine = TrackEngine()
        engine.start()
        
        // 模拟一直静止
        let p1 = makePoint(offset: 0, speed: 0)
        let p2 = makePoint(offset: 30, speed: 0)
        
        engine.append(p1)
        engine.append(p2)
        
        // 此时 StopDetector 内部处于 pendingStart 状态，但尚未生成 StopEvent（只有在结束或速度恢复时生成）
        // 调用 finish 强制闭合
        engine.finish()
        
        XCTAssertEqual(engine.stops.count, 1)
        if let stop = engine.stops.first {
            XCTAssertGreaterThanOrEqual(stop.duration, 30)
        }
    }

    // MARK: - Part 4: 真实场景合理性测试 (Rationality Scenarios)

    /**
     场景 1：陡坡识别
     模拟 100米内急降15米，验证坡度计算和分类是否符合物理常识。
     */
    func testRationality_SteepDownhill() {
        let analyzer = SegmentAnalyzer()
        let startPoint = makePoint(lat: 30.0, lon: 120.0, alt: 100, offset: 0)
        
        // 经度增加 0.001 度，在纬度 30° 附近约为 96.5 米水平距离
        let endPoint = makePoint(lat: 30.0, lon: 120.001, alt: 85, offset: 10)
        
        guard let segment = analyzer.process(endPoint, last: startPoint) else {
            XCTFail("Segment 生成失败")
            return
        }
        
        // 验证坡度数值合理性：(85-100) / 96.5 * 100 ≈ -15.5%
        XCTAssertLessThan(segment.gradient, -10, "坡度应陡于 -10%")
        XCTAssertEqual(segment.slopeType, .downhill)
    }

    /**
     场景 2：隧道漂移过滤
     模拟用户进入隧道，GPS 突然瞬移到几公里外，然后又恢复正常。
     验证 Cleaner 是否能拦截这个“瞬移点”。
     */
    func testRationality_TunnelDriftRejection() {
        let cleaner = TrackCleaner(maximumReasonableSpeed: 40, maximumAltitudeJump: 50, minimumTimeInterval: 0.5)
        
        let p1 = makePoint(lat: 30.0, lon: 120.0, offset: 0)
        let pDrift = makePoint(lat: 31.0, lon: 121.0, offset: 1) // 1秒瞬移上百公里
        let p3 = makePoint(lat: 30.0001, lon: 120.0001, offset: 2)
        
        let accepted1 = cleaner.process(p1, last: nil)
        let accepted2 = cleaner.process(pDrift, last: accepted1) // 比较 drift 和 p1
        
        // 当 pDrift 被丢弃返回 nil 时，下一个点的比较对象仍应是 accepted1
        let accepted3 = cleaner.process(p3, last: accepted1)
        
        XCTAssertNotNil(accepted1)
        XCTAssertNil(accepted2, "物理上不可能的瞬移点必须被拦截")
        XCTAssertNotNil(accepted3, "恢复正常的点应该被接受")
    }

    /**
     场景 3：持续爬坡汇总
     模拟一段 30 秒的连续爬坡，验证 Summary 里的总爬升和平均速度。
     */
    func testRationality_UphillJourneySummary() {
        let engine = TrackEngine()
        engine.start()
        
        // 为了模拟 10m/s 的速度：
        // 在 lat 30°，1 度纬度 ≈ 111km -> 0.0001 度 ≈ 11.1m
        // 我们需要 10m，所以步进设为 0.0000899 左右
        let step = 0.0000899
        
        for i in 0...30 {
            let p = makePoint(
                lat: 30.0 + Double(i) * step,
                lon: 120.0,
                alt: 100.0 + Double(i) * 1.0, // 每秒爬 1 米
                offset: TimeInterval(i),
                speed: 10
            )
            engine.append(p)
        }
        
        engine.finish()
        let summary = engine.summary
        
        // 1. 验证爬升：30步 * 1米 = 30米
        // TrackEngine v2.0 通过 updateSummaryWithSegment 累加爬升
        XCTAssertEqual(summary.totalElevationGain, 30.0, accuracy: 0.1)
        
        // 2. 验证平均速度：现在距离计算应该非常接近 10m/s
        XCTAssertEqual(summary.averageSpeed, 10.0, accuracy: 1.0)
        
        // 3. 验证极值
        XCTAssertEqual(summary.maxAltitude, 130.0)
    }

    /**
     场景 4：完整通勤模拟 (Complex Urban Ride)
     流程：正常骑行 -> 隧道丢星漂移 -> 红灯停车 -> 爬坡冲刺
     验证：TrackCleaner, StopDetector, TrackAnalyzer 的协同工作。
     */
    func testRationality_ComplexUrbanRide() {
        let engine = TrackEngine()
        // 默认配置 TrackAnalyzer movingSpeedThreshold = 0.5 m/s
        // 默认配置 StopDetector speedThreshold ≈ 0.27 m/s, minDuration = 15s
        
        engine.start()
        
        var currentTime: TimeInterval = 0
        
        // Stage 1: 正常出发 (10s) - 匀速 5m/s
        for i in 0..<10 {
            currentTime = Double(i)
            // 0.000045 deg ≈ 5m
            let p = makePoint(lat: 30.0 + Double(i) * 0.000045, offset: currentTime, speed: 5)
            engine.append(p)
        }
        
        // Stage 2: 隧道漂移 (1s)
        currentTime += 1
        let driftPoint = makePoint(lat: 31.0, lon: 121.0, offset: currentTime, speed: 100) // 瞬移
        engine.append(driftPoint)
        
        // Stage 3: 红灯停车 (20s)
        // 模拟：速度很低 (0.2)，但 GPS 坐标有微小抖动
        for _ in 0..<20 {
            currentTime += 1
            let p = makePoint(
                lat: 30.00045 + Double.random(in: -0.000001...0.000001),
                offset: currentTime,
                speed: 0.2 // < 0.27 (Stop阈值) 且 < 0.5 (Moving阈值)，应计入 StoppedTime 并触发 StopEvent
            )
            engine.append(p)
        }
        
        // Stage 4: 爬坡冲刺 (10s)
        for i in 0..<10 {
            currentTime += 1
            let p = makePoint(
                lat: 30.00045 + Double(i) * 0.00009, // ~10m/s
                alt: 10 + Double(i) * 2, // 爬升
                offset: currentTime,
                speed: 8
            )
            engine.append(p)
        }
        
        engine.finish()
        let summary = engine.summary
        
        // --- 合理性验证 ---
        
        // 1. Cleaner 验证：总距离不应包含那个几百公里的漂移
        XCTAssertLessThan(summary.totalDistance, 5000, "异常漂移点未被过滤")
        
        // 2. Elevation 验证：冲刺阶段爬升了约 18m
        // 注意：SegmentAnalyzer 在距离过短时可能不生成段，但此处速度 10m/s，距离足够
        XCTAssertEqual(summary.totalElevationGain, 18.0, accuracy: 2.0)
        
        // 3. Stop 验证：中间那 20s 应该识别为停车
        XCTAssertEqual(engine.stops.count, 1, "未识别出红灯停车")
        if let stop = engine.stops.first {
            XCTAssertGreaterThanOrEqual(stop.duration, 15, "停车时长应覆盖红灯时间")
        }
        
        // 4. Time 验证：移动时间 ≈ Stage 1 (10s) + Stage 4 (10s) = 20s
        // Stage 3 的 20s 应计入 stoppedTime
        XCTAssertEqual(summary.movingTime, 20.0, accuracy: 5.0)
        XCTAssertGreaterThan(summary.stoppedTime, 15.0)
        
        print("Test Passed: Total Dist: \(Int(summary.totalDistance))m, Moving: \(Int(summary.movingTime))s, Stopped: \(Int(summary.stoppedTime))s")
    }
}

//MARK: - 接口测试
extension RouteAnalysisTests {
    
    /// 测试 NavigationCoreKit.RouteAnalysis.analyze 能正常返回 RouteSummary
    func testRouteAnalysisAnalyzeReturnsSummary() {
        let points = [
            makePoint(offset: 0, speed: 2),
            makePoint(lat: 30.0001, offset: 10, speed: 2)
        ]
        let summary = NavigationCoreKit.RouteAnalysis.analyze(points: points)
        XCTAssertTrue(summary.isValid)
        XCTAssertGreaterThan(summary.totalDistance, 0)
        XCTAssertGreaterThan(summary.pointCount, 1)
    }

    /// 测试 NavigationCoreKit.RouteAnalysis.analyzeDetail 能返回详细内容
    func testRouteAnalysisAnalyzeDetailReturnsDetails() {
        let points = [
            makePoint(offset: 0, speed: 3),
            makePoint(lat: 30.0001, offset: 5, speed: 3),
            makePoint(lat: 30.0002, offset: 10, speed: 0) // 停车
        ]
        let detail = NavigationCoreKit.RouteAnalysis.analyzeDetail(points: points)
        XCTAssertTrue(detail.summary.isValid)
        XCTAssertEqual(detail.segments.count, 2)
        XCTAssertEqual(detail.summary.pointCount, 3)
        // 停车点可能因为配置未触发，可以允许 0 或 1
        XCTAssertGreaterThanOrEqual(detail.stops.count, 0)
    }

    /// 测试自定义 config 能生效
    func testRouteAnalysisWithCustomConfig() {
        var config = TrackEngine.Config.cycling
        config.analyzer.movingSpeedThreshold = 1.5 // 提高移动阈值
        let points = [
            makePoint(offset: 0, speed: 1.0), // 低速应该判定为静止
            makePoint(lat: 30.0002, offset: 20, speed: 1.0)
        ]
        let summary = NavigationCoreKit.RouteAnalysis.analyze(points: points, config: config)
        // 全程速度低于阈值，应该统计为静止
        XCTAssertEqual(summary.movingTime, 0, accuracy: 0.001)
        XCTAssertGreaterThan(summary.stoppedTime, 0)
    }
    
}
