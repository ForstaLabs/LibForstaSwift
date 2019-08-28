//
//  Sendable.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 8/5/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import SwiftyJSON
import Starscream
import SignalProtocol


/// Forsta message types (used in the Forsta message exchange payload)
public enum FLIMessageType: String {
    /// A control message -- see `FLIControlMessageType`
    case control = "control"
    /// A content message (i.e., plain/html text)
    case content = "content"
    /// A poll message (defines prescribed responses)
    case poll = "poll"
    /// A poll response message (provides prescribed responses to a poll message)
    case pollResponse = "pollResponse"
}

/// Forsta thread types (used in the Forsta message exchange payload)
public enum FLIThreadType: String {
    /// A thread where anybody can send to the group
    case conversation = "conversation"
    /// A thread where it is a broadcast
    case announcement = "announcement"
}

/// Forsta control message types (used in the Forsta message exchange payload)
public enum FLIControlMessageType: String {
    /// Update thread metadata -- key/value dict in `threadUpdates`
    case threadUpdate = "threadUpdate"
    
    /// Clear history of current thread across my devices
    case threadClear = "threadClear"
    
    /// Archive thread across my devices (WITHOUT leaving the distribution)
    case threadArchive = "threadArchive"
    
    /// Restore/unarchive thread across my devices
    case threadRestore = "threadRestore"
    
    /// Delete the thread (leaving the distribution) across my devices
    case threadDelete = "threadDelete"
    
    /// Indicate to thread participants where your read-position is
    case readMark = "readMark"
    
    /// Indicate that user is actively typing a message for the thread
    case pendingMessage = "pendingMessage"
    
    /// Stop notifications, etc. for a period.  See `snoozeUntil` in the payload.
    case snooze = "snooze"
    
    /// Request to assist in provisioning a new device
    case provisionRequest = "provisionRequest"
    
    /// Request synchronization with a device's own peers (self devices)
    case syncRequest = "syncRequest"
    
    /// Respond to `.syncRequest`
    case syncResponse = "syncResponse"
    
    /// Discover threads from peers
    case discoverRequest = "discoverRequest"
    
    /// Response to `.discoverRequest`
    case discoverResponse = "discoverResponse"
    
    /// Ask a client for any pre-messages it has for the sender
    case preMessageCheck = "preMessageCheck"
    
    /// Client prompting a bot to perform an ACL operation
    case aclRequest = "aclRequest"
    
    /// Bot responding to `.aclRequest`
    case aclResponse = "aclResponse"
    
    /// Block a user by ID
    case userBlock = "userBlock"
    
    /// Unblock a user by ID
    case userUnblock = "userUnblock"
    
    /// Initiate contact with peers
    case beacon = "beacon"
    
    /// Extended metadata for a message using the END_SESSION flag
    case closeSession = "closeSession"
    
    /// A broadcast offer of or intent to participate in an WebRTC call
    case callJoin = "callJoin"
    
    /// A broadcast leaving/rejecting of a WebRTC call
    case callLeave = "callLeave"
    
    /// Offering a WebRTC connection to a specific device in a call
    case callOffer = "callOffer"
    
    /// Accepting a connection offer from a specific device in a call
    case callAcceptOffer = "callAcceptOffer"
    
    /// Control message providing WebRTC call ICE candidates to establish a connection with a device
    case callICECandidates = "callICECandidates"
}

/// Address for specifying recipients for sending
public enum MessageRecipient {
    /// Address of a user's specific device
    case device(_ address: SignalAddress)
    /// Address of a user's entire set of devices
    case user(_ address: UUID)
}

/// Protocol for a sendable message
public protocol Sendable {
    /// The message timestamp (visible at the envelope level)
    var timestamp: Date { get }

    /// Message expiration (number of seconds after read)
    var expiration: TimeInterval? { get }
    
    /// The Signal envelope end-session flag
    var endSessionFlag: Bool { get }
    /// The Signal envelope expiration-timer update flag
    var expirationTimerUpdateFlag: Bool { get }

    /// The Forsta message payload
    var payload: ForstaPayloadV1 { get }
}

/// A convenience wrapper for v1 of the Forsta message exchange payload
/// (see https://bit.ly/forsta-payload for details)
public class ForstaPayloadV1: CustomStringConvertible {

    /// The underlying JSON
    public var json: JSON

    /// Initialize with an (optional) JSON string
    public init(_ jsonString: String? = nil) {
        self.json = JSON(string: jsonString ?? "[\"version\": 1]") ?? JSON(["version": 1])
        for item in json.arrayValue {
            if item["version"].intValue == 1 {
                json = item
            }
        }
    }
    /// Initialize with existing payload object
    public init(_ payload: ForstaPayloadV1) {
        self.json = payload.json
    }
    /// Initialize with `JSON` object
    public init(_ json: JSON) {
        self.json = json
    }

    /// The current underlying `JSON` object encoded as a JSON string
    var jsonString: String {
        return json.rawString([.castNilToNSNull: true]) ?? "<malformed JSON>"
    }
    
    /// A pretty-printed version of the current payload's JSON string
    public var description: String {
        return json.description
    }
    
    /// The message's globally-unique ID (required)
    public var messageId: UUID? {
        get {
            return UUID(uuidString: json["messageId"].string ?? "")
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "messageId")
            } else {
                json["messageId"].string = value!.lcString
            }
        }
    }
    
    /// A reference to another message, by ID (useful for message replies, or survey responses)
    public var messageRef: UUID? {
        get {
            return UUID(uuidString: json["messageRef"].string ?? "")
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "messageRef")
            } else {
                json["messageRef"].string = value!.lcString
            }
        }
    }
    
    /// Optionally override the origin of the message if different from source
    public var sender: SignalAddress? {
        get {
            guard
                let userId = json["sender"]["userId"].string,
                let deviceId = json["sender"]["device"].uInt32 else {
                    return nil
            }
            return SignalAddress(userId: userId, deviceId: deviceId)
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "sender")
            } else {
                json["sender"] = ["userId": value!.name, "device": value!.deviceId]
            }
        }
    }
    
    /// The type of payload this is (required)
    public var messageType: FLIMessageType? {
        get {
            return FLIMessageType(rawValue: json["messageType"].stringValue)
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "messageType")
            } else {
                json["messageType"].string = value!.rawValue
            }
        }
    }
    
    /// For a `.content` message, it has a body consisting of an array of these
    public enum BodyItem: CustomStringConvertible {
        /// Plain text version of the `.content` message (required)
        case plain(_ value: String)
        /// Html version of the `.content` message (optional)
        case html(_ value: String)
        /// Unknown body element
        case unknown(_ value: String)
        
        /// String encoding of the item
        public var description: String {
            return "\"\(self.raw)\""
        }
        /// Raw data for the item
        public var raw: String {
            switch self {
            case .plain(let str): return str
            case .html(let str): return str
            default: return "<bad item>"
            }
        }
    }

    /// Array of message `BodyItem`, required for `.content` message types
    public var body: [BodyItem]? {
        get {
            if !json["data"]["body"].exists() { return nil }
            return json["data"]["body"].arrayValue.map {
                switch $0["type"].stringValue {
                case "text/plain": return .plain($0["value"].stringValue)
                case "text/html": return .html($0["value"].stringValue)
                default: return .unknown($0["value"].stringValue)
                }
            }
        }
        set(value) {
            if value == nil {
                json["data"].dictionaryObject?.removeValue(forKey: "body")
            } else {
                let ary:[[String: String]] = value!.map {
                    switch $0 {
                    case .plain(let value): return ["type": "text/plain", "value": value]
                    case .html(let value): return ["type": "text/plain", "value": value]
                    case .unknown(let value): return ["type": "text/unknown", "value": value]
                    }
                }
                if !json["data"].exists() {
                    json["data"] = [:]
                }
                json["data"]["body"] = JSON(ary)
            }
        }
    }
    
    /// directly manipulate the (presumed singular) `.plain` entry in the `body` array
    public var bodyPlain: String? {
        get {
            let ary = (body ?? []).filter({ switch $0 { case .plain: return true; default: return false }})
            return ary.count > 0 ? ary[0].raw : nil
        }
        set(value) {
            var ary = (body ?? []).filter({ switch $0 { case .plain: return false; default: return true }})
            if value != nil {
                ary.append(.html(value!))
            }
            body = ary.count > 0 ? ary : nil
        }
    }
    
    /// directly manipulate the (presumed singular) `.html` entry in the `body` array
    public var bodyHtml: String? {
        get {
            let ary = (body ?? []).filter({ switch $0 { case .html: return true; default: return false }})
            return ary.count > 0 ? ary[0].raw : nil
        }
        set(value) {
            var ary = (body ?? []).filter({ switch $0 { case .html: return false; default: return true }})
            if value != nil {
                ary.append(.html(value!))
            }
            body = ary.count > 0 ? ary : nil
        }
    }
    
    /// Control message type (meaningful only for `.control` messages)
    public var controlMessageType: FLIControlMessageType? {
        get {
            return FLIControlMessageType(rawValue: json["data"]["control"].stringValue)
        }
        set(value) {
            if value == nil {
                json["data"].dictionaryObject?.removeValue(forKey: "control")
            } else {
                if !json["data"].exists() {
                    json["data"] = [:]
                }
                json["data"]["control"].string = value!.rawValue
            }
        }
    }
    
    /// The tag-math distribution expression for this message (required)
    public var threadExpression: String? {
        get {
            return json["distribution"]["expression"].string
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "distribution")
            } else {
                json["distribution"] = ["expression": value!]
            }
        }
    }
    
    /// The globally-unique thread ID (required)
    public var threadId: UUID? {
        get {
            return UUID(uuidString: json["threadId"].string ?? "")
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "threadId")
            } else {
                json["threadId"].string = value!.lcString
            }
        }
    }
    
    /// The thread title (optional; provide this if you wish to change the thread title)
    public var threadTitle: String? {
        get {
            return json["threadTitle"].string
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "threadTitle")
            } else {
                json["threadTitle"].string = value!
            }
        }
    }
    
    /// The thread type
    public var threadType: FLIThreadType? {
        get {
            return FLIThreadType(rawValue: json["threadType"].stringValue)
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "threadType")
            } else {
                json["threadType"].string = value!.rawValue
            }
        }
    }
    
    /// The user agent sending this message (optional)
    public var userAgent: String? {
        get {
            return json["userAgent"].string
        }
        set(value) {
            if value == nil {
                json.dictionaryObject?.removeValue(forKey: "userAgent")
            } else {
                json["userAgent"].string = value!
            }
        }
    }
}


extension Sendable {
    /// INTERNAL: the Signal_Content encoding of this `Sendable`
    var contentProto: Signal_Content {
        get {
            var dm = Signal_DataMessage()
            dm.body = "[\(payload.jsonString)]"
            if self.expiration != nil { dm.expireTimer = UInt32(self.expiration!.milliseconds) }
            var flags: UInt32 = 0
            if self.endSessionFlag { flags |= UInt32(Signal_DataMessage.Flags.endSession.rawValue) }
            if self.expirationTimerUpdateFlag { flags |= UInt32(Signal_DataMessage.Flags.expirationTimerUpdate.rawValue) }
            if flags != 0 { dm.flags = flags }

            // TODO: set .attachments based on some sort of attachment pointers...

            var content = Signal_Content()
            content.dataMessage = dm

            return content;
        }
    }
    
    /// Pretty-printed version of this `Sendable`
    public var description: String {
        return """
        Sendable @ \(timestamp.millisecondsSince1970) \
        \(expiration != nil ? "EXPIRATION \(expiration!)": "") \
        \(endSessionFlag ? "\n>>> END SESSION FLAG" : "") \
        \(expirationTimerUpdateFlag ? "\n>>> EXPIRATION TIMER UPDATE FLAG" : "")
        \(payload.description.indentWith(">>> "))
        """
    }
}
