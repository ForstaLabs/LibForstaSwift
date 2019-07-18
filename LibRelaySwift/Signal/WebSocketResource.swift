//
//  WebSocketResource.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 6/11/19.
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
        print("handleContentMessage", envelope)
        
        // let session = SessionCipher(store: self.signalClient.store, remoteAddress: envelope.source)
        // let msg = try PreKeySignalMessage(from: envelope.content)

        // let bundle = SessionPreKeyBundle(msg)
        // let foo = try session.decrypt(envelope.content)
    }
    
    func handleLegacyMessage(_ envelope: Relay_Envelope) throws {
        print("handleLegacyMessage", envelope)
    }
}


typealias WSResponseHandler = (_ request: OutgoingWSRequest, _ status: UInt32, _ message: String, _ body: Data?) -> Void
typealias WSRequestHandler = (_ request: IncomingWSRequest) -> Void

class WSRequest {
    class Path {
        static let queueEmpty = "/api/v1/queue/empty"
        static let message = "/api/v1/message"
    }

    let wsr: WebSocketResource
    let id: UInt64
    let verb: String
    let path: String
    let body: Data?
    
    init(wsr: WebSocketResource, id: UInt64? = nil, verb: String, path: String, body: Data? = nil) {
        self.wsr = wsr
        self.id = id ?? UInt64.random(in: UInt64.min...UInt64.max)
        self.verb = verb
        self.path = path
        self.body = body
    }
}

class IncomingWSRequest: WSRequest {
    func respond(status: UInt32, message: String) -> Promise<Void> {
        var msg = Relay_WebSocketMessage()
        msg.type = .response
        msg.response.id = self.id
        msg.response.status = status
        msg.response.message = message
        
        return self.wsr.send(msg)
    }
}

class OutgoingWSRequest: WSRequest {
    var onSuccess: WSResponseHandler?
    var onError: WSResponseHandler?
    
    init(wsr: WebSocketResource, id: UInt64? = nil, verb: String, path: String, body: Data? = nil, onSuccess: WSResponseHandler? = nil, onError: WSResponseHandler? = nil) {
        self.onSuccess = onSuccess
        self.onError = onError
        super.init(wsr: wsr, id: id, verb: verb, path: path, body: body)
    }
    
    func send() -> Promise<JSON> {
        var msg = Relay_WebSocketMessage()
        msg.type = .request
        msg.request.id = self.id
        msg.request.verb = self.verb
        msg.request.path = self.path
        if self.body != nil { msg.request.body = self.body! }
        
        let (promise, seal) = Promise<JSON>.pending()
        
        self.onError = { request, status, message, data in
            var dict: [String: Any] = [ "status": status,
                                        "message": message ]
            if data != nil { dict["data"] = data! }
            seal.reject(LibRelayError.requestRejected(why: JSON(dict)))
        }
        
        self.onSuccess = { request, status, message, data in
            var dict: [String: Any] = [ "status": status,
                                        "message": message ]
            if data != nil { dict["data"] = data! }
            seal.fulfill(JSON(dict))
        }
        
        self.wsr.outgoingRequests[self.id] = self
        
        return self.wsr.send(msg).then { return promise }
    }
}

func fallbackRequestHandler(request: IncomingWSRequest) {
    print("sending fallback response of 404 Not found to request: \(request.verb) \(request.path)")
    let _ = request.respond(status: 404, message: "Not found")
}

class WebSocketResource: WebSocketDelegate {
    var socket: WebSocket?
    let signalClient: SignalClient
    var outgoingRequests = [UInt64 : OutgoingWSRequest]()
    var requestHandler: WSRequestHandler
    
    init(signalClient: SignalClient, requestHandler: WSRequestHandler? = nil) {
        self.signalClient = signalClient
        self.requestHandler = requestHandler != nil ? requestHandler! : fallbackRequestHandler
    }
    
    func connect() {
        guard signalClient.serverUrl != nil, signalClient.username != nil, signalClient.password != nil else {
            print("CANNOT CONNECT!")
            return
        }
        let url = "\(signalClient.serverUrl!)/v1/websocket/?login=\(signalClient.username!)&password=\(signalClient.password!)"
        print("CONNECTING to \(url)")
        socket = WebSocket(url: URL(string: url)!)
        socket!.delegate = self
        socket!.connect()
    }
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("Socket connected!")
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("Socket disconnected!")
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("Socket received message!")
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        do {
            let x = try Relay_WebSocketMessage(serializedData: data)
            print("Got a ws message!")
            if x.hasRequest {
                print("... it's a request!")
                self.requestHandler(IncomingWSRequest(wsr: self, verb: x.request.verb, path: x.request.path, body: x.request.hasBody ? x.request.body : nil))
            } else if x.hasResponse {
                let id = x.response.hasID ? x.response.id : 0
                let body: Data? = x.response.hasBody ? x.response.body : nil
                let message = x.response.hasMessage ? x.response.message : ""
                let status = x.response.hasStatus ? x.response.status : 500
                
                print("... it's a response! (\(status), \(message))")
                
                guard let request = outgoingRequests[id] else {
                    print("... but it has no matching request.")
                    return
                }
                outgoingRequests.removeValue(forKey: id)
                if let callback: WSResponseHandler = (status >= 200 && status < 300) ? request.onSuccess : request.onError {
                    print("... and there is a callback for status \(status).")
                    callback(request, status, message, body)
                }
            } else {
                throw LibRelayError.internalError(why: "Unrecognized incoming WebSocket request type.")
            }
        } catch let error {
            print("Error in websocketDidReceiveData:", error.localizedDescription)
        }
    }
    
    func send(_ message: Relay_WebSocketMessage) -> Promise<Void> {
        return Promise { seal in
            var data: Data
            do {
                data = try message.serializedData()
            } catch {
                return seal.reject(LibRelayError.internalError(why: "Message not properly initialized."))
            }
            if socket == nil || !socket!.isConnected { return seal.reject(LibRelayError.internalError(why: "No connected websocket.")) }
            self.socket!.write(data: data, completion: { seal.fulfill(()) })
        }
    }
    
    func disconnect() {
        self.socket?.disconnect()
        self.socket = nil
    }
}
