//
//  Extensions.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 4/24/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire
import CommonCrypto
import SignalProtocol


/// Forsta's `Notification.Name`s
public extension Notification.Name {
    /// Atlas credential has been set in the KV store.
    static let atlasCredentialSet = Notification.Name("atlasCredentialSet")
    
    /// Atlas credential has expired and authentication needs to be performed again
    static let atlasCredentialExpired = Notification.Name("atlasCredentialExpired")
    
    /// Identity key changed on an incoming message
    /// -- includes "address" of type SignalAddress
    static let signalIdentityKeyChanged = Notification.Name("signalIdentityKeyChanged")
    
    /// Incoming delivery receipt
    /// -- includes "deliveryReceipt" of type DeliveryReceipt
    static let signalDeliveryReceipt = Notification.Name("signalDeliveryReceipt")

    /// Incoming message
    /// -- includes "inboundMessage" of type InboundMessage
    static let signalInboundMessage = Notification.Name("signalInboundMessage")
    
    /// Incoming read receipts
    /// -- includes "readSyncReceipts" of type [ReadSyncReceipt]
    static let signalReadSyncReceipts = Notification.Name("signalReadSyncReceipts")

    /// Incoming queue is now empty
    /// -- includes no extra data
    static let signalQueueEmpty = Notification.Name("signalQueueEmpty")
    
    /// Websocket connection to the Signal Server established
    static let signalConnected = Notification.Name("signalConnected")
    
    /// Websocket connection to the Signal Server ended
    /// -- includes "error" of type Error if applicable
    static let signalDisconnected = Notification.Name("signalDisconnected")
}

/// Utility extensions to `NotificationCenter`
extension NotificationCenter {
    ///
    /// Broadcast a notification on the main thread.
    ///
    static func broadcast(_ name: Notification.Name, _ userInfo: [String: Any]? = nil) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }
}

/// Utility extensions to `Request`
extension Request {
    public func debugLog() -> Self {
        #if DEBUG
        debugPrint(self)
        #endif
        return self
    }
}

/// Utility extensions to `Date`
public extension Date {
    var millisecondsSince1970:UInt64 {
        return UInt64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    init(millisecondsSince1970:Int64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds: millisecondsSince1970))
    }
    init(millisecondsSince1970:UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds: millisecondsSince1970))
    }
}

/// Utility extensions to `TimeInterval`
public extension TimeInterval {
    var milliseconds:UInt64 {
        return UInt64((self * 1000.0).rounded())
    }
    init(milliseconds:UInt64) {
        self.init(milliseconds / 1000)
    }
    init(milliseconds:UInt32) {
        self.init(milliseconds / 1000)
    }
    init(milliseconds:Int64) {
        self.init(milliseconds / 1000)
    }
}

/// Utility extensions to `SignalAddress`
extension SignalAddress: CustomStringConvertible {
    convenience init(userId: String, deviceId: UInt32) {
        self.init(name: userId, deviceId: (Int32(deviceId)))
    }
    convenience init(userId: UUID, deviceId: UInt32) {
        self.init(name: userId.lcString, deviceId: (Int32(deviceId)))
    }
    convenience init(userId: UUID, deviceId: Int32) {
        self.init(name: userId.lcString, deviceId: deviceId)
    }
    public convenience init?(description: String) {
        let parts = description.components(separatedBy: ".")
        guard parts.count == 2,
            let userId = UUID(uuidString: parts[0]),
            let deviceId = Int32(parts[1]) else {
            return nil
        }
        self.init(userId: userId, deviceId: deviceId)
    }
    var userId: UUID {
        return UUID(uuidString: self.name)!
    }
    public var description: String {
        return "\(self.name).\(self.deviceId)"
    }
}

/// Utility extensions to `JSON`
public extension JSON {
    init(string: String) throws {
        let dataFromString = string.data(using: .utf8, allowLossyConversion: false)!
        try self.init(data: dataFromString)
    }
}

/// Utility extensions to `UUID`
public extension UUID {
    var lcString: String {
        get {
            return self.uuidString.lowercased()
        }
    }
}

/// Utility extensions to `String`
public extension String {
    func indentWith(_ prefix: String) -> String {
        return prefix + self.replacingOccurrences(of: "\n", with: "\n"+prefix)
    }
}
