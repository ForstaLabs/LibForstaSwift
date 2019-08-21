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

    public var expiration: TimeInterval?
    public var endSessionFlag: Bool
    public var expirationTimerUpdateFlag: Bool
    
    public var payload = ForstaPayloadV1()

    init(recipients: [MessageRecipient] = [MessageRecipient](),
         timestamp: Date = Date(),
         sender: SignalAddress? = nil,
         messageId: UUID = UUID(),
         messageType: FLIMessageType = .content,
         threadId: UUID = UUID(),
         threadExpression: String,
         expiration: TimeInterval? = nil,
         endSessionFlag: Bool = false,
         expirationTimerUpdateFlag: Bool = false,
         userAgent: String = "LibSignalSwift Client",
         threadTitle: String? = nil,
         threadType: FLIThreadType? = nil,
         messageRef: UUID? = nil,
         bodyPlain: String? = nil,
         bodyHtml: String? = nil
        ) {
        self.recipients = recipients
        self.timestamp = timestamp
        self.payload.sender = sender
        self.payload.messageId = messageId
        self.payload.messageType = messageType
        self.payload.threadId = threadId
        self.payload.threadExpression = threadExpression
        self.expiration = expiration
        self.endSessionFlag = endSessionFlag
        self.expirationTimerUpdateFlag = expirationTimerUpdateFlag
        self.payload.userAgent = userAgent
        self.payload.threadTitle = threadTitle
        self.payload.threadType = threadType
        self.payload.messageRef = messageRef
        
        var bodyItems = [ForstaPayloadV1.BodyItem]()
        if bodyPlain != nil { bodyItems.append(.plain(bodyPlain!)) }
        if bodyHtml != nil { bodyItems.append(.html(bodyHtml!)) }
        if bodyItems.count > 0 { self.payload.body = bodyItems }
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
            
            let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
            let response = Message(threadId: inboundMessage!.payload.threadId!,
                                   threadExpression: inboundMessage!.payload.threadExpression!,
                                   threadType: .conversation,
                                   bodyPlain: "Hello, world!")

            /*
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
             */
            
            
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
    
    func testPayload() {
        let payload = ForstaPayloadV1()
        
        XCTAssert(payload.jsonString == "{\"version\": 1}")
        
        let messageId = UUID()
        XCTAssert(payload.messageId == nil)
        payload.messageId = messageId
        XCTAssert(payload.messageId! == messageId)
        
        let messageRef = UUID()
        XCTAssert(payload.messageRef == nil)
        payload.messageRef = messageRef
        XCTAssert(payload.messageRef! == messageRef)
        
        let sender = SignalAddress(userId: UUID(), deviceId: Int32(42))
        XCTAssert(payload.sender == nil)
        payload.sender = sender
        XCTAssert(payload.sender! == sender)
        
        let messageType = FLIMessageType.content
        XCTAssert(payload.messageType == nil)
        payload.messageType = messageType
        XCTAssert(payload.messageType! == messageType)
        
        let body: [ForstaPayloadV1.BodyItem] = [.plain("yo baby")]
        XCTAssert(payload.body == nil)
        payload.body = body
        XCTAssert(payload.body != nil)
        switch payload.body![0] {
        case .plain(let string): XCTAssert(string == "yo baby")
        default: XCTFail()
        }

        let threadExpression = "@foo + @bar"
        XCTAssert(payload.threadExpression == nil)
        payload.threadExpression = threadExpression
        XCTAssert(payload.threadExpression! == threadExpression)
        
        let threadId = UUID()
        XCTAssert(payload.threadId == nil)
        payload.threadId = threadId
        XCTAssert(payload.threadId! == threadId)
        
        let threadTitle = "my thread title"
        XCTAssert(payload.threadTitle == nil)
        payload.threadTitle = threadTitle
        XCTAssert(payload.threadTitle! == threadTitle)
        
        let threadType = FLIThreadType.conversation
        XCTAssert(payload.threadType == nil)
        payload.threadType = threadType
        XCTAssert(payload.threadType! == threadType)
        
        let userAgent = "muh useragent"
        XCTAssert(payload.userAgent == nil)
        payload.userAgent = userAgent
        XCTAssert(payload.userAgent! == userAgent)

        print("filled:", payload.jsonString)
        
        payload.messageId = nil
        XCTAssert(payload.messageId == nil)
        
        payload.messageRef = nil
        XCTAssert(payload.messageRef == nil)
        
        payload.sender = nil
        XCTAssert(payload.sender == nil)
        
        payload.messageType = nil
        XCTAssert(payload.messageType == nil)
        
        payload.body = nil
        XCTAssert(payload.body == nil)
        
        payload.threadExpression = nil
        XCTAssert(payload.threadExpression == nil)
        
        payload.threadId = nil
        XCTAssert(payload.threadId == nil)
        
        payload.threadTitle = nil
        XCTAssert(payload.threadTitle == nil)
        
        payload.threadType = nil
        XCTAssert(payload.threadType == nil)
        
        payload.userAgent = nil
        XCTAssert(payload.userAgent == nil)
        
        XCTAssert(payload.json["version"] == 1)
        XCTAssert(payload.json["data"].exists())
        XCTAssert(payload.json["data"].dictionary!.count == 0)
    }
    
    func testPreKeySendAndReceive() {
        
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

            let theGoodPart = XCTestExpectation()
            
            let message = Message(threadId: UUID(uuidString: "F12E22AA-8A63-49D7-B71A-2470F3469B3E")!,
                                  threadExpression: "(<2b53e98b-170f-4102-9d82-e43d5abb7998>+<e4faa7e0-5670-4436-a1b5-afd673e58298>+<e98bf10d-528f-44c4-99cd-c488385771cc>)",
                                  threadType: .conversation,
                                  bodyPlain: "Hello, world!")
            message.recipients.append(MessageRecipient.user(UUID(uuidString: "14871866-c0b4-4d1a-ab36-2a930385baf0")!))
            
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
            print(message)
            sender.send(message)
                .map { response in
                    print("send result:", response)
                    message.payload.body = [.plain("Hello again, world!")]
                    message.timestamp = Date()
                }
                /*
                .then {
                    sender.send(message)
                }
                .done { result in
                    print("second send result:", result)
                }
                 */
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
    
    func testBlah() {
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
            
            while true {
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
                wait(for: [connectAndReceive], timeout: 5 * 60.0)
                
                let sender = MessageSender(signalClient: signalClient, webSocketResource: wsr)
                let response = Message(threadId: inboundMessage!.payload.threadId!,
                                       threadExpression: inboundMessage!.payload.threadExpression!,
                                       threadType: inboundMessage!.payload.threadType,
                                       bodyPlain: "Hello, world!")
                
                
                response.recipients.append(.device(inboundMessage!.source))
                print(response)
                let thenSend = XCTestExpectation()
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
                wait(for: [thenSend], timeout: 5 * 60.0)
                wsr.disconnect()
            }
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
}
