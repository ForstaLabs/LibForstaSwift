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


public class MessageSender {
    let signalClient: SignalClient
    let wsr: WebSocketResource
    
    init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
    }
    
    /// Transmit a Sendable (i.e., a message)
    public func send(_ message: Sendable) -> Promise<JSON> {
        return firstly { () -> Promise<JSON> in
            var results: [Promise<JSON>] = []
            var messageData = try message.contentProto.serializedData()
            pad(&messageData)
            
            for recipient in message.recipients {
                switch recipient {
                case .device(let address): results.append(self.sendToDevice(address: address, paddedClearMessage: messageData))
                case .user: continue
                }
            }
            
            return results[0] // TODO: make this plural!
        }
    }
    
    /// Fetch prekey bundle for address and process it
    func updateKeysForAddr(_ addr: SignalAddress) -> Promise<Void> {
        return self.updateKeysForAddr(addr: addr.name, deviceId: UInt32(addr.deviceId))
    }
    
    /// Fetch prekey bundles for address (either all devices for the address, or only a specific device) and process them
    func updateKeysForAddr(addr: String, deviceId: UInt32? = nil) -> Promise<Void> {
        return self.signalClient.getKeysForAddr(addr: addr, deviceId: deviceId)
            .map { bundles in
                for bundle in bundles {
                    let addr = SignalAddress(name: addr, deviceId: bundle.deviceId)
                    try SessionBuilder(for: addr, in: self.signalClient.store).process(preKeyBundle: bundle)
                }
        }
    }
    
    /// Encrypt padded clear message, accepting changed identity keys
    /// Returns CiphertextMessage and remote registration id
    func encryptWithKeyChangeRecovery(address: SignalAddress, paddedClearMessage: Data) -> Promise<(CiphertextMessage, UInt32)> {
        let cipher = SessionCipher(for: address, in: self.signalClient.store)
        var attempts = 0
        repeat {
            attempts += 1
            do {
                let encryptedMessage = try cipher.encrypt(paddedClearMessage)
                return Promise.value((encryptedMessage, try cipher.remoteRegistrationId()))
            } catch SignalError.untrustedIdentity {
                NotificationCenter.broadcast(.signalIdentityKeyChanged, ["address": address])
                let _ = self.signalClient.store.identityKeyStore.save(identity: nil, for: address)
            } catch let error {
                return Promise.init(error: error)
            }
        } while attempts < 2
        
        return Promise.init(error: SignalError.untrustedIdentity)
    }
    
    /// Send a padded clear message to a specific device, fetching/updating keys as necessary
    func sendToDevice(address: SignalAddress, paddedClearMessage: Data, retry: Bool = true) -> Promise<JSON> {
        return firstly
            { () -> Promise<Void> in
                if !self.signalClient.store.sessionStore.containsSession(for: address) {
                    return self.updateKeysForAddr(address)
                } else {
                    return Promise<Void>.value(())
                }
            }
            .then {
                self.encryptWithKeyChangeRecovery(address: address, paddedClearMessage: paddedClearMessage)
            }
            .map { (encryptedMessage, remoteRegistrationId) -> [String: Any] in
                [
                    "type": Signal_Envelope.TypeEnum.ciphertext.rawValue,
                    "content": encryptedMessage.data.base64EncodedString(),
                    "destinationRegistrationId": remoteRegistrationId,
                    "destinationDeviceId": address.deviceId,
                    "timestamp": Date().millisecondsSince1970
                ]
            }
            .then { bundle -> Promise<(Int, JSON)> in
                self.signalClient.deliverToDevice(address: address, parameters: bundle)
            }
            .then { result -> Promise<JSON> in
                let (statusCode, json) = result
                if statusCode == 410 && retry {
                    let _ = self.signalClient.store.sessionStore.deleteSession(for: address) // force an updateKeys on retry
                    return self.sendToDevice(address: address, paddedClearMessage: paddedClearMessage, retry: false)
                } else if statusCode >= 300 {
                    throw ForstaError(.requestRejected, json)
                }
                return Promise<JSON>.value(json)
        }
    }
    
    func sendToUser(userId: UUID, paddedClearMessage: Data) -> Promise<(Int, JSON)> {
        return Promise.value((42, JSON(42)))
    }
    
    let x = """
        async _sendToDevice(addr, deviceId, recurse) {
            const protoAddr = new libsignal.ProtocolAddress(addr, deviceId);
            const sessionCipher = new libsignal.SessionCipher(ns.store, protoAddr);
            if (!(await sessionCipher.hasOpenSession())) {
                await this.getKeysForAddr(addr, [deviceId]);
            }
            let encryptedMessage;
            let attempts = 0;
            do {
                try {
                    encryptedMessage = await sessionCipher.encrypt(this.getPaddedMessageBuffer());
                } catch(e) {
                    if (e instanceof libsignal.UntrustedIdentityKeyError) {
                        await this._handleIdentityKeyError(e, {forceThrow: !!attempts});
                    } else {
                        this._emitError(addr, "Failed to create message", e);
                        return;
                    }
                }
            } while(!encryptedMessage && !attempts++);
            const messageBundle = this.toJSON(protoAddr, encryptedMessage, this.timestamp);
            let resp;
            try {
                resp = await this.signal.sendMessage(addr, deviceId, messageBundle);
            } catch(e) {
                if (e instanceof ns.ProtocolError && e.code === 410) {
                    sessionCipher.closeOpenSession();  // Force getKeysForAddr on next call.
                    return await this._sendToDevice(addr, deviceId, /*recurse*/ false);
                } else if (e.code === 401 || e.code === 403) {
                    throw e;
                } else {
                    this._emitError(addr, "Failed to send message", e);
                    return;
                }
            }
            this._emitSent(addr, resp.received);
            return resp;
        }
"""

    /// Internal: Pad outgoing plaintext before encryption
    private func pad(_ plaintext: inout Data, partSize: Int = 160, terminator: UInt8 = 0x80) {
        var thePad = Data(count: partSize + 1 - ((plaintext.count + 1) % partSize))
        thePad[0] = terminator
        plaintext.append(thePad)
    }
}
