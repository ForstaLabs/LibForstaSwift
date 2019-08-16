//
//  SignalClientTests.swift
//  LibForstaSwiftTests
//
//  Created by Greg Perkins on 5/22/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import XCTest
import PromiseKit
import SwiftyJSON
// import SwiftOTP

@testable import LibForstaSwift
import SignalProtocol


class Message: Sendable, CustomStringConvertible {
    public var recipients: [MessageRecipient]
    
    public var timestamp: Date
    public var senderUserId: UUID
    public var senderDeviceId: UInt32
    
    public var messageId: UUID
    public var messageType: FLIMessageType
    public var threadId: UUID
    public var distributionExpression: String
    
    public var expiration: TimeInterval?
    public var endSessionFlag: Bool
    public var expirationTimerUpdateFlag: Bool
    
    public var data: JSON?
    public var userAgent: String?
    public var threadTitle: String?
    public var threadType: FLIThreadType?
    public var messageRef: UUID?
    
    init(recipients: [MessageRecipient] = [MessageRecipient](),
         timestamp: Date = Date(),
         senderUserId: UUID,
         senderDeviceId: UInt32,
         messageId: UUID = UUID(),
         messageType: FLIMessageType = .content,
         threadId: UUID = UUID(),
         distributionExpression: String,
         expiration: TimeInterval? = nil,
         endSessionFlag: Bool = false,
         expirationTimerUpdateFlag: Bool = false,
         data: JSON? = nil,
         userAgent: String = "LibSignalSwift Client",
         threadTitle: String? = nil,
         threadType: FLIThreadType? = nil,
         messageRef: UUID? = nil
        ) {
        self.recipients = recipients
        self.timestamp = timestamp
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.messageId = messageId
        self.messageType = messageType
        self.threadId = threadId
        self.distributionExpression = distributionExpression
        self.expiration = expiration
        self.endSessionFlag = endSessionFlag
        self.expirationTimerUpdateFlag = expirationTimerUpdateFlag
        self.data = data
        self.userAgent = userAgent
        self.threadTitle = threadTitle
        self.threadType = threadType
        self.messageRef = messageRef
    }
}

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
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
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
            watchEverything()
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
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
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
                forName: .signalInboundMessage,
                object: nil,
                queue: nil) { notification in
                    inboundMessage = notification.userInfo?["inboundMessage"] as? InboundMessage
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
                                   threadId: UUID(uuidString: inboundMessage!.body[0]["threadId"].stringValue)!,
                                   distributionExpression: inboundMessage!.body[0]["distribution"]["expression"].stringValue,
                                   data: TextMessageData(plain: "Hello, world!"),
                                   threadType: .conversation)

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
            
            
            response.recipients.append(.device(inboundMessage!.source))
            print(response)
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
    
    func watchEverything() {
        let _ = NotificationCenter.default.addObserver(
            forName: .signalQueueEmpty,
            object: nil,
            queue: nil) { _ in
                print(">>> message queue is empty")
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalIdentityKeyChanged,
            object: nil,
            queue: nil) { notification in
                let address = notification.userInfo?["address"] as! SignalAddress
                print(">>> identity key changed", address)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalDeliveryReceipt,
            object: nil,
            queue: nil) { notification in
                let receipt = notification.userInfo?["deliveryReceipt"] as! DeliveryReceipt
                print(">>>", receipt)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalInboundMessage,
            object: nil,
            queue: nil) { notification in
                let inboundMessage = notification.userInfo?["inboundMessage"] as! InboundMessage
                print(">>>", inboundMessage)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalReadSyncReceipts,
            object: nil,
            queue: nil) { notification in
                let receipts = notification.userInfo?["readSyncReceipts"] as! [ReadSyncReceipt]
                print(">>>", receipts)
        }
    }
    
    func testPreKeySend() {
        
        do {
            watchEverything()
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
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
                    } else {
                        XCTFail("surprising error")
                    }
                }
                .finally {
                    registrated.fulfill()
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectified = XCTestExpectation()
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .signalQueueEmpty,
                object: nil,
                queue: nil) { _ in
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
                                  data: TextMessageData(plain: "Hello, world!"))
            message.recipients.append(MessageRecipient.device(SignalAddress(userId: "bd1f7e2d-55f5-4a3b-933d-ab7cf51503ca", deviceId: 1)))

            let receiptReceived = XCTestExpectation()
            let receiptObserver = NotificationCenter.default.addObserver(
                forName: .signalDeliveryReceipt,
                object: nil,
                queue: nil) { notification in
                    let receipt = notification.userInfo?["deliveryReceipt"] as! DeliveryReceipt
                    receiptReceived.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(receiptObserver) }

            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            print("sending message", message)
            sender.send(message)
                .map { response in
                    print("FIRST message sent:", response)
                }
                .then {
                    sender.send(message)
                }
                .done { response in
                    print("SECOND message sent:", response)
                }
                .catch { error in
                    XCTFail("error \(error)")
                }
                .finally {
                    // theGoodPart.fulfill()
            }

            wait(for: [theGoodPart], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
}
