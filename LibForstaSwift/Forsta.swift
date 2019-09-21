//
//  Forsta.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 8/22/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit

/// This is THE top-level helper class for using LibForstaSwift.
public class Forsta {
    // -MARK: Attributes
    
    /// An Atlas client for Forsta Atlas server operations.
    /// This will restore from the kvstore and continue using an authenticated session if possible.
    public let atlas: AtlasClient
    
    /// A Signal client for Forsta Signal server operations.
    /// This uses the kvstore to maintain cryptographic messaging keys and sessions, and remote account/device identities.
    public let signal: SignalClient
    
    private let wsr: WebSocketResource
    private let receiver: MessageReceiver
    private let sender: MessageSender
    
    // -MARK: Constructors
    
    /// Initialize with a `KVStorageProtocol`
    public init(_ kvstore: KVStorageProtocol) throws {
        self.atlas = AtlasClient(kvstore: kvstore)
        self.signal = try SignalClient(atlasClient: atlas)
        self.wsr = WebSocketResource()
        self.receiver = MessageReceiver(signalClient: signal, webSocketResource: wsr)
        self.sender = MessageSender(signalClient: signal)
    }
    
    // -MARK: Pass-throughs for operations outside the Atlas and Signal clients
    
    /// Connect the Signal server web socket for messaging.
    public func connect() throws {
        self.wsr.connect(url: try self.signal.messagingSocketUrl())
    }
    
    /// Disconnect the Signal server web socket.
    public func disconnect() {
        self.wsr.disconnect()
    }

    /// Transmit a `Sendable` (i.e., a message) to a list of `MessageRecipient`
    /// (specific devices and/or users' whole collections of devices)
    ///
    /// - parameters:
    ///     - sendable: the `Sendable` message
    ///     - recipients: the list of recipients (optional) -- empty means only send sync to self
    ///     - syncToSelf: whether or not to send this message to our other devices (defaults to `true`)
    ///
    /// - returns: a `Promise<[MessageSender.TransmissionInfo]>` with information
    ///            about the transmission to each of the recipients
    ///
    /// Note: References to self (our specific `.device`, or all of our devices in the case of
    ///       our `.user`) are ignored in the list of recipients.
    ///
    public func send(_ sendable: Sendable,
                     to recipients: [MessageRecipient] = [],
                     syncToSelf: Bool = true) -> Promise<[MessageSender.TransmissionInfo]> {
        return self.sender.send(sendable, to: recipients, syncToSelf: syncToSelf)
    }
    
    ///
    /// Send a sync message of a list of `SyncReadReceipt` to our other devices to indicate specific messages having been read.
    ///
    /// - parameters:
    ///     - receipts: the list of read-receipts for messages from others
    ///
    /// - returns:a `Promise<MessageSender.TransmissionInfo>` indicating the success of the transmission
    ///
    public func sendSyncReadReceipts(_ receipts: [SyncReadReceipt]) -> Promise<MessageSender.TransmissionInfo> {
        return self.sender.sendSyncReadReceipts(receipts)
    }
}
