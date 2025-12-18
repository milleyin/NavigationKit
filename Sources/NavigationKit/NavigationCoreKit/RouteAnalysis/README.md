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
