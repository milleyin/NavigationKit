//
//  TrackEngine.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 `TrackEngine` 是 RouteAnalysis 的“轨迹计算总控引擎”。

 它只负责**算法编排**与**结果汇总**，不负责任何设备数据采集（例如 CoreLocation 或 MapKit）。
 你只需要把应用层/数据层产生的 `GeoPoint` 输入进来，`TrackEngine` 将按既定流水线：

 1. 清洗（`TrackCleaner`）——剔除异常点、重复点、时间倒退点等
 2. 平滑（`TrackSmoother`，可选）——对轨迹做滤波
 3. 分析（`TrackAnalyzer`）——累计距离、时间、最大速度、平均速度等
 4. 分段（`SegmentAnalyzer`）——切分坡段、速度段等
 5. 停车（`StopDetector`）——识别停车点
 6. 汇总（`RouteSummary`）——输出统一的轨迹摘要结果

 - Important: `TrackEngine` 必须保持“纯算法”，不依赖 UI 或系统环境，确保可单测与可回放。
 - Note: `TrackEngine` 设计为同步处理：输入确定、输出确定。多线程/异步由上层自行决定。
 */
public final class TrackEngine {

    // MARK: - Types

    /**
     引擎运行状态。

     - Note: `running` 表示正在接收轨迹点；
       `finished` 表示轨迹已结束，不再接收点；
       `idle` 表示尚未开始或已 reset。
     */
    public enum State: Equatable {
        case idle
        case running
        case finished
    }

    /**
     引擎配置，用于控制清洗、平滑、停车识别等策略。

     - Important: 所有单位均使用国际单位制（SI）。
     */
    public struct Config: Sendable, Equatable {

        /// 是否启用轨迹清洗。默认 `true`。
        public var enableCleaner: Bool = true

        /// 是否启用轨迹平滑。默认 `false`（先不开，避免早期过拟合）。
        public var enableSmoother: Bool = false

        /// 停车判定速度阈值（m/s）。低于该阈值视为“可能停车”。
        public var stopSpeedThreshold: Double = 0.277_777_777_8 // 1 km/h

        /// 停车判定最短持续时间（秒）。低速持续超过该值视为停车。
        public var stopMinimumDuration: TimeInterval = 15

        /// 允许的最小时间间隔（秒）。小于该值可视为“噪声点/重复点”。
        public var minimumTimeInterval: TimeInterval = 0.2

        /// 允许的最大合理速度（m/s）。超过该值可视为异常点（仅供 cleaner 参考）。
        public var maximumReasonableSpeed: Double = 80 // ~288 km/h，先给个保守上限

        /// 允许的最大合理海拔突变（米）。超过该值可视为异常点（仅供 cleaner 参考）。
        public var maximumAltitudeJump: Double = 200

        /// 平滑系数（0~1），越小越平滑
        public var smootherAlpha: Double = 0.2

        public init() {}
    }

    /**
     停车事件（最小模型）
     */
    public struct StopEvent: Sendable, Equatable {

        /// 停车起始点（含坐标与时间）
        public let start: GeoPoint

        /// 停车结束点（含坐标与时间）
        public let end: GeoPoint

        /// 停车持续时间（秒）
        public var duration: TimeInterval {
            max(0, end.timestamp.timeIntervalSince(start.timestamp))
        }

        public init(start: GeoPoint, end: GeoPoint) {
            self.start = start
            self.end = end
        }
    }

    // MARK: - Public Outputs

    /// 当前引擎状态。
    public private(set) var state: State = .idle

    /// 轨迹点数量（输入后、清洗/平滑后的有效点数量）。
    public private(set) var pointsCount: Int = 0

    /// 最近一次处理后的轨迹摘要。
    public private(set) var summary: RouteSummary = .empty

    /// 分段结果（后续 SegmentAnalyzer 实现后会逐步丰富）。
    public private(set) var segments: [RouteSegment] = []

    /// 停车事件列表（后续 StopDetector 实现后会逐步丰富）。
    public private(set) var stops: [StopEvent] = []

    // MARK: - Dependencies (Algorithm Modules)

    private let config: Config

    private let cleaner: TrackCleaner
    private let smoother: TrackSmoother
    private let analyzer: TrackAnalyzer
    private let segmentAnalyzer: SegmentAnalyzer
    private let stopDetector: StopDetector

    // MARK: - Internal State

    /// 最近一次“进入引擎流水线”的有效点
    private var lastAcceptedPoint: GeoPoint?

    // MARK: - Init

    /**
     初始化 `TrackEngine`。

     - Important: 该类不持有任何系统资源，初始化不会触发定位/网络/传感器。
     - Parameter config: 引擎配置，控制清洗、平滑、停车识别等策略。
     */
    public init(config: Config = .init()) {
        self.config = config

        self.cleaner = TrackCleaner(
            maximumReasonableSpeed: config.maximumReasonableSpeed,
            maximumAltitudeJump: config.maximumAltitudeJump,
            minimumTimeInterval: config.minimumTimeInterval
        )

        self.smoother = TrackSmoother(config: .init(alpha: config.smootherAlpha))

        self.analyzer = TrackAnalyzer()
        self.segmentAnalyzer = SegmentAnalyzer()

        /// ✅ StopDetector 统一在这里初始化（以后想换策略就改 config）
        self.stopDetector = StopDetector(
            speedThreshold: config.stopSpeedThreshold,
            minimumDuration: config.stopMinimumDuration
        )
    }

    // MARK: - Lifecycle
    /**
     启动引擎，进入 `running` 状态，准备接收轨迹点。

     - Important: `start()` 不会清空已有结果；如果你想从零开始，请先调用 `reset()`。
     - Note: 你可以在一次轨迹录制流程中多次调用 `start()`，重复调用不会产生副作用。
     - Postcondition: `state == .running`
     */
    public func start() {
        guard state != .running else { return }
        if state == .idle { state = .running }
        if state == .finished { state = .running }
    }
    /**
     结束轨迹处理流程。

     - Important: `finish()` 会将引擎状态置为 `finished`，之后默认不再接收新点。
     - Note: 如果你仍希望继续追加点，可以再次调用 `start()` 进入 `running`。
     - Postcondition: `state == .finished`
     */
    public func finish() {
        guard state != .finished else { return }

        /// ✅ 统一由 StopDetector 收尾 pending stop
        stops = stopDetector.finish(
            stops: stops,
            lastPoint: lastAcceptedPoint
        )

        state = .finished
    }
    /**
     重置引擎到初始状态。

     - Important: 该方法会清空摘要、分段、停车等所有结果，并清空内部状态。
     - Note: `reset()` 后引擎处于 `idle`，需要调用 `start()` 才会继续处理点。
     - Postcondition:
       - `state == .idle`
       - `pointsCount == 0`
       - `summary == .empty`
       - `segments.isEmpty == true`
       - `stops.isEmpty == true`
     */
    public func reset() {
        state = .idle

        pointsCount = 0
        summary = .empty
        segments.removeAll()
        stops.removeAll()

        lastAcceptedPoint = nil

        cleaner.reset()
        smoother.reset()
        analyzer.reset()
        segmentAnalyzer.reset()
        stopDetector.reset()
    }

    // MARK: - Input
    /**
     追加一个轨迹点（实时录制场景的主要入口）。

     - Important:
       1. 该方法只接受 `GeoPoint`，不关心数据来源；
          应用层可来自 CoreLocation、文件回放、网络同步等。
       2. 该方法是同步处理：调用结束后，`summary/segments/stops` 均为最新状态。

     - Warning: 若 `state != .running`，该方法默认不会处理输入点（避免误写入）。

     - Parameter point: 轨迹点（建议包含 timestamp、coordinate、altitude、speed 等）。
     */
    public func append(_ point: GeoPoint) {
        guard state == .running else { return }

        // 1) Cleaner：丢掉异常点/重复点/时间倒退点等
        let cleaned: GeoPoint?
        if config.enableCleaner {
            cleaned = cleaner.process(point, last: lastAcceptedPoint)
        } else {
            cleaned = point
        }

        guard var accepted = cleaned else { return }

        // 2) Smoother（可选）
        if config.enableSmoother {
            accepted = smoother.process(accepted, last: lastAcceptedPoint)
        }

        // 3) 更新内部状态
        pointsCount += 1

        // 4) Analyzer：先更新基础 summary（距离/时间/速度等）
        summary = analyzer.process(accepted, last: lastAcceptedPoint, summary: summary)

        // 5) SegmentAnalyzer：生成/追加 segments
        segments = segmentAnalyzer.process(accepted, last: lastAcceptedPoint, segments: segments)

        // ✅ 6) 把 SegmentAnalyzer 的结果“喂回 TrackAnalyzer”（回写 summary）
        summary = applySegmentsBackToSummary(
            summary: summary,
            latestPoint: accepted,
            segments: segments
        )

        // ✅ 7) StopDetector：统一由 StopDetector 处理停车逻辑
        stops = stopDetector.process(
            accepted,
            last: lastAcceptedPoint,
            stops: stops
        )

        lastAcceptedPoint = accepted
    }
    /**
     批量处理轨迹点（回放/导入场景）。

     - Important: 该方法会按输入数组顺序依次 `append`，因此输入顺序必须是时间正序。
     - Parameter points: 轨迹点数组（建议已按时间排序）。
     */
    public func process(_ points: [GeoPoint]) {
        if state != .running { start() }
        for p in points {
            append(p)
        }
    }
}

// MARK: - Segment → Summary Bridge

private extension TrackEngine {

    /**
     将 SegmentAnalyzer 产物回写到 RouteSummary。

     - Important:
       目前 `TrackAnalyzer` 仍然是“点驱动”的统计，
       但分段信息（坡度、海拔增益等）天然更适合基于 segment 汇总。
       所以我们在 TrackEngine 做一个“桥接回写”，让链路闭环先跑起来。

     - Note:
       这是首版策略：简单可用、便于单测。
       后续你如果决定把这些统计逻辑正式挪进 TrackAnalyzer（或新建 TrackSummaryAnalyzer），
       这里只需要替换掉即可。
     */
    private func applySegmentsBackToSummary(summary: RouteSummary,latestPoint: GeoPoint,segments: [RouteSegment]) -> RouteSummary {

        // segmentCount
        let segmentCount = segments.count

        // elevation gain / loss
        var gain: Double = 0
        var loss: Double = 0

        // gradient stats
        var maxG: Double
        var minG: Double

        if segments.isEmpty {
            // 没有 segment，继承旧值（首点 / 异常情况）
            maxG = summary.maxGradient
            minG = summary.minGradient
        } else {
            // 由 segments 自身决定
            maxG = -Double.greatestFiniteMagnitude
            minG =  Double.greatestFiniteMagnitude
        }

        for s in segments {
            if s.elevationDelta > 0 { gain += s.elevationDelta }
            if s.elevationDelta < 0 { loss += abs(s.elevationDelta) }

            maxG = max(maxG, s.gradient)
            minG = min(minG, s.gradient)
        }

        // max/min altitude（点驱动，增量更新）
        let maxAlt: Double
        let minAlt: Double
        if summary.pointCount <= 1 {
            maxAlt = latestPoint.altitude
            minAlt = latestPoint.altitude
        } else {
            maxAlt = max(summary.maxAltitude, latestPoint.altitude)
            minAlt = min(summary.minAltitude, latestPoint.altitude)
        }

        return RouteSummary(
            isValid: summary.isValid,
            pointCount: summary.pointCount,
            segmentCount: segmentCount,
            totalDistance: summary.totalDistance,
            averageSpeed: summary.averageSpeed,
            maxSpeed: summary.maxSpeed,
            totalTime: summary.totalTime,
            movingTime: summary.movingTime,
            stoppedTime: summary.stoppedTime,
            totalElevationGain: gain,
            totalElevationLoss: loss,
            maxAltitude: maxAlt,
            minAltitude: minAlt,
            maxGradient: maxG,
            minGradient: minG,
            startPoint: summary.startPoint,
            endPoint: summary.endPoint,
            metadata: summary.metadata
        )
    }
}
