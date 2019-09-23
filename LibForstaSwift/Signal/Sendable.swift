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
    /// The Signal envelope expiration-timer update flag
    var expirationTimerUpdateFlag: Bool { get }

    /// Information about uploaded attachments (use `SignalClient`.`uploadAttachment(...)` to do this)
    var attachments: [AttachmentInfo] { get }
    /// The Forsta message payload
    var payload: ForstaPayloadV1 { get }
}



extension Sendable {
    /// INTERNAL: the Signal_Content protobuf encoding for this `Sendable`
    var contentProto: Signal_Content {
        get {
            var json = payload.json
            if !json["data"].exists() { json["data"] = JSON([:]) }
            json["data"]["attachments"] = JSON(attachments.map { info in [
                "name": info.name,
                "size": info.size,
                "type": info.type,
                "mtime": info.mtime.millisecondsSince1970
                ]
            })

            var dm = Signal_DataMessage()
            dm.body = "[\(ForstaPayloadV1(json).jsonString)]"
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
