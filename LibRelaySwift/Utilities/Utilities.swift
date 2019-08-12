//
//  Utilities.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 4/24/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire
import CommonCrypto
import SignalProtocol


extension Notification.Name {
    /// Atlas credential has been set in the KV store.
    static let atlasCredentialSet = Notification.Name("atlasCredentialSet")
    
    /// Atlas credential has expired and authentication needs to be performed again
    static let atlasCredentialExpired = Notification.Name("atlasCredentialExpired")
    
    /// Identity key changed on an incoming message
    static let relayIdentityKeyChanged = Notification.Name("relayIdentityKeyChanged")
    
    /// Incoming delivery receipt
    /// -- includes "deliveryReceipt" of type DeliveryReceipt
    static let relayDeliveryReceipt = Notification.Name("relayDeliveryReceipt")

    /// Incoming message
    /// -- includes "inboundMessage" of type InboundMessage
    static let relayInboundMessage = Notification.Name("relayInboundMessage")
    
    /// Incoming read receipts
    /// -- includes "readSyncReceipts" of type [ReadSyncReceipt]
    static let relayReadSyncReceipts = Notification.Name("relayReadSyncReceipts")

    /// Incoming queue is now empty
    /// -- includes no extra data
    static let relayEmptyQueue = Notification.Name("relayEmptyQueue")
}


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


/// The various LibRelay errors.
enum LibRelayError: Error {
    case requestRejected(why: JSON)
    case requestFailure(why: Error)
    case internalError(why: String)
}
extension LibRelayError {
    var isRequestFailure: Bool {
        get {
            switch self {
            case .requestFailure(_): return true
            default: return false
            }
        }
    }
    
    var rejectedBecause: JSON {
        get {
            switch self {
            case .requestRejected(let why): return why
            default: return JSON([:])
            }
        }
    }
}

extension Request {
    public func debugLog() -> Self {
        #if DEBUG
        debugPrint(self)
        #endif
        return self
    }
}

extension Date {
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

extension TimeInterval {
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

extension SignalAddress: CustomStringConvertible {
    convenience init(userId: String, deviceId: UInt32) {
        self.init(name: userId, deviceId: (Int32(deviceId)))
    }
    convenience init(userId: UUID, deviceId: UInt32) {
        self.init(name: userId.lcString, deviceId: (Int32(deviceId)))
    }
    var userId: UUID {
        get {
            return UUID(uuidString: self.name)!
        }
    }
    public var description: String {
        return "\(self.name).\(self.deviceId )"
    }
}

extension JSON {
    init(string: String) throws {
        let dataFromString = string.data(using: .utf8, allowLossyConversion: false)!
        try self.init(data: dataFromString)
    }
}

extension UUID {
    var lcString: String {
        get {
            return self.uuidString.lowercased()
        }
    }
}

extension String {
    func indentWith(_ prefix: String) -> String {
        return prefix + self.replacingOccurrences(of: "\n", with: "\n"+prefix)
    }
}
