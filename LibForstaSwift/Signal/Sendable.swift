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
    var senderUserId: UUID { get }
    var senderDeviceId: UInt32 { get }
    
    var messageId: UUID { get }
    var messageType: FLIMessageType { get }
    var threadId: UUID { get }
    var distributionExpression: String { get }
    
    var expiration: TimeInterval? { get }
    var endSessionFlag: Bool { get }
    var expirationTimerUpdateFlag: Bool { get }

    // optional body stuff
    var data: JSON? { get }         // the literal data field of the message exchange payload
    var userAgent: String? { get }
    var threadTitle: String? { get }
    var threadType: FLIThreadType? { get }
    var messageRef: UUID? { get }
}

func TextMessageData(plain: String, html: String? = nil) -> JSON {
    var body = [["type": "text/plain", "value": plain]]
    if html != nil { body.append(["type": "text/html", "value": html!]) }
    return JSON(["body" : body])
}

extension Sendable {
    var contentProto: Signal_Content {
        get {
            var body = JSON([[
                "version": 1,
                "messageId": self.messageId.lcString,
                "messageType": self.messageType.rawValue,
                "threadId": self.threadId.lcString,
                "sender": [
                    "userId": self.senderUserId.lcString,
                    "device": self.senderDeviceId,
                ],
                "distribution": [
                    "expression": self.distributionExpression
                ]
                ]])
            
            if self.data != nil { body[0]["data"] = self.data! }
            if self.userAgent != nil { body[0]["userAgent"] = JSON(self.userAgent!) }
            if self.threadTitle != nil { body[0]["threadTitle"] = JSON(self.threadTitle!) }
            if self.threadType != nil { body[0]["threadType"] = JSON(self.threadType!.rawValue) }
            if self.messageRef != nil { body[0]["messageRef"] = JSON(self.messageRef!.lcString) }
            
            var dm = Signal_DataMessage()
            dm.body = body.rawString([.castNilToNSNull: true])!
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
        Sendable from \(senderUserId).\(senderDeviceId) @ \(timestamp)
        >>> distribution: \(distributionExpression)
        >>> \(messageType) message \(messageId) in \(threadType?.rawValue ?? "<no type>") thread \(threadId) (\(threadTitle ?? "<no title>")) \
        \(messageRef != nil ? "\n>>> references message \(messageRef!)" : "")
        \((data != nil ? "data: \(data!.rawString() ?? "<malformed body>"))" : "").indentWith(">>> "))
        """
    }
}
