# NavigationKit使用指南

> **🚏 本指南总结 `CoreLocationKit`（定位功能）和 `AppleMapKit`（地图功能）的使用方式，适用于 iOS & macOS 开发。**

> **🚨 友情提醒：目前工作比较忙，没空测试，可能bug一堆，请谨慎服用**

> **🔧 安装：使用 Swift Package Manager（SPM）安裝**  

## 📍 CoreLocationKit - 位置管理

`CoreLocationKit` 是一个封装了 `CoreLocation` 框架的 SDK，用于管理 **定位、方向、地址解析** 等功能。

### 1️⃣ 初始化 `CoreLocationKit`

`CoreLocationKit` 采用 **单例模式**，直接使用：

```swift
let locationManager = CoreLocationKit.shared
```

### 2️⃣ 订阅位置更新

使用 `Combine` 监听 **当前位置** 变化：

```swift
import Combine

var cancellable: AnyCancellable?

cancellable = CoreLocationKit.shared.locationPublisher
    .sink { location in
        if let location = location {
            print("当前位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        } else {
            print("无法获取当前位置")
        }
    }
```

### 3️⃣ 获取当前位置

如果只想获取 **当前定位信息**（而不是持续监听），可以直接访问：

```swift
if let currentLocation = CoreLocationKit.shared.currentLocation {
    print("当前坐标: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
} else {
    print("无法获取当前位置")
}
```

### 4️⃣ 监听授权状态

监听 **定位权限** 变化：

```swift
cancellable = CoreLocationKit.shared.authorizationStatusPublisher
    .sink { status in
        print("当前定位授权状态: \(status.rawValue)")
    }
```

### 5️⃣ 监听方向（指南针）

监听 **设备方向** 变化：

```swift
cancellable = CoreLocationKit.shared.headingPublisher
    .sink { heading in
        if let heading = heading {
            print("当前方向: \(heading.trueHeading)")
        } else {
            print("无法获取方向数据")
        }
    }
```

### 6️⃣ 获取当前地址

获取当前位置对应的 **地址**：

```swift
cancellable = CoreLocationKit.shared.addressPublisher
    .sink(receiveCompletion: { completion in
        if case .failure(let error) = completion {
            print("地址解析失败: \(error)")
        }
    }, receiveValue: { address in
        print("当前位置地址: \(address)")
    })
```

### 7️⃣ 设置是否允许后台定位

启用 **后台定位**（默认关闭）：

```swift
CoreLocationKit.shared.allowBackgroundLocationUpdates(true)
```

---

## 🗺 AppleMapKit - 地图管理

`AppleMapKit` 封装了 `MKMapView`，提供地图渲染、标注、导航等功能。

### 1️⃣ 初始化 `AppleMapKit`

```swift
let appleMap = AppleMapKit()
```

### 2️⃣ 在 `UIKit` 里使用 `AppleMapKit`

```swift
import UIKit

class MapViewController: UIViewController {
    private let appleMap = AppleMapKit()

    override func viewDidLoad() {
        super.viewDidLoad()
        appleMap.mapView.frame = view.bounds
        view.addSubview(appleMap.mapView)
    }
}
```

### 3️⃣ 在 `SwiftUI` 里使用 `AppleMapKit`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        AppleMap()
            .edgesIgnoringSafeArea(.all)  // ✅ 全屏地图
    }
}
```

### 4️⃣ 设置用户追踪模式

```swift
appleMap.setUserTrackingMode(.follow)
```

### 5️⃣ 添加标注（多个商家/地点）

```swift
let annotations = [
    MultipleAnnotations(name: "商店 A", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
    MultipleAnnotations(name: "商店 B", location: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094))
]
appleMap.addAnnotations(annotations)
```

### 6️⃣ 绘制导航线路

```swift
let startLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
let destinationLocation = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2711)
appleMap.drawRoute(from: startLocation, to: destinationLocation)
```

### 7️⃣ 设置自定义标记图像（仅 iOS 可用）

```swift
#if canImport(UIKit)
appleMap.customAnnotationImage = UIImage(named: "customPin")
#endif
```

## 🏃后续功能
- [ ] RouteKit / 轨迹记录 / 路径规划
- [ ] SyncKit / 多设备位置同步 / 云存储
