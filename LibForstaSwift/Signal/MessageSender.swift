//
//  MessageSender.swift
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


/// Manage sending messages
public class MessageSender {
    /// the `SignalClient` that is being used by this sender
    let signalClient: SignalClient

    /// init with a `SignalClient`
    public init(signalClient: SignalClient) {
        self.signalClient = signalClient
    }
    
    /// Information from the Signal server about a message transmission activity
    public class TransmissionInfo: CustomStringConvertible {
        /// time it was received
        public let received: Date
        /// whether it needs sync
        public let needsSync: Bool
        /// the recipient it was sent to
        public let recipient: MessageRecipient
        /// the number of devices involved (useful when the recipient was a `.user`)
        public let deviceCount: Int
        
        /// init with recipient, device count, and Signal server response JSON
        init(recipient: MessageRecipient, deviceCount: Int, json: JSON) {
            self.received = Date(millisecondsSince1970: json["received"].uInt64Value)
            self.needsSync = json["needsSync"].boolValue
            self.recipient = recipient
            self.deviceCount = deviceCount
        }
        
        /// human-readable rendering of the info
        public var description: String {
            return "<<\(self.recipient) [\(self.deviceCount)] @ \(self.received.millisecondsSince1970), \(self.needsSync ? "needs sync" : "no sync needed")>>"
        }
    }
    
    /// Transmit a `Sendable` (i.e., a message) to a list of `MessageRecipient`
    /// (specific devices and/or users' whole collections of devices)
    ///
    /// - parameters:
    ///     - sendable: the `Sendable` message
    ///     - recipients: the list of recipients (optional) -- empty means only send sync to self
    ///     - syncToSelf: whether or not to sync to our other devices (defaults to `true`)
    ///
    /// Note: References to self (our specific `.device`, or all of our devices in the case of
    ///       our `.user`) are ignored in the list of recipients.
    ///
    public func send(_ sendable: Sendable, to recipients: [MessageRecipient] = [], syncToSelf: Bool = true) -> Promise<[TransmissionInfo]> {
        return firstly { () -> Promise<[TransmissionInfo]> in
            try sendable.payload.sanityCheck()
            var results: [Promise<TransmissionInfo>] = []
            let contentProto = sendable.contentProto

            var paddedClearData = try contentProto.serializedData()
            pad(&paddedClearData)
            
            for recipient in recipients {
                switch recipient {
                case .device(let address):
                    if address != self.signalClient.signalAddress {
                        results.append(self.sendToDevice(address: address, paddedClearData: paddedClearData, timestamp: sendable.timestamp))
                    }
                case .user(let userId):
                    if userId != self.signalClient.signalAddress?.userId {
                        results.append(self.sendToUser(userId: userId, paddedClearData: paddedClearData, timestamp: sendable.timestamp))
                    }
                }
            }
            
            if syncToSelf {
                results.append(self.sendSync(signalContent: contentProto, timestamp: sendable.timestamp, threadId: sendable.payload.threadId))
            }
            
            return when(fulfilled: results)
        }
    }
    
    /// send sync message to our other devices for an outgoing message
    func sendSync(signalContent: Signal_Content,
                          timestamp: Date,
                          threadId: UUID? = nil,
                          expirationStartTimestamp: Date? = nil) -> Promise<MessageSender.TransmissionInfo> {
        let dataMessage = signalContent.dataMessage
        
        var sentMessage = Signal_SyncMessage.Sent()
        sentMessage.message = dataMessage
        sentMessage.timestamp = timestamp.millisecondsSince1970
        if threadId != nil {
            sentMessage.destination = threadId!.lcString
        }
        if expirationStartTimestamp != nil {
            sentMessage.expirationStartTimestamp = expirationStartTimestamp!.millisecondsSince1970
        }
        
        var syncMessage = Signal_SyncMessage()
        syncMessage.sent = sentMessage
        
        var content = Signal_Content()
        content.syncMessage = syncMessage
        
        guard let userId = self.signalClient.signalAddress?.userId else {
            return Promise<MessageSender.TransmissionInfo>.init(error: ForstaError(.configuration, "my own userId isn't available"))
        }
        
        do {
            var paddedClearData = try content.serializedData()
            pad(&paddedClearData)
            return self.sendToUser(userId: userId, paddedClearData: paddedClearData, timestamp: timestamp)
        } catch let error {
            return Promise<MessageSender.TransmissionInfo>.init(error: ForstaError("couldn't serialize content", cause: error))
        }
    }

    /// Fetch prekey bundle for address and process it
    func updatePrekeysForUser(_ userId: UUID) -> Promise<Void> {
        return self.updatePrekeysForUser(userId: userId.lcString)
    }
    
    
    /// Fetch prekey bundle for address and process it
    func updatePrekeysForUser(_ addr: SignalAddress) -> Promise<Void> {
        return self.updatePrekeysForUser(userId: addr.name, deviceId: UInt32(addr.deviceId))
    }
    
    /// Fetch prekey bundles for address (either all devices for the address, or only a specific device) and process them
    func updatePrekeysForUser(userId: String, deviceId: UInt32? = nil) -> Promise<Void> {
        guard let myUserIdString = self.signalClient.signalAddress?.userId.lcString,
            let myDeviceId = self.signalClient.signalAddress?.deviceId else {
            return Promise<Void>.init(error: ForstaError(.configuration, "own address isn't available"))
        }
        return self.signalClient.getKeysForAddr(addr: userId, deviceId: deviceId)
            .map { bundles in
                let devices = bundles.filter { !(userId == myUserIdString && $0.deviceId == myDeviceId) }
                for bundle in devices {
                    let addr = SignalAddress(name: userId, deviceId: bundle.deviceId)
                    try SessionBuilder(for: addr, in: self.signalClient.store).process(preKeyBundle: bundle)
                }
        }
    }
    
    /// Encrypt padded clear data, accepting changed identity keys
    /// Returns CiphertextMessage and remote registration id
    func encryptWithKeyChangeRecovery(address: SignalAddress, paddedClearData: Data) throws -> (CiphertextMessage, UInt32) {
        let cipher = SessionCipher(for: address, in: self.signalClient.store)
        var attempts = 0
        repeat {
            attempts += 1
            do {
                let encryptedMessage = try cipher.encrypt(paddedClearData)
                return (encryptedMessage, try cipher.remoteRegistrationId())
            } catch SignalError.untrustedIdentity {
                NotificationCenter.broadcast(.signalIdentityKeyChanged, ["address": address])
                let _ = self.signalClient.store.identityKeyStore.save(identity: nil, for: address)
            } catch let error {
                throw ForstaError("internal error", cause: error)
            }
        } while attempts < 2

        throw ForstaError(.untrustedIdentity, "untrusted identity key")
    }
    
    // Build a message transmission bundle
    func messageTransmissionBundle(deviceId: Int32,
                                   registrationId: UInt32,
                                   encryptedMessage: CiphertextMessage,
                                   timestamp: Date) -> [String: Any] {
        return [
            "type": encryptedMessage.type == .preKey
                ? Signal_Envelope.TypeEnum.prekeyBundle.rawValue
                : Signal_Envelope.TypeEnum.ciphertext.rawValue,
            "content": encryptedMessage.message.base64EncodedString(),
            "destinationRegistrationId": registrationId,
            "destinationDeviceId": deviceId,
            "timestamp": timestamp.millisecondsSince1970
        ]
    }
    
    /// Send a padded clear data to a specific device, fetching/updating keys as necessary
    func sendToDevice(address: SignalAddress, paddedClearData: Data, timestamp: Date, retry: Bool = true) -> Promise<TransmissionInfo> {
        return firstly
            { () -> Promise<Void> in
                if !self.signalClient.store.sessionStore.containsSession(for: address) {
                    return self.updatePrekeysForUser(address)
                } else {
                    return Promise<Void>.value(())
                }
            }
            .map {
                try self.encryptWithKeyChangeRecovery(address: address, paddedClearData: paddedClearData)
            }
            .map { (encryptedMessage, remoteRegistrationId) -> [String: Any] in
                self.messageTransmissionBundle(deviceId: address.deviceId,
                                               registrationId: remoteRegistrationId,
                                               encryptedMessage: encryptedMessage, timestamp: timestamp)
            }
            .then { bundle -> Promise<(Int, JSON)> in
                self.signalClient.deliverToDevice(address: address, messageBundle: bundle)
            }
            .then { (statusCode, json) -> Promise<TransmissionInfo> in
                if statusCode == 410 && retry {
                    let _ = self.signalClient.store.sessionStore.deleteSession(for: address) // force an updateKeys on retry
                    return self.sendToDevice(address: address, paddedClearData: paddedClearData, timestamp: timestamp, retry: false)
                } else if statusCode >= 300 {
                    throw ForstaError(.requestRejected, json)
                }
                return Promise<TransmissionInfo>.value(TransmissionInfo(recipient:.device(address), deviceCount: 1, json: json))
        }
    }
    
    func sendToUser(userId: UUID, paddedClearData: Data, timestamp: Date, allowRetries: Bool = true) -> Promise<TransmissionInfo> {
        let deviceIds = self.signalClient.store.sessionStore.subDeviceSessions(for: userId) ?? []
        var messageBundles: [[String: Any]]
        do {
            messageBundles = try deviceIds.map { id -> [String: Any] in
                let (encryptedMessage, registrationId) =
                    try encryptWithKeyChangeRecovery(address: SignalAddress(userId: userId, deviceId: id),
                                                     paddedClearData: paddedClearData)
                return self.messageTransmissionBundle(deviceId: id,
                                                      registrationId: registrationId,
                                                      encryptedMessage: encryptedMessage,
                                                      timestamp: timestamp)
            }
        } catch let error {
            return Promise<TransmissionInfo>(error: error)
        }
        return
            self.signalClient.deliverToUser(userId: userId, messageBundles: messageBundles)
            .then { (statusCode, json) -> Promise<TransmissionInfo> in
                if statusCode < 300 {
                    return Promise<TransmissionInfo>.value(TransmissionInfo(recipient:.user(userId), deviceCount: messageBundles.count, json: json))
                } else if statusCode == 410 || statusCode == 409 {
                    if (!allowRetries) {
                        throw ForstaError(.transmissionFailure, "Hit retry limit attempting to reload device list")
                    }
                    if (statusCode == 409) {
                        // remove device IDs for extra devices
                        for extra in json["extraDevices"].arrayValue {
                            let deviceId = extra.uInt32Value
                            let _ = self.signalClient.store.sessionStore.deleteSession(for: SignalAddress(userId: userId, deviceId: deviceId))
                            print("removed extra device \(deviceId)")
                        }
                    } else {
                        // close open sessions on stale devices
                        for extra in json["staleDevices"].arrayValue {
                            let deviceId = extra.uInt32Value
                            let _ = self.signalClient.store.sessionStore.deleteSession(for: SignalAddress(userId: userId, deviceId: deviceId))
                            print("removed stale device \(deviceId)")
                        }
                    }
                    
                    // no optimization for now -- just update all of the device keys for the user
                    print("updating prekeys for user \(userId)")
                    return self.updatePrekeysForUser(userId).then {
                        self.sendToUser(userId: userId, paddedClearData: paddedClearData, timestamp: timestamp, allowRetries: statusCode == 409)
                    }
                } else {
                    throw ForstaError(.requestRejected, json)
                }
        }
    }
    
    /// Internal: Pad outgoing plaintext before encryption
    private func pad(_ plaintext: inout Data, partSize: Int = 160, terminator: UInt8 = 0x80) {
        var thePad = Data(count: partSize + 1 - ((plaintext.count + 1) % partSize))
        thePad[0] = terminator
        plaintext.append(thePad)
    }
}
