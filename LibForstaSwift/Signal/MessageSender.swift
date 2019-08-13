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


class MessageSender {
    let signalClient: SignalClient
    let wsr: WebSocketResource
    
    init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
    }
    
    /// Transmit a Sendable (i.e., a message)
    func send(_ message: Sendable) -> Promise<(Int, JSON)> {
        return firstly { () -> Promise<(Int, JSON)> in
            var results: [Promise<(Int, JSON)>] = []
            var clearMessage = try message.contentProto.serializedData()
            pad(&clearMessage)
            
            for recipient in message.recipients {
                let specificAddress: SignalAddress
                switch recipient {
                case .device(let addr): specificAddress = addr
                case .user: continue
                }
                let cipher = SessionCipher(for: specificAddress, in: self.signalClient.store)
                let encryptedMessage = try cipher.encrypt(clearMessage)
                let remoteRegistrationId = try cipher.remoteRegistrationId()
                
                let bundle: [String: Any] = [
                    "type": Relay_Envelope.TypeEnum.ciphertext.rawValue,
                    "content": encryptedMessage.data.base64EncodedString(),
                    "destinationRegistrationId": remoteRegistrationId,
                    "destinationDeviceId": specificAddress.deviceId,
                    "timestamp": Date().millisecondsSince1970
                ]
                
                results.append(self.signalClient.deliverToDevice(address: specificAddress, parameters: bundle))
            }
            
            return results[0] // TODO: make this plural!
        }
    }
    
    /// Internal: Pad outgoing plaintext before encryption
    private func pad(_ plaintext: inout Data, partSize: Int = 160, terminator: UInt8 = 0x80) {
        var thePad = Data(count: partSize + 1 - ((plaintext.count + 1) % partSize))
        thePad[0] = terminator
        plaintext.append(thePad)
    }
}
