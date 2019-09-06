//
//  ForstaPayload.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 8/29/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SignalProtocol
import SwiftyJSON


/// A convenience wrapper for v1 of the Forsta message exchange payload
/// (see https://bit.ly/forsta-payload for details)
public class ForstaPayloadV1: CustomStringConvertible {
    /// The underlying payload JSON that is being manipulated/reflected
    public var json: JSON
    
    // -MARK: Constructors
    
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
    
    // -MARK: Utilities
    
    /// The current underlying `JSON` object encoded as a JSON string
    var jsonString: String {
        return json.rawString([.castNilToNSNull: true]) ?? "<malformed JSON>"
    }
    
    /// A pretty-printed version of the current payload's JSON string
    public var description: String {
        return json.description
    }
    
    /// Throw an error if mandatory fields are missing, etc.
    public func sanityCheck() throws {
        // check that mandatory fields are present
        if json["version"].int == nil { throw ForstaError(.invalidPayload, "missing version") }
        if messageId == nil { throw ForstaError(.invalidPayload, "missing messageId") }
        if messageType == nil { throw ForstaError(.invalidPayload, "missing messageType") }
        if threadId == nil { throw ForstaError(.invalidPayload, "missing threadId") }
        if threadExpression == nil { throw ForstaError(.invalidPayload, "missing threadExpression") }
        
        // check basic coherence between control messages and specifying a control message type
        if messageType == .control && controlType == nil {
            throw ForstaError(.invalidPayload, "control message is missing control type")
        }
        if controlType != nil && messageType != .control {
            throw ForstaError(.invalidPayload, "control type specified in non-control message")
        }
        
        // check basic coherence on body contents
        if bodyHtml != nil && bodyPlain == nil {
            throw ForstaError(.invalidPayload, "plain body text is required if there is html body text")
        }
    }
    
    /// Internal: ensure this (dictionary) path exists
    private func ensurePath(_ path: ArraySlice<String>) {
        func ensure(_ dict: inout JSON, _ path: ArraySlice<String>) {
            if path.count > 0 {
                if !dict[path.first!].exists() { dict[path.first!] = [:] }
                ensure(&(dict[path.first!]), path.dropFirst())
            }
        }
        
        ensure(&json, path)
    }
    
    /// Internal: clear the key at this path (removing empty dictionaries)
    private func clearKey(_ path: ArraySlice<String>) {
        func clear(_ dict: inout JSON, _ path: ArraySlice<String>) {
            if path.count > 0 {
                clear(&(dict[path.first!]), path.dropFirst())
                if path.count == 1 || dict[path.first!].dictionaryValue.count == 0 {
                    dict.dictionaryObject?.removeValue(forKey: path.first!)
                }
            }
        }
        
        clear(&json, path)
    }
    
    // -MARK: Accessor properties for the underlying JSON
    
    /// The message's globally-unique ID (required)
    public var messageId: UUID? {
        get {
            return UUID(uuidString: json["messageId"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["messageId"])
            } else {
                json["messageId"].string = value!.lcString
            }
        }
    }
    
    /// A reference to another message, by ID (useful for message replies, or survey responses)
    public var messageRef: UUID? {
        get {
            return UUID(uuidString: json["messageRef"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["messageRef"])
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
                clearKey(["sender"])
            } else {
                json["sender"] = ["userId": value!.name, "device": value!.deviceId]
            }
        }
    }
    
    /// The type of payload this is (required)
    public var messageType: MessageType? {
        get {
            return MessageType(rawValue: json["messageType"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["messageType"])
            } else {
                json["messageType"].string = value!.rawValue
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
                clearKey(["data", "body"])
            } else {
                let ary:[[String: String]] = value!.map {
                    switch $0 {
                    case .plain(let value): return ["type": "text/plain", "value": value]
                    case .html(let value): return ["type": "text/plain", "value": value]
                    case .unknown(let value): return ["type": "text/unknown", "value": value]
                    }
                }
                ensurePath(["data"])
                json["data"]["body"] = JSON(ary)
            }
        }
    }
    
    /// Directly manipulate the (presumed singular) `.plain` entry in the `body` array
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
    
    /// Directly manipulate the (presumed singular) `.html` entry in the `body` array
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
    public var controlType: ControlType? {
        get {
            return ControlType(rawValue: json["data"]["control"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["data", "control"])
            } else {
                ensurePath(["data"])
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
                clearKey(["distribution", "expression"])
            } else {
                json["distribution"] = ["expression": value!]
            }
        }
    }
    
    /// The globally-unique thread ID (required)
    public var threadId: UUID? {
        get {
            return UUID(uuidString: json["threadId"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["threadId"])
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
                clearKey(["threadTitle"])
            } else {
                json["threadTitle"].string = value!
            }
        }
    }
    
    /// The thread type
    public var threadType: ThreadType? {
        get {
            return ThreadType(rawValue: json["threadType"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["threadType"])
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
                clearKey(["userAgent"])
            } else {
                json["userAgent"].string = value!
            }
        }
    }

    /// readMark timestamp (only relevant for `.control` messages of type `.readMark`)
    public var readMark: Date? {
        get {
            guard let timestamp = json["data"]["readMark"].uInt64 else {
                return nil
            }
            return Date(millisecondsSince1970: timestamp)
        }
        set(value) {
            if value == nil {
                clearKey(["data", "readMark"])
            } else {
                ensurePath(["data"])
                json["data"]["readMark"].uInt64 = value!.millisecondsSince1970
            }
        }
    }
    
    /// threadUpdate.threadTitle (only relevant for `.control` messages of type `.threadUpdate`)
    public var threadUpdateTitle: String? {
        get {
            return json["data"]["threadUpdate"]["threadTitle"].string
        }
        set(value) {
            if value == nil {
                clearKey(["data", "threadUpdate", "threadTitle"])
            } else {
                ensurePath(["data", "threadUpdate"])
                json["data"]["threadUpdate"]["threadTitle"].string = value!
            }
        }
    }
    
    /// threadUpdate.expression (only relevant for `.control` messages of type `.threadUpdate`)
    public var threadUpdateExpression: String? {
        get {
            return json["data"]["threadUpdate"]["expression"].string
        }
        set(value) {
            if value == nil {
                clearKey(["data", "threadUpdate", "expression"])
            } else {
                ensurePath(["data", "threadUpdate"])
                json["data"]["threadUpdate"]["expression"].string = value!
            }
        }
    }

    /// callVersion (only relevant for call-related `.control` messages)
    public var callVersion: Int? {
        get {
            return json["data"]["callVersion"].int
        }
        set(value) {
            if value == nil {
                clearKey(["data", "callVersion"])
            } else {
                ensurePath(["data"])
                json["data"]["callVersion"].int = value!
            }
        }
    }
    
    
    /// callId (only relevant for call-related `.control` messages)
    public var callId: UUID? {
        get {
            return UUID(uuidString: json["data"]["callId"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["data", "callId"])
            } else {
                ensurePath(["data"])
                json["data"]["callId"].string = value!.lcString
            }
        }
    }
    
    /// peerId (only relevant for call-related `.control` messages)
    public var peerId: UUID? {
        get {
            return UUID(uuidString: json["data"]["peerId"].stringValue)
        }
        set(value) {
            if value == nil {
                clearKey(["data", "peerId"])
            } else {
                ensurePath(["data"])
                json["data"]["peerId"].string = value!.lcString
            }
        }
    }
    
    /// Call offer sdp string (only relevant for `.control` messages of type `.callAnswer`)
    public var sdpOffer: String? {
        get {
            return json["data"]["offer"].string
        }
        set(value) {
            if value == nil {
                clearKey(["data", "offer"])
            } else {
                ensurePath(["data"])
                json["data"]["offer"].string = value!
            }
        }
    }
    
    /// Call answer sdp string (only relevant for `.control` messages of type `.callOffer`)
    public var sdpAnswer: String? {
        get {
            return json["data"]["answer"].string
        }
        set(value) {
            if value == nil {
                clearKey(["data", "answer"])
            } else {
                ensurePath(["data"])
                json["data"]["answer"].string = value!
            }
        }
    }
    
    /// iceCandidates (only relevant for `.control` messages of type `.callICECandidates`)
    public var iceCandidates: [JSON]? {
        get {
            return json["data"]["icecandidates"].array
        }
        set(value) {
            if value == nil {
                clearKey(["data", "icecandidates"])
            } else {
                ensurePath(["data"])
                json["data"]["icecandidates"] = JSON(value!)
            }
        }
    }

    // - MARK: Related Enums
    
    /// A `.content` message's `body` is represented by an array of `BodyItem`
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

    /// Forsta message types
    public enum MessageType: String {
        /// A control message -- see `ControlType`
        case control = "control"
        /// A content message (i.e., plain/html text)
        case content = "content"
        /// A poll message (defines prescribed responses)
        case poll = "poll"
        /// A poll response message (provides prescribed responses to a poll message)
        case pollResponse = "pollResponse"
    }

    /// Forsta thread types
    public enum ThreadType: String {
        /// A thread where anybody can send to the group
        case conversation = "conversation"
        /// A thread where it is a broadcast
        case announcement = "announcement"
    }

    /// Forsta control message types (used in the Forsta message exchange payload)
    public enum ControlType: String {
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
}
