//
//  TrackSmoother.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

public final class TrackSmoother {

    public init() {}

    /// 当前版本：直接返回原始点
    public func smooth(_ point: GeoPoint) -> GeoPoint {
        return point
    }
}
