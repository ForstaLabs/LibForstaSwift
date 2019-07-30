//
//  SignalClientTests.swift
//  LibRelaySwiftTests
//
//  Created by Greg Perkins on 5/22/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import XCTest
import PromiseKit
import SwiftyJSON
// import SwiftOTP

@testable import LibRelaySwift
import SignalProtocol

class SignalClientTests: XCTestCase {
    
    func testRegisterAndConnect() {
        do {
            let atlasClient = AtlasClient(kvstore: MemoryKVStore())
            let signalClient = try SignalClient(atlasClient: atlasClient)
            
            let registrated = XCTestExpectation(description: "registerAccount test")
            atlasClient.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    signalClient.registerAccount(name: "testing")
                }
                .done { result in
                    print(result)
                }
                .catch { error in
                    if let lre = error as? LibRelayError {
                        XCTFail(lre.rejectedBecause.rawString()!)
                    } else {
                        XCTFail("surprising error")
                    }
                }
                .finally {
                    registrated.fulfill()
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectified = XCTestExpectation()
            let wsr = WebSocketResource(signalClient: signalClient, requestHandler: { request in
                print("sending response of 404 Not found to request: \(request.verb) \(request.path)")
                let _ = request.respond(status: 404, message: "Not found")
                connectified.fulfill()
            })
            wsr.connect()
            wait(for: [connectified], timeout: 60.0)
            wsr.disconnect()
        } catch {
            XCTFail("surprising error")
        }
    }
    
    func testPreKeyReceiveAndResponse() {

        do {
            let atlasClient = AtlasClient(kvstore: MemoryKVStore())
            let signalClient = try SignalClient(atlasClient: atlasClient)
            
            let registrated = XCTestExpectation()
            atlasClient.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    signalClient.registerAccount(name: "testing")
                }
                .done { result in
                    print(result)
                }
                .catch { error in
                    if let lre = error as? LibRelayError {
                        XCTFail(lre.rejectedBecause.rawString()!)
                    } else {
                        XCTFail("surprising error")
                    }
                }
                .finally {
                    registrated.fulfill()
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectAndReceive = XCTestExpectation()
            var incomingMessage: Relay_DataMessage? = nil
            var incomingEnvelope: Relay_Envelope? = nil
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .relayDataMessage,
                object: nil,
                queue: nil) { notification in
                    incomingMessage = notification.userInfo?["dataMessage"] as! Relay_DataMessage
                    incomingEnvelope = notification.userInfo?["envelope"] as! Relay_Envelope
                    print("RECEIVED", incomingMessage!.body)
                    connectAndReceive.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(dataMessageObserver) }
            let wsr = WebSocketResource(signalClient: signalClient)
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect()
            wait(for: [connectAndReceive], timeout: 2 * 60.0)
            let thenSend = XCTestExpectation()
            
            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            let message = Message()
            let bodyStr = incomingMessage!.body
            message.body = try JSON(string:bodyStr)
            let userId = atlasClient.kvstore.get(DNK.ssAddress) as String?
            let deviceId = atlasClient.kvstore.get(DNK.ssDeviceId) as UInt32?
            message.body![0]["sender"] = JSON(["userId": userId ?? "wut", "device": deviceId ?? 42])
            message.body![0]["data"] = JSON(["body": ["type": "text/plain", "value": "How 'bout them apples?"]])
            message.body![0]["messageId"] = JSON(UUID())
            
            signalClient.getKeysForAddr(addr: incomingEnvelope!.source, deviceId: incomingEnvelope!.sourceDevice)
                .done { result in
                    print("GET KEYS FOR PARTICULAR DEVICE", result)
                }
                .catch { error in
                    print("ERROR", error)
            }
            
            signalClient.getKeysForAddr(addr: incomingEnvelope!.source)
                .done { result in
                    print("GET KEYS FOR ALL DEVICES", result)
                }
                .catch { error in
                    print("ERROR", error)
            }
            
            
            message.recipients.append(SignalAddress(userId: incomingEnvelope!.source, deviceId: incomingEnvelope!.sourceDevice))
            try sender.send(message)
                .done { result in
                    print("SEND COMPLETE", result)
                }
                .catch { error in
                    print("SEND ERROR", error)
                }
                .finally {
                    thenSend.fulfill()
            }
            wait(for: [thenSend], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testPreKeySend() {
        
        do {
            let atlasClient = AtlasClient(kvstore: MemoryKVStore())
            let signalClient = try SignalClient(atlasClient: atlasClient)
            
            let registrated = XCTestExpectation()
            atlasClient.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    signalClient.registerAccount(name: "testing")
                }
                .done { result in
                    print(result)
                }
                .catch { error in
                    if let lre = error as? LibRelayError {
                        XCTFail(lre.rejectedBecause.rawString()!)
                    } else {
                        XCTFail("surprising error")
                    }
                }
                .finally {
                    registrated.fulfill()
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectAndReceive = XCTestExpectation()
            var incomingMessage: Relay_DataMessage? = nil
            var incomingEnvelope: Relay_Envelope? = nil
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .relayDataMessage,
                object: nil,
                queue: nil) { notification in
                    incomingMessage = notification.userInfo?["dataMessage"] as! Relay_DataMessage
                    incomingEnvelope = notification.userInfo?["envelope"] as! Relay_Envelope
                    print("RECEIVED", incomingMessage!.body)
                    connectAndReceive.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(dataMessageObserver) }
            let wsr = WebSocketResource(signalClient: signalClient)
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect()
            // wait(for: [connectAndReceive], timeout: 2 * 60.0)
            
            let theGoodPart = XCTestExpectation()
            
            let myUserId = atlasClient.kvstore.get(DNK.ssAddress) as String?
            let myDeviceId = atlasClient.kvstore.get(DNK.ssDeviceId) as UInt32?
            let message = Message()
            let theirUserId = "bd1f7e2d-55f5-4a3b-933d-ab7cf51503ca"
            let theirDeviceId = 1
            message.recipients.append(SignalAddress(userId: theirUserId, deviceId: UInt32(theirDeviceId)))
            message.body = try JSON(string:#"""
[
  {
    "version": 1,
    "threadType": "conversation",
    "messageType": "content",
    "messageId": "\#(UUID().uuidString.lowercased())",
    "threadId": "be5b66ee-f6f4-45e2-9f5f-bdae9ee9c7a8",
    "userAgent": "LibRelaySwift",
    "data": {
      "body": [
        {
          "type": "text/plain",
          "value": "Foo the bar!"
        }
      ]
    },
    "sender": {
      "userId": "\#(myUserId ?? "wut")",
      "device": \#(myDeviceId ?? 42)
    },
    "distribution": {
      "expression": "(<2b53e98b-170f-4102-9d82-e43d5abb7998>+<e98bf10d-528f-44c4-99cd-c488385771cc>)"
    }
  }
]
"""#)
            print("here is the body json:", message.body!)

            signalClient.getKeysForAddr(addr: theirUserId)
                .done { result in
                    print("GET KEYS FOR ALL DEVICES", result)
                }
                .catch { error in
                    print("ERROR", error)
                }
                .finally {
                    XCTFail("stop here")
                    theGoodPart.fulfill()
            }
            
                    // do something with the result

            /*
            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            try sender.send(message)
                .done { result in
                    print("SEND COMPLETE", result)
                }
                .catch { error in
                    print("SEND ERROR", error)
                }
                .finally {
                    thenSend.fulfill()
            }
            */
            wait(for: [theGoodPart], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
}
