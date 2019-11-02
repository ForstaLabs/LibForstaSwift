//
//  Sendable.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 8/5/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import Starscream
import SignalProtocol
import SwiftyJSON

/// Address for specifying recipients for sending
public enum MessageRecipient {
    /// Address of a user's specific device
    case device(_ address: SignalAddress)
    /// Address of a user's entire set of devices
    case user(_ address: UUID)
}

/// Protocol for a sendable message
public protocol Sendable {
    /// The message timestamp (used to identify messages in Signal)
    var timestamp: Date { get }

    /// Message expiration (number of seconds after read)
    var expiration: TimeInterval? { get }
    
    /// The Signal envelope end-session flag
    var endSessionFlag: Bool { get }
    /// The Signal envelope expiration-timer-update flag
    var expirationTimerUpdateFlag: Bool { get }

    /// Information about uploaded attachments (use `SignalClient`.`uploadAttachment(...)` to upload them)
    var attachments: [AttachmentInfo] { get }
    /// The Forsta message payload
    var payload: ForstaPayloadV1 { get }
}



extension Sendable {
    /// INTERNAL: the Signal_Content protobuf encoding for this `Sendable`
    func contentProto(privateKey: Data) throws -> Signal_Content {
        var payloadCopy = payload
        payloadCopy.attachments = attachments.map {
            return ForstaPayloadV1.Attachment(from: $0)
        }
        let signatureMessage = """
        \(timestamp.millisecondsSince1970)\
        \(payload.threadExpression ?? "")\
        \(payload.messageId?.lcString ?? "")\
        \(payload.threadId?.lcString ?? "")\
        \(payload.messageRef?.lcString ?? "")\
        \(payload.data?.body?.map({ $0.value }).joined() ?? "")\
        \(attachments.map({ $0.hash?.base64EncodedString() ?? "" }).joined())
        """
        
        payloadCopy.signature = try SignalCommonCrypto.generateSignature(privateKeyData: privateKey, message: signatureMessage.toData())
        
        var dm = Signal_DataMessage()
        dm.body = payloadCopy.json() ?? "<json encoding error>"
        if self.expiration != nil { dm.expireTimer = UInt32(self.expiration!.milliseconds) }
        var flags: UInt32 = 0
        if self.endSessionFlag { flags |= UInt32(Signal_DataMessage.Flags.endSession.rawValue) }
        if self.expirationTimerUpdateFlag { flags |= UInt32(Signal_DataMessage.Flags.expirationTimerUpdate.rawValue) }
        if flags != 0 { dm.flags = flags }
        
        dm.attachments = attachments.map { info -> Signal_AttachmentPointer in
            var pointer = Signal_AttachmentPointer()
            pointer.id = info.id
            pointer.contentType = info.type
            pointer.key = info.key
            return pointer
        }
        
        var content = Signal_Content()
        content.dataMessage = dm
        
        return content;
    }

    /// Pretty-printed version of this `Sendable`
    public var description: String {
        return """
        SENDABLE @ \(timestamp.millisecondsSince1970) \
        \(expiration != nil ? "\n>>> Expiration of \(expiration!) seconds": "") \
        \(endSessionFlag ? "\n>>> END-SESSION flag set" : "") \
        \(expirationTimerUpdateFlag ? "\n>>> EXPIRATION-TIMER-UPDATE flag set" : "") \
        \(attachments.count > 0 ? "\n>>> Attachments \(attachments.map { $0.description })" : "")
        \(payload.description.indentWith(">>> "))
        """
    }
}
