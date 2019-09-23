//
//  ForstaPayload.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 8/29/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SignalProtocol

/// A convenience wrapper for consuming/producing v1 of the
/// Forsta message exchange JSON payload (see https://bit.ly/forsta-payload for details)
public struct ForstaPayloadV1: CustomStringConvertible, Codable {
    // -MARK: Constructors
    
    /// Initialize with an (optional) JSON payload string
    public init(_ jsonString: String? = nil) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64

        do {
            let data = (jsonString ?? "[{\"version\": 1}]").toData()
            // let ary = (try? decoder.decode([ForstaPayloadV1].self, from: data)) ?? []
            let ary = try decoder.decode([ForstaPayloadV1].self, from: data)
            
            for item in ary {
                if item.version == 1 {
                    self = item
                }
            }
        } catch let error {
            print("ERROR:", error)
            print("WAS TRYING TO DECODE:", jsonString ?? "")
        }
    }

    /// The Forsta message exchange payload version
    public var version: Int?

    /// The message's globally-unique ID (required)
    public var messageId: UUID?

    /// A reference to another message, by ID (useful for message replies, or survey responses)
    public var messageRef: UUID?

    /// The schema for `.sender`
    public struct AddressSchema: Codable {
        /// User ID
        public var userId: UUID
        /// Device ID
        public var device: UInt32?
    }
    /// Optionally override the origin of the message if different from source
    public var sender: AddressSchema?

    /// The type of payload this is (required)
    public var messageType: MessageType?

    /// The schema for the `.data` in a message exchange payload
    public struct DataSchema: Codable {
        /// The ephemeral public key provided by a new device for provisioning (only relevant for `.control` messages of type `.provisionRequest`)
        public var key: Data?
        /// Provisioning UUID, string-encoded in a form we will use as-is (only relevant for `.control` messages of type `.provisionRequest`)
        public var uuid: String?
        
        /// The schema for `.data` `.body` entries
        public struct BodySchema: Codable {
            /// Either "text/plain" or "text/html" (sorry, this isn't a sensible enum because the "/" currently gets encoded/decoded inappropriately)
            public var type: String
            /// The text of said type
            public var value: String
        }
        /// Representations of the message body (plain text, html)
        public var body: [BodySchema]?
        /// The control-message type (only relevant for messages of type `.control`)
        public var control: ControlType?
        /// The timestamp of the most recently read message by the sender (only relevant for `.control` messages of type `.readMark`)
        public var readMark: Date?
        /// The schema for `.data` `.threadUpdate` in a message exchange payload
        public struct ThreadUpdateSchema: Codable {
            /// New thread title
            public var threadTitle: String?
            /// New distribution tag-math expression
            public var expression: String?
        }
        /// Information to update regarding this thread (only relevant for `.control` messages of type `.threadUpdate`)
        public var threadUpdate: ThreadUpdateSchema?
        
        /// Call version (only relevant in call-related `.control` messages)
        public var version: Int?
        /// Call members (only relevant for `.control` of type `.callJoin`)
        public var members: [UUID]?
        /// Call originator (only relevant for `.control` of type `.callJoin`)
        public var originator: UUID?
        /// Call ID (only relevant in call-related `.control` messages)
        public var callId: UUID?
        /// Call peer ID (only relevant in call-related `.control` messages)
        public var peerId: UUID?
        
        /// Types of media a peer could send/receive
        public enum StreamType:String, Codable {
            /// Audio stream
            case audio = "audio"
            /// Video stream
            case video = "video"
        }
        /// Stream types the peer expects to send
        public var sends: [StreamType]?
        /// Stream types the peer expects to receive
        public var receives: [StreamType]?

        /// The schema for `.data` `.icecandidates` elements
        public typealias IceCandidate = [String: String]
        /// ICE candidates (only relevant for `.control` messages of type `.callICECandidates`)
        public var icecandidates: [IceCandidate]?
        
        /// The schema for `.data` `.offer`
        public struct SdpOfferSchema: Codable {
            /// Fixed type == "offer"
            public var type: String = "offer"
            /// The actual SDP string
            public var sdp: String?
        }
        /// SDP offer details (only relevant for `.control` messages of type `.callOffer`)
        public var offer: SdpOfferSchema?
        
        /// The schema for `.data` `.answer`
        public struct SdpAnswerSchema: Codable {
            /// Fixed type == "answer"
            public var type: String = "answer"
            /// The actual SDP string
            public var sdp: String?
        }
        /// SDP answer details (only relevant for `.control` messages of type `.callAcceptOffer`)
        var answer: SdpAnswerSchema?

        /// The schema for `.data` `.attachments`
        struct AttachmentSchema: Codable {
            /// The file name
            public var name: String
            /// The file size in bytes
            public var size: Int
            /// The file mime-type
            public var type: String
            /// The file modification-time
            public var mtime: Date
            
            init(from info: AttachmentInfo) {
                self.name = info.name
                self.size = info.size
                self.type = info.type
                self.mtime = info.mtime
            }
        }
        /// Further details about the attachments specified in the Signal envelope
        var attachments: [AttachmentSchema]?
    }
    
    /// Any relevant details for this message
    public var data: DataSchema?
    
    /// The schema for `.distribution`
    public struct DistributionSchema: Codable {
        /// The tag-math distribution expression for this message (required)
        public var expression: String?
        /// The user IDs that `.expression` resolves to (optional)
        public var users: [UUID]?
    }
    /// The message's distribution (required)
    public var distribution: DistributionSchema?
    
    /// The globally-unique thread ID (required)
    public var threadId: UUID?
    
    /// The thread title (optional)
    public var threadTitle: String?
    
    /// The thread type
    public var threadType: ThreadType?
    
    /// The user agent sending this message (optional)
    public var userAgent: String?

    // -MARK: Helper Accessors
    
    /// Directly manipulate the (presumed only) plain-text entry in the `.data` `.body` array
    public var bodyPlain: String? {
        get {
            return (data?.body ?? []).first(where: { $0.type == "text/plain" })?.value
        }
        set(value) {
            var ary = (data?.body ?? []).filter({ $0.type != "text/plain" })
            if value != nil {
                ary.append(DataSchema.BodySchema(type: "text/plain", value: value!))
            }
            if data == nil { data = DataSchema() }
            data!.body = ary.count > 0 ? ary : nil
        }
    }
    
    /// Directly manipulate the (presumed only) HTML entry in the `.data` `.body` array
    public var bodyHtml: String? {
        get {
            return (data?.body ?? []).first(where: { $0.type == "text/html" })?.value
        }
        set(value) {
            var ary = (data?.body ?? []).filter({ $0.type != "text/html" })
            if value != nil {
                ary.append(DataSchema.BodySchema(type: "text/html", value: value!))
            }
            if data == nil { data = DataSchema() }
            data!.body = ary.count > 0 ? ary : nil
        }
    }
    
    /// Alias for `.data` `.control` -- the type of this control message (meaningful only for `.control` messages)
    public var controlType: ControlType? {
        get {
            return data?.control
        }
        set(value) {
            if data == nil { data = DataSchema() }
            data!.control = value
        }
    }
    
    /// Alias for `.distribution` `.expression` -- the tag-math distribution expression for this message (required)
    public var threadExpression: String? {
        get {
            return distribution?.expression
        }
        set(value) {
            if distribution == nil {
                distribution = DistributionSchema(expression: value!, users: nil)
            } else {
                distribution!.expression = value
            }
            if distribution?.expression == nil && distribution?.users == nil {
                distribution = nil
            }
        }
    }

    /// Alias for `.data` `.readMark` (only relevant for `.control` messages of type `.readMark`)
    public var readMark: Date? {
        get {
            return data?.readMark
        }
        set(value) {
            if data == nil { data = DataSchema() }
            data!.readMark = value
        }
    }
    
    /// Alias for `.data` `.threadUpdate` `.threadTitle` (only relevant for `.control` messages of type `.threadUpdate`)
    public var threadUpdateTitle: String? {
        get {
            return data?.threadUpdate?.threadTitle
        }
        set(value) {
            if value == nil {
                data?.threadUpdate?.threadTitle = nil
            } else {
                if data == nil { data = DataSchema() }
                if data!.threadUpdate == nil { data!.threadUpdate = DataSchema.ThreadUpdateSchema() }
                data!.threadUpdate!.threadTitle = value
            }
            if data?.threadUpdate?.threadTitle == nil && data?.threadUpdate?.expression == nil {
                data?.threadUpdate = nil
            }
        }
    }
    
    /// Alias for `.data` `.threadUpdate` `.expression` (only relevant for `.control` messages of type `.threadUpdate`)
    public var threadUpdateExpression: String? {
        get {
            return data?.threadUpdate?.expression
        }
        set(value) {
            if value == nil {
                data?.threadUpdate?.expression = nil
            } else {
                if data == nil { data = DataSchema() }
                if data!.threadUpdate == nil { data!.threadUpdate = DataSchema.ThreadUpdateSchema() }
                data!.threadUpdate!.expression = value
            }
            if data?.threadUpdate?.threadTitle == nil && data?.threadUpdate?.expression == nil {
                data?.threadUpdate = nil
            }
        }
    }

    /// Alias for `.data` `.version` (only relevant for call-related `.control` messages)
    public var callVersion: Int? {
        get {
            return data?.version
        }
        set(value) {
            if value == nil {
                data?.version = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.version = value
            }
        }
    }

    /// Alias for `.data` `.callId` (only relevant for call-related `.control` messages)
    public var callId: UUID? {
        get {
            return data?.callId
        }
        set(value) {
            if value == nil {
                data?.callId = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.callId = value
            }
        }
    }

    /// Alias for `.data` `.peerId` (only relevant for call-related `.control` messages)
    public var peerId: UUID? {
        get {
            return data?.peerId
        }
        set(value) {
            if value == nil {
                data?.peerId = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.peerId = value
            }
        }
    }

    /// Alias for `.data` `.originator` (only relevant for `.control` of type `.callJoin`)
    public var callOriginator: UUID? {
        get {
            return data?.originator
        }
        set(value) {
            if value == nil {
                data?.originator = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.originator = value
            }
        }
    }
    
    /// Alias for `.data` `.members` (only relevant for `.control` of type `.callJoin`)
    public var callMembers: [UUID]? {
        get {
            return data?.members
        }
        set(value) {
            if value == nil {
                data?.members = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.members = value
            }
        }
    }
    
    /// Alias for `.data` `.offer` `.sdp` (only relevant for `.control` messages of type `.callOffer`)
    public var sdpOffer: String? {
        get {
            return data?.offer?.sdp
        }
        set(value) {
            if value == nil {
                data?.offer = nil
            } else {
                if data == nil { data = DataSchema() }
                if data!.offer == nil { data!.offer = DataSchema.SdpOfferSchema() }
                data!.offer!.sdp = value
            }
        }
    }
    
    /// Alias for `.data` `.answer` `.sdp` (only relevant for `.control` messages of type `.callAcceptOffer`)
    public var sdpAnswer: String? {
        get {
            return data?.answer?.sdp
        }
        set(value) {
            if value == nil {
                data?.answer = nil
            } else {
                if data == nil { data = DataSchema() }
                if data!.answer == nil { data!.answer = DataSchema.SdpAnswerSchema() }
                data!.answer!.sdp = value
            }
        }
    }
    
    /// Alias for `.data` `.icecandidates` (only relevant for `.control` messages of type `.callICECandidates`)
    public var iceCandidates: [DataSchema.IceCandidate]? {
        get {
            return data?.icecandidates
        }
        set(value) {
            if value == nil {
                data?.icecandidates = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.icecandidates = value
            }
        }
    }
    
    /// Alias for `.data` `.sends` (only relevant for call-related `.control` messages)
    public var callSends: [DataSchema.StreamType]? {
        get {
            return data?.sends
        }
        set(value) {
            if value == nil {
                data?.sends = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.sends = value
            }
        }
    }
    
    /// Alias for `.data` `.receives` (only relevant for call-related `.control` messages)
    public var callReceives: [DataSchema.StreamType]? {
        get {
            return data?.receives
        }
        set(value) {
            if value == nil {
                data?.receives = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.receives = value
            }
        }
    }

    /// Alias for `.data` `.key` (only relevant for `.control` messages of type `.provisionRequest`)
    public var provisioningKey: Data? {
        return data?.key
    }
    
    /// Alias for `.data` `.uuid` (only relevant for `.control` messages of type `.provisionRequest`)
    public var provisioningUuidString: String? {
        return data?.uuid
    }
    
    /// Alias for `.data` `.attachments` (be sure that these correspond 1:1 with Signal envelope attachement information!)
    var attachments: [DataSchema.AttachmentSchema]? {
        get {
            return data?.attachments
        }
        set(value) {
            if value == nil {
                data?.attachments = nil
            } else {
                if data == nil { data = DataSchema() }
                data!.attachments = value
            }
        }
    }

    // -MARK: Utilities
    
    /// This payload encoded as a JSON string
    func json(prettyPrint: Bool = false) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        if prettyPrint {
            encoder.outputFormatting = .prettyPrinted
        }
        
        guard
            let data = try? encoder.encode(self),
            let string = String(data: data, encoding: .utf8) else {
                return nil
        }
        return "[\(string.lowercasedJsonUuidValues)]"
    }
    
    /// A pretty-printed version of this payload's JSON encoding
    public var description: String {
        return json(prettyPrint: true) ?? "<failed to encode payload JSON>"
    }
    
    /// Throw an error if mandatory fields are missing, etc.
    public func sanityCheck() throws {
        // check that mandatory fields are present
        if version == nil { throw ForstaError(.invalidPayload, "missing version") }
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
    
    // - MARK: Related Subtypes

    /// Forsta message types
    public enum MessageType: String, Codable {
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
    public enum ThreadType: String, Codable {
        /// A thread where anybody can send to the group
        case conversation = "conversation"
        /// A thread where it is a broadcast
        case announcement = "announcement"
    }

    /// Forsta control message types (used in the Forsta message exchange payload)
    public enum ControlType: String, Codable {
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
        
        /// Indicates that a call is ongoing with the recipient, from the sender's perspective
        case callHeartbeat = "callHeartbeat"
    }
}
