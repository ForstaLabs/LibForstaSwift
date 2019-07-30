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
                NotificationCenter.broadcast(.relayDeliveryReceipt, ["envelope": envelope])
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
        if content.hasSyncMessage {
            print("notifying of sync contentMessage")
            NotificationCenter.broadcast(.relaySyncMessage, ["envelope": envelope, "syncMessage": content.syncMessage])
        } else if content.hasDataMessage {
            print("notifying of data contentMessage")
            NotificationCenter.broadcast(.relayDataMessage, ["envelope": envelope, "dataMessage": content.dataMessage])
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
