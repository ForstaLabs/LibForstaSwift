//
//  MessageReceiver.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 8/5/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import SwiftyJSON
import Starscream
import SignalProtocol


class ReadSyncReceipt: CustomStringConvertible {
    let sender: UUID
    let timestamp: Date
    
    init(_ sender: UUID, _ timestamp: Date) {
        self.sender = sender
        self.timestamp = timestamp
    }
    var description: String {
        return "ReadSyncReceipt(\(self.sender) @ \(self.timestamp ))"
    }
}

class DeliveryReceipt: CustomStringConvertible {
    let address: SignalAddress
    let timestamp: Date
    
    init(_ address: SignalAddress, _ timestamp: Date) {
        self.address = address
        self.timestamp = timestamp
    }
    var description: String {
        return "DeliveryReceipt(\(self.address) @ \(self.timestamp ))"
    }
}

class InboundMessage: CustomStringConvertible {
    var source: SignalAddress
    var timestamp: Date
    var expiration: TimeInterval?
    var serverAge: TimeInterval
    var serverReceived: Date
    
    var body: JSON
    
    // specific to sync messages
    var expirationStart: Date?
    var destination: String?
    
    init(source: SignalAddress,
         timestamp: Date,
         expiration: TimeInterval? = nil,
         serverAge: TimeInterval,
         serverReceived: Date,
         body: JSON,
         expirationStart: Date? = nil,
         destination: String? = nil) {
        self.source = source
        self.timestamp = timestamp
        self.expiration = expiration
        self.serverAge = serverAge
        self.serverReceived = serverReceived
        self.body = body
        self.expirationStart = expirationStart
        self.destination = destination
    }
    
    var description: String {
        return """
        InboundMessage from \(source) @ \(timestamp) good for \(expiration ?? -1)
        \((body.rawString() ?? "<malformed body>").indentWith(">>> "))
        """
    }
}

class MessageReceiver {
    let signalClient: SignalClient
    let wsr: WebSocketResource
    
    init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
        self.wsr.requestHandler = self.handleRequest
    }
    
    /// Handle an incoming websocket request (/queue/empty or /message)
    private func handleRequest(request: IncomingWSRequest) {
        // print("Handling WS request \(request.verb) \(request.path)...")
        if request.path == WSRequest.Path.queueEmpty {
            NotificationCenter.broadcast(.signalEmptyQueue)
            let _ = request.respond(status: 200, message: "OK")
            return
        } else if request.path != WSRequest.Path.message || request.verb != "PUT" {
            print("Expected PUT /api/v1/message; got \(request.verb) \(request.path)")
            let _ = request.respond(status: 400, message: "Invalid Resource");
            return
        }
        do {
            let signalingKey = signalClient.kvstore.get(DNK.ssSignalingKey)
            guard request.body != nil else {
                throw LibForstaError.internalError(why: "No body for incoming request.")
            }
            guard signalingKey != nil else {
                throw LibForstaError.internalError(why: "No signaling key established.")
            }
            let data = try decryptWebSocketMessage(message: request.body!, signalingKey: signalingKey!)
            let envelope = try Relay_Envelope(serializedData: data)
            if envelope.type == .receipt {
                let receipt = DeliveryReceipt(SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                              Date(millisecondsSince1970: envelope.timestamp))
                NotificationCenter.broadcast(.signalDeliveryReceipt, ["deliveryReceipt": receipt])
            } else if envelope.hasContent {
                try handleContentMessage(envelope)
            } else if envelope.hasLegacyMessage {
                try handleLegacyMessage(envelope)
            } else {
                throw LibForstaError.internalError(why: "Received message with no content.")
            }
            let _ = request.respond(status: 200, message: "OK")
        } catch let error {
            print("Error handling incoming message", error.localizedDescription)
            let _ = request.respond(status: 500, message: "Bad encrypted websocket message")
        }
    }
    
    /// Internal: Handle a "Content" message, extracting incoming messages, sync messages, sync read-receipts
    private func handleContentMessage(_ envelope: Relay_Envelope) throws {
        let plainText = try self.decrypt(envelope, envelope.content);
        let content = try Relay_Content(serializedData: plainText)
        var sent: Relay_SyncMessage.Sent? = nil
        var dm: Relay_DataMessage? = nil
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
            var receipts = [ReadSyncReceipt]()
            for r in content.syncMessage.read {
                guard let sender: UUID = UUID(uuidString: r.sender) else {
                    throw LibForstaError.internalError(why: "Received sync message with malformed read receipt sender: \(r.sender).")
                }
                let timestamp: Date = Date(millisecondsSince1970: r.timestamp)
                receipts.append(ReadSyncReceipt(sender, timestamp))
            }
            happy = true
            NotificationCenter.broadcast(.signalReadSyncReceipts, ["readSyncReceipts": receipts])
        }
        
        if dm != nil {
            let msg = InboundMessage(source: SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                     timestamp: Date(millisecondsSince1970: envelope.timestamp),
                                     expiration: (dm?.hasExpireTimer ?? false)
                                        ? TimeInterval(milliseconds: dm!.expireTimer)
                                        : nil,
                                     serverAge: TimeInterval(milliseconds: envelope.age),
                                     serverReceived: Date(millisecondsSince1970: envelope.received),
                                     body: try JSON(string: dm?.body ?? "[]"),
                                     expirationStart: (sent?.hasExpirationStartTimestamp ?? false)
                                        ? Date(millisecondsSince1970: sent!.expirationStartTimestamp)
                                        : nil,
                                     destination: (sent?.hasDestination ?? false) ? sent!.destination : nil)
            happy = true
            NotificationCenter.broadcast(.signalInboundMessage, ["inboundMessage": msg])
        }
        
        if !happy {
            throw LibForstaError.internalError(why: "Received content message with no dataMessage or syncMessage.")
        }
    }
    
    private func handleLegacyMessage(_ envelope: Relay_Envelope) throws {
        throw LibForstaError.internalError(why: "Not implemented.")
    }
    
    /// Internal: Axolotl-decrypt an incoming envelope's content
    private func decrypt(_ envelope: Relay_Envelope, _ cyphertext: Data) throws -> Data {
        let addr = SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice)
        let sessionCipher = SessionCipher(for: addr, in: self.signalClient.store)
        let plainText: Data
        if envelope.type == .prekeyBundle {
            plainText = try sessionCipher.decrypt(preKeySignalMessage: cyphertext)
        } else if envelope.type == .ciphertext {
            plainText = try sessionCipher.decrypt(signalMessage: cyphertext)
        } else {
            throw LibForstaError.internalError(why: "Unknown buffer type: \(envelope.type)")
        }
        return try unpad(paddedPlaintext: plainText)
    }
    
    /// Internal: Unpad an incoming envelope's plaintext after decrypting
    private func unpad(paddedPlaintext: Data) throws -> Data {
        for idx in (0...paddedPlaintext.count-1).reversed() {
            if paddedPlaintext[idx] == 0x00 { continue }
            else if paddedPlaintext[idx] == 0x80 {
                return paddedPlaintext.prefix(upTo: idx)
            } else {
                throw LibForstaError.internalError(why: "Invalid padding.")
            }
        }
        throw LibForstaError.internalError(why: "Invalid buffer.")
    }
    
    private func verifyWSMessageMAC(data: Data, key: Data, expectedMAC: Data) throws {
        let calculatedMAC = signalClient.crypto.hmacSHA256(for: data, with: key)
        if calculatedMAC[..<expectedMAC.count] != expectedMAC {
            throw LibForstaError.internalError(why: "Bad MAC")
        }
    }
    
    private func decryptWebSocketMessage(message: Data, signalingKey: Data) throws -> Data {
        guard signalingKey.count == 52 else {
            throw LibForstaError.internalError(why: "Invalid signalKey length.")
        }
        guard message.count >= 1 + 16 + 10 else {
            throw LibForstaError.internalError(why: "Invalid message length.")
        }
        guard message[0] == 1 else {
            throw LibForstaError.internalError(why: "Invalid message version number \(message[0]).")
        }
        
        let aesKey = signalingKey[0...31]
        let macKey = signalingKey[32...32+19]
        let iv = message[1...16]
        let ciphertext = message[1+16...message.count-11]
        let ivAndCyphertext = message[0...message.count-11]
        let mac = message[(message.count-10)...]
        
        try verifyWSMessageMAC(data: ivAndCyphertext, key: macKey, expectedMAC: mac)
        return try signalClient.crypto.decrypt(message: ciphertext, with: .AES_CBCwithPKCS5, key: aesKey, iv: iv)
    }
}
