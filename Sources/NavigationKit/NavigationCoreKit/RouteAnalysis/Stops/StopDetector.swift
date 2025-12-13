//
//  File.swift
//  NavigationKit
//
//  Created by mille on 2025/12/9.
//

import Foundation

public final class StopDetector {

    public init() {}

    /// 当前版本：永远认为在移动
    public func isStopped(_ point: GeoPoint) -> Bool {
        return false
    }
}
