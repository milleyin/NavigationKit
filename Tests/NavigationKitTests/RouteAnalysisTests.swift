//
//  File.swift
//  NavigationKit
//
//  Created by mille on 2025/12/26.
//

import XCTest
@testable import NavigationCoreKit

class RouteAnalysisTests: XCTestCase {
//RouteAnalysisTests_Part1
    // MARK: - Helpers

    private func makePoint(lat: Double = 25.0, lon: Double = 121.0, alt: Double = 10, time: Date, speed: Double? = nil) -> GeoPoint {
        GeoPoint(
            latitude: lat,
            longitude: lon,
            altitude: alt,
            timestamp: time,
            speed: speed,
            course: nil
        )
    }

    ///GeoDistance：同点距离为 0
    func test01_GeoDistance_ZeroDistance() {
        let t = Date()
        let p = makePoint(time: t)

        let d = GeoDistance.distance(from: p, to: p)
        XCTAssertEqual(d, 0, accuracy: 0.0001)
    }

    ///GeoDistance：对称性
    func test02_GeoDistance_Symmetry() {
        let t = Date()
        let a = makePoint(lat: 25.0, lon: 121.0, time: t)
        let b = makePoint(lat: 25.001, lon: 121.001, time: t)

        let d1 = GeoDistance.distance(from: a, to: b)
        let d2 = GeoDistance.distance(from: b, to: a)

        XCTAssertEqual(d1, d2, accuracy: 0.0001)
    }

    ///TrackCleaner：第一个点必须被接受
    func test03_Cleaner_AcceptsFirstPoint() {
        let cleaner = TrackCleaner(
            maximumReasonableSpeed: 50,
            maximumAltitudeJump: 100,
            minimumTimeInterval: 0.5
        )

        let p = makePoint(time: Date())
        XCTAssertNotNil(cleaner.process(p, last: nil))
    }

    ///TrackCleaner：时间倒退点必须被丢弃
    func test04_Cleaner_RejectsBackwardTime() {
        let cleaner = TrackCleaner(
            maximumReasonableSpeed: 50,
            maximumAltitudeJump: 100,
            minimumTimeInterval: 0.5
        )

        let t = Date()
        let last = makePoint(time: t)
        let current = makePoint(time: t.addingTimeInterval(-1))

        XCTAssertNil(cleaner.process(current, last: last))
    }

    ///SegmentAnalyzer：两点生成一个 segment
    func test05_SegmentAnalyzer_GeneratesSegment() {
        let analyzer = SegmentAnalyzer()
        let t = Date()

        let a = makePoint(time: t)
        let b = makePoint(
            lat: 25.001,
            lon: 121.001,
            alt: 20,
            time: t.addingTimeInterval(10)
        )

        let segments = analyzer.process(b, last: a, segments: [])
        XCTAssertEqual(segments.count, 1)
    }

    ///SegmentAnalyzer：segment 基本数值合理
    func test06_SegmentAnalyzer_SegmentValues() {
        let analyzer = SegmentAnalyzer()
        let t = Date()

        let a = makePoint(time: t)
        let b = makePoint(
            lat: 25.001,
            lon: 121.001,
            alt: 20,
            time: t.addingTimeInterval(10)
        )

        let segment = analyzer.process(b, last: a, segments: []).first!

        XCTAssertTrue(segment.distance > 0)
        XCTAssertTrue(segment.time > 0)
        XCTAssertTrue(segment.averageSpeed > 0)
    }

    ///SlopeClassifier：坡度分类逻辑
    func test07_SlopeClassifier() {
        XCTAssertEqual(SlopeClassifier.classify(gradient: 5), .uphill)
        XCTAssertEqual(SlopeClassifier.classify(gradient: -5), .downhill)
        XCTAssertEqual(SlopeClassifier.classify(gradient: 0.2), .flat)
    }

    ///TrackAnalyzer：点数递增
    func test08_TrackAnalyzer_PointCount() {
        let analyzer = TrackAnalyzer()
        let t = Date()

        let a = makePoint(time: t)
        let b = makePoint(
            lat: 25.001,
            lon: 121.001,
            time: t.addingTimeInterval(10),
            speed: 3
        )

        var summary = RouteSummary.empty
        summary = analyzer.process(a, last: nil, summary: summary)
        summary = analyzer.process(b, last: a, summary: summary)

        XCTAssertEqual(summary.pointCount, 2)
    }

    ///TrackAnalyzer：有效轨迹判定
    func test09_TrackAnalyzer_Validity() {
        let analyzer = TrackAnalyzer()
        let t = Date()

        let a = makePoint(time: t)
        let b = makePoint(
            lat: 25.001,
            lon: 121.001,
            time: t.addingTimeInterval(10),
            speed: 3
        )

        var summary = RouteSummary.empty
        summary = analyzer.process(a, last: nil, summary: summary)
        XCTAssertFalse(summary.isValid)

        summary = analyzer.process(b, last: a, summary: summary)
        XCTAssertTrue(summary.isValid)
    }

    ///TrackEngine：最小完整链路
    func test10_TrackEngine_BasicFlow() {
        let engine = TrackEngine()
        engine.start()

        let t = Date()
        let a = makePoint(time: t, speed: 2)
        let b = makePoint(
            lat: 25.001,
            lon: 121.001,
            alt: 15,
            time: t.addingTimeInterval(10),
            speed: 2
        )

        engine.append(a)
        engine.append(b)

        XCTAssertEqual(engine.pointsCount, 2)
        XCTAssertEqual(engine.segments.count, 1)
        XCTAssertTrue(engine.summary.isValid)
    }
}

extension RouteAnalysisTests {
    
    /*
    • 11～13：SegmentAnalyzer 的数理正确性
    • 14～16：SlopeClassifier 是纯函数、无状态、可预期
    • 17～18：StopDetector 的状态机逻辑
    • 19：TrackEngine.reset() 的幂等与彻底性
    • 20：process(points) ≡ 多次 append
    */
    // MARK: - Helpers
    
    private func makePoint(lat: Double, lon: Double, alt: Double, time: TimeInterval, speed: Double? = nil) -> GeoPoint {
        GeoPoint(
            latitude: lat,
            longitude: lon,
            altitude: alt,
            timestamp: Date(timeIntervalSince1970: time),
            speed: speed
        )
    }
    
    // MARK: - 11. SegmentAnalyzer：段数量正确
    
    func testSegmentCountMatchesPointCountMinusOne() {
        let analyzer = SegmentAnalyzer()
        
        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 0.001, alt: 0, time: 10)
        let p3 = makePoint(lat: 0, lon: 0.002, alt: 0, time: 20)
        
        var segments: [RouteSegment] = []
        segments = analyzer.process(p2, last: p1, segments: segments)
        segments = analyzer.process(p3, last: p2, segments: segments)
        
        XCTAssertEqual(segments.count, 2)
    }
    
    // MARK: - 12. SegmentAnalyzer：distance > 0
    
    func testSegmentDistanceIsPositive() {
        let analyzer = SegmentAnalyzer()
        
        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 0.001, alt: 0, time: 10)
        
        let segments = analyzer.process(p2, last: p1, segments: [])
        
        XCTAssertGreaterThan(segments.first!.distance, 0)
    }
    
    // MARK: - 13. SegmentAnalyzer：averageSpeed = distance / time
    
    func testSegmentAverageSpeedCalculation() {
        let analyzer = SegmentAnalyzer()
        
        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 0.001, alt: 0, time: 10)
        
        let segment = analyzer.process(p2, last: p1, segments: []).first!
        
        let expected = segment.distance / 10
        XCTAssertEqual(segment.averageSpeed, expected, accuracy: 0.0001)
    }
    
    // MARK: - 14. SlopeClassifier：上坡
    
    func testSlopeClassifierUphill() {
        let type = SlopeClassifier.classify(gradient: 5.0)
        XCTAssertEqual(type, .uphill)
    }
    
    // MARK: - 15. SlopeClassifier：下坡
    
    func testSlopeClassifierDownhill() {
        let type = SlopeClassifier.classify(gradient: -5.0)
        XCTAssertEqual(type, .downhill)
    }
    
    // MARK: - 16. SlopeClassifier：平路
    
    func testSlopeClassifierFlat() {
        let type = SlopeClassifier.classify(gradient: 0.3)
        XCTAssertEqual(type, .flat)
    }
    
    // MARK: - 17. TrackEngine：StopDetector 识别停车
    
    func testStopDetectionCreatesStopEvent() {
        let engine = TrackEngine()
        
        engine.start()
        
        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0, speed: 0)
        let p2 = makePoint(lat: 0, lon: 0, alt: 0, time: 20, speed: 0)
        let p3 = makePoint(lat: 0, lon: 0.001, alt: 0, time: 30, speed: 3)
        
        engine.append(p1)
        engine.append(p2)
        engine.append(p3)
        
        XCTAssertEqual(engine.stops.count, 1)
        XCTAssertGreaterThanOrEqual(engine.stops.first!.duration, 15)
    }
    
    // MARK: - 18. TrackEngine：finish 会补全未结束停车
    
    func testFinishClosesPendingStop() {
        let engine = TrackEngine()
        
        engine.start()
        
        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0, speed: 0)
        let p2 = makePoint(lat: 0, lon: 0, alt: 0, time: 20, speed: 0)
        
        engine.append(p1)
        engine.append(p2)
        engine.finish()
        
        XCTAssertEqual(engine.stops.count, 1)
    }
    
    // MARK: - 19. TrackEngine：reset 清空状态
    
    func testResetClearsAllState() {
        let engine = TrackEngine()
        
        engine.start()
        engine.append(makePoint(lat: 0, lon: 0, alt: 0, time: 0))
        engine.reset()
        
        XCTAssertEqual(engine.pointsCount, 0)
        XCTAssertTrue(engine.segments.isEmpty)
        XCTAssertTrue(engine.stops.isEmpty)
        XCTAssertEqual(engine.state, .idle)
    }
    
    // MARK: - 20. TrackEngine：process(points) 等价于多次 append
    
    func testBatchProcessEqualsAppend() {
        let engine = TrackEngine()
        engine.start()
        
        let points = [
            makePoint(lat: 0, lon: 0, alt: 0, time: 0),
            makePoint(lat: 0, lon: 0.001, alt: 0, time: 10),
            makePoint(lat: 0, lon: 0.002, alt: 0, time: 20)
        ]
        
        engine.process(points)
        
        XCTAssertEqual(engine.pointsCount, 3)
        XCTAssertEqual(engine.segments.count, 2)
        XCTAssertTrue(engine.summary.totalDistance > 0)
    }
}

extension RouteAnalysisTests {

    // MARK: - 21. Cleaner：时间过密点被丢弃

    func testCleanerDropsTooDensePoints() {
        let cleaner = TrackCleaner(
            maximumReasonableSpeed: 50,
            maximumAltitudeJump: 100,
            minimumTimeInterval: 1.0
        )

        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 0.0001, alt: 0, time: 0.2)

        let accepted1 = cleaner.process(p1, last: nil)
        let accepted2 = cleaner.process(p2, last: accepted1)

        XCTAssertNotNil(accepted1)
        XCTAssertNil(accepted2)
    }

    // MARK: - 22. Cleaner：异常速度点被丢弃

    func testCleanerDropsUnreasonableSpeed() {
        let cleaner = TrackCleaner(
            maximumReasonableSpeed: 10, // 很低的阈值
            maximumAltitudeJump: 100,
            minimumTimeInterval: 1
        )

        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 1.0, alt: 0, time: 1) // 极远

        let accepted1 = cleaner.process(p1, last: nil)
        let accepted2 = cleaner.process(p2, last: accepted1)

        XCTAssertNotNil(accepted1)
        XCTAssertNil(accepted2)
    }

    // MARK: - 23. TrackEngine：关闭 Cleaner 仍可正常工作

    func testEngineWorksWithCleanerDisabled() {
        var config = TrackEngine.Config()
        config.enableCleaner = false

        let engine = TrackEngine(config: config)
        engine.start()

        let p1 = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        let p2 = makePoint(lat: 0, lon: 0.001, alt: 0, time: 10)

        engine.append(p1)
        engine.append(p2)

        XCTAssertEqual(engine.pointsCount, 2)
        XCTAssertEqual(engine.segments.count, 1)
    }

    // MARK: - 24. TrackEngine：关闭 Smoother 不影响输出数量

    func testEngineWithoutSmootherProducesSamePointCount() {
        var config = TrackEngine.Config()
        config.enableSmoother = false

        let engine = TrackEngine(config: config)
        engine.start()

        let points = [
            makePoint(lat: 0, lon: 0, alt: 0, time: 0),
            makePoint(lat: 0, lon: 0.001, alt: 0, time: 10),
            makePoint(lat: 0, lon: 0.002, alt: 0, time: 20)
        ]

        points.forEach { engine.append($0) }

        XCTAssertEqual(engine.pointsCount, 3)
        XCTAssertEqual(engine.segments.count, 2)
    }

    // MARK: - 25. Smoother：alpha = 0 强制平滑到前一个点

    func testSmootherAlphaZeroFreezesValues() {
        let smoother = TrackSmoother(config: .init(alpha: 0))

        let last = makePoint(lat: 1, lon: 1, alt: 100, time: 0)
        let current = makePoint(lat: 10, lon: 10, alt: 1000, time: 10)

        let smoothed = smoother.process(current, last: last)

        XCTAssertEqual(smoothed.latitude, last.latitude)
        XCTAssertEqual(smoothed.longitude, last.longitude)
        XCTAssertEqual(smoothed.altitude, last.altitude)
    }

    // MARK: - 26. 空轨迹 finish 不产生 StopEvent

    func testFinishWithNoPointsProducesNoStops() {
        let engine = TrackEngine()
        engine.start()
        engine.finish()

        XCTAssertTrue(engine.stops.isEmpty)
    }

    // MARK: - 27. 单点轨迹：summary 不 valid，但系统不崩

    func testSinglePointTrackIsInvalidButStable() {
        let engine = TrackEngine()
        engine.start()

        let p = makePoint(lat: 0, lon: 0, alt: 0, time: 0)
        engine.append(p)

        XCTAssertEqual(engine.pointsCount, 1)
        XCTAssertFalse(engine.summary.isValid)
        XCTAssertEqual(engine.segments.count, 0)
    }
}
