//
//  MessageSender.swift
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


class MessageSender {
    let signalClient: SignalClient
    let wsr: WebSocketResource
    
    init(signalClient: SignalClient, webSocketResource: WebSocketResource? = nil) {
        self.signalClient = signalClient
        self.wsr = webSocketResource ?? WebSocketResource(signalClient: signalClient)
    }
    
    func send(_ message: Message) throws -> Promise<(Int, JSON)> {
        var results: [Promise<(Int, JSON)>] = []
        var clearMessage = try message.toProto().serializedData()
        pad(&clearMessage)
        
        for recipient in message.recipients {
            let cipher = SessionCipher(for: recipient, in: self.signalClient.store)
            let encryptedMessage = try cipher.encrypt(clearMessage)
            let remoteRegistrationId = try cipher.remoteRegistrationId()
            
            let bundle: [String: Any] = [
                "type": Relay_Envelope.TypeEnum.ciphertext.rawValue,
                "content": encryptedMessage.data.base64EncodedString(),
                "destinationRegistrationId": remoteRegistrationId,
                "destinationDeviceId": recipient.deviceId,
                "timestamp": Date().millisecondsSince1970
            ]
            
            results.append(self.signalClient.deliverToDevice(address: recipient, parameters: bundle))
        }
        
        return results[0] // TODO: make this plural!
    }
    
    func pad(_ plaintext: inout Data, partSize: Int = 160, terminator: UInt8 = 0x80) {
        var muhPad = Data(count: partSize + 1 - ((plaintext.count + 1) % partSize))
        muhPad[0] = terminator
        plaintext.append(muhPad)
    }
}
