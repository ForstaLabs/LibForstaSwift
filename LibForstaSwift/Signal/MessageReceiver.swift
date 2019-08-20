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


public class ReadSyncReceipt: CustomStringConvertible {
    let sender: UUID
    let timestamp: Date
    
    init(_ sender: UUID, _ timestamp: Date) {
        self.sender = sender
        self.timestamp = timestamp
    }
    public var description: String {
        return "ReadSyncReceipt(\(self.sender) @ \(self.timestamp.millisecondsSince1970 ))"
    }
}

public class DeliveryReceipt: CustomStringConvertible {
    let address: SignalAddress
    let timestamp: Date
    
    init(_ address: SignalAddress, _ timestamp: Date) {
        self.address = address
        self.timestamp = timestamp
    }
    public var description: String {
        return "DeliveryReceipt(\(self.address) @ \(self.timestamp.millisecondsSince1970 ))"
    }
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
            json = try JSON(string: string ?? "[]")
        } catch {
            json = JSON([])
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
                json["sender"]["userId"].string = value!.userId.lcString
                json["sender"]["device"].int32 = value!.deviceId
            }
        }
    }
    
    /*
     getMessageType
     getThreadExpression
     getThreadId
     getThreadTitle
     getThreadType
     getTimestamp
     getUserAgent
     */
}

public class InboundMessage: CustomStringConvertible {
    var source: SignalAddress
    var timestamp: Date
    var expiration: TimeInterval?
    var serverAge: TimeInterval
    var serverReceived: Date
    var endSessionFlag: Bool
    var expirationTimerUpdateFlag: Bool
    
    var body: String
    var payload: ForstaPayloadV1
    
    // specific to sync messages
    var expirationStart: Date?
    var destination: String?
    
    init(source: SignalAddress,
         timestamp: Date,
         expiration: TimeInterval? = nil,
         serverAge: TimeInterval,
         serverReceived: Date,
         endSessionFlag: Bool = false,
         expirationTimerUpdateFlag: Bool = false,
         body: String,
         expirationStart: Date? = nil,
         destination: String? = nil) {
        self.source = source
        self.timestamp = timestamp
        self.expiration = expiration
        self.serverAge = serverAge
        self.serverReceived = serverReceived
        self.endSessionFlag = endSessionFlag
        self.expirationTimerUpdateFlag = expirationTimerUpdateFlag
        self.body = body
        self.payload = ForstaPayloadV1(body)
        self.expirationStart = expirationStart
        self.destination = destination
    }
    

    public var description: String {
        return """
        InboundMessage from \(source) @ \(timestamp.millisecondsSince1970) good for \(expiration ?? -1)
        \((payload.jsonString).indentWith(">>> "))
        """
    }
}

public class MessageReceiver {
    let signalClient: SignalClient
    let wsr: WebSocketResource
    
    init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
        self.wsr.requestHandler = self.handleRequest
    }
    
    /// Handle an incoming websocket request (/queue/empty or /message)
    private func handleRequest(request: IncomingWSRequest) {
        print("Handling WS request \(request.verb) \(request.path)...")
        if request.path == WSRequest.Path.queueEmpty {
            NotificationCenter.broadcast(.signalQueueEmpty)
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
                throw ForstaError(.invalidMessage, "No body for incoming WS request.")
            }
            guard signalingKey != nil else {
                throw ForstaError(.decryptionError, "No signaling key established.")
            }
            let data = try decryptWebSocketMessage(message: request.body!, signalingKey: signalingKey!)
            let envelope = try Signal_Envelope(serializedData: data)
            if envelope.type == .receipt {
                let receipt = DeliveryReceipt(SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                              Date(millisecondsSince1970: envelope.timestamp))
                NotificationCenter.broadcast(.signalDeliveryReceipt, ["deliveryReceipt": receipt])
            } else if envelope.hasContent {
                try handleContentMessage(envelope)
            } else if envelope.hasLegacyMessage {
                throw ForstaError(.legacyMessage, "Legacy signal messages not supported.")
            } else {
                throw ForstaError(.invalidMessage, "Received message with no content.")
            }
            let _ = request.respond(status: 200, message: "OK")
        } catch let error {
            print("Error handling incoming message", error.localizedDescription)
            let _ = request.respond(status: 500, message: "Bad encrypted websocket message")
        }
    }
    
    /// Internal: Handle a "Content" message, extracting incoming messages, sync messages, sync read-receipts
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
            var receipts = [ReadSyncReceipt]()
            for r in content.syncMessage.read {
                guard let sender: UUID = UUID(uuidString: r.sender) else {
                    throw ForstaError(.invalidMessage, "Synced read-receipt has malformed sender: \(r.sender)")
                }
                let timestamp: Date = Date(millisecondsSince1970: r.timestamp)
                receipts.append(ReadSyncReceipt(sender, timestamp))
            }
            happy = true
            NotificationCenter.broadcast(.signalReadSyncReceipts, ["readSyncReceipts": receipts])
        }
        
        if dm != nil {
            let expirationTimerUpdateFlag = dm!.hasFlags && (dm!.flags & UInt32(Signal_DataMessage.Flags.expirationTimerUpdate.rawValue)) != 0
            let endSessionFlag = dm!.hasFlags && (dm!.flags & UInt32(Signal_DataMessage.Flags.endSession.rawValue)) != 0
            // let bodyJson =  try JSON(string: dm!.body ?? "[]")
            let msg = InboundMessage(source: SignalAddress(userId: envelope.source, deviceId: envelope.sourceDevice),
                                     timestamp: Date(millisecondsSince1970: envelope.timestamp),
                                     expiration: dm!.hasExpireTimer
                                        ? TimeInterval(milliseconds: dm!.expireTimer)
                                        : nil,
                                     serverAge: TimeInterval(milliseconds: envelope.age),
                                     serverReceived: Date(millisecondsSince1970: envelope.received),
                                     endSessionFlag: endSessionFlag,
                                     expirationTimerUpdateFlag: expirationTimerUpdateFlag,
                                     body: dm!.hasBody ? dm!.body : "",
                                     expirationStart: (sent?.hasExpirationStartTimestamp ?? false)
                                        ? Date(millisecondsSince1970: sent!.expirationStartTimestamp)
                                        : nil,
                                     destination: (sent?.hasDestination ?? false) ? sent!.destination : nil)
            happy = true
            NotificationCenter.broadcast(.signalInboundMessage, ["inboundMessage": msg])
        }
        
        if !happy {
            throw ForstaError(.invalidMessage, "Inbound content message has no dataMessage or syncMessage.")
        }
    }
    
    /// Internal: Axolotl-decrypt an incoming envelope's content
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
    
    private func verifyWSMessageMAC(data: Data, key: Data, expectedMAC: Data) throws {
        let calculatedMAC = signalClient.crypto.hmacSHA256(for: data, with: key)
        if calculatedMAC[..<expectedMAC.count] != expectedMAC {
            throw ForstaError(.invalidMac)
        }
    }
    
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
        
        try verifyWSMessageMAC(data: ivAndCyphertext, key: macKey, expectedMAC: mac)
        return try signalClient.crypto.decrypt(message: ciphertext, with: .AES_CBCwithPKCS5, key: aesKey, iv: iv)
    }
}
