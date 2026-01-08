//
//  TrackEngine.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

/**
 - Important:
     `TrackEngine` 是 RouteAnalysis 的“轨迹计算总控引擎”。它只负责 **算法编排** 与 **结果汇总**，不负责任何设备数据采集（如 CoreLocation / MapKit）。
 
 - Important:
     `TrackEngine` 必须保持“纯算法”，不依赖 UI 或系统环境，以确保 **可单元测试、可回放、可复现**。

 - Optimization:
     v2.0 进行了性能重构：
     采用 **增量更新 (Incremental Update)** 策略替代了全量遍历。
     现在 `append` 操作的时间复杂度稳定在 **O(1)**，彻底解决了长轨迹录制时的性能下降问题。

 - SeeAlso:
   1. 清洗（`TrackCleaner`）—— 剔除异常点、重复点、时间倒退点
   2. 平滑（`TrackSmoother`，可选）—— 对轨迹做滤波
   3. 分析（`TrackAnalyzer`）—— 距离、时间、速度统计
   4. 分段（`SegmentAnalyzer`）—— 坡段、速度段切分
   5. 停车（`StopDetector`）—— 停车点识别
   6. 汇总（`RouteSummary`）—— 输出统一轨迹摘要

 - Note:
     该引擎为 **同步处理模型**：
     输入确定 → 输出确定。
     并发 / 异步调度由上层负责。
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
        
        /// 清洗器配置。传 `nil` 则禁用清洗功能。
        public var cleaner: TrackCleaner.Config? = .init()
        
        /// 平滑器配置。传 `nil` 则禁用平滑功能（默认关闭，防过拟合）。
        public var smoother: TrackSmoother.Config? = nil
        
        /// 停车检测配置。
        public var stopDetection: StopDetector.Config = .init()
        
        /// 基础统计分析配置（如移动速度阈值）。
        public var analyzer: TrackAnalyzer.Config = .init()
        
        /// 针对特定场景的预设（方便用户直接调用）
        public static let cycling = Config() // 默认就是骑行
        public static let hiking: Config = {
            var c = Config()
            c.cleaner?.maxReasonableSpeed = 10 // 徒步速度
            c.stopDetection.speedThreshold = 0.1
            return c
        }()
        
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

    /// 分段结果（v2.0 改为增量追加）。
    public private(set) var segments: [RouteSegment] = []

    /// 停车事件列表。
    public private(set) var stops: [StopEvent] = []

    // MARK: - Dependencies (Algorithm Modules)

    private let config: Config

    private let cleaner: TrackCleaner?
    private let smoother: TrackSmoother?
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
    public init(config: Config = .cycling) {
        self.config = config
        // Cleaner & Smoother (Optional)
        if let c = config.cleaner { self.cleaner = TrackCleaner(config: c) } else { self.cleaner = nil }
        if let s = config.smoother { self.smoother = TrackSmoother(config: s) } else { self.smoother = nil }
        
        // Analyzer & Detector (Required)
        self.analyzer = TrackAnalyzer(config: config.analyzer)
        self.stopDetector = StopDetector(config: config.stopDetection)
        
        self.segmentAnalyzer = SegmentAnalyzer()
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
        state = .running
    }
    
    /**
     结束轨迹处理流程。

     - Important: `finish()` 会将引擎状态置为 `finished`，之后默认不再接收新点。
     - Note: 如果仍希望继续追加点，可以再次调用 `start()` 进入 `running`。
     - Postcondition: `state == .finished`
     */
    public func finish() {
        guard state != .finished else { return }

        /// 统一由 StopDetector 收尾 pending stop
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

        cleaner?.reset()
        smoother?.reset()
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
       3. v2.0 优化：执行 O(1) 复杂度的增量更新。

     - Warning: 若 `state != .running`，该方法默认不会处理输入点（避免误写入）。

     - Parameter point: 轨迹点（建议包含 timestamp、coordinate、altitude、speed 等）。
     */
    public func append(_ point: GeoPoint) {
        guard state == .running else { return }
        
        // 1. Cleaner (Optional)
        // 修正逻辑：
        // - 如果 cleaner 存在：必须听它的（它返回 nil 就丢弃，返回点就保留）。
        // - 如果 cleaner 不存在：直接放行 (cleaned = point)。
        
        let cleaned: GeoPoint?
        if let cleaner = cleaner {
            cleaned = cleaner.process(point, last: lastAcceptedPoint)
        } else {
            cleaned = point
        }
        
        // 如果被洗掉了 (cleaned == nil)，直接 return，不再往下走
        guard let accepted = cleaned else { return }
        
        // 2. Smoother (Optional)
        // ✨ 同上，smoother 存在就平滑，不存在就用原值
        let smoothed = smoother?.process(accepted, last: lastAcceptedPoint) ?? accepted
        
        // 3. Update Internal State
        pointsCount += 1
        
        // 4. Analyzer (Point-Driven)
        summary = analyzer.process(smoothed, last: lastAcceptedPoint, summary: summary)
        summary = updateSummaryAltitude(summary: summary, point: smoothed)
        
        // 5. SegmentAnalyzer (Segment-Driven)
        if let newSegment = segmentAnalyzer.process(smoothed, last: lastAcceptedPoint) {
            segments.append(newSegment)
            summary = updateSummaryWithSegment(summary: summary, segment: newSegment)
        }
        
        // 6. StopDetector
        stops = stopDetector.process(smoothed, last: lastAcceptedPoint, stops: stops)
        
        lastAcceptedPoint = smoothed
    }
    
    /**
     批量处理轨迹点（回放/导入场景）。

     - Important: 该方法会按输入数组顺序依次 `append`，因此输入顺序必须是时间正序。
     - Parameter points: 轨迹点数组（建议已按时间排序）。
     */
    public func process(_ points: [GeoPoint]) {
        if state != .running { start() }
        points.forEach { append($0) }
    }
}

// MARK: - Incremental Update Helpers (Private)

private extension TrackEngine {

    /**
     [O(1)] 增量更新：根据新生成的 Segment 更新统计信息（爬升、坡度）。
     */
    func updateSummaryWithSegment(summary: RouteSummary, segment: RouteSegment) -> RouteSummary {
        
        // 更新爬升/下降
        var gain = summary.totalElevationGain
        var loss = summary.totalElevationLoss
        if segment.elevationDelta > 0 {
            gain += segment.elevationDelta
        } else {
            loss += abs(segment.elevationDelta)
        }
        
        // 更新坡度极值
        // 注意：如果是第一个段落，原 summary 中的极值可能为初始值 (0)，需要特殊处理
        let maxG: Double
        let minG: Double
        
        if summary.segmentCount == 0 {
             // 此时传入的 summary.segmentCount 还没加 1（或者刚加），
             // 但逻辑上这是第一个有效的 segment update
             maxG = segment.gradient
             minG = segment.gradient
        } else {
             maxG = max(summary.maxGradient, segment.gradient)
             minG = min(summary.minGradient, segment.gradient)
        }
        
        return RouteSummary(
            isValid: summary.isValid,
            pointCount: summary.pointCount,
            segmentCount: summary.segmentCount + 1, // 手动 +1，保持同步
            totalDistance: summary.totalDistance,
            averageSpeed: summary.averageSpeed,
            maxSpeed: summary.maxSpeed,
            totalTime: summary.totalTime,
            movingTime: summary.movingTime,
            stoppedTime: summary.stoppedTime,
            totalElevationGain: gain,
            totalElevationLoss: loss,
            maxAltitude: summary.maxAltitude,
            minAltitude: summary.minAltitude,
            maxGradient: maxG,
            minGradient: minG,
            startPoint: summary.startPoint,
            endPoint: summary.endPoint,
            metadata: summary.metadata
        )
    }
    
    /**
     [O(1)] 增量更新：根据当前点更新海拔极值。
     */
    func updateSummaryAltitude(summary: RouteSummary, point: GeoPoint) -> RouteSummary {
        
        let maxAlt: Double
        let minAlt: Double
        
        // 如果是第一个点（或之前的点数少于1），直接以当前点初始化
        // 注意：pointsCount 在调用此方法前已经 +1 了
        if summary.pointCount <= 1 {
            maxAlt = point.altitude
            minAlt = point.altitude
        } else {
            maxAlt = max(summary.maxAltitude, point.altitude)
            minAlt = min(summary.minAltitude, point.altitude)
        }
        
        return RouteSummary(
            isValid: summary.isValid,
            pointCount: summary.pointCount,
            segmentCount: summary.segmentCount,
            totalDistance: summary.totalDistance,
            averageSpeed: summary.averageSpeed,
            maxSpeed: summary.maxSpeed,
            totalTime: summary.totalTime,
            movingTime: summary.movingTime,
            stoppedTime: summary.stoppedTime,
            totalElevationGain: summary.totalElevationGain,
            totalElevationLoss: summary.totalElevationLoss,
            maxAltitude: maxAlt,
            minAltitude: minAlt,
            maxGradient: summary.maxGradient,
            minGradient: summary.minGradient,
            startPoint: summary.startPoint,
            endPoint: summary.endPoint,
            metadata: summary.metadata
        )
    }
}
