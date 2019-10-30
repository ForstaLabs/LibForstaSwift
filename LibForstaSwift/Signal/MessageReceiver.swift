//
//  MessageReceiver.swift
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


/// Read-receipt to indicate *among our own devices* what messages have been read by the user
public class SyncReadReceipt: CustomStringConvertible {
    // -MARK: Attributes
    
    /// the read-message's sender's userId
    public let sender: UUID
    /// the read-message's timestamp (used to identify messages in Signal)
    public let timestamp: Date
    
    /// init with sender and timestamp
    public init(_ sender: UUID, _ timestamp: Date) {
        self.sender = sender
        self.timestamp = timestamp
    }
    
    // -MARK: Utilities
    
    /// human-readable string for this receipt
    public var description: String {
        return "SyncReadReceipt(\(self.sender) @ \(self.timestamp.millisecondsSince1970))"
    }
}

/// Signal server delivery receipt for a message being received by a recipient's device
public class DeliveryReceipt: CustomStringConvertible {
    // -MARK: Attributes
    
    /// the device that retrieved a message we sent from the Signal server
    public let address: SignalAddress
    /// the timestamp of the sent message (used to identify messages in Signal)
    public let timestamp: Date
    
    /// init with address and timestamp
    init(_ address: SignalAddress, _ timestamp: Date) {
        self.address = address
        self.timestamp = timestamp
    }
    
    // -MARK: Utilities
    
    /// human-readable string for this receipt
    public var description: String {
        return "DeliveryReceipt(\(self.address) @ \(self.timestamp.millisecondsSince1970))"
    }
}

/// Information about an attached file that has been encrypted and uploaded
/// (use `SignalClient`.`uploadAttachment(...)` to get these)
public class AttachmentInfo: CustomStringConvertible {
    // -MARK: Attributes
    /// The file name
    public let name: String
    /// The file size in bytes
    public let size: Int
    /// The file modification time
    public let mtime: Date
    /// The content integrity hash
    public let hash: Data?

    /// The file content mime type
    public let type: String
    /// The storage id used to download the encrypted file contents
    public let id: UInt64
    /// The key used to encrypt the file contents before upload
    public let key: Data

    

    init(name: String, size: Int, type: String, mtime: Date, hash: Data?, id: UInt64, key: Data) {
        self.name = name
        self.size = size
        self.type = type
        self.mtime = mtime
        self.hash = hash
        self.id = id
        self.key = key
    }
    
    // -MARK: Utilities
    
    /// A human-readable summary of this info
    public var description: String {
        return "<\(id): \(name), \(type), \(size) bytes>"
    }
}

/// An inbound message (whether from another user or as a sync message from self)
public class InboundMessage: CustomStringConvertible, Sendable {
    // -MARK: Attributes
    
    /// Device that sent the message (note that this would be one of ours if it is a sync message)
    public var source: SignalAddress
    /// Timestamp of the sent message
    public var timestamp: Date
    /// Expiration of the message in seconds, if provided
    public var expiration: TimeInterval?
    /// How long the message was retained by the Signal server before it was received here
    public var serverAge: TimeInterval
    /// Timestamp for when the Signal server received the message (useful for correcting clock skew)
    public var serverReceived: Date
    /// Whether the end-session flag was set in the envelope
    public var endSessionFlag: Bool
    /// Whether the expiration-timer-update flag was set in the envelope
    public var expirationTimerUpdateFlag: Bool
    
    /// A `ForstaPayloadV1` initialized with the the inbound message's envelope body
    public var payload: ForstaPayloadV1
    
    /// Information about any associated attachments -- use `SignalClient.fetchAttachment()` to retrieve and decrypt them
    public var attachments: [AttachmentInfo]
    
    /// Expiration start-time (if there was an expiration and this is a sync message from another of our devices)
    public var expirationStart: Date?
    /// The "destination" set in the sync message container (in Forsta, this is usually the threadId for the message)
    public var destination: String?
    
    // -MARK: Internal Attributes
    
    /// The Signal envelope body you shouldn't need to look at directly
    /// because `.payload` represents the same information in a nice form
    public var signalBody: String
    
    
    init(source: SignalAddress,
         timestamp: Date,
         expiration: TimeInterval? = nil,
         serverAge: TimeInterval,
         serverReceived: Date,
         endSessionFlag: Bool = false,
         expirationTimerUpdateFlag: Bool = false,
         signalBody: String,
         signalAttachments: [Signal_AttachmentPointer] = [],
         expirationStart: Date? = nil,
         destination: String? = nil) {
        self.source = source
        self.timestamp = timestamp
        self.expiration = expiration
        self.serverAge = serverAge
        self.serverReceived = serverReceived
        self.endSessionFlag = endSessionFlag
        self.expirationTimerUpdateFlag = expirationTimerUpdateFlag
        self.signalBody = signalBody
        self.payload = ForstaPayloadV1(signalBody)
        self.expirationStart = expirationStart
        self.destination = destination
        
        if signalAttachments.count != self.payload.attachments?.count ?? 0 {
            let subAttachments = (self.payload.data?.messages ?? []).flatMap { $0.attachments }
            if signalAttachments.count == subAttachments.count {
                self.payload.attachments = subAttachments
            } else {
                print("WARNING: envelope attachment count \(signalAttachments.count) doesn't match payload attachment count \(self.payload.attachments?.count ?? 0)")
            }
        }

        self.attachments = zip(signalAttachments, self.payload.attachments ?? []).map {
            let (signal, forsta) = $0
            return AttachmentInfo(name: forsta.name ?? "",
                                  size: forsta.size ?? 0,
                                  type: signal.contentType,
                                  mtime: forsta.mtime ?? Date.timestamp,
                                  hash: forsta.hash,
                                  id: signal.id,
                                  key: signal.key)
        }
    }
    
    // -MARK: Utilities
    
    /// human-readable string to get the gist of this `InboundMessage`
    public var description: String {
        return """
        INBOUND @ \(timestamp.millisecondsSince1970)
        >>> From \(source) \
        \(expiration != nil ? "\n>>> Expiration of \(expiration!) seconds": "") \
        \(endSessionFlag ? "\n>>> END-SESSION flag set" : "") \
        \(expirationTimerUpdateFlag ? "\n>>> EXPIRATION-TIMER-UPDATE flag set" : "") \
        \(attachments.count > 0 ? "\n>>> Attachments \(attachments.map { $0.description })" : "")
        \(payload.description.indentWith(">>> "))
        """
    }
    
    public func verifySignature(store: SignalStore) throws -> Bool {
        let message = """
        \(timestamp.millisecondsSince1970)\
        \(payload.threadExpression ?? "")\
        \(payload.messageId?.lcString ?? "")\
        \(payload.threadId?.lcString ?? "")\
        \(payload.messageRef?.lcString ?? "")\
        \(payload.bodyPlain ?? "")\
        \(payload.bodyHtml ?? "")\
        \(attachments.map { $0.hash?.base64EncodedString() ?? "" }.joined())
        """
        var signer = source.userId
        if payload.sender != nil {
            signer = payload.sender!.userId
        }
        guard
            let signature = payload.signature,
            let pubKey = store.forstaIdentityKeyStore.publicIdentityKey(for: signer) else {
                return false
        }
        
        return try SignalCommonCrypto.verifySignature(signature: signature, publicKeyData: pubKey, message: message.toData())
    }
}


/// Manage receiving and decrypting Forsta messages destined for this device
public class MessageReceiver {
    /// The `SignalClient` to use
    let signalClient: SignalClient
    /// The `WebSocketResource` to listen to
    let wsr: WebSocketResource
    
    // -MARK: Constructors
    
    /// Init with `SignalClient` and an optional `WebSocketResource` to use (it will make its own if not provided)
    public init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
        self.wsr.requestHandler = self.handleRequest
    }
    
    
    /// Handle an incoming websocket request (/queue/empty or /message), decoding and decrypting for this device
    private func handleRequest(request: IncomingWSRequest) {
        // print("Handling WS request \(request.verb) \(request.path)...")
        if request.path == WSRequest.Path.queueEmpty {
            NotificationCenter.broadcast(.signalQueueEmpty)
            self.signalClient.delegates.notify { $0.queueEmpty() }
            let _ = request.respond(status: 200, message: "OK")
            return
        } else if request.path != WSRequest.Path.message || request.verb != "PUT" {
            print("Expected PUT /api/v1/message; got \(request.verb) \(request.path)")
            let _ = request.respond(status: 400, message: "Invalid Resource");
            return
        }
        do {
            guard request.body != nil else {
                throw ForstaError(.invalidMessage, "No body for incoming WS request.")
            }
            guard self.signalClient.signalingKey != nil else {
                throw ForstaError(.decryptionError, "No signaling key established.")
            }
            let data = try decryptWebSocketMessage(message: request.body!, signalingKey: self.signalClient.signalingKey!)
            let envelope = try Signal_Envelope(serializedData: data)
            if envelope.type == .receipt {
                let receipt = DeliveryReceipt(SignalAddress(userId: envelope.source,
                                                            deviceId: envelope.sourceDevice),
                                              Date(millisecondsSince1970: envelope.timestamp))
                NotificationCenter.broadcast(.signalDeliveryReceipt, ["deliveryReceipt": receipt])
                self.signalClient.delegates.notify { $0.deliveryReceipt(receipt: receipt) }
            } else if envelope.hasContent {
                try handleContentMessage(envelope)
            } else if envelope.hasLegacyMessage {
                throw ForstaError(.legacyMessage, "Legacy signal messages not supported.")
            } else {
                throw ForstaError(.invalidMessage, "Received message with no content.")
            }
            let _ = request.respond(status: 200, message: "OK")
        } catch let error {
            print("Telling Signal server we had an error handling incoming message", error.localizedDescription)
            let _ = request.respond(status: 500, message: "Bad encrypted websocket message")
        }
    }
    
    /// Internal: Handle a "Content" message, extracting and decrypting incoming messages, sync messages, sync read-receipts
    private func handleContentMessage(_ envelope: Signal_Envelope) throws {
        let plainText = try self.decrypt(envelope, envelope.content);
        let content = try Signal_Content(serializedData: plainText)
        var sent: Signal_SyncMessage.Sent? = nil
        var dm: Signal_DataMessage? = nil
        var happy = false
        if content.hasSyncMessage && content.syncMessage.hasSent {
            // receiving a message sent by another device for this account
            sent = content.syncMessage.sent
            dm = sent!.message
        } else if content.hasDataMessage {
            // receiving a message sent by some other account
            dm = content.dataMessage
        } else if content.hasSyncMessage && content.syncMessage.read.count > 0 {
            // receiving a collection of read-receipts from another device for this account
            var receipts = [SyncReadReceipt]()
            for r in content.syncMessage.read {
                guard let sender: UUID = UUID(uuidString: r.sender) else {
                    throw ForstaError(.invalidMessage, "Synced read-receipt has malformed sender: \(r.sender)")
                }
                let timestamp: Date = Date(millisecondsSince1970: r.timestamp)
                receipts.append(SyncReadReceipt(sender, timestamp))
            }
            happy = true
            NotificationCenter.broadcast(.signalSyncReadReceipts, ["syncReadReceipts": receipts])
            self.signalClient.delegates.notify { $0.syncReadReceipts(receipts: receipts) }
        }
        
        if dm != nil {
            let expirationTimerUpdateFlag = dm!.hasFlags && (dm!.flags & UInt32(Signal_DataMessage.Flags.expirationTimerUpdate.rawValue)) != 0
            let endSessionFlag = dm!.hasFlags && (dm!.flags & UInt32(Signal_DataMessage.Flags.endSession.rawValue)) != 0
            let msg = InboundMessage(source: SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                     timestamp: Date(millisecondsSince1970: envelope.timestamp),
                                     expiration: dm!.hasExpireTimer
                                        ? TimeInterval(milliseconds: dm!.expireTimer)
                                        : nil,
                                     serverAge: TimeInterval(milliseconds: envelope.age),
                                     serverReceived: Date(millisecondsSince1970: envelope.received),
                                     endSessionFlag: endSessionFlag,
                                     expirationTimerUpdateFlag: expirationTimerUpdateFlag,
                                     signalBody: dm!.hasBody ? dm!.body : "",
                                     signalAttachments: dm!.attachments,
                                     expirationStart: (sent?.hasExpirationStartTimestamp ?? false)
                                        ? Date(millisecondsSince1970: sent!.expirationStartTimestamp)
                                        : nil,
                                     destination: (sent?.hasDestination ?? false) ? sent!.destination : nil)
            happy = true
            NotificationCenter.broadcast(.signalInboundMessage, ["inboundMessage": msg])
            self.signalClient.delegates.notify { $0.inboundMessage(message: msg) }
        }
        
        if !happy {
            throw ForstaError(.invalidMessage, "Inbound content message has no dataMessage or syncMessage.")
        }
    }
    
    /// Internal: Signal-Axolotl-decrypt an incoming envelope's content
    private func decrypt(_ envelope: Signal_Envelope, _ cyphertext: Data) throws -> Data {
        let addr = SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice)
        let sessionCipher = SessionCipher(for: addr, in: self.signalClient.store)
        let paddedClearData: Data
        if envelope.type == .prekeyBundle {
            paddedClearData = try sessionCipher.decrypt(preKeySignalMessage: cyphertext)
        } else if envelope.type == .ciphertext {
            paddedClearData = try sessionCipher.decrypt(signalMessage: cyphertext)
        } else {
            throw ForstaError(.invalidMessage, "Invalid envelope type: \(envelope.type)")
        }
        return try unpad(paddedClearData: paddedClearData)
    }
    
    /// Internal: Unpad an incoming envelope's plaintext after decrypting
    private func unpad(paddedClearData: Data, terminator: UInt8 = 0x80) throws -> Data {
        for idx in (0...paddedClearData.count-1).reversed() {
            if paddedClearData[idx] == 0x00 { continue }
            else if paddedClearData[idx] == terminator {
                return paddedClearData.prefix(upTo: idx)
            } else {
                throw ForstaError(.decryptionError, "Invalid padding terminator.")
            }
        }
        throw ForstaError(.decryptionError, "Padding with no content.")
    }
    
    /// Internal: decrypt the inbound message (encrypted by the Signal server for us)
    private func decryptWebSocketMessage(message: Data, signalingKey: Data) throws -> Data {
        guard signalingKey.count == 52 else {
            throw ForstaError(.invalidKey, "Invalid signaling key length.")
        }
        guard message.count >= 1 + 16 + 10 else {
            throw ForstaError(.invalidLength, "Invalid message length.")
        }
        guard message[0] == 1 else {
            throw ForstaError(.invalidMessage, "Message version number \(message[0]) != 1.")
        }
        
        let aesKey = signalingKey[0...31]
        let macKey = signalingKey[32...32+19]
        let iv = message[1...16]
        let ciphertext = message[1+16...message.count-11]
        let ivAndCyphertext = message[0...message.count-11]
        let mac = message[(message.count-10)...]
        
        try SignalCommonCrypto.verifyMAC(data: ivAndCyphertext, key: macKey, expectedMAC: mac)
        return try SignalCommonCrypto.decrypt(message: ciphertext, key: aesKey, iv: iv)
    }
}
