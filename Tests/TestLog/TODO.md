# NavigationKit RouteAnalysis 改进计划

> 基于 2026-01-18 实际测试日志的分析结果

## 📊 测试场景总结

- **测试日期**: 2026-01-18
- **测试时长**: 23分15秒 (02:56:37 - 03:19:53)
- **总距离**: 3.07 km
- **轨迹点数**: 10 个
- **定位权限**: 始终允许 ✅
- **运行模式**: 大部分时间在后台

### 发现的问题

1. **后台定位频率极低** - 3公里只记录了10个点
2. **`speed` 数据缺失** - 后台模式下大量点的 `speed` 为 `nil`
3. **movingTime 计算不准** - 23分钟的行程只判定39秒在移动
4. **averageSpeed 失真** - 显示 78.84 km/h（实际应为 ~8-10 km/h）

---

## 🔴 高优先级任务

### Task 1: 修复 TrackAnalyzer 对 `speed = nil` 的处理

**问题描述**:
```swift
// 当前代码：TrackAnalyzer.swift 第 77 行
let speed = max(current.speed ?? 0, 0)
```

当 `speed` 为 `nil` 时，直接当作 `0` 处理，导致：
- 后台采集的轨迹段被误判为"静止"
- `movingTime` 严重偏小（测试中只有 39秒，实际应有 ~18分钟）
- `averageSpeed` 虚高（因为分母太小）

**改进方案**:

```swift
// 建议修改 TrackAnalyzer.swift process 方法中的时间统计部分
if let last = last {
    let deltaTime = current.timestamp.timeIntervalSince(last.timestamp)
    if deltaTime > 0 {
        totalTime += deltaTime

        // ✅ 优先使用 GPS 速度，若无则基于位移推断
        let speed: Double
        if let reportedSpeed = current.speed {
            // GPS 提供了速度数据，直接使用
            speed = max(reportedSpeed, 0)
        } else {
            // 后台模式常见：speed 为 nil
            // 推断速度 = 两点间距离 / 时间间隔
            let distance = GeoDistance.distance(from: last, to: current)
            speed = (deltaTime > 0) ? distance / deltaTime : 0
        }
        
        if speed > movingSpeedThreshold {
            movingTime += deltaTime
        } else {
            stoppedTime += deltaTime
        }
    }
}
```

**预期效果**:
- `movingTime`: 39s → ~1100s
- `averageSpeed`: 283 km/h → ~10 km/h
- 数据更符合实际情况

**影响范围**:
- ✅ 不破坏 API
- ✅ 单元测试兼容（speed 有值时行为不变）
- ⚠️ 需要更新测试用例，覆盖 `speed = nil` 的场景

**工作量**: ~10 行代码

---

## 🟡 中优先级任务

### Task 2: 修复 StopDetector 对 `speed = nil` 的处理

**问题描述**:
```swift
// 当前代码：StopDetector.swift 第 83 行
let speed = max(0, point.speed ?? 0)
```

同样的问题：`nil` 被当作 `0`，导致后台所有点都触发"可能停车"状态。

**改进方案**:

1. 修改 `process` 方法签名，增加 `last` 参数：

```swift
public func process(
    _ point: GeoPoint, 
    last: GeoPoint?,  // ← 新增
    stops: [TrackEngine.StopEvent]
) -> [TrackEngine.StopEvent]
```

2. 推断速度逻辑：

```swift
let speed: Double
if let reportedSpeed = point.speed {
    speed = max(0, reportedSpeed)
} else if let last = last {
    // 基于位移推断
    let distance = GeoDistance.distance(from: last, to: point)
    let deltaTime = point.timestamp.timeIntervalSince(last.timestamp)
    speed = (deltaTime > 0) ? distance / deltaTime : 0
} else {
    // 第一个点，无法推断
    speed = 0
}
```

3. 更新 TrackEngine 中的调用：

```swift
// TrackEngine.swift 第 262 行
stops = stopDetector.process(smoothed, last: lastAcceptedPoint, stops: stops)
```

**影响范围**:
- ⚠️ API 变更（Breaking Change）
- 需要更新所有调用处
- 需要更新单元测试

**工作量**: ~15 行代码 + 测试更新

**替代方案**:
如果不想破坏 API，可以新增一个 `process(_:last:stops:)` 重载方法，保留旧方法标记为 `@available(*, deprecated)`。

---

### Task 3: 完善 `averageSpeed` 的文档说明

**问题描述**:
当前 `RouteSummary.averageSpeed` 的文档不够清晰，用户可能误解其含义。

**改进方案**:

```swift
// RouteSummary.swift

/// 平均速度（单位：米/秒）
///
/// - Important: 
///   该速度基于 **移动时间** (`movingTime`) 计算，不包含静止时段。
///   如果你需要"全程平均速度"，请使用 `totalDistance / totalTime`。
///
/// - Formula: `totalDistance / movingTime`
///
/// - Note: 
///   "移动" 的定义由 `TrackAnalyzer.Config.movingSpeedThreshold` 控制。
///   默认阈值为 0.5 m/s (1.8 km/h)，低于此速度的时段视为静止。
///
/// - SeeAlso: 
///   - `movingTime`: 移动时间（速度 > 阈值的累计时间）
///   - `totalTime`: 总时间（首尾点时间跨度）
///   - `TrackAnalyzer.Config.movingSpeedThreshold`
///
/// - Example:
///   ```swift
///   let movingAverage = summary.averageSpeed * 3.6  // 转换为 km/h
///   let overallAverage = (summary.totalDistance / summary.totalTime) * 3.6
///   print("移动平均: \(movingAverage) km/h")
///   print("整体平均: \(overallAverage) km/h")
///   ```
public let averageSpeed: Double
```

**工作量**: ~15 行注释

---

### Task 4: 在 UI 层增加"整体平均速度"显示

**建议**:
在 HomePageViewModel 的 `analyzeRoute()` 方法中，同时显示两个速度值：

```swift
// HomePageViewModel.swift
let averageSpeedKmh = summary.averageSpeed * 3.6
let overallSpeedKmh = (summary.totalDistance / summary.totalTime) * 3.6

Log("  🚀 移动平均: \(String(format: "%.2f", averageSpeedKmh)) km/h")
Log("  🏃 整体平均: \(String(format: "%.2f", overallSpeedKmh)) km/h")
Log("  ⏱️ 移动时长: \(formatTime(summary.movingTime))")
Log("  ⏱️ 停止时长: \(formatTime(summary.stoppedTime))")
```

这样用户可以同时看到两个维度的数据。

**工作量**: UI 层改动，不属于 NavigationKit 本身

---

## 📝 低优先级任务

### Task 5: 增加后台模式使用文档

**建议位置**: README.md 或新建 `Docs/BackgroundMode.md`

**内容要点**:

````markdown
## ⚠️ 后台模式注意事项

### iOS 后台定位的限制

在 iOS 后台模式下，CoreLocation 会：

1. **降低位置更新频率**
   - 前台：~1秒/次
   - 后台：几分钟/次（取决于移动速度和系统资源）

2. **speed 数据可能缺失**
   - `CLLocation.speed` 可能为 `-1` 或不可用
   - NavigationKit 会基于位移推断速度（v2.1+）

3. **精度可能下降**
   - 后台模式下 GPS 精度可能从 5-10m 降至 50-100m

### NavigationKit 的处理策略

#### v2.0（当前版本）
- `speed = nil` → 视为 `0` → 计入 `stoppedTime`
- ⚠️ 可能导致 `movingTime` 偏小，`averageSpeed` 偏高

#### v2.1+（计划中）
- `speed = nil` → 基于位移推断 → 更准确的移动/静止判定
- ✅ 推荐用于后台轨迹记录场景

### 最佳实践

如果你的 App 主要在后台记录轨迹：

1. **权限配置**
   ```swift
   // Info.plist
   NSLocationAlwaysAndWhenInUseUsageDescription
   UIBackgroundModes: ["location"]
   ```

2. **调整阈值**
   ```swift
   var config = TrackEngine.Config()
   config.analyzer.movingSpeedThreshold = 0.2  // 降低移动阈值
   config.stopDetection.speedThreshold = 0.15  // 降低停车阈值
   ```

3. **UI 显示**
   - 同时显示"移动平均速度"和"整体平均速度"
   - 显示 `movingTime` 和 `stoppedTime` 帮助用户理解

4. **数据验证**
   - 检查 `summary.pointCount`（点数过少说明采样稀疏）
   - 检查平均时间间隔：`totalTime / (pointCount - 1)`
   - 如果间隔 > 60秒，建议提示用户数据可能不准确

### 测试建议

后台模式测试场景：
- ✅ 骑行/驾车 10公里以上
- ✅ App 全程后台运行
- ✅ 对比前台和后台的数据差异
````

**工作量**: ~1小时文档编写

---

### Task 6: 增加单元测试覆盖 `speed = nil` 场景

**测试用例建议**:

```swift
// RouteAnalysisTests.swift

/// 测试后台模式：speed 为 nil 时应基于位移推断
func testBackgroundMode_SpeedNilInference() {
    let engine = TrackEngine()
    engine.start()
    
    // 模拟后台采集：点稀疏，speed 为 nil
    let p1 = makePoint(lat: 30.0, lon: 120.0, offset: 0, speed: nil)
    let p2 = makePoint(lat: 30.001, lon: 120.0, offset: 60, speed: nil)  // 60秒后
    
    engine.append(p1)
    engine.append(p2)
    engine.finish()
    
    let summary = engine.summary
    
    // 验证：即使 speed 为 nil，也应正确判定为"移动"
    // 距离约 111m，时间 60s，推断速度 = 1.85 m/s > 0.5 (阈值)
    XCTAssertGreaterThan(summary.movingTime, 50, "应判定为移动状态")
    XCTAssertLessThan(summary.stoppedTime, 10, "不应判定为静止")
}

/// 测试前后台混合：部分点有 speed，部分没有
func testMixedMode_PartialSpeedData() {
    let engine = TrackEngine()
    engine.start()
    
    engine.append(makePoint(offset: 0, speed: 5.0))       // 前台
    engine.append(makePoint(lat: 30.001, offset: 10, speed: 5.0))
    engine.append(makePoint(lat: 30.002, offset: 70, speed: nil))  // 后台
    engine.append(makePoint(lat: 30.003, offset: 130, speed: nil))
    engine.append(makePoint(lat: 30.004, offset: 140, speed: 5.0)) // 恢复前台
    
    engine.finish()
    
    // 验证整体统计的合理性
    XCTAssertGreaterThan(engine.summary.movingTime, 120)
    XCTAssertTrue(engine.summary.isValid)
}
```

**工作量**: ~2小时（编写 + 调试）

---

## 🎯 实施建议

### Phase 1: 核心修复（1-2天）
1. ✅ Task 1: 修复 TrackAnalyzer
2. ✅ Task 2: 修复 StopDetector
3. ✅ Task 6: 增加单元测试

### Phase 2: 文档完善（半天）
4. ✅ Task 3: 完善注释
5. ✅ Task 5: 增加后台模式文档

### Phase 3: UI 层改进（1天）
6. ✅ Task 4: UI 层显示优化（这个在 App 项目中实现）

---

## 📋 验证清单

完成上述改进后，使用相同测试场景验证：

- [ ] `movingTime` 应为 ~1000-1200 秒（而非 39 秒）
- [ ] `stoppedTime` 应为 ~200-400 秒（而非 1356 秒）
- [ ] `averageSpeed` 应为 ~10 km/h（而非 78.84 km/h）
- [ ] Stop 事件识别更准确
- [ ] 单元测试全部通过
- [ ] 前台模式下的行为不受影响

---

## 🚀 长期优化方向

### 1. 自适应阈值
根据采样频率自动调整 `movingSpeedThreshold`：
- 前台（1秒/点）→ 阈值 0.5 m/s
- 后台（60秒/点）→ 阈值 0.2 m/s

### 2. GPS 质量评分
增加 `summary.quality` 字段：
```swift
public enum DataQuality {
    case excellent  // 前台，高频采样
    case good       // 前台，正常采样
    case fair       // 后台，中频采样
    case poor       // 后台，低频采样
}
```

### 3. 轨迹平滑优化
针对后台稀疏点，提供插值选项：
```swift
config.smoother = .enabled(interpolation: .catmullRom)
```

---

## 📝 相关资料

- **测试日志**: `Tests/TestLog/2026-01-18.log`
- **问题分析**: [Internal Discussion Thread]
- **Apple 文档**: [Core Location Best Practices](https://developer.apple.com/documentation/corelocation)

---

**最后更新**: 2026-01-19  
**目标版本**: NavigationKit 2.1
