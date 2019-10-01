//
//  Delegates.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 10/1/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation

/// A generic class for managing collections of delegates properly with weak references
public class Delegates<T> {
    private var delegates = [Weak<T>]()
    
    public init() { }
    
    /// Add a new delegate
    public func add(_ delegate: T) {
        self.delegates.append(Weak(delegate))
        gc()
    }
    
    /// Remove a specific delegate
    public func remove(_ delegate: T) {
        self.delegates = self.delegates.filter { $0.value != nil && !$0.equals(delegate) }
    }
    
    /// Remove all delegates
    public func removeAll() {
        self.delegates = []
    }
    
    /// Count of live delegates
    public var count: Int {
        gc()
        return self.delegates.count
    }
    
    /// Iterate over the delegates with a closure to make calls, send messages, do work
    ///
    /// i.e., you can do `.notify({ $0.someDelegateCall(...) })`
    public func notify(_ todo: (_ theDelegate: T) -> Void) {
        for delegate in self.delegates {
            if delegate.value != nil {
                todo(delegate.value!)
            }
        }
        gc()
    }
    
    private func gc() {
        self.delegates = self.delegates.filter { $0.value != nil }
    }
    
    /**
     * Container for a weakly referenced object.
     *
     * Only use this for |T| with reference-semantic entities
     * That is - <T> should inherit from AnyObject or Class-only protocols, but not structs or enums.
     *
     * Based on https://devforums.apple.com/message/981472#981472, but also supports class-only protocols
     */
    private struct Weak<T> {
        private weak var _value: AnyObject?
        
        public var value: T? {
            get {
                return _value as? T
            }
            set {
                _value = newValue as AnyObject
            }
        }
        
        public func equals(_ other: T) -> Bool {
            let rhs = other as AnyObject
            if let lhs = self._value {
                return lhs === rhs
            }
            return false
        }
        
        public init(_ value: T) {
            self.value = value
        }
    }
}
