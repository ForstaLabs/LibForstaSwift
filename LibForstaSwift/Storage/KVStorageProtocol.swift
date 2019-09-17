//
//  KVStorage.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 4/23/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SwiftyJSON
import SignalProtocol

///
/// A simple namespace-key-value storage protocol to stashing and retrieving `Data` blobs.
///
public protocol KVStorageProtocol {
    ///
    /// Sets the `Data` value for a key in a namespace.
    ///
    func set(ns: CustomStringConvertible, key: CustomStringConvertible, value: Data)

    ///
    /// Gets the `Data` value for a key in a namespace.
    ///
    func get(ns: CustomStringConvertible, key: CustomStringConvertible) -> Data?
    
    ///
    /// Removes a key from a namespace.
    ///
    func remove(ns: CustomStringConvertible, key: CustomStringConvertible)
    
    ///
    /// Tests whether a namespace has a key.
    ///
    func has(ns: CustomStringConvertible, key: CustomStringConvertible) -> Bool
    
    ///
    /// Gets all keys in a namespace.
    ///
    func keys(ns: CustomStringConvertible) -> [String]
}

public extension KVStorageProtocol {
    // -MARK: Derived helpers for saving/restoring various useful types
    
    /// Derived extension to set a `Numeric` value for a key in a namespace.
    func set<T: Numeric>(ns: CustomStringConvertible, key: CustomStringConvertible, value: T) {
        let data = withUnsafeBytes(of: value) { Data($0) }
        set(ns: ns, key: key, value: data)
    }
    
    /// Derived extension to get a `Numeric` value for a key in a namespace.
    func get<T: Numeric>(ns: CustomStringConvertible, key: CustomStringConvertible) -> T? {
        if let data = get(ns: ns, key: key) {
            var value: T = 0
            assert(data.count == MemoryLayout.size(ofValue: value))
            let _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
            return value
        }
        
        return nil
    }
    
    /// Derived extension to set a `ToFromData` value for a key in a namespace.
    func set<T: ToFromData>(ns: CustomStringConvertible, key: CustomStringConvertible, value: T) {
        do {
            set(ns: ns, key: key, value: try value.toData())
        } catch let error {
            assertionFailure("conversion to data failed: \(error.localizedDescription)")
        }
    }
    
    /// Derived extension to get a `ToFromData` value for a key in a namespace.
    func get<T: ToFromData>(ns: CustomStringConvertible, key: CustomStringConvertible) -> T? {
        if let val = get(ns: ns, key: key) {
            do {
                return try T.fromData(val)
            } catch let error {
                assertionFailure("conversion from data failed: \(error.localizedDescription)")
            }
        }
        
        return nil
    }

    // -MARK: Ergonomic helpers that set/get in the default namespace
    
    /// The "default namespace" we use to ergonomically stash a handful of global things.
    var defaultNamespace: String { return "The Default State Namespace" }

    /// Derived method to set a `Data` value for a key in the default namespace.
    func set(_ key: CustomStringConvertible, _ value: Data) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    /// Derived method to get a `Data` value for a key in the default namespace.
    func get(_ key: CustomStringConvertible) -> Data? {
        return get(ns: defaultNamespace, key: key)
    }
    
    /// Derived method to remove a key in the default namespace.
    func remove(_ key: CustomStringConvertible) {
        remove(ns: defaultNamespace, key: key)
    }
    
    /// Derived method to set a `Numeric` value for a key in the default namespace.
    func set<T: Numeric>(_ key: CustomStringConvertible, _ value: T) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    /// Derived method to get a `Numeric` value for a key in the default namespace.
    func get<T: Numeric>(_ key: CustomStringConvertible) -> T? {
        return get(ns: defaultNamespace, key: key)
    }
    
    /// Derived method to set a `ToFromData` value for a key in the default namespace.
    func set<T: ToFromData>(_ key: CustomStringConvertible, _ value: T) {
        set(ns: defaultNamespace, key: key, value: value)
    }
    
    /// Derived method to get a `ToFromData` value for a key in the default namespace.
    func get<T: ToFromData>(_ key: CustomStringConvertible) -> T? {
        return get(ns: defaultNamespace, key: key)
    }
}

/// A generic class for using store-backed default-namespace typed values,
/// cached locally for speed (so note this means that each instance assumes
/// there is no other cache to keep it's value coherent with).
public class KVBacked<T> where T: ToFromData {
    var kvstore: KVStorageProtocol
    var cache: T?
    let key: CustomStringConvertible
    
    /// Create a `KVBacked`
    public init(kvstore: KVStorageProtocol, key: CustomStringConvertible, initial: T? = nil) {
        self.key = key
        self.kvstore = kvstore
        
        if initial != nil && self.value == nil {
            self.value = initial
        }
    }
    
    /// get and set the backed, cached value
    public var value: T? {
        get {
            if cache == nil {
                cache = kvstore.get(key)
            }
            return cache
        }
        set(value) {
            cache = value
            if value == nil {
                kvstore.remove(key)
            } else {
                kvstore.set(key, value!)
            }
        }
    }
}

// -MARK: Data (de)serialization for types we care about

/// A simple protocol for things that we want
/// to be able to serialize-to and reconstitute-from `Data`
public protocol ToFromData {
    /// Serialize self to `Data`
    func toData() throws -> Data
    
    /// Deserialize from `Data`
    static func fromData(_ data: Data) throws -> Self
}

extension Data: ToFromData {
    /// Serialize a `Data` to `Data`
    public func toData() -> Data {
        return self
    }
    
    /// Deserialize a `Data` from `Data`
    static public func fromData(_ data: Data) -> Data {
        return data
    }
}

extension String: ToFromData {
    /// Serialize a `String` to `Data`
    public func toData() -> Data {
        return self.data(using: .utf8)!
    }
    
    /// Deserialize a `String` from `Data`
    static public func fromData(_ data: Data) -> String {
        return String(data: data, encoding: .utf8)!
    }
}

extension JSON: ToFromData {
    /// Serialize a `JSON` to `Data`
    public func toData() throws -> Data {
        return try self.rawData()
    }
    
    /// Deserialize a `JSON` from `Data`
    static public func fromData(_ data: Data) throws -> JSON {
        return JSON(data)
    }
}

extension UUID: ToFromData {
    /// Serialize a `UUID` to `Data`
    public func toData() throws -> Data {
        return withUnsafeBytes(of: self.uuid, { Data($0) })
    }
    
    /// Deserialize a `UUID` from `Data`
    static public func fromData(_ data: Data) throws -> UUID {
        var value = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        assert(data.count == MemoryLayout.size(ofValue: value))
        let _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        return value
    }
}

extension SignalAddress: ToFromData {
    /// Serialize a `SignalAddress` to `Data`
    public func toData() throws -> Data {
        return self.description.toData()
    }
    
    /// Deserialize a `SignalAddress` from `Data`
    static public func fromData(_ data: Data) throws -> SignalAddress {
        guard let value = SignalAddress(description: String.fromData(data)) else {
            throw ForstaError(.storageError, "could not parse SignalAddress")
        }
        return value
    }
}
