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
            print("JSON DECODING ERROR:", error)
            print("WAS TRYING TO DECODE:", jsonString ?? "")
        }
    }
    
    // -MARK: Attributes

    /// The Forsta message exchange payload version
    public var version: Int?

    /// The message's globally-unique ID (required)
    public var messageId: UUID? = UUID()

    /// A reference to another message, by ID (useful for message replies, or survey responses)
    public var messageRef: UUID?

    /// Optionally override the origin of the message if different from source
    public var sender: Address?

    /// The type of payload this is (required)
    public var messageType: MessageType?
    
    /// Any relevant details for this message
    public var data: DataElement?
    
    /// The message's distribution (required)
    public var distribution: Distribution?
    
    /// The globally-unique thread ID (required)
    public var threadId: UUID?
    /// The thread title (optional)
    public var threadTitle: String?
    /// The thread type
    public var threadType: ThreadType?
    
    /// The user agent sending this message (optional)
    public var userAgent: String?
    
    // -MARK: Substructure Schema
    
    /// The schema for the `.data` attribute in a message exchange payload
    public struct DataElement: Codable {
        /// Representations of the message body (plain text, html)
        public var body: [Body]?
        
        /// The control-message type (only relevant for messages of type `.control`)
        public var control: ControlType?
        
        /// The timestamp of the most recently read message by the sender (only relevant for `.control` messages of type `.readMark`)
        public var readMark: Date?
        
        /// Information to update regarding this thread (only relevant for `.control` messages of type `.threadUpdate`)
        public var threadUpdate: ThreadUpdate?
        
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
        
        /// Stream types the peer expects to send (only relevant in call-related `.control` messages)
        public var sends: [StreamType]?
        /// Stream types the peer expects to receive (only relevant in call-related `.control` messages)
        public var receives: [StreamType]?

        /// ICE candidates (only relevant for `.control` messages of type `.callICECandidates`)
        public var icecandidates: [IceCandidate]?
        
        /// SDP offer details (only relevant for `.control` messages of type `.callOffer`)
        public var offer: SDP?
        
        /// SDP answer details (only relevant for `.control` messages of type `.callAcceptOffer`)
        public var answer: SDP?

        /// Further details about the attachments specified in the Signal envelope
        var attachments: [Attachment]?
        
        /// The ephemeral public key provided by a new device for provisioning (only relevant for `.control` messages of type `.provisionRequest`)
        public var key: Data?
        /// Provisioning UUID, string-encoded in a form we will use as-is (only relevant for `.control` messages of type `.provisionRequest`)
        public var uuid: String?
        
        /// Devices for a sync request (only relevant for `.control` messages of type `.syncRequest`)
        public var devices: [UInt32]?
        /// Known contacts for a sync request (only relevant for `.control` messages of type `.syncRequest`)
        public var knownContacts: [KnownContact]?
        /// Known messages for a sync request (only relevant for `.control` messages of type `.syncRequest`)
        public var knownMessages: [UUID]?
        /// Known threads for a sync request (only relevant for `.control` messages of type `.syncRequest`)
        public var knownThreads: [KnownThread]?
        /// How long this is valid in milliseconds (only relevant for `.control` messages of type `.syncRequest`)
        public var ttl: UInt64?
        /// What type of sync request this is (only relevant for `.control` messages of type `.syncRequest`)
        public var type: SyncRequestType?
        
        public var messages: [SyncMessage]?
    }
    
    /// The schema for `.data.messages` (only relevant for `.control` messges of type `.syncResponse`)
    public struct SyncMessage: Codable {
        public var attachments: [Attachment]
        public var expiration: Date?
        public var expirationUpdate: Date?
        public var flags: UInt64?
        public var id: UUID
        public var incoming: Bool?
        public var keyChange: Bool?
        public var members: [UUID]
        public var mentions: [UUID]?
        public var messageRef: UUID?
        public var monitors: [UUID]?
        public var pendingMembers: [UUID]?
        public var plain: String?
        public var read: Date?
        public var received: Date
        public var replies: [UUID]?
        public var safe_html: String?
        public var sender: UUID
        public var senderDevice: UInt32
        public var source: UUID?
        public var sourceDevice: UInt32?
        public var sent: Date
        public var threadId: UUID
        public var type: MessageType
        public var userAgent: String?
        public var actions: [String]? // what is this?
        public var actionOptions: [String]? // what is this?
        public var action: String? // what is this?
        public var serverAge: Date?
        public var timestamp: Date
        
        /// Initialize from components
        public init(
            attachments: [Attachment],
            expiration: Date? = nil,
            expirationUpdate: Date? = nil,
            flags: UInt64? = nil,
            id: UUID,
            incoming: Bool? = nil,
            keyChange: Bool? = nil,
            members: [UUID],
            mentions: [UUID]? = nil,
            messageRef: UUID? = nil,
            monitors: [UUID]? = nil,
            pendingMembers: [UUID]? = nil,
            plain: String? = nil,
            read: Date? = nil,
            received: Date,
            replies: [UUID]? = nil,
            safe_html: String? = nil,
            sender: UUID,
            senderDevice: UInt32,
            source: UUID? = nil,
            sourceDevice: UInt32? = nil,
            sent: Date,
            threadId: UUID,
            type: MessageType,
            userAgent: String? = nil,
            actions: [String]? = nil,
            actionOptions: [String]? = nil,
            action: String? = nil,
            serverAge: Date? = nil,
            timestamp: Date)
        {
            self.attachments = attachments
            self.expiration = expiration
            self.expirationUpdate = expirationUpdate
            self.flags = flags
            self.id = id
            self.incoming = incoming
            self.keyChange = keyChange
            self.members = members
            self.mentions = mentions
            self.messageRef = messageRef
            self.monitors = monitors
            self.pendingMembers = pendingMembers
            self.plain = plain
            self.read = read
            self.received = received
            self.replies = replies
            self.safe_html = safe_html
            self.sender = sender
            self.senderDevice = senderDevice
            self.source = source
            self.sourceDevice = sourceDevice
            self.sent = sent
            self.threadId = threadId
            self.type = type
            self.userAgent = userAgent
            self.actions = actions
            self.actionOptions = actionOptions
            self.action = action
            self.serverAge = serverAge
            self.timestamp = timestamp
        }
    }
    
    /// The schema for `.data.knownContacts`
    public struct KnownContact: Codable {
        /// ID of known user
        public var id: UUID
        /// Last updated timestamp for user
        public var updated: Date
        
        /// Initialize from components
        public init(id: UUID, updated: Date) {
            self.id = id
            self.updated = updated
        }
    }

    /// The schema for `.data.knownThreads`
    public struct KnownThread: Codable {
        /// ID of known thread
        public var id: UUID
        /// Last activity timestamp for known thread
        public var lastActivity: Date
        
        /// Initialize from components
        public init(id: UUID, lastActivity: Date) {
            self.id = id
            self.lastActivity = lastActivity
        }
    }
    
    /// The schema for `.sender`
    public struct Address: Codable {
        /// User ID
        public var userId: UUID
        /// Device ID
        public var device: UInt32?
        
        /// Initialize from a SignalAddress
        public init(_ address: SignalAddress) {
            self.userId = address.userId
            self.device = UInt32(address.deviceId)
        }
    }
    
    /// The schema for `.data` `.body` entries
    public struct Body: Codable {
        /// Type is either "text/plain" or "text/html" (this isn't a sensible enum because "/" currently gets encoded/decoded inappropriately)
        public var type: String
        /// The text of said type
        public var value: String
        
        /// Initialize from components
        public init(type: String, value: String) {
            self.type = type
            self.value = value
        }
    }
    
    /// The schema for `.data` `.threadUpdate` in a message exchange payload
    public struct ThreadUpdate: Codable {
        /// New thread title
        public var threadTitle: String?
        /// New distribution tag-math expression
        public var expression: String?
        
        /// Initialize from components
        public init(threadTitle: String? = nil, expression: String? = nil) {
            self.threadTitle = threadTitle
            self.expression = expression
        }
    }
    
    /// The schema for `.data` `.icecandidates` elements
    public struct IceCandidate: Codable {
        public var candidate: String
        public var sdpMid: String?
        public var sdpMLineIndex: Int32
        public var serverUrl: String?
        
        /// Initialize from components
        public init(candidate: String, sdpMid: String? = nil, sdpMLineIndex: Int32, serverUrl: String? = nil) {
            self.candidate = candidate
            self.sdpMid = sdpMid
            self.sdpMLineIndex = sdpMLineIndex
            self.serverUrl = serverUrl
        }
    }
    
    /// The schema for `.data` `.answer` and `.offer`
    public struct SDP: Codable {
        /// types of SDP
        public enum SdpType: String, Codable {
            case answer
            case offer
        }
        /// SDP type
        public var type: SdpType
        /// The SDP string
        public var sdp: String
        
        /// Initialize from components
        public init(type: SdpType, sdp: String) {
            self.type = type
            self.sdp = sdp
        }
    }
    
    /// The schema for `.data` `.attachments`
    public struct Attachment: Codable {
        /// The file name
        public var name: String?
        /// The file size in bytes
        public var size: Int?
        /// The file mime-type
        public var type: String
        /// The file modification-time
        public var mtime: Date?
        /// An optional index (used to clarify relationship to Signal envelope attachment information in `.syncResponse`s)
        public var index: UInt?
        
        /// Initialize from `AttachmentInfo`
        init(from info: AttachmentInfo) {
            self.name = info.name
            self.size = info.size
            self.type = info.type
            self.mtime = info.mtime
            self.index = nil
        }
    }

    /// The schema for `.distribution`
    public struct Distribution: Codable {
        /// The tag-math distribution expression for this message (required)
        public var expression: String?
        /// The user IDs that `.expression` resolves to (optional)
        public var users: [UUID]?
        
        /// Initialize from components
        public init(expression: String? = nil, users: [UUID]? = nil) {
            self.expression = expression
            self.users = users
        }
    }
    
    // -MARK: Helper Accessors
    
    /// Directly manipulate the (presumed only) plain-text entry in the `.data` `.body` array
    public var bodyPlain: String? {
        get {
            return (data?.body ?? []).first(where: { $0.type == "text/plain" })?.value
        }
        set(value) {
            var ary = (data?.body ?? []).filter({ $0.type != "text/plain" })
            if value != nil {
                ary.append(Body(type: "text/plain", value: value!))
            }
            if data == nil { data = DataElement() }
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
                ary.append(Body(type: "text/html", value: value!))
            }
            if data == nil { data = DataElement() }
            data!.body = ary.count > 0 ? ary : nil
        }
    }
    
    /// Alias for `.data` `.control` -- the type of this control message (meaningful only for `.control` messages)
    public var controlType: ControlType? {
        get {
            return data?.control
        }
        set(value) {
            if data == nil { data = DataElement() }
            data!.control = value
        }
    }
    
    /// Alias for `.distribution` `.expression` -- the tag-math distribution expression for this message (required)
    public var threadExpression: String? {
        get {
            return distribution?.expression
        }
        set(value) {
            if value == nil {
                distribution = nil
            } else {
                if distribution == nil {
                    distribution = Distribution(expression: value!, users: nil)
                } else {
                    distribution!.expression = value!
                }
            }
        }
    }

    /// Alias for `.data` `.readMark` (only relevant for `.control` messages of type `.readMark`)
    public var readMark: Date? {
        get {
            return data?.readMark
        }
        set(value) {
            if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
                if data!.threadUpdate == nil { data!.threadUpdate = ThreadUpdate() }
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
                if data == nil { data = DataElement() }
                if data!.threadUpdate == nil { data!.threadUpdate = ThreadUpdate() }
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
                if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
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
                if data == nil { data = DataElement() }
                if data!.offer == nil {
                    data!.offer = SDP(type: .offer, sdp: value!)
                } else {
                    data!.offer!.sdp = value!
                }
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
                if data == nil { data = DataElement() }
                if data!.answer == nil {
                    data!.answer = SDP(type: .answer, sdp: value!)
                } else {
                    data!.answer!.sdp = value!
                }
            }
        }
    }
    
    /// Alias for `.data` `.icecandidates` (only relevant for `.control` messages of type `.callICECandidates`)
    public var iceCandidates: [IceCandidate]? {
        get {
            return data?.icecandidates
        }
        set(value) {
            if value == nil {
                data?.icecandidates = nil
            } else {
                if data == nil { data = DataElement() }
                data!.icecandidates = value
            }
        }
    }
    
    /// Alias for `.data` `.sends` (only relevant for call-related `.control` messages)
    public var callSends: [StreamType]? {
        get {
            return data?.sends
        }
        set(value) {
            if value == nil {
                data?.sends = nil
            } else {
                if data == nil { data = DataElement() }
                data!.sends = value
            }
        }
    }
    
    /// Alias for `.data` `.receives` (only relevant for call-related `.control` messages)
    public var callReceives: [StreamType]? {
        get {
            return data?.receives
        }
        set(value) {
            if value == nil {
                data?.receives = nil
            } else {
                if data == nil { data = DataElement() }
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
    var attachments: [Attachment]? {
        get {
            return data?.attachments
        }
        set(value) {
            if value == nil {
                data?.attachments = nil
            } else {
                if data == nil { data = DataElement() }
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
    
    /// Types of media a peer could send/receive
    public enum StreamType: String, Codable {
        /// Audio stream
        case audio
        /// Video stream
        case video
    }

    /// Forsta message types
    public enum MessageType: String, Codable {
        /// A control message -- see `ControlType`
        case control
        /// A content message (i.e., plain text and optional html)
        case content
        /// A poll message (defines prescribed responses)
        case poll
        /// A poll response message (provides prescribed responses to a poll message)
        case pollResponse
    }

    /// Forsta thread types
    public enum ThreadType: String, Codable {
        /// A thread where anybody can send to the group
        case conversation
        /// A thread where it is a broadcast
        case announcement
    }

    /// Forsta control message types (used in the Forsta message exchange payload)
    public enum ControlType: String, Codable {
        /// Update thread metadata -- any attributes set in `.data` `.threadUpdate` will be used
        case threadUpdate
        /// Clear history of current thread across my devices
        case threadClear
        /// Archive thread across my devices (WITHOUT leaving the distribution)
        case threadArchive
        /// Restore/unarchive thread across my devices
        case threadRestore
        /// Delete the thread (leaving the distribution) across my devices
        case threadDelete
        /// Indicate to thread participants where your read-position is
        case readMark
        /// Indicate that user is actively typing a message for the thread
        case pendingMessage
        /// Stop notifications, etc. for a period.  See `snoozeUntil` in the payload.
        case snooze
        /// Request to assist in provisioning a new device
        case provisionRequest
        /// Request synchronization with a device's own peers (self devices)
        case syncRequest
        /// Respond to `.syncRequest`
        case syncResponse
        /// Discover threads from peers
        case discoverRequest
        /// Response to `.discoverRequest`
        case discoverResponse
        /// Ask a client for any pre-messages it has for the sender
        case preMessageCheck
        /// Client prompting a bot to perform an ACL operation
        case aclRequest
        /// Bot responding to `.aclRequest`
        case aclResponse
        /// Block a user by ID
        case userBlock
        /// Unblock a user by ID
        case userUnblock
        /// Initiate contact with peers
        case beacon
        /// Extended metadata for a message using the END_SESSION flag
        case closeSession
        /// A broadcast offer of or intent to participate in an WebRTC call
        case callJoin
        /// A broadcast leaving/rejecting of a WebRTC call
        case callLeave
        /// Offering a WebRTC connection to a specific device in a call
        case callOffer
        /// Accepting a connection offer from a specific device in a call
        case callAcceptOffer
        /// Control message providing WebRTC call ICE candidates to establish a connection with a device
        case callICECandidates
        /// Indicates that a call is ongoing with the recipient, from the sender's perspective
        case callHeartbeat
    }
    
    public enum SyncRequestType: String, Codable {
        /// syncing content history
        case contentHistory
        /// syncing device information
        case deviceInfo
    }
}
