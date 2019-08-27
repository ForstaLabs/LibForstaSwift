//
//  TestKVStore.swift
//  LibForstaSwiftTests
//
//  Created by Greg Perkins on 4/23/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import XCTest
import SwiftyJSON
import LibForstaSwift

class MemoryKVStore: KVStorageProtocol {
    var data = [String: [String: Data]]()
    
    func set(ns: CustomStringConvertible, key: CustomStringConvertible, value: Data) {
        if var namespace = data[ns.description] {
            namespace[key.description] = value
            data[ns.description] = namespace    // why the hell is this line required??
        } else {
            data[ns.description] = [key.description: value]
        }
    }
    
    func get(ns: CustomStringConvertible, key: CustomStringConvertible) -> Data? {
        return (data[ns.description] ?? [:])[key.description]
    }
    
    func remove(ns: CustomStringConvertible, key: CustomStringConvertible) {
        data[ns.description]?.removeValue(forKey: key.description)
    }
    
    func has(ns: CustomStringConvertible, key: CustomStringConvertible) -> Bool {
        return (data[ns.description] ?? [:])[key.description] != nil
    }
    
    func keys(ns: CustomStringConvertible) -> [String] {
        return [String]((data[ns.description] ?? [:]).keys)
    }
}

class KVStoreTests: XCTestCase {
    func testMemoryKVStore() {
        let store = MemoryKVStore()
        
        store.set(ns: "ns1", key: "key1", value: "value1".data(using: .unicode)!)
        let val1 = store.get(ns: "ns1", key: "key1") ?? "oops1".data(using: .unicode)!
        store.set(ns: "ns1", key: "key1", value: "value2".data(using: .unicode)!)
        let val2 = store.get(ns: "ns1", key: "key1") ?? "oops2".data(using: .unicode)!
        let val3 = store.get(ns: "ns1", key: "dunno") ?? "oops3".data(using: .unicode)!

        XCTAssert(String(data:val1, encoding:.unicode) == "value1")
        XCTAssert(String(data:val2, encoding:.unicode) == "value2")
        XCTAssert(String(data:val3, encoding:.unicode) == "oops3")
        
        XCTAssert(store.has(ns: "ns1", key:"key1"))
        XCTAssert(!store.has(ns: "ns1", key:"key2"))
        XCTAssert(!store.has(ns: "ns2", key:"key1"))

        let keys = store.keys(ns: "ns1")
        XCTAssert(keys == ["key1"])
        
        store.remove(ns: "ns1", key:"key1")
        
        let keys2 = store.keys(ns: "ns1")
        XCTAssert(keys2 == [])
        
        let keys3 = store.keys(ns: "unknown")
        XCTAssert(keys3 == [])
        
        let data1 = "some data".data(using: .unicode)!
        let data2 = "some other data".data(using: .unicode)!
        
        store.set("foo", data1)
        store.set("bar", data2)
        
        let state1 = store.get("foo")
        let state2 = store.get("bar")
        XCTAssert(state1 == data1)
        XCTAssert(state2 == data2)
        
        store.remove("foo")
        
        let state3 = store.get("foo")
        XCTAssert(state3 == nil)
        
        store.set("x", "Hello")
        XCTAssert((store.get("x") as String? ?? "") == "Hello")
        
        store.set("y", "World")
        XCTAssert((store.get("y") as String? ?? "") == "World")

        store.set("x", JSON(["something": "Hello"]))
        store.set("y", JSON(["anotherthing": "World"]))
        
        let x:JSON? = store.get("x")
        XCTAssert(x!["something"].stringValue == "Hello")
        let y:JSON? = store.get("y")
        XCTAssert(y!["anotherthing"].stringValue == "World")

        store.set("x", 42)
        store.set("y", 24)
        XCTAssert(store.get("x")! == 42)
        XCTAssert(store.get("y")! == 24)
        
        store.set("x", Double(42.42))
        store.set("y", Double(24.24))
        XCTAssert((store.get("x") as Double?)! == 42.42)
        XCTAssert((store.get("y") as Double?)! == 24.24)
        
        let u1 = UUID()
        let u2 = UUID()
        store.set("x", u1)
        store.set("y", u2)
        XCTAssert((store.get("x") as UUID?)! == u1)
        XCTAssert((store.get("y") as UUID?)! == u2)
    }
    func testMismatch() {
        let store = MemoryKVStore()
        
        let fromX: UInt8 = 42
        let fromY: UInt32 = 24
        
        store.set("x", fromX)
        store.set("y", fromY)
        
        let toWrongX: JSON? = store.get("x")
        let toWrongY: JSON? = store.get("y")
        print(toWrongX!)
        print(toWrongY!)
        // XCTAssert(toWrongX! == fromX)
        // XCTAssert(toWrongY! == fromY)
    }
}
