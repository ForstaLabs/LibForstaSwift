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
            var inboundMessage: InboundMessage? = nil
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .relayMessage,
                object: nil,
                queue: nil) { notification in
                    inboundMessage = notification.userInfo?["inboundMessage"] as! InboundMessage
                    print("RECEIVED", inboundMessage)
                    connectAndReceive.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(dataMessageObserver) }
            let wsr = WebSocketResource(signalClient: signalClient)
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect()
            wait(for: [connectAndReceive], timeout: 2 * 60.0)
            let thenSend = XCTestExpectation()
            
            let userId = atlasClient.kvstore.get(DNK.ssAddress) as UUID?
            let deviceId = atlasClient.kvstore.get(DNK.ssDeviceId) as UInt32?
            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            let response = Message(senderUserId: userId ?? UUID(),
                                   senderDeviceId: deviceId ?? 0,
                                   distributionExpression: "", // message.body![0]["distribution"]["expression"].stringValue,
                                   data: TextMessageData(plain: "Hello, world!")
            )

            signalClient.getKeysForAddr(inboundMessage!.source)
                .done { result in
                    print("GET KEYS FOR PARTICULAR DEVICE", result)
                }
                .catch { error in
                    print("ERROR", error)
            }
            
            signalClient.getKeysForAddr(addr: inboundMessage!.source.name)
                .done { result in
                    print("GET KEYS FOR ALL DEVICES", result)
                }
                .catch { error in
                    print("ERROR", error)
            }
            
            
            response.recipients.append(.device(address: inboundMessage!.source))
            sender.send(response)
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
            
            let connectified = XCTestExpectation()
            var incomingMessage: Relay_DataMessage? = nil
            var incomingEnvelope: Relay_Envelope? = nil
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .relayEmptyQueue,
                object: nil,
                queue: nil) { _ in
                    print("connection up and running")
                    connectified.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(dataMessageObserver) }
            let wsr = WebSocketResource(signalClient: signalClient)
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect()
            wait(for: [connectified], timeout: 2 * 60.0)
            print("proceeding with send")
            
            let theGoodPart = XCTestExpectation()
            
            let myUserId = atlasClient.kvstore.get(DNK.ssAddress) as UUID?
            let myDeviceId = atlasClient.kvstore.get(DNK.ssDeviceId) as UInt32?
            let message = Message(senderUserId: myUserId ?? UUID(),
                                  senderDeviceId: myDeviceId ?? 0,
                                  distributionExpression: "(<2b53e98b-170f-4102-9d82-e43d5abb7998>+<e98bf10d-528f-44c4-99cd-c488385771cc>)",
                                  data: TextMessageData(plain: "Hello, world!")
            )
            let theirUserId = "bd1f7e2d-55f5-4a3b-933d-ab7cf51503ca"
            let theirDeviceId = 1

            let receiptReceived = XCTestExpectation()
            let receiptObserver = NotificationCenter.default.addObserver(
                forName: .relayDeliveryReceipt,
                object: nil,
                queue: nil) { notification in
                    let receipt = notification.userInfo?["deliveryReceipt"] as! DeliveryReceipt
                    print(receipt)
                    receiptReceived.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(receiptObserver) }

            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            signalClient.getKeysForAddr(addr: theirUserId)
                .map { result in
                    print("GOT KEYS FOR ALL DEVICES", result)
                    for bundle in result {
                        let addr = SignalAddress(name: theirUserId, deviceId: bundle.deviceId)
                        try SessionBuilder(for: addr, in: signalClient.store).process(preKeyBundle: bundle)
                        message.recipients.append(.device(address: addr))
                    }
                    print("sending message", message.description)
                }
                .then {
                    sender.send(message)
                }
                .catch { error in
                    XCTFail("error \(error)")
                }
                .finally {
                    print("message sent!")
                    // theGoodPart.fulfill()
            }
            
            wait(for: [theGoodPart], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
}
