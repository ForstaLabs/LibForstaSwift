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
        InboundMessage from \(source) @ \(timestamp) for \(expiration ?? -1)
        \(body.rawString() ?? "<malformed body>")
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
    
    func handleRequest(request: IncomingWSRequest) {
        print("Handling request \(request.verb) \(request.path)...")
        if request.path == WSRequest.Path.queueEmpty {
            print("Websocket queue empty")
            NotificationCenter.broadcast(.relayEmptyQueue)
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
                throw LibRelayError.internalError(why: "No body for incoming request.")
            }
            guard signalingKey != nil else {
                throw LibRelayError.internalError(why: "No signaling key established.")
            }
            let data = try signalClient.decryptWebSocketMessage(message: request.body!, signalingKey: signalingKey!)
            let envelope = try Relay_Envelope(serializedData: data)
            handleEnvelope(envelope)
            let _ = request.respond(status: 200, message: "OK")
        } catch let error {
            print("Error handling incoming message", error.localizedDescription)
            let _ = request.respond(status: 500, message: "Bad encrypted websocket message")
        }
    }
    
    func handleEnvelope(_ envelope: Relay_Envelope) {
        print("got envelope! \(envelope.type)")
        do {
            if envelope.type == .receipt {
                let receipt = DeliveryReceipt(SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                              Date(millisecondsSince1970: envelope.timestamp))
                NotificationCenter.broadcast(.relayDeliveryReceipt, ["deliveryReceipt": receipt])
            } else if envelope.hasContent {
                try handleContentMessage(envelope)
            } else if envelope.hasLegacyMessage {
                try handleLegacyMessage(envelope)
            } else {
                throw LibRelayError.internalError(why: "Received message with no content.")
            }
        } catch let error {
            print("error in handleEnvelope!", error)
        }
    }
    
    func handleContentMessage(_ envelope: Relay_Envelope) throws {
        let plainText = try self.decrypt(envelope, envelope.content);
        let content = try Relay_Content(serializedData: plainText)
        var sent: Relay_SyncMessage.Sent? = nil
        var dm: Relay_DataMessage? = nil
        if content.hasSyncMessage && content.syncMessage.hasSent {
            sent = content.syncMessage.sent
            dm = sent!.message
        } else if content.hasDataMessage {
            dm = content.dataMessage
        } else if content.hasSyncMessage && content.syncMessage.read.count > 0 {
            var receipts = [ReadSyncReceipt]()
            for r in content.syncMessage.read {
                guard let sender: UUID = UUID(uuidString: r.sender) else {
                    throw LibRelayError.internalError(why: "Received sync message with malformed read receipt sender: \(r.sender).")
                }
                let timestamp: Date = Date(millisecondsSince1970: r.timestamp)
                receipts.append(ReadSyncReceipt(sender, timestamp))
            }
            NotificationCenter.broadcast(.relayReadSyncReceipts, ["readSyncReceipts": receipts])
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
            NotificationCenter.broadcast(.relayMessage, ["inboundMessage": msg])
        } else {
            throw LibRelayError.internalError(why: "Received content message with no dataMessage or syncMessage.")
        }
    }
    
    func handleLegacyMessage(_ envelope: Relay_Envelope) throws {
        throw LibRelayError.internalError(why: "Not implemented.")
    }
    
    func decrypt(_ envelope: Relay_Envelope, _ cyphertext: Data) throws -> Data {
        print(envelope.type)
        let addr = SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice)
        let sessionCipher = SessionCipher(for: addr, in: self.signalClient.store)
        let plainText: Data
        if envelope.type == .prekeyBundle {
            plainText = try sessionCipher.decrypt(preKeySignalMessage: cyphertext)
        } else if envelope.type == .ciphertext {
            plainText = try sessionCipher.decrypt(signalMessage: cyphertext)
        } else {
            throw LibRelayError.internalError(why: "Unknown buffer type: \(envelope.type)")
        }
        return try unpad(paddedPlaintext: plainText)
    }
    
    func unpad(paddedPlaintext: Data) throws -> Data {
        for idx in (0...paddedPlaintext.count-1).reversed() {
            if paddedPlaintext[idx] == 0x00 { continue }
            else if paddedPlaintext[idx] == 0x80 {
                return paddedPlaintext.prefix(upTo: idx)
            } else {
                throw LibRelayError.internalError(why: "Invalid padding.")
            }
        }
        throw LibRelayError.internalError(why: "Invalid buffer.")
    }
}
