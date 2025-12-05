# 🚀 NavigationKit — Swift Navigation Framework

![Banner](https://github.com/user-attachments/assets/9c049d13-42ca-47e7-a576-a2dc0afc8c8b)

> **NavigationKit is a modular Swift framework providing location services, map rendering, and navigation-related algorithms.**
> Built with `CoreLocation`, `MapKit`, `Combine`, and a plug-in architecture for advanced navigation computation.

> ⚠️ **Still under development — use with caution, bugs are expected.**

---

# 📦 Module Overview

NavigationKit consists of **three major layers**:

```
NavigationKit        ← Public API
├── CoreLocationKit  ← GPS / heading / elevation (raw sensors)
├── AppleMapKit      ← Map rendering & routing
└── NavigationCoreKit← Algorithms (elevation, filtering, geo distance…)
```

---

# 📍 CoreLocationKit  
**Unified access to GPS, speed, heading, altitude & reverse geocoding**

### 🔹 Subscribe to Continuous GPS Updates
```swift
CoreLocationKit.shared.locationPublisher
    .sink { location in
        print("lat:", location?.coordinate.latitude ?? 0)
    }
```

### 🔹 Request One-Time Location
```swift
CoreLocationKit.shared.requestCurrentLocation()
```

### 🔹 Speed (m/s)
```swift
CoreLocationKit.shared.speedPublisher
    .sink { speed in
        print("speed:", speed)
    }
```

### 🔹 Altitude (meters)
```swift
CoreLocationKit.shared.altitudePublisher
    .sink { alt in
        print("altitude:", alt)
    }
```

### 🔹 Heading (degrees)
```swift
CoreLocationKit.shared.headingPublisher
    .sink { heading in
        print("heading:", heading?.trueHeading ?? 0)
    }
```

### 🔹 Reverse Geocoding
```swift
CoreLocationKit.shared.addressPublisher
    .sink(receiveValue: { print($0) })
```

---

# 🗺 AppleMapKit  
Minimal wrapper around `MKMapView`.

### 🔹 Use in SwiftUI
```swift
struct AppleMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        AppleMapKit().mapView
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
}
```

### 🔹 Add Annotations
```swift
appleMap.addAnnotations([
    MultipleAnnotations(name: "A", location: .init(latitude: 37.7, longitude: -122.4))
])
```

### 🔹 Draw a Route
```swift
appleMap.drawRoute(from: start, to: destination)
```

---

# 🧠 NavigationCoreKit  
**Algorithm layer for navigation logic**

This module contains reusable **mathematical & geospatial tools**, independent from UI.

## 1️⃣ ElevationKit  
Tools for **elevation, slope calculation, smoothing, and statistics**.

### 🔹 ElevationManager
Processes altitude inputs and provides normalized elevation outputs.

### 🔹 ElevationFilter
Low-pass filtering to remove GPS altitude noise.

### 🔹 GradientCalculator
Computes slope (% or degrees) between two points.

```swift
let gradient = GradientCalculator.slope(from: 120, to: 150, distance: 30)
print("slope =", gradient)
```

### 🔹 ElevationStatistics
Aggregate metrics for routes:

- Ascent  
- Descent  
- Max / min altitude  
- Average gradient  

---

## 2️⃣ Speed Utilities
- Speed filters  
- Running average  
- Motion smoothing  
*(coming soon)*

---

## 3️⃣ Geo Distance (Haversine)
```swift
let d = Haversine.distance(
    from: CLLocationCoordinate2D(latitude: 25.0, longitude: 121.0),
    to: CLLocationCoordinate2D(latitude: 25.01, longitude: 121.02)
)
```

---

# 🧩 Installation (SPM)
```
https://github.com/milleyin/NavigationKit.git
```

---

# 📌 Notes
- iOS ≥ 13, macOS ≥ 11  
- Requires location permissions in Info.plist  
- GPS altitude is noisy — ElevationFilter recommended  
- Route drawing requires network (Apple routing service)

---

# 🏁 Summary

NavigationKit gives you:

### ✔ Real-time GPS, speed, heading, altitude  
### ✔ Reverse geocoding  
### ✔ Map rendering + routing  
### ✔ Modular navigation algorithms (elevation, slope, distances)  
### ✔ SwiftUI-friendly architecture  
### ✔ Fully composable SPM modules  

