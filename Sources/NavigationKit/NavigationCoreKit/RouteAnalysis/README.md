# RouteAnalysis
<pre>
├── ...
├── RouteAnalysis
│   ├── Distance
│   │   ├── BearingCalculator.swift
│   │   └── GeoDistance.swift
│   ├── Models
│   │   ├── _README.md
│   │   ├── GeoPoint.swift
│   │   ├── RouteSegment.swift
│   │   └── RouteSummary.swift
│   ├── README.md
│   ├── Segments
│   │   ├── ElevationGainAnalyzer.swift
│   │   ├── SegmentAnalyzer.swift
│   │   └── SlopeClassifier.swift
│   ├── Stops
│   │   └── StopDetector.swift
│   └── Track
│       ├── TrackAnalyzer.swift
│       ├── TrackCleaner.swift
│       ├── TrackEngine.swift
│       └── TrackSmoother.swift
└── Speed
    ├── SpeedFilter.swift
    └── SpeedManager.swift
</pre>
`RouteAnalysis` 是 `NavigationKit` 中用于 **轨迹分析（Track Analysis）** 的纯算法模块。

它不依赖 UI、不依赖系统环境（如 CoreLocation / MapKit），  
只接收标准化的 `GeoPoint` 输入，  
输出结构化的轨迹分析结果（`RouteSummary` / `RouteSegment` / Stop Events），  
支持 **实时录制** 与 **历史轨迹回放** 两种使用场景。

---

## 设计目标

- **纯算法、可单测、可回放**
- **职责分离清晰，不做“万能类”**
- **允许阶段性实现，不强行一次性完美**
- **点驱动 + 段驱动并存，逐步演进**

---

## 核心数据模型

### GeoPoint

轨迹系统中的最小数据单元，代表一次原始定位采样。

特点：
- 仅包含**原始数据**
- 不包含任何算法处理结果
- 可来自 CoreLocation / 文件 / 网络

---

### RouteSegment

由两个连续 `GeoPoint` 构成的最小分析单元（点 → 段）。

描述内容包括：
- 距离
- 时间
- 平均速度
- 海拔变化
- 坡度（gradient）
- 坡段类型（uphill / downhill / flat）

> `RouteSegment` 只承载结果，不包含计算逻辑。

---

### RouteSummary

整条轨迹的统计汇总结果，用于 UI / 存储 / 同步。

包含：
- 距离、时间、速度统计
- 海拔统计
- 坡度统计
- 起点 / 终点
- 自定义 metadata

---

## 总控引擎：TrackEngine

`TrackEngine` 是整个 RouteAnalysis 的**算法编排中枢**。

它负责：
- 模块调用顺序
- 状态管理
- 中间结果回写
- 最终结果汇总

### 处理流水线

```
GeoPoint
  ↓
TrackCleaner
  ↓
TrackSmoother (optional)
  ↓
TrackAnalyzer
  ↓
SegmentAnalyzer
  ↓
Segment → Summary Bridge
  ↓
StopDetector
```

---

## 模块职责概览

### TrackCleaner
- 丢弃异常点（时间倒退 / 过密 / 速度异常 / 海拔突变）
- 无状态、只做是否接受判断

### TrackSmoother
- 对通过清洗的点做低通滤波
- 不丢点、不改变时间顺序

### TrackAnalyzer
- 点驱动整体统计（距离 / 时间 / 速度）
- 完全无状态，summary 递推生成

### SegmentAnalyzer
- 唯一的「点 → 段」入口
- 计算距离、时间、坡度
- 接入 `SlopeClassifier`

### SlopeClassifier
- 坡度数值 → 坡段类型映射
- 不涉及轨迹上下文

### StopDetector
- 基于速度识别停车时间区间
- 与 TrackAnalyzer 的 stoppedTime 语义独立

---

## Segment → Summary 桥接策略（当前阶段）

当前阶段采用 **桥接回写**：

- TrackAnalyzer：点驱动统计
- SegmentAnalyzer：段级结果
- TrackEngine：负责将 segment 统计回写到 summary

该设计用于：
- 保证链路闭环
- 避免过早引入复杂 Analyzer
- 保证阶段性可测试、可维护

---

## 已知的阶段性实现（V1）

### 海拔爬升 / 下降（Elevation Gain / Loss）

当前策略：
- 基于 `RouteSegment.elevationDelta` 的直接累计（naive）

说明：
- 该实现用于链路验证
- 不处理噪声、回抖、微小起伏
- **不作为最终爬升算法**

---

## 规划中的下一阶段优化（V2+）

以下模块已预留，但当前版本刻意保持为空或最小实现：

### BearingCalculator
- 目标：提供更稳定、可复用的航向角 / 方向计算
- 当前状态：占位文件，仅保留接口
- 未来用途：
  - 轨迹方向变化分析
  - 转向检测
  - 与地图 / UI 方向展示解耦

### ElevationGainAnalyzer
- 目标：替代当前 naive elevation gain/loss 统计
- 规划能力：
  - 去噪（小幅上下抖动）
  - 阈值过滤
  - 可配置爬升策略
- 未来将独立于 TrackAnalyzer / SegmentAnalyzer

### TrackSummaryAnalyzer（候选）
- 用于统一承接「段级 → 汇总级」统计逻辑
- 可能取代当前 TrackEngine 内的桥接回写实现

---

## 当前状态总结

- ✅ 架构清晰、职责稳定
- ✅ 支持实时 / 回放 / 导入
- ✅ 所有模块可单测
- ⚠️ 性能与算法精度仍以正确性优先
- ⚠️ 若干统计为阶段性实现，已明确演进路径

---

## 适用场景

- 骑行 / 徒步 / 行驶轨迹分析
- 行程记录
- 历史轨迹回放
- 数据导入（GPX / KML）
