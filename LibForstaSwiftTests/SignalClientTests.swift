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
    public var timestamp: Date
    public var expiration: TimeInterval?
    public var endSessionFlag: Bool
    public var expirationTimerUpdateFlag: Bool
    
    public var payload = ForstaPayloadV1()

    init(timestamp: Date = Date(),
         messageId: UUID = UUID(),
         messageType: ForstaPayloadV1.MessageType = .content,
         threadId: UUID = UUID(),
         threadExpression: String,
         expiration: TimeInterval? = nil,
         endSessionFlag: Bool = false,
         expirationTimerUpdateFlag: Bool = false,
         userAgent: String = "LibSignalSwift Client",
         threadTitle: String? = nil,
         threadType: ForstaPayloadV1.ThreadType = .conversation,
         messageRef: UUID? = nil,
         bodyPlain: String? = nil,
         bodyHtml: String? = nil
        ) {
        self.timestamp = timestamp
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
        self.payload.bodyPlain = bodyPlain
        self.payload.bodyHtml = bodyHtml
    }
}

class SignalClientTests: XCTestCase {
    func testTimestamps() {
        for _ in 1...1000000 {
            let d1 = Date.timestamp
            let ts1 = d1.millisecondsSince1970
            let d2 = Date(millisecondsSince1970: ts1)
            let ts2 = d2.millisecondsSince1970
            XCTAssert(ts1 == ts2)
            XCTAssert(d1 == d2)
        }
    }
    
    func testPayload() {
        var payload = ForstaPayloadV1()
        
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
        
        let originator = UUID()
        XCTAssert(payload.callOriginator == nil)
        payload.callOriginator = originator
        XCTAssert(payload.callOriginator! == originator)

        let offer = "some sdp call offer string"
        XCTAssert(payload.sdpOffer == nil)
        payload.sdpOffer = offer
        XCTAssert(payload.sdpOffer! == offer)

        let answer = "some sdp call answer string"
        XCTAssert(payload.sdpAnswer == nil)
        payload.sdpAnswer = answer
        XCTAssert(payload.sdpAnswer! == answer)

        let members = [UUID(), UUID(), UUID()]
        XCTAssert(payload.callMembers == nil)
        payload.callMembers = members
        XCTAssert(payload.callMembers! == members)

        let messageType = ForstaPayloadV1.MessageType.content
        XCTAssert(payload.messageType == nil)
        payload.messageType = messageType
        XCTAssert(payload.messageType! == messageType)
        
        let controlType = ForstaPayloadV1.ControlType.callJoin
        XCTAssert(payload.controlType == nil)
        payload.controlType = controlType
        XCTAssert(payload.controlType! == controlType)
        
        let body: [ForstaPayloadV1.BodyItem] = [.plain("yo baby")]
        XCTAssert(payload.body == nil)
        XCTAssert(payload.bodyPlain == nil)
        XCTAssert(payload.bodyHtml == nil)
        payload.body = body
        XCTAssert(payload.body != nil)
        XCTAssert(payload.bodyPlain != nil)
        XCTAssert(payload.bodyHtml == nil)
        switch payload.body![0] {
        case .plain(let string): XCTAssert(string == "yo baby")
        default: XCTFail()
        }
        XCTAssert(payload.bodyPlain == "yo baby")
        
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
        
        let threadType = ForstaPayloadV1.ThreadType.conversation
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
        
        payload.controlType = nil
        XCTAssert(payload.controlType == nil)
        
        payload.callOriginator = nil
        XCTAssert(payload.callOriginator == nil)
        
        payload.sdpOffer = nil
        XCTAssert(payload.sdpOffer == nil)
        
        payload.sdpAnswer = nil
        XCTAssert(payload.sdpAnswer == nil)
        
        payload.callMembers = nil
        XCTAssert(payload.callMembers == nil)
        
        payload.body = nil
        XCTAssert(payload.body == nil)
        XCTAssert(payload.bodyPlain == nil)
        XCTAssert(payload.bodyHtml == nil)
        
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
        XCTAssert(!(payload.json["data"].exists()))
        
        payload = ForstaPayloadV1()
        XCTAssert(payload.threadUpdateExpression == nil)
        payload.threadUpdateExpression = "@a + @b"
        XCTAssert(payload.threadUpdateExpression == "@a + @b")
        payload.threadUpdateExpression = nil
        XCTAssert(payload.threadUpdateExpression == nil)
        
        XCTAssert(payload.threadUpdateTitle == nil)
        payload.threadUpdateTitle = "a title"
        XCTAssert(payload.threadUpdateTitle == "a title")
        payload.threadUpdateTitle = nil
        XCTAssert(payload.threadUpdateTitle == nil)
        
        let now = Date.timestamp
        XCTAssert(payload.readMark == nil)
        payload.readMark = now
        XCTAssert(payload.readMark == now)
        payload.readMark = nil
        XCTAssert(payload.readMark == nil)
    }
    
    
    func testRegisterAndConnect() {
        do {
            let atlasClient = AtlasClient(kvstore: MemoryKVStore())
            let signalClient = try SignalClient(atlasClient: atlasClient)
            
            let registrated = XCTestExpectation(description: "registerAccount test")
            atlasClient.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    signalClient.registerAccount(deviceLabel: "testing")
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
            let wsr = WebSocketResource(requestHandler: { request in
                print("sending response of 404 Not found to request: \(request.verb) \(request.path)")
                let _ = request.respond(status: 404, message: "Not found")
                connectified.fulfill()
            })
            wsr.connect(url: try signalClient.messagingSocketUrl())
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
                    signalClient.registerAccount(deviceLabel: "testing")
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
            let wsr = WebSocketResource()
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect(url: try signalClient.messagingSocketUrl())
            wait(for: [connectAndReceive], timeout: 2 * 60.0)
            let thenSend = XCTestExpectation()
            
            let sender = MessageSender(signalClient: signalClient)
            let response = Message(threadId: inboundMessage!.payload.threadId!,
                                   threadExpression: inboundMessage!.payload.threadExpression!,
                                   threadType: .conversation,
                                   bodyPlain: "Hello, world!")

            print("\n>>>", response)
            sender.send(response, to: [.device(inboundMessage!.source)])
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
                print("\n>>> message queue is empty")
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalIdentityKeyChanged,
            object: nil,
            queue: nil) { notification in
                let address = notification.userInfo?["address"] as! SignalAddress
                print("\n>>> identity key changed", address)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalDeliveryReceipt,
            object: nil,
            queue: nil) { notification in
                let receipt = notification.userInfo?["deliveryReceipt"] as! DeliveryReceipt
                print("\n>>>", receipt)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalInboundMessage,
            object: nil,
            queue: nil) { notification in
                let inboundMessage = notification.userInfo?["inboundMessage"] as! InboundMessage
                print("\n>>>", inboundMessage)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalReadSyncReceipts,
            object: nil,
            queue: nil) { notification in
                let receipts = notification.userInfo?["readSyncReceipts"] as! [ReadSyncReceipt]
                print("\n>>>", receipts)
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalConnected,
            object: nil,
            queue: nil) { _ in
                print("\n>>> signal server websocket connected")
        }
        
        let _ = NotificationCenter.default.addObserver(
            forName: .signalDisconnected,
            object: nil,
            queue: nil) { notification in
                let error = notification.userInfo?["error"] as? Error
                print("\n>>> signal server websocked disconnected", error ?? "")
        }
    }
    func testPreKeySendAndReceive() {
        
        do {
            watchEverything()
            let atlasClient = AtlasClient(kvstore: MemoryKVStore())
            let signalClient = try SignalClient(atlasClient: atlasClient)
            
            let registrated = XCTestExpectation()
            atlasClient.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    signalClient.registerAccount(deviceLabel: "testing")
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
            let wsr = WebSocketResource()
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect(url: try signalClient.messagingSocketUrl())
            wait(for: [connectified], timeout: 2 * 60.0)

            let theReceive = XCTestExpectation()
            let theSend = XCTestExpectation()

            let receiptReceived = XCTestExpectation()
            let receiptObserver = NotificationCenter.default.addObserver(
                forName: .signalDeliveryReceipt,
                object: nil,
                queue: nil) { notification in
                    let receipt = notification.userInfo?["deliveryReceipt"] as! DeliveryReceipt
                    receiptReceived.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(receiptObserver) }
            
            let sender = MessageSender(signalClient: signalClient)
            let message = Message(threadId: UUID(uuidString: "2cfe708c-42a9-4a63-b215-ad841e1e2399")!,
                                  threadExpression: "(<2b53e98b-170f-4102-9d82-e43d5abb7998>+<e4faa7e0-5670-4436-a1b5-afd673e58298>)",
                                  threadType: .conversation,
                                  bodyPlain: "Hello, world!")
            print("\n>>>", message)
            sender.send(message, to: [.user(UUID(uuidString: "14871866-c0b4-4d1a-ab36-2a930385baf0")!)])
                .map { response in
                    print("send result:", response)
                }
                .catch { error in
                    XCTFail("error \(error)")
                }
                .finally {
                    theSend.fulfill()
            }
            
            let inboundObserver = NotificationCenter.default.addObserver(
                forName: .signalInboundMessage,
                object: nil,
                queue: nil) { notification in
                    let inboundMessage = notification.userInfo?["inboundMessage"] as? InboundMessage
                    if inboundMessage?.payload.messageType! == .content {
                        theReceive.fulfill()
                    }
            }
            defer { NotificationCenter.default.removeObserver(inboundObserver) }
            
            wait(for: [theSend, theReceive], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testNewAccountConversation() {
        do {
            watchEverything()
            let forsta = try Forsta(MemoryKVStore())

            let registrated = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    forsta.signal.registerAccount(deviceLabel: "testing")
                }
                .done {
                    print("registered account")
                    registrated.fulfill()
                }
                .catch { error in
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
                    } else {
                        XCTFail("surprising error")
                    }
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectified = XCTestExpectation()
            let _ = NotificationCenter.default.addObserver(
                forName: .signalConnected,
                object: nil,
                queue: nil) { _ in
                    connectified.fulfill()
            }
            try forsta.connect()
            wait(for: [connectified], timeout: 2 * 60.0)

            let theEnd = XCTestExpectation()
            
            let _ = NotificationCenter.default.addObserver(
                forName: .signalInboundMessage,
                object: nil,
                queue: nil) { notification in
                    let inbound = notification.userInfo?["inboundMessage"] as? InboundMessage
                    if inbound?.payload.messageType! == .content {
                        let words = inbound!.payload.body![0].raw
                        if words == "end" {
                            theEnd.fulfill()
                        }
                        let outbound = Message(threadId: inbound!.payload.threadId!,
                                               threadExpression: inbound!.payload.threadExpression!,
                                               bodyPlain: "That's \(words.count) character\(words.count == 1 ? "" : "s"), yo.")
                        print("\n>>>", outbound)
                        forsta.send(outbound, to: [.user(inbound!.source.userId)])
                            .map { response in
                                print("send result:", response)
                            }
                            .catch { error in
                                XCTFail("send error \(error)")
                        }
                    }
            }

            wait(for: [theEnd], timeout: 5 * 60.0)
            forsta.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testGetAll() {
        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas.forsta.io"
            
            let finished = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "", password: "")
                .then { _ in
                    forsta.atlas.getTags()
                }
                .then { result -> Promise<[JSON]> in
                    print("\(result.count) results")
                    return forsta.atlas.getTags()
                }
                .done { result in
                    print("\(result.count) results")
                    finished.fulfill()
                }
                .catch { error in
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
                    } else {
                        XCTFail("surprising error")
                    }
            }
            wait(for: [finished], timeout: 60.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testRtcServers() {
        
        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"

            let finished = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .then { _ in
                    forsta.atlas.getRtcTurnServersInfo()
                }
                .done { result in
                    print(result)
                    finished.fulfill()
                }
                .catch { error in
                    print("ERRORING!")
                    XCTFail(error.localizedDescription)
                    print("ERRORED!")
            }
            wait(for: [finished], timeout: 5*6*10.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testRegisterDevice() {

        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"

            let finished = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .map { stuff in
                    forsta.signal.registerDevice(deviceLabel: "foo the bar")
                }
                .then { registrator -> Promise<Void> in
                    return registrator.complete
                }
                .done {
                    finished.fulfill()
                }
                .catch { error in
                    if let e = error as? ForstaError {
                        print(e)
                    } else {
                        print(error)
                    }
                    XCTFail(error.localizedDescription)
            }
            wait(for: [finished], timeout: 5*6*10.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testAgreement() throws {
        let forsta = try Forsta(MemoryKVStore())
        
        let pubKey = Data([5, 239, 170, 16, 171, 98, 104, 236, 70, 100, 230, 43, 185, 74, 114, 210, 117, 30, 178, 102, 86, 128, 247, 16, 104, 237, 119, 165, 188, 194, 18, 24, 45])
        let privKey = Data([240, 75, 137, 33, 250, 129, 45, 123, 186, 62, 192, 174, 158, 21, 144, 106, 12, 132, 114, 2, 117, 222, 3, 28, 183, 174, 153, 136, 151, 169, 177, 102])
        
        let expected = Data([171, 129, 171, 89, 95, 194, 145, 144, 106, 36, 158, 103, 150, 99, 227, 65, 212, 135, 218, 207, 111, 208, 192, 245, 228, 222, 118, 203, 252, 93, 123, 114])
        let result = try forsta.signal.calculateAgreement(publicKeyData: pubKey.dropFirst(), privateKeyData: privKey)

        XCTAssert(expected == result)
    }
    
    func testNewDeviceConversation() {
        do {
            watchEverything()
            let forsta = try Forsta(MemoryKVStore())

            let registrated = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .map { _ in
                    forsta.signal.registerDevice(deviceLabel: "test new device conversation")
                }
                .then { registrator -> Promise<Void> in
                    registrator.complete
                }
                .done {
                    print("registered new device")
                    registrated.fulfill()
                }
                .catch { error in
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
                    } else {
                        XCTFail("surprising error")
                    }
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectified = XCTestExpectation()
            let _ = NotificationCenter.default.addObserver(
                forName: .signalConnected,
                object: nil,
                queue: nil) { _ in
                    connectified.fulfill()
            }
            try forsta.connect()
            wait(for: [connectified], timeout: 2 * 60.0)
            
            let theEnd = XCTestExpectation()
            
            let _ = NotificationCenter.default.addObserver(
                forName: .signalInboundMessage,
                object: nil,
                queue: nil) { notification in
                    let inbound = notification.userInfo?["inboundMessage"] as? InboundMessage
                    if inbound?.payload.messageType! == .content {
                        let words = inbound!.payload.body![0].raw
                        if words == "end" {
                            theEnd.fulfill()
                        }
                        let outbound = Message(threadId: inbound!.payload.threadId!,
                                               threadExpression: inbound!.payload.threadExpression!,
                                               bodyPlain: "That's \(words.count) character\(words.count == 1 ? "" : "s"), yo.")
                        print("\n>>>", outbound)
                        forsta.send(outbound, to: [.user(inbound!.source.userId)])
                            .map { response in
                                print("send result:", response)
                            }
                            .catch { error in
                                XCTFail("send error \(error)")
                        }
                    }
            }
            
            wait(for: [theEnd], timeout: 5 * 60.0)
            forsta.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testProvisionResponse() {
        do {
            watchEverything()
            let forsta = try Forsta(MemoryKVStore())
            
            let registrated = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .then { _ in
                    forsta.signal.registerAccount(deviceLabel: "new account to test provision response")
                }
                .done {
                    registrated.fulfill()
                    print("registered new account")
                }
                .catch { error in
                    if let ferr = error as? ForstaError {
                        XCTFail(ferr.description)
                    } else {
                        XCTFail("surprising error")
                    }
            }
            wait(for: [registrated], timeout: 10.0)
            
            let connectified = XCTestExpectation()
            let _ = NotificationCenter.default.addObserver(
                forName: .signalConnected,
                object: nil,
                queue: nil) { _ in
                    print("connected")
                    connectified.fulfill()
            }
            try forsta.connect()
            wait(for: [connectified], timeout: 2 * 60.0)

            let theEnd = XCTestExpectation()
            
            let _ = NotificationCenter.default.addObserver(
                forName: .signalInboundMessage,
                object: nil,
                queue: nil) { notification in
                    let inbound = notification.userInfo?["inboundMessage"] as? InboundMessage
                    guard let payload = inbound?.payload else {
                        print("no inbound message payload!")
                        return
                    }
                    if payload.messageType! == .control && payload.controlType == .provisionRequest {
                        print("it's a provision request!")
                        guard
                            let provisioningKey = payload.provisioningKey,
                            let provisioningUuid = payload.provisioningUuidString else {
                                print("missing provisioning parts!")
                                return
                        }
                        
                        forsta.signal.linkDevice(uuidString: provisioningUuid, ephemeralPublicKey: provisioningKey)
                            .done { iHandledIt in
                                print("finished: \(iHandledIt ? "I handled it":"someone else beat me to it")")
                                theEnd.fulfill()
                            }
                            .catch { error in
                                if let ferr = error as? ForstaError {
                                    XCTFail(ferr.description)
                                } else {
                                    XCTFail("inner surprising error \(error)")
                                }
                        }
                    }
            }
            
            wait(for: [theEnd], timeout: 5 * 60.0)
            forsta.disconnect()
        } catch let error {
            XCTFail("outer surprising error \(error)")
        }
    }
}
