//
//  KVStorage.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 4/23/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SwiftyJSON

///
/// A Namespace-Key-Value storage protocol.
///
public protocol KVStorageProtocol {
    ///
    /// sets the value for a key in a namespace
    ///
    func set(ns: String, key: AnyHashable, value: Data)

    ///
    /// gets value for a key in a namespace
    ///
    func get(ns: String, key: AnyHashable) -> Data?
    
    ///
    /// removes a key from a namespace
    ///
    func remove(ns: String, key: AnyHashable)
    
    ///
    /// test for whether a namespace has a key
    ///
    func has(ns: String, key: AnyHashable) -> Bool
    
    ///
    /// gets all keys in a namespace
    ///
    func keys(ns: String) -> [AnyHashable]
}

public extension KVStorageProtocol {
    // MARK:- Derived helpers for saving/restoring various useful types
    
    func set<T: Numeric>(ns: String, key: AnyHashable, value: T) {
        let data = withUnsafeBytes(of: value) { Data($0) }
        set(ns: ns, key: key, value: data)
    }
    
    func get<T: Numeric>(ns: String, key: AnyHashable) -> T? {
        if let data = get(ns: ns, key: key) {
            var value: T = 0
            assert(data.count == MemoryLayout.size(ofValue: value))
            let _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
            return value
        }
        
        return nil
    }
    
    func set<T: ToFromData>(ns: String, key: AnyHashable, value: T) {
        do {
            set(ns: ns, key: key, value: try value.toData())
        } catch let error {
            assertionFailure("conversion from data failed: \(error.localizedDescription)")
        }
    }
    
    func get<T: ToFromData>(ns: String, key: AnyHashable) -> T? {
        if let val = get(ns: ns, key: key) {
            do {
                return try T.fromData(val)
            } catch let error {
                assertionFailure("conversion from data failed: \(error.localizedDescription)")
            }
        }
        
        return nil
    }

    // MARK:- Ergonomic helpers that set/get in the default namespace
    
    var defaultNamespace: String { return "The Default State Namespace" }

    func set(_ key: AnyHashable, _ value: Data) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    func get(_ key: AnyHashable) -> Data? {
        return get(ns: defaultNamespace, key: key)
    }
    
    func remove(_ key: AnyHashable) {
        remove(ns: defaultNamespace, key: key)
    }
    
    func set<T: Numeric>(_ key: AnyHashable, _ value: T) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    func get<T: Numeric>(_ key: AnyHashable) -> T? {
        return get(ns: defaultNamespace, key: key)
    }
    
    func set<T: ToFromData>(_ key: AnyHashable, _ value: T) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    func get<T: ToFromData>(_ key: AnyHashable) -> T? {
        return get(ns: defaultNamespace, key: key)
    }
}

// MARK:- Data (de)serialization for types we care about
public protocol ToFromData {
    func toData() throws -> Data
    static func fromData(_ data: Data) throws -> Self
}

extension String: ToFromData {
    public func toData() -> Data {
        return self.data(using: .utf8)!
    }
    static public func fromData(_ data: Data) -> String {
        return String(data: data, encoding: .utf8)!
    }
}

extension JSON: ToFromData {
    public func toData() throws -> Data {
        return try self.rawData()
    }
    static public func fromData(_ data: Data) throws -> JSON {
        return JSON(data)
    }
}

