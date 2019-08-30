//
//  WebSocketResource.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 6/11/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import SwiftyJSON
import Starscream
import SignalProtocol


/// the type signature of a websocket response handler
public typealias WSResponseHandler = (_ request: OutgoingWSRequest, _ status: UInt32, _ message: String, _ body: Data?) -> Void
/// the type signature of a websocket request handler
public typealias WSRequestHandler = (_ request: IncomingWSRequest) -> Void

/// Base class for managing a websocket request
public class WSRequest {
    /// possible paths for endpoints on our Signal server
    public class Path {
        static let queueEmpty = "/api/v1/queue/empty"
        static let message = "/api/v1/message"
    }

    let wsr: WebSocketResource
    let id: UInt64
    let verb: String
    let path: String
    let body: Data?
    
    /// construct a websocket request for our Signal server
    public init(wsr: WebSocketResource, id: UInt64? = nil, verb: String, path: String, body: Data? = nil) {
        self.wsr = wsr
        self.id = id ?? UInt64.random(in: UInt64.min...UInt64.max)
        self.verb = verb
        self.path = path
        self.body = body
    }
}

/// an incoming websocket request
public class IncomingWSRequest: WSRequest {
    /// respond to this incoming request
    public func respond(status: UInt32, message: String) -> Promise<Void> {
        var msg = Signal_WebSocketMessage()
        msg.type = .response
        msg.response.id = self.id
        msg.response.status = status
        msg.response.message = message
        
        return self.wsr.send(msg)
    }
}

/// an outgoing websocket request
public class OutgoingWSRequest: WSRequest {
    /// optional onSuccess handler
    var onSuccess: WSResponseHandler?
    /// optional onError handler
    var onError: WSResponseHandler?
    
    /// construct an outgoing request
    public init(wsr: WebSocketResource, id: UInt64? = nil, verb: String, path: String, body: Data? = nil, onSuccess: WSResponseHandler? = nil, onError: WSResponseHandler? = nil) {
        self.onSuccess = onSuccess
        self.onError = onError
        super.init(wsr: wsr, id: id, verb: verb, path: path, body: body)
    }
    
    /// actually send the outgoing request
    func send() -> Promise<JSON> {
        var msg = Signal_WebSocketMessage()
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
            seal.reject(ForstaError(.requestRejected, JSON(dict)))
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

/// The fallback request handler we use if one is not provided (it immediately rejects all requests)
func fallbackRequestHandler(request: IncomingWSRequest) {
    print("sending fallback response of 404 Not found to request: \(request.verb) \(request.path)")
    let _ = request.respond(status: 404, message: "Not found")
}

/// Manage a websocket, reporting dis/connection, routing incoming requests to handlers, and sending websocket requests on demand
public class WebSocketResource: WebSocketDelegate {
    var lastConnect: Date?
    var socket: WebSocket?
    let signalClient: SignalClient
    var outgoingRequests = [UInt64 : OutgoingWSRequest]()
    var requestHandler: WSRequestHandler
    
    /// init with a `SignalClient` and an optional requestHandler (falls back to our default that rejects all requests)
    public init(signalClient: SignalClient, requestHandler: WSRequestHandler? = nil) {
        self.signalClient = signalClient
        self.requestHandler = requestHandler != nil ? requestHandler! : fallbackRequestHandler
    }
    
    /// connect with our Atlas-designated Signal server using our pre-negotiated credentials
    public func connect() {
        lastConnect = Date()
        guard signalClient.serverUrl != nil, signalClient.signalServerUsername != nil, signalClient.password != nil else {
            print("CANNOT CONNECT (missing server url, username, or password)")
            return
        }
        let url = "\(signalClient.serverUrl!)/v1/websocket/?login=\(signalClient.signalServerUsername!)&password=\(signalClient.password!)"
        socket = WebSocket(url: URL(string: url)!)
        socket!.delegate = self
        socket!.connect()
    }
    
    /// broadcast notification of connecting
    public func websocketDidConnect(socket: WebSocketClient) {
        NotificationCenter.broadcast(.signalConnected)
    }
    
    /// broadcast notification of a disconnect
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        NotificationCenter.broadcast(.signalDisconnected, error != nil ? ["error": error!] : nil)
        if lastConnect != nil {
            connect() // just immediately reconnect until we purposefully disconnect
        }
    }
    
    /// absorb receiving a text message
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("Socket received message: \(text)")
    }
    
    /// handle incoming data (responses to outgoing requests, routing to a requestHandler on incoming requests)
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        do {
            let x = try Signal_WebSocketMessage(serializedData: data)
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
                throw ForstaError(.invalidType, "Unrecognized incoming WebSocket request type.")
            }
        } catch let error {
            print("Error in websocketDidReceiveData:", error.localizedDescription)
        }
    }
    
    /// send a `Signal_WebSocketMessage` out
    func send(_ message: Signal_WebSocketMessage) -> Promise<Void> {
        return Promise { seal in
            var data: Data
            do {
                data = try message.serializedData()
            } catch {
                return seal.reject(ForstaError(.invalidMessage, "WS message not properly initialized."))
            }
            if socket == nil || !socket!.isConnected { return seal.reject(ForstaError(.configuration, "No connected websocket.")) }
            self.socket!.write(data: data, completion: { seal.fulfill(()) })
        }
    }
    
    /// disconnect the socket and free its resources
    public func disconnect() {
        self.lastConnect = nil
        self.socket?.disconnect()
        self.socket = nil
    }
}
