//
//  Forsta.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 8/22/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import SwiftyJSON
import SignalProtocol

/// A top-level helper class for using LibForstaSwift
public class Forsta {
    /// An Atlas client for all Forsta Atlas server operations.
    /// This will restore from the kvstore and continue using an authenticated session if possible.
    public let atlas: AtlasClient
    
    /// A Signal client for all Forsta Signal server operations.
    /// This uses the kvstore to maintain cryptographic messaging keys and sessions, and remote account/device identities.
    public let signal: SignalClient
    
    private let wsr: WebSocketResource
    private let receiver: MessageReceiver
    private let sender: MessageSender
    
    /// Initialize with a `KVStorageProtocol`
    public init(_ kvstore: KVStorageProtocol) throws {
        self.atlas = AtlasClient(kvstore: kvstore)
        self.signal = try SignalClient(atlasClient: atlas)
        self.wsr = WebSocketResource(signalClient: signal)
        self.receiver = MessageReceiver(signalClient: signal, webSocketResource: wsr)
        self.sender = MessageSender(signalClient: signal)
    }
    
    // MARK:- Pass-throughs for everything not in the Atlas and Signal clients
    
    /// Connect the Signal Server web socket.
    public func connect() {
        self.wsr.connect()
    }
    
    /// Disconnect the Signal Server web socket.
    public func disconnect() {
        self.wsr.disconnect()
    }

    /// Send to recipient(s) device(s).
    public func send(_ sendable: Sendable, to recipients: [MessageRecipient]) -> Promise<[MessageSender.TransmissionInfo]> {
        return self.sender.send(sendable, to: recipients)
    }
}
