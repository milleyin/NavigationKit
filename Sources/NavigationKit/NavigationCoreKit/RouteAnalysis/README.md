NavigationCoreKit/
  ├── RouteAnalysis/
  │     ├── Models/
  │     │     ├── GeoPoint.swift
  │     │     └── RouteSegment.swift
  │     │
  │     ├── Distance/
  │     │     ├── GeoDistance.swift       ← Haversine / Vincenty
  │     │     └── BearingCalculator.swift
  │     │
  │     ├── Track/
  │     │     ├── TrackAnalyzer.swift     ← 轨迹整体分析
  │     │     ├── TrackCleaner.swift      ← 清洗异常点
  │     │     └── TrackSmoother.swift     ← 滤波（可选）
  │     │
  │     ├── Segments/
  │     │     ├── SegmentAnalyzer.swift   ← 坡段切分＋速度段落
  │     │     └── SlopeClassifier.swift   ← 自动识别上坡/下坡
  │     │
  │     └── Stops/
  │           └── StopDetector.swift      ← 停车识别

✅ 第一优先级（最基础）
    1.    TrackCleaner
    •    去重
    •    时间乱序
    •    不合理跳点（瞬移）

这是所有后续算法的地基。

⸻

✅ 第二优先级（数值稳定性）
    2.    TrackSmoother
    •    位置 / 速度 / 海拔
    •    可以先 very naive（滑动平均都行）

⸻

✅ 第三优先级（分析入口）
    3.    SegmentAnalyzer
    •    先只切“连续段”
    •    不用一开始就坡度 / 停车

⸻

✅ 第四优先级（统计）
    4.    StopDetector
    5.    TrackAnalyzer → RouteSummary
