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


extension Notification.Name {
    /// Atlas credential has been set in the KV store.
    static let atlasCredentialSet = Notification.Name("atlasCredentialSet")
    
    /// Atlas credential has expired and authentication needs to be performed again
    static let atlasCredentialExpired = Notification.Name("atlasCredentialExpired")
    
    /// Identity key changed on an incoming message
    static let relayIdentityKeyChanged = Notification.Name("relayIdentityKeyChanged")
    
    /// Delivery receipt on an incoming message
    static let relayDeliveryReceipt = Notification.Name("relayDeliveryReceipt")
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
func raddr(_ userId: String, _ deviceId: Int32) -> RelayAddress {
    return "\(userId).\(deviceId)"
}
