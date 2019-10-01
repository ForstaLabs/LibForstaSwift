//
//  DelegatesTests.swift
//  LibForstaSwiftTests
//
//  Created by Greg Perkins on 10/1/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import XCTest
import LibForstaSwift

public protocol Delegate: class {
    func foo()
}

class ConcreteDelegate: Delegate {
    let name: String
    var foos: Int
    
    init(_ name: String) {
        self.name = name
        self.foos = 0
        print("init \(self.name)")
    }
    
    deinit {
        print("deinit \(self.name)")
    }
    
    public func foo() {
        self.foos += 1
    }
}

class DelegatesTests: XCTestCase {
    func testDelegates() {
        let delegates = Delegates<Delegate>()
        print("creating")
        var d1: ConcreteDelegate? = ConcreteDelegate("d1")
        let d2 = ConcreteDelegate("d2")
        
        XCTAssert(delegates.count == 0)
        delegates.add(d1!)
        delegates.add(d2)
        XCTAssert(delegates.count == 2)
        XCTAssert(d1!.foos == 0)
        XCTAssert(d2.foos == 0)
        delegates.notify({ $0.foo() })
        XCTAssert(d1!.foos == 1)
        XCTAssert(d2.foos == 1)
        print("before removing d1 reference")
        d1 = nil
        print("after removing d1 reference")
        XCTAssert(delegates.count == 1)
        delegates.notify({ $0.foo() })
        XCTAssert(d2.foos == 2)
        delegates.remove(d2)
        XCTAssert(delegates.count == 0)
        delegates.notify({ $0.foo() })
        XCTAssert(d2.foos == 2)
        print("done")
    }
}
