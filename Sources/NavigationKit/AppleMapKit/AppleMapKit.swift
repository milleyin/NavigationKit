//
//  AppleMapKit.swift
//  NavigationKit
//
//  Created by Mille Yin on 2025/2/17.
//

import Foundation
import MapKit

struct AppleMap {
    
    @EnvironmentObject var location: LocationService
    
    
    var userTrackingMode: MKUserTrackingMode
    
    var isBackToUserLocation: Bool
    
    ///自动添加的多个地图标记(商店)
    var annotations: [MultipleAnnotations]?
    
    ///自动添加的单个地图标记
    var annotation: SingleAnnotation?
    
    ///自定义标记图片
    var customAnnotationImage: UIImage? = UIImage(named: "defaultLocation")
    
    ///搜索结果
    var searchResultPins: [AppleMapLandMark]?
    
    
    ///万能回调，用于外部传入自定义的地图操作
    var mapCallBack: ((MKMapView) -> Void)?
    
    // 添加一个属性来暂时保存被移除的标注(地图点击时使用)
    var tempRemovedAnnotations: [MKAnnotation] = []
    
    
}

//MARK: 逻辑

extension AppleMap: UIViewRepresentable {
    
    final class Coordinator: NSObject {
        
        var parent: AppleMap
        ///搜索结果（因为UI更新会导致searchResultPins被清空，所以要建立一个持久化存储搜索结果）
        var staticSearchResultPins: [AppleMapLandMark] = []
        
        init(_ parent: AppleMap) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(hex: "#0A84FF") // 设置导航线颜色
                renderer.lineWidth = 8       // 设置导航线宽度
                renderer.lineCap = .round
                
//                self.parent.viewModel.isReadyToStartNavi = true
                self.parent.viewModel.navigationButtonState = .startTonavigation
                
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
    ///init map
    func makeUIView(context: Context) -> MKMapView {
        
        let mapView = MKMapView()
        
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode
        self.setMapColorScheme(on: mapView)
        
        if let userLocation = location.currentLocation?.coordinate {
            mapView.setRegion(MKCoordinateRegion(center: userLocation, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: true)
        }
        
        return mapView
    }
    ///update map
    func updateUIView(_ mapView: MKMapView, context: Context) {
        
        if userTrackingMode == .follow {
            mapView.setCenter(mapView.userLocation.coordinate, animated: true)
        }
        
        // 避免在选中标注时重新刷新
        if mapView.selectedAnnotations.isEmpty {
            //地图上添加标记
            updateMapAnnotations(mapView)
        }
        
        // 万能回调，以允许对地图进行自定义操作
        mapCallBack?(mapView)
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    ///添加标记到地图上的逻辑
    private func updateMapAnnotations(_ mapView: MKMapView) {
        // 优先更新搜索结果标注
        if let searchResultPins = searchResultPins, !searchResultPins.isEmpty {
            updateSearchResultsOnMapView(on: mapView, with: searchResultPins)
            mapView.showAnnotations(mapView.annotations, animated: true)
            return
        }
        
        // 更新多个标注（商店）
        if let annotations = annotations, !annotations.isEmpty {
            updateAnnotationsForMultipleAnnotations(on: mapView, with: annotations)
            mapView.showAnnotations(mapView.annotations, animated: true)
            return
        }
        
        // 更新单个标注（停车位置）
        if let annotation = annotation {
            updateAnnotationsForSingleAnnotation(on: mapView, with: annotation)
        }
    }
    
    ///地图上添加搜索结果
    private func updateSearchResultsOnMapView(on mapView: MKMapView, with searchResults: [AppleMapLandMark]?) {
        mapView.removeAnnotations(mapView.annotations)
        
        if let searchResults = searchResults {
            for pin in searchResults {
                let annotation = MKPointAnnotation()
                annotation.title = pin.name
                annotation.subtitle = pin.title
                annotation.coordinate = pin.coordinate
                annotation.id = pin.id
                
                //添加到地图上
                mapView.addAnnotation(annotation)
            }
            // 将搜索结果存储到 Coordinator 的持久化属性中
            if let coordinator = mapView.delegate as? Coordinator {
                coordinator.staticSearchResultPins = searchResults
            }
        }
    }
    
    ///地图上添加多个pin
    private func updateAnnotationsForMultipleAnnotations(on mapView: MKMapView, with annotations: [MultipleAnnotations]?) {
        mapView.removeAnnotations(mapView.annotations)
        
        if let annotations = annotations {
            for pin in annotations {
                let annotation = MKPointAnnotation()
                annotation.title = pin.name
                annotation.coordinate = pin.location
                mapView.addAnnotation(annotation)
            }
        }
    }
    
    ///地图上添加单个pin
    private func updateAnnotationsForSingleAnnotation(on mapView: MKMapView, with annotation: SingleAnnotation?) {
        guard let pin = annotation else { return }
        
        // 检查地图上是否已经有相同位置的标注，避免重复添加
        if let _ = mapView.annotations.first(where: {
            $0.coordinate.latitude == pin.location.latitude && $0.coordinate.longitude == pin.location.longitude
        }) {
            // 如果已经存在相同的标注，则不做任何操作
            return
        }
        
        // 移除地图上所有其他的标注（但不移除相同的标注）
        mapView.removeAnnotations(mapView.annotations)
        
        // 添加新的标注
        let newAnnotation = MKPointAnnotation()
        newAnnotation.coordinate = pin.location
        mapView.addAnnotation(newAnnotation)
    }
    
    ///判断系统颜色模式
    private func setMapColorScheme(on mapView: MKMapView) {
        if colorScheme == .light {
            mapView.overrideUserInterfaceStyle = .light
        }else {
            mapView.overrideUserInterfaceStyle = .dark
        }
    }
}
// MARK: - MKMapViewDelegate

extension AppleMap.Coordinator: MKMapViewDelegate {
    // 自定义 pin 的视图
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // 检查是否是用户位置，不自定义用户位置的 pin
        if annotation is MKUserLocation {
            return nil
        }
        
        // 自定义标注视图标识符
        let identifier = "customImage"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true // 允许显示信息
        } else {
            annotationView?.annotation = annotation
        }
        // 设置自定义的图标
        if let image = parent.customAnnotationImage {
            let resizedImage = resizeImage(image: image, targetSize: CGSize(width: 21, height: 31)) // 调整图片大小
            annotationView?.image = resizedImage
        }
        
        
        // 可选：设置辅助视图（如右侧的按钮）
//        let rightButton = UIButton(type: .custom)
//        annotationView?.rightCalloutAccessoryView = rightButton
        
        return annotationView
    }
    
    /// 处理点击标注的事件
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        
        guard let annotation = view.annotation, let annotationID = annotation.id else {
            print("未找到有效的 id")
            return
        }
        // 在 searchResults 中查找匹配的 pin
        // 从 Coordinator 中获取持久化的搜索结果
        if let matchingPin = staticSearchResultPins.first(where: { $0.id == annotationID }) {
                print("选中的 pin 是: \(matchingPin.name)")
//            User.shared.userSelectedPin = matchingPin
            self.parent.viewModel.userSelectedPin = matchingPin
            
            } else {
                print("未找到匹配的搜索结果")
            }
        
        DispatchQueue.main.async {
            // 移除除被点击标注之外的其他所有标注
            //筛选要暂时移除的pin
            let annotationsToRemove = mapView.annotations.filter { $0 !== annotation }
            // 将移除的暂存起来
            self.parent.tempRemovedAnnotations = annotationsToRemove
            //移除
            mapView.removeAnnotations(annotationsToRemove)
            // 设置缩放范围
            let zoomRegion = MKCoordinateRegion(center: annotation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
            // 更新地图视图以缩放到选中的标注
            mapView.setRegion(zoomRegion, animated: true)
            
            self.parent.viewModel.navigationButtonState = .drawRoute
        }
    }
    
    /// 处理取消选中标注的事件
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        
        DispatchQueue.main.async {
//            User.shared.userSelectedPin = nil
            self.parent.viewModel.userSelectedPin = nil
            mapView.removeOverlays(mapView.overlays)
            self.parent.viewModel.navigationButtonState = .none
            
            //取消选择时，把暂存的pin加回来
            mapView.addAnnotations(self.parent.tempRemovedAnnotations)
            //清空暂存
            self.parent.tempRemovedAnnotations.removeAll()
            //清除绘制线路
            mapView.removeOverlays(mapView.overlays)
            //恢复地图缩放
            mapView.showAnnotations(mapView.annotations, animated: true)
        }
    }
}

extension AppleMap.Coordinator {
    /// 调整图片大小的方法
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // 确定调整比例
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        // 调整图像大小
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: rect)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
}

extension AppleMap {
    
    /// 在地图上绘制导航线路
    static func addRoute(_ mapView: MKMapView, from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        let startPlacemark = MKPlacemark(coordinate: start)
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        
        let directionRequest = MKDirections.Request()
        directionRequest.source = MKMapItem(placemark: startPlacemark)
        directionRequest.destination = MKMapItem(placemark: destinationPlacemark)
        directionRequest.transportType = .automobile
        
        let directions = MKDirections(request: directionRequest)
        directions.calculate { response, error in
            print("请求线路")
            guard let response = response, let route = response.routes.first else {
                print("导航线路生成失败: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                // 清除旧线路
                mapView.removeOverlays(mapView.overlays)
                // 添加新线路
                mapView.addOverlay(route.polyline, level: .aboveRoads)
                
                // 调整地图的显示区域
                let routeRect = route.polyline.boundingMapRect
                let edgePadding = UIEdgeInsets(top: 100, left: 50, bottom: 350, right: 50) // 设置边距
                mapView.setVisibleMapRect(routeRect, edgePadding: edgePadding, animated: true)
            }
        }
    }
}




//MARK: 数据模型
struct MultipleAnnotations: Identifiable {
    var id = UUID()
    var name: String
    var location: CLLocationCoordinate2D
    var address: String
    var openTime: String
    var phoneNumber: String
    var rating: Int // 新增评分字段
    var availableAppointments: Int // 新增可用预约数字段
}

struct SingleAnnotation {
    var location: CLLocationCoordinate2D
}
