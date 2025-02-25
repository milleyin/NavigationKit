//
//  AppleMapKit.swift
//  NavigationKit
//
//  Created by Mille Yin on 2025/2/17.
//

import Foundation
import MapKit

#if canImport(UIKit)
import UIKit
#endif

/// Apple 地图工具，封装 `MKMapView`
public final class AppleMapKit: NSObject, MKMapViewDelegate {
    
    /// 地图视图实例
    public let mapView: MKMapView
    
    /// 追踪模式
    public var userTrackingMode: MKUserTrackingMode {
        didSet { mapView.userTrackingMode = userTrackingMode }
    }
    
    /// 自定义标记图像（仅 iOS 可用）
#if canImport(UIKit)
    public var customAnnotationImage: UIImage?
#endif
    
    /// 允许外部（SwiftUI 的 Coordinator）接管代理
    public weak var externalDelegate: MKMapViewDelegate?
    
    /// 初始化 `AppleMapKit`
    public init(userTrackingMode: MKUserTrackingMode = .follow) {
        self.mapView = MKMapView()
        self.userTrackingMode = userTrackingMode
        
        super.init()
        
        mapView.delegate = self  // ✅ 直接用 self 作为 delegate
        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode
    }
    
    /**
     设置用户追踪模式
     
     - parameter mode: `MKUserTrackingMode`
     */
    public func setUserTrackingMode(_ mode: MKUserTrackingMode) {
        self.userTrackingMode = mode
    }
    
    /**
     在地图上添加多个标记
     
     - parameter annotations: 标记数组
     */
    public func addAnnotations(_ annotations: [MultipleAnnotations]) {
        let mapAnnotations = annotations.map { annotation -> MKPointAnnotation in
            let point = MKPointAnnotation()
            point.coordinate = annotation.location
            point.title = annotation.name
            return point
        }
        mapView.addAnnotations(mapAnnotations)
    }
    
    /**
     在地图上绘制导航线路
     
     - parameter start: 起点坐标
     - parameter destination: 终点坐标
     */
    public func drawRoute(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        let startPlacemark = MKPlacemark(coordinate: start)
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: startPlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self, let route = response?.routes.first else {
                print("导航线路生成失败: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                self.mapView.removeOverlays(self.mapView.overlays)
                self.mapView.addOverlay(route.polyline, level: .aboveRoads)
                
                let routeRect = route.polyline.boundingMapRect
                
#if canImport(UIKit)
                let edgePadding = UIEdgeInsets(top: 100, left: 50, bottom: 350, right: 50)
#else
                let edgePadding = NSEdgeInsets(top: 100, left: 50, bottom: 350, right: 50)
#endif
                
                self.mapView.setVisibleMapRect(routeRect, edgePadding: edgePadding, animated: true)
            }
        }
    }
    /**
     跳转 Apple Maps App 开始导航
     
     - parameter start: 可选的起点坐标，默认为当前定位
     - parameter destination: 终点坐标
     - parameter destinationName: 终点名称
     - Warning: 确保设备已安装 Apple Maps。
     */
    public func openInAppleMaps(start: CLLocationCoordinate2D?, destination: CLLocationCoordinate2D, destinationName: String) {
        let startItem: MKMapItem
        if let start = start {
            let startPlacemark = MKPlacemark(coordinate: start)
            startItem = MKMapItem(placemark: startPlacemark)
            startItem.name = "当前位置"
        } else {
            startItem = MKMapItem.forCurrentLocation()
        }
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = destinationName
        
        let options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        MKMapItem.openMaps(with: [startItem, destinationItem], launchOptions: options)
    }
}

// MARK: - MKMapViewDelegate

extension AppleMapKit {
    
    /// 处理标记的自定义视图
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        // 如果 externalDelegate 存在，则先调用 externalDelegate 的方法
        if let delegateView = externalDelegate?.mapView?(mapView, viewFor: annotation) {
            return delegateView
        }
        guard !(annotation is MKUserLocation) else { return nil }
        
        let identifier = "CustomAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
#if canImport(UIKit)
        if let image = customAnnotationImage {
            annotationView?.image = resizeImage(image: image, targetSize: CGSize(width: 21, height: 31))
        }
#endif
        
        return annotationView
    }
    
    /// 处理导航线条的渲染
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        
        // 先检查 externalDelegate 是否实现了该方法
        if let renderer = externalDelegate?.mapView?(mapView, rendererFor: overlay) {
            return renderer
        }
        
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        
        let renderer = MKPolylineRenderer(polyline: polyline)
        
#if canImport(UIKit)
        renderer.strokeColor = UIColor.systemBlue
#else
        renderer.strokeColor = NSColor.systemBlue
#endif
        
        renderer.lineWidth = 8
        renderer.lineCap = .round
        
        return renderer
    }
}

#if canImport(UIKit)
// MARK: - 图片处理
extension AppleMapKit {
    
    /// 调整图片大小（仅 iOS 可用）
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage? {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        let newSize = widthRatio > heightRatio
            ? CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
            : CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: rect)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
#endif

// MARK: - 数据模型

/// 代表多个商家标记
public struct MultipleAnnotations: Identifiable {
    public var id = UUID()
    public var name: String
    public var location: CLLocationCoordinate2D
}

/// 代表单个标记
public struct SingleAnnotation {
    public var location: CLLocationCoordinate2D
}
