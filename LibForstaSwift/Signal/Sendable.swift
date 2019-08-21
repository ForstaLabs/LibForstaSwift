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


public enum FLIMessageType: String {
    case control = "control"
    case content = "content"
    case poll = "poll"
    case pollResponse = "pollResponse"
}

public enum FLIThreadType: String {
    case conversation = "conversation"
    case announcement = "announcement"
}

public enum FLIControlMessageType: String {
    case threadUpdate = "threadUpdate"
    case threadClear = "threadClear"
    case threadArchive = "threadArchive"
    case threadRestore = "threadRestore"
    case threadDelete = "threadDelete"
    case readMark = "readMark"
    case pendingMessage = "pendingMessage"
    case snooze = "snooze"
    case provisionRequest = "provisionRequest"
    case syncRequest = "syncRequest"
    case syncResponse = "syncResponse"
    case discoverRequest = "discoverRequest"
    case discoverResponse = "discoverResponse"
    case preMessageCheck = "preMessageCheck"
    case aclRequest = "aclRequest"
    case aclResponse = "aclResponse"
    case userBlock = "userBlock"
    case userUnblock = "userUnblock"
    case beacon = "beacon"
    case closeSession = "closeSession"
    case callJoin = "callJoin"
    case callLeave = "callLeave"
    case callOffer = "callOffer"
    case callAcceptOffer = "callAcceptOffer"
    case callICECandidates = "callICECandidates"
}

public enum MessageRecipient {
    case device(_ address: SignalAddress)
    case user(_ address: UUID)
}

public protocol Sendable {
    var recipients: [MessageRecipient] { get }
    
    var timestamp: Date { get }

    var expiration: TimeInterval? { get }
    var endSessionFlag: Bool { get }
    var expirationTimerUpdateFlag: Bool { get }

    var payload: ForstaPayloadV1 { get }
}

public class ForstaPayloadV1 {
    var json: JSON
    
    init(_ payload: ForstaPayloadV1) {
        self.json = payload.json
    }
    init(_ json: JSON) {
        self.json = json
    }
    init(_ string: String? = nil) {
        self.json = JSON([])
        do {
            json = try JSON(string: string ?? "[\"version\": 1]")
        } catch {
            json = JSON(["version": 1])
        }
        for item in json.arrayValue {
            if item["version"].intValue == 1 {
                json = item
            }
        }
    }
    
    var jsonString: String {
        return json.rawString([.castNilToNSNull: true]) ?? "<malformed JSON>"
    }
    
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
    
    public enum BodyItem: CustomStringConvertible {
        case plain(_ value: String)
        case html(_ value: String)
        case unknown(_ value: String)
        
        public var description: String {
            switch self {
            case .plain(let str): return "\"\(str)\""
            case .html(let str): return "\"\(str)\""
            default: return "<bad item>"
            }
        }
    }

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
    
    public var description: String {
        return """
        Sendable @ \(timestamp.millisecondsSince1970)
        >>> distribution: \(payload.threadExpression ?? "<no distribution expression>")
        >>> \(payload.messageType?.rawValue ?? "<no message type>") message \(payload.messageId?.description ?? "<no message id>") in \(payload.threadType?.rawValue ?? "<no type>") thread \(payload.threadId?.description ?? "<no thread id>") (\(payload.threadTitle ?? "<no title>")) \
        \(payload.messageRef != nil ? "\n>>> references message \(payload.messageRef!)" : "")
        \((payload.body?.description ?? "<no body>").indentWith(">>> "))
        """
    }
}
