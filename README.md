# NavigationKit User Guide

![DALL·E-2025-02-21-15 01 39-A-professional-and-modern-promotional-banner-for-NavigationKit-a-powerful-Swift-framework-for-navigation-and-location-based-services -The-design-sh](https://github.com/user-attachments/assets/9c049d13-42ca-47e7-a576-a2dc0afc8c8b)

[中文](README_cn.md)

> **🚏 This guide summarizes the usage of `CoreLocationKit` (location services) and `AppleMapKit` (map rendering & navigation) for iOS & macOS development.**

> **🚨 Warning: Currently, I'm quite busy, so I haven't fully tested it. There might be many bugs. Use with caution!**

> **🔧 Installation: Use Swift Package Manager (SPM) for integration**  

---

## 📍 CoreLocationKit - Location Management

`CoreLocationKit` is an SDK that encapsulates the `CoreLocation` framework, providing functionalities such as **location tracking, heading updates, and reverse geocoding**.

### 1️⃣ Initialize `CoreLocationKit`

`CoreLocationKit` uses a **singleton pattern**, so you can use it directly:
```swift
let locationManager = CoreLocationKit.shared
```

---

### 2️⃣ Subscribe to Location Updates (Continuous Tracking)

Use `Combine` to listen for **real-time location updates**:
```swift
import Combine

var cancellable: AnyCancellable?

cancellable = CoreLocationKit.shared.locationPublisher
    .sink { location in
        if let location = location {
            print("Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        } else {
            print("Unable to get location")
        }
    }
```

---

### 3️⃣ Get Current Location (One-time Request)

If you **only need the location once**, use:
```swift
CoreLocationKit.shared.requestCurrentLocation()
```
Then listen for `locationPublisher`:
```swift
cancellable = CoreLocationKit.shared.locationPublisher
    .compactMap { $0 }
    .sink { location in
        print("Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
```

---

### 4️⃣ Listen to Authorization Status

Monitor **changes in location authorization**:
```swift
cancellable = CoreLocationKit.shared.authorizationStatusPublisher
    .sink { status in
        print("Current location authorization status: \(status.rawValue)")
    }
```

---

### 5️⃣ Monitor Device Heading (Compass)

Listen for **device heading updates**:
```swift
cancellable = CoreLocationKit.shared.headingPublisher
    .sink { heading in
        if let heading = heading {
            print("Current heading: \(heading.trueHeading)")
        } else {
            print("Unable to get heading data")
        }
    }
```

---

### 6️⃣ Retrieve Address from Current Location (Reverse Geocoding)

Get the **address** of the current location:
```swift
cancellable = CoreLocationKit.shared.addressPublisher
    .sink(receiveCompletion: { completion in
        if case .failure(let error) = completion {
            print("Failed to retrieve address: \(error)")
        }
    }, receiveValue: { address in
        print("Current address: \(address)")
    })
```

---

### 7️⃣ Enable Background Location Updates

Enable **background location tracking** (disabled by default):
```swift
CoreLocationKit.shared.allowBackgroundLocationUpdates(true)
```

---

## 🗺 AppleMapKit - Map Management

`AppleMapKit` is a wrapper around `MKMapView`, providing map rendering, annotations, and navigation features.

### 1️⃣ Initialize `AppleMapKit`
```swift
let appleMap = AppleMapKit()
```

---

### 2️⃣ Use `AppleMapKit` in `UIKit`
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

---

### 3️⃣ Use `AppleMapKit` in `SwiftUI`
`AppleMapKit` needs to be **wrapped in `UIViewRepresentable`** to work in `SwiftUI`:
```swift
import SwiftUI

struct AppleMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        return AppleMapKit().mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        AppleMapView()
            .edgesIgnoringSafeArea(.all)  // ✅ Full-screen map
    }
}
```

---

### 4️⃣ Set User Tracking Mode
```swift
appleMap.setUserTrackingMode(.follow)
```

---

### 5️⃣ Add Annotations (Multiple Locations)
```swift
let annotations = [
    MultipleAnnotations(name: "Store A", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
    MultipleAnnotations(name: "Store B", location: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094))
]
appleMap.addAnnotations(annotations)
```

---

### 6️⃣ Draw Navigation Route
```swift
let startLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
let destinationLocation = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2711)
appleMap.drawRoute(from: startLocation, to: destinationLocation)
```
**⚠️ Note: This method will** **clear existing routes** **before drawing a new one.**

---

### 7️⃣ Set Custom Annotation Image (iOS Only)
```swift
#if canImport(UIKit)
appleMap.customAnnotationImage = UIImage(named: "customPin")
#endif
```
**⚠️ Recommended image size: `21x31` pixels to avoid UI distortion.**

---

## 🏃 Upcoming Features
- [ ] **RouteKit / Route Recording / Path Planning**
- [ ] **SyncKit / Multi-device Location Sync / Cloud Storage**
