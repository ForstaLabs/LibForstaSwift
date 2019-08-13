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
            seal.reject(LibForstaError.requestRejected(why: JSON(dict)))
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
        guard signalClient.serverUrl != nil, signalClient.signalServerUsername != nil, signalClient.password != nil else {
            print("CANNOT CONNECT!")
            return
        }
        let url = "\(signalClient.serverUrl!)/v1/websocket/?login=\(signalClient.signalServerUsername!)&password=\(signalClient.password!)"
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
            if x.hasRequest {
                self.requestHandler(IncomingWSRequest(wsr: self, verb: x.request.verb, path: x.request.path, body: x.request.hasBody ? x.request.body : nil))
            } else if x.hasResponse {
                let id = x.response.hasID ? x.response.id : 0
                let body: Data? = x.response.hasBody ? x.response.body : nil
                let message = x.response.hasMessage ? x.response.message : ""
                let status = x.response.hasStatus ? x.response.status : 500
                
                print("got a ws response! (\(status), \(message))")
                
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
                throw LibForstaError.internalError(why: "Unrecognized incoming WebSocket request type.")
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
                return seal.reject(LibForstaError.internalError(why: "Message not properly initialized."))
            }
            if socket == nil || !socket!.isConnected { return seal.reject(LibForstaError.internalError(why: "No connected websocket.")) }
            self.socket!.write(data: data, completion: { seal.fulfill(()) })
        }
    }
    
    func disconnect() {
        self.socket?.disconnect()
        self.socket = nil
    }
}
