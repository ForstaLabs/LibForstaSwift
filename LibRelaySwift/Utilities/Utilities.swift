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
    static let relayDeliveryReceipt = Notification.Name("relayDeliveryReceipt")

    /// Incoming sync message
    static let relaySyncMessage = Notification.Name("relaySyncMessage")
    
    /// Incoming data message
    static let relayDataMessage = Notification.Name("relayDataMessage")
}

extension NotificationCenter {
    ///
    /// Broadcast a notification on the main thread.
    ///
    static func broadcast(_ name: Notification.Name, _ userInfo: [String: Any]?) {
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

typealias RelayAddress = String
/// generate a RelayAddress (String of userId.deviceId)
func raddr(_ userId: String, _ deviceId: UInt32) -> RelayAddress {
    return "\(userId).\(deviceId)"
}

extension Date {
    var millisecondsSince1970:Int64 {
        return Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds:Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

extension SignalAddress {
    convenience init(userId: String, deviceId: UInt32) {
        self.init(name: userId, deviceId: (Int32(deviceId)))
    }
}

extension JSON {
    init(string: String) throws {
        let dataFromString = string.data(using: .utf8, allowLossyConversion: false)!
        try self.init(data: dataFromString)
    }
}
