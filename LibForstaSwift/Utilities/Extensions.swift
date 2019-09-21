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
    /// -- includes "syncReadReceipts" of type [SyncReadReceipt]
    static let signalSyncReadReceipts = Notification.Name("signalSyncReadReceipts")

    /// Incoming queue is now empty
    /// -- includes no extra data
    static let signalQueueEmpty = Notification.Name("signalQueueEmpty")
    
    /// Websocket connection to the Signal Server established
    static let signalConnected = Notification.Name("signalConnected")
    
    /// Websocket connection to the Signal Server ended
    /// -- includes "error" of type Error if applicable
    static let signalDisconnected = Notification.Name("signalDisconnected")
}

extension NotificationCenter {
    /// Broadcast a notification on the main thread.
    static func broadcast(_ name: Notification.Name, _ userInfo: [String: Any]? = nil) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }
}

extension Request {
    /// An AlamoFire `Request` debug log-emitter
    public func debugLog() -> Self {
        #if DEBUG
        debugPrint(self)
        #endif
        return self
    }
}

public extension Date {
    /// Date expressed in int milliseconds since 1970 (UInt64)
    var millisecondsSince1970:UInt64 {
        return UInt64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    /// Date initialized with int milliseconds since 1970 (Int64)
    init(millisecondsSince1970:Int64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds: millisecondsSince1970))
    }
    /// Date initialized with int milliseconds since 1970 (UInt64)
    init(millisecondsSince1970:UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds: millisecondsSince1970))
    }
    
    /// Date initialized with int milliseconds since 1970 (UInt64)
    init(timestamp: UInt64) {
        self.init(millisecondsSince1970: Int64(timestamp))
    }
    /// Date initialized with int milliseconds since 1970 (Int64)
    init(timestamp: Int64) {
        self.init(millisecondsSince1970: timestamp)
    }
    
    /// Date initialized to **milliseconds resolution**, making it safe for use as a Signal timestamp
    init(timestamp: Date) {
        self.init(millisecondsSince1970: timestamp.millisecondsSince1970)
    }
    /// Date of "now" initialized to **milliseconds resolution**, making it safe for use as a Signal timestamp
    static var timestamp: Date {
        return Date(millisecondsSince1970: Date().millisecondsSince1970)
    }
}

public extension TimeInterval {
    /// Time interval expressed in int milliseconds (UInt64)
    var milliseconds:UInt64 {
        return UInt64((self * 1000.0).rounded())
    }
    /// Init a time interval using milliseconds (UInt64)
    init(milliseconds:UInt64) {
        self.init(Double(milliseconds) / 1000.0)
    }
    /// Time interval expressed in int milliseconds (UInt32)
    init(milliseconds:UInt32) {
        self.init(Double(milliseconds) / 1000.0)
    }
    /// Time interval expressed in int milliseconds (Int64)
    init(milliseconds:Int64) {
        self.init(Double(milliseconds) / 1000.0)
    }
}

extension SignalAddress: CustomStringConvertible {
    /// convenience init using clearer `userId` label for the string
    public convenience init(userId: String, deviceId: UInt32) {
        self.init(name: userId, deviceId: (Int32(deviceId)))
    }
    /// convenience init using safer `UUID` for `userId`
    public convenience init(userId: UUID, deviceId: UInt32) {
        self.init(name: userId.lcString, deviceId: (Int32(deviceId)))
    }
    /// convenience init using safer `UUID` for `userId`
    public convenience init(userId: UUID, deviceId: Int32) {
        self.init(name: userId.lcString, deviceId: deviceId)
    }
    /// deserialize from a `description` string
    public convenience init?(description: String) {
        let parts = description.components(separatedBy: ".")
        guard parts.count == 2,
            let userId = UUID(uuidString: parts[0]),
            let deviceId = Int32(parts[1]) else {
            return nil
        }
        self.init(userId: userId, deviceId: deviceId)
    }
    /// accessor for the address' `name` as a `UUID`
    public var userId: UUID {
        return UUID(uuidString: self.name)!
    }
    /// serialize as a "userId.deviceId" string
    public var description: String {
        return "\(self.name).\(self.deviceId)"
    }
}

public extension JSON {
    /// init a `JSON` object from a JSON-encoded string
    init?(string: String) {
        let dataFromString = string.data(using: .utf8, allowLossyConversion: false)!
        do {
            try self.init(data: dataFromString)
        } catch {
            return nil
        }
    }
}

public extension UUID {
    /// the lowercased string form of this `UUID`
    /// (Forsta uses the lowercase string exclusively in message payloads and user addresses)
    var lcString: String {
        get {
            return self.uuidString.lowercased()
        }
    }
}

public extension String {
    /// utility for prefixing every line in a `String` with some string
    func indentWith(_ prefix: String) -> String {
        return prefix + self.replacingOccurrences(of: "\n", with: "\n" + prefix)
    }
}
