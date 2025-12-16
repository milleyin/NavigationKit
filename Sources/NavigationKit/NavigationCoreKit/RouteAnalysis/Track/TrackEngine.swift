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
        
        public init() {}
    }

    /**
     停车事件（最小模型）。

     - Important: 后续你可以将其替换为更完整的 Stop 模型，
       或把它移动到 Stops 模块单独定义。
     */
    public struct StopEvent: Equatable, Sendable {

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

    /// StopDetector 的内部状态（最小实现：由 TrackEngine 暂存）
    private var pendingStopStart: GeoPoint?

    // MARK: - Init

    /**
     初始化 `TrackEngine`。

     - Important: 该类不持有任何系统资源，初始化不会触发定位/网络/传感器。
     - Parameter config: 引擎配置，控制清洗、平滑、停车识别等策略。
     */
    public init(config: Config = .init()) {
        self.config = config

        self.cleaner = TrackCleaner(maximumReasonableSpeed: config.maximumReasonableSpeed, maximumAltitudeJump: config.maximumAltitudeJump, minimumTimeInterval: config.minimumTimeInterval)
//        self.smoother = TrackSmoother(config: config)
//        self.analyzer = TrackAnalyzer()
//        self.segmentAnalyzer = SegmentAnalyzer()
//        self.stopDetector = StopDetector(config: config)
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

        // 如果存在 pending stop（低速开始但未结束），这里可以按需关闭。
        if let start = pendingStopStart, let end = lastAcceptedPoint {
            let event = StopEvent(start: start, end: end)
            if event.duration >= config.stopMinimumDuration {
                stops.append(event)
            }
        }
        pendingStopStart = nil

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
        pendingStopStart = nil

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
       若你希望在 `idle` 也能自动 start，可在应用层自行决定调用 `start()`。

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

        // 4) Analyzer：更新 summary（距离/时间/速度/海拔等）
        summary = analyzer.process(accepted, last: lastAcceptedPoint, current: summary)

        // 5) SegmentAnalyzer：更新 segments（先占位，后续丰富）
        segments = segmentAnalyzer.process(accepted, last: lastAcceptedPoint, segments: segments)

        // 6) StopDetector：更新 stops（先做一个最小逻辑，后续可替换为 StopDetector 完整实现）
        updateStopsIfNeeded(point: accepted, last: lastAcceptedPoint)

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

    // MARK: - Stops (Minimal Implementation)

    /**
     最小停车识别逻辑（先让 Traveller 能用）。

     判定规则：
     - 当速度 <= `stopSpeedThreshold` 时进入“可能停车”状态，记录 start 点；
     - 当速度 > `stopSpeedThreshold` 时结束停车，生成 StopEvent；
     - 只有 `duration >= stopMinimumDuration` 才会记录到 `stops`。

     - Note: 这里的速度单位为 m/s，符合你“原始值保持 SI”的原则。
     */
    private func updateStopsIfNeeded(point: GeoPoint, last: GeoPoint?) {
        let speed = max(0, point.speed ?? 0)

        if speed <= config.stopSpeedThreshold {
            if pendingStopStart == nil {
                pendingStopStart = point
            }
        } else {
            if let start = pendingStopStart {
                let end = point
                let event = StopEvent(start: start, end: end)
                if event.duration >= config.stopMinimumDuration {
                    stops.append(event)
                }
                pendingStopStart = nil
            }
        }
    }
}
