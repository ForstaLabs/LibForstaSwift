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
    
    public var attachments: [AttachmentInfo]
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
         bodyHtml: String? = nil,
         attachments: [AttachmentInfo] = []
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
        self.attachments = attachments
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
        
        XCTAssert(payload.json() == "[{\"version\":1}]")
        
        payload.iceCandidates = nil
        XCTAssert(payload.iceCandidates == nil)
        payload.iceCandidates = [ForstaPayloadV1.IceCandidate(candidate: "yo", sdpMid: "baby", sdpMLineIndex: 42)]
        XCTAssert(payload.iceCandidates != nil)
        XCTAssert(payload.iceCandidates?.count == 1)
        
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
        payload.sender = sender.payloadAddress
        XCTAssert(payload.sender!.device == sender.payloadAddress.device)
        XCTAssert(payload.sender!.userId == sender.payloadAddress.userId)
        
        let originator = UUID()
        XCTAssert(payload.callOriginator == nil)
        payload.callOriginator = originator
        XCTAssert(payload.callOriginator! == originator)

        let offer = "some sdp call \n offer string"
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
        
        XCTAssert(payload.data?.body == nil)
        XCTAssert(payload.bodyPlain == nil)
        XCTAssert(payload.bodyHtml == nil)
        payload.bodyPlain = "plain stuff"
        payload.bodyHtml = "html stuff"
        XCTAssert(payload.data?.body != nil)
        XCTAssert(payload.bodyPlain != nil)
        XCTAssert(payload.bodyHtml != nil)
        XCTAssert(payload.bodyPlain == "plain stuff")
        
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
        
        print("filled:", payload)
        
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
        
        payload.bodyPlain = nil
        payload.bodyHtml = nil
        XCTAssert(payload.bodyPlain == nil)
        XCTAssert(payload.bodyHtml == nil)
        XCTAssert(payload.data?.body?.count == nil)
        
        payload.threadExpression = nil
        XCTAssert(payload.threadExpression == nil)
        
        payload.threadId = nil
        XCTAssert(payload.threadId == nil)
        
        payload.iceCandidates = nil
        XCTAssert(payload.iceCandidates == nil)
        
        payload.threadTitle = nil
        XCTAssert(payload.threadTitle == nil)
        
        payload.threadType = nil
        XCTAssert(payload.threadType == nil)
        
        payload.userAgent = nil
        XCTAssert(payload.userAgent == nil)
        
        print("emptied:", payload)
        XCTAssert(payload.version == 1)

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
        print("emptied2:", payload)
        
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
            forName: .signalSyncReadReceipts,
            object: nil,
            queue: nil) { notification in
                let receipts = notification.userInfo?["syncReadReceipts"] as! [SyncReadReceipt]
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
                        let words = inbound!.payload.bodyPlain ?? ""
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
                .then { registrator in
                    registrator.complete
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
    
    func testCancelRegisterDevice() {
        var registrator: SignalClient.AutoprovisionTask?
        
        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"
            
            let finished = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@password:swift.test", password: "asdfasdf24")
                .map { _ in
                    let _ = print("authenticated")
                }
                .map {
                    registrator = forsta.signal.registerDevice(deviceLabel: "cancellation test B")
                }
                .then { _ -> Promise<Void> in
                    let _ = after(seconds: 3).done { _ in
                        print("cancelling asyncrhonously after a few seconds")
                        registrator!.cancel()
                    }
                    print("WAITING on registration completion starting now...")
                    return registrator!.complete
                }
                .done {
                    XCTFail("this shouldn't complete normally, due to cancellation")
                }
                .catch { error in
                    if let e = error as? ForstaError {
                        XCTAssert(e.type == .canceled)
                        finished.fulfill()
                    } else {
                        XCTFail("registration errored \(error)")
                    }
            }
            wait(for: [finished], timeout: 20.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testAgreement() throws {
        let pubKey = Data([5, 239, 170, 16, 171, 98, 104, 236, 70, 100, 230, 43, 185, 74, 114, 210, 117, 30, 178, 102, 86, 128, 247, 16, 104, 237, 119, 165, 188, 194, 18, 24, 45])
        let privKey = Data([240, 75, 137, 33, 250, 129, 45, 123, 186, 62, 192, 174, 158, 21, 144, 106, 12, 132, 114, 2, 117, 222, 3, 28, 183, 174, 153, 136, 151, 169, 177, 102])
        
        let expected = Data([171, 129, 171, 89, 95, 194, 145, 144, 106, 36, 158, 103, 150, 99, 227, 65, 212, 135, 218, 207, 111, 208, 192, 245, 228, 222, 118, 203, 252, 93, 123, 114])
        let result = try SignalCommonCrypto.calculateAgreement(publicKeyData: pubKey.dropFirst(), privateKeyData: privKey)

        XCTAssert(expected == result)
    }
    
    func testNew_DEVICE_Conversation() {
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
                        if inbound!.payload.bodyPlain == "end" { theEnd.fulfill() }
                        forsta.sendSyncReadReceipts([SyncReadReceipt(inbound!.source.userId, inbound!.timestamp)])
                            .map { results in
                                let _ = print("sent sync read receipts", results)
                        }
                        .map { _ in
                            let msg = Message(
                                messageType: .control,
                                threadId: inbound!.payload.threadId!,
                                threadExpression: inbound!.payload.threadExpression!
                            )
                            msg.payload.controlType = .readMark
                            msg.payload.readMark = inbound!.timestamp
                            return msg
                        }
                        .then { readMark in
                            forsta.send(readMark, to: [.user(inbound!.source.userId)])
                        }
                        .map { results in
                            let _ = print("\nsent a readMark", results)
                        }
                        .then {
                            self.buildResponse(to: inbound!, using: forsta)
                        }
                        .map { outbound in
                            print("\n>>>", outbound)
                            return outbound
                        }
                        .then { outbound in
                            forsta.send(outbound, to: [.user(inbound!.source.userId)])
                        }
                        .map { response in
                            print("send result:", response)
                        }
                        .catch { error in
                            XCTFail("send error \(error)")
                        }
                    }
            }
            
            wait(for: [theEnd], timeout: 4 * 60.0 * 60.0)
            forsta.disconnect()
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    let memeData = "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"
    
    func buildResponse(to inbound: InboundMessage, using forsta: Forsta) -> Promise<Message> {
        let files = inbound.attachments.map { forsta.signal.downloadAttachment($0) }
        return when(fulfilled: files)
            .then { downloads -> Promise<[AttachmentInfo]> in
                var uploads: [Promise<AttachmentInfo>] = zip(inbound.attachments, downloads).map {
                    let (info, data) = $0
                    var newData: Data
                    if info.type == "text/plain" {
                        let text = String(data: data, encoding: .utf8) ?? "<text unavailable>"
                        newData = (text + "\nSwift was here.\n").toData()
                    } else {
                        newData = data
                    }
                    return forsta.signal.uploadAttachment(data: newData, name: "new-\(info.name)", type: info.type, mtime: Date())
                }
                if try SignalCommonCrypto.random(bytes: 1)[0] < 80 {
                    uploads.append(forsta.signal.uploadAttachment(data: Data(base64Encoded: self.memeData)!, name: "meme.jpg", type: "image/jpeg", mtime: Date()))
                }
                return when(fulfilled: uploads)
            }
            .map { attachments in
                let inText = inbound.payload.bodyPlain ?? ""
                let outText = "That's \(inText.count) character\(inText.count == 1 ? "" : "s")\(inbound.attachments.count > 0 ? " and \(inbound.attachments.count) attachment\(inbound.attachments.count == 1 ? "" : "s")" : ""), yo."
                return Message(threadId: inbound.payload.threadId!,
                               threadExpression: inbound.payload.threadExpression!,
                               bodyPlain: outText,
                               attachments: attachments)
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
    
    func testRegisterDeviceAndSyncSend() {
        
        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"
            
            let sentified = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .map { stuff in
                    forsta.signal.registerDevice(deviceLabel: "test register and sync send")
                }
                .then { task in
                    task.complete
                }
                .map {
                    let _ = print("registered")
                }
                .then { _ in
                    forsta.send(Message(threadId: UUID(uuidString: "e4652d6e-20f1-49d5-a22c-caefa5e4306f")!,
                                        threadExpression: "(<8745c66c-518e-48b0-b3a7-d1d6cbe85059>+<e4faa7e0-5670-4436-a1b5-afd673e58298>)",
                                        threadType: .conversation,
                                        bodyPlain: "Sync this!"),
                                to: [MessageRecipient.user(UUID(uuidString: "b1d29795-d40e-4ee3-9f76-f6dd07d94bcb")!)])
                }
                .done { results in
                    let _ = print("sent")
                    let _ = print(results)
                    sentified.fulfill()
                }
                .catch { error in
                    if let e = error as? ForstaError {
                        print(e)
                    } else {
                        print(error)
                    }
                    XCTFail(error.localizedDescription)
            }
            wait(for: [sentified], timeout: 6*10.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }

    func testAttachmentEncryptDecrypt() throws {
        do {
            let keys = try SignalCommonCrypto.random(bytes: 64)
            let iv = try SignalCommonCrypto.random(bytes: 16)
            
            let content = "Hello, world!".toData()
            
            let encrypted = try SignalCommonCrypto.encryptAttachment(data: content, keys: keys, iv: iv)
            let decrypted = try SignalCommonCrypto.decryptAttachment(data: encrypted, keys: keys)
            
            XCTAssert(decrypted == content)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testFetchAttachment() {
        let attachmentInfo = AttachmentInfo(
            name: "hello.txt",
            size: 14,
            type: "text/plain",
            mtime: Date(),
            id: 8734968899990206249,
            key: Data(base64Encoded: "Oq1v9Fwyle9FPxKLWKgBg4kUMjmy0+P+pATdZMmPI36i4n7KlGYgm5BAEDvOlRcc7tYQsAH6vstgKvbNpzxF9Q==")!
        )

        do {
            let forsta = try Forsta(MemoryKVStore())
            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"
            
            let allDone = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .map { stuff in
                    forsta.signal.registerDevice(deviceLabel: "test register and sync send")
                }
                .then { task in
                    task.complete
                }
                .map {
                    let _ = print("registered")
                }
                .then { _ in
                    forsta.signal.downloadAttachment(attachmentInfo)
                }
                .done { fileData in
                    XCTAssert(fileData.count == attachmentInfo.size)
                    let _ = print("Here's the content:", String(data: fileData, encoding: .utf8)!)
                    allDone.fulfill()
                }
                .catch { error in
                    if let e = error as? ForstaError {
                        print(e)
                    } else {
                        print(error)
                    }
                    XCTFail(error.localizedDescription)
            }
            wait(for: [allDone], timeout: 6*10.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
    
    func testUploadDownloadAttachment() {

        do {
            let forsta = try Forsta(MemoryKVStore())

            let content = "Hello, world!".toData()

            forsta.atlas.serverUrl = "https://atlas-dev.forsta.io"
            
            let allDone = XCTestExpectation()
            forsta.atlas.authenticateViaPassword(userTag: "@greg1:forsta", password: "asdfasdf24")
                .map { stuff in
                    forsta.signal.registerDevice(deviceLabel: "test register and sync send")
                }
                .then { task in
                    task.complete
                }
                .map {
                    let _ = print("registered\nuploading...")
                }
                .then { _ in
                    forsta.signal.uploadAttachment(data: content, name: "hello.txt", type: "text/plain", mtime: Date())
                }
                .then { info -> Promise<Data> in
                    let _ = print("downloading...")
                    return forsta.signal.downloadAttachment(info)
                }
                .done { attachmentData in
                    XCTAssert(attachmentData == content)
                    let _ = print("finished")
                    allDone.fulfill()
                }
                .catch { error in
                    if let e = error as? ForstaError {
                        print(e)
                    } else {
                        print(error)
                    }
                    XCTFail("NO BUENO")
            }
            wait(for: [allDone], timeout: 6*10.0)
        } catch let error {
            XCTFail("surprising error \(error)")
        }
    }
}
