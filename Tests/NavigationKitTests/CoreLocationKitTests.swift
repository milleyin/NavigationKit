//
//  CoreLocationKitTests.swift
//  
//
//  Created by Mille Yin on 2025/2/15.
//

import XCTest
import CoreLocationKit
import CoreLocation
import Combine

final class CoreLocationKitTests: XCTestCase {
    
    let locationKit = CoreLocationKit.shared
    
    var cancellables: Set<AnyCancellable> = []
    
    override func setUp() {
        super.setUp()
    }
    
    func testLocationPublisher() {
        let expectation = XCTestExpectation(description: "获取位置信息")
        
        locationKit.locationPublisher
            .receive(on: RunLoop.main)
            .sink { location in
                if let location = location {
                    print("测试获取到位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 20.0)
    }
}
