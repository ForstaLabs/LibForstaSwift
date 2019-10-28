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
            let wsr = WebSocketResource(signalClient: signalClient, requestHandler: { request in
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
            let wsr = WebSocketResource(signalClient: signalClient)
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
            let wsr = WebSocketResource(signalClient: signalClient)
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
            let forsta = try ForstaClient(MemoryKVStore())

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
            let forsta = try ForstaClient(MemoryKVStore())
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
            let forsta = try ForstaClient(MemoryKVStore())
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
            let forsta = try ForstaClient(MemoryKVStore())
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
            let forsta = try ForstaClient(MemoryKVStore())
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
    
    func testSigning() throws {

        let keyPair = try Signal.generateIdentityKeyPair()
        
        var message = "Foo the bar, Baz!".toData()
        
        let signature = try SignalCommonCrypto.generateSignature(privateKeyData: keyPair.privateKey, message: message)
        XCTAssert(signature.count == 64)
        
        let verify1 = try SignalCommonCrypto.verifySignature(signature: signature, publicKeyData: keyPair.publicKey, message: message)
        XCTAssert(verify1)
        
        var badPub = keyPair.publicKey.dropFirst()
        badPub[10] = 42
        
        let verify2 = try Utility.curve25519Verify(signature: signature, publicKey: badPub, message: message)
        XCTAssert(!verify2)
        
        message[3] = 88 // X
        let verify3 = try SignalCommonCrypto.verifySignature(signature: signature, publicKeyData: keyPair.publicKey, message: message)
        XCTAssert(!verify3)
    }


    func testProvisionResponse() {
        do {
            watchEverything()
            let forsta = try ForstaClient(MemoryKVStore())
            
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
            let forsta = try ForstaClient(MemoryKVStore())
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
            let forsta = try ForstaClient(MemoryKVStore())
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
            let forsta = try ForstaClient(MemoryKVStore())

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
    
    func testRegisterAndDeleteDevice() {
        let completed = XCTestExpectation()
        let label = "test new device create/delete"
        do {
            let forsta = try ForstaClient(MemoryKVStore())
            firstly {
                forsta.atlas.authenticateViaPassword(userTag: "greg1", password: "asdfasdf24")
            }
            .map { _ in
                forsta.signal.registerDevice(deviceLabel: label)
            }
            .then { task in
                task.complete
            }
            .then {
                forsta.atlas.getSignalAccountInfo()
            }
            .then { info -> Promise<Void> in
                let myId = forsta.signal.signalAddress!.deviceId
                let x = info.devices.first { $0.id == myId && $0.label == label }
                XCTAssert(x != nil)
                return forsta.signal.deleteDevice(deviceId: UInt32(myId))
            }
            .then { _ in
                forsta.atlas.getSignalAccountInfo()
            }
            .map { info -> Void in
                let myId = forsta.signal.signalAddress!.deviceId
                let x = info.devices.first { $0.id == myId && $0.label == label }
                XCTAssert(x == nil)
                completed.fulfill()
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTFail(ferr.description)
                } else {
                    XCTFail("surprising error")
                }
            }
        } catch {
            XCTFail("surprising error")
        }
        wait(for: [completed], timeout: 60.0)
    }
    
    func testNewDeviceConversation() {
        watchEverything()
        let completed = XCTestExpectation()
        let conversation = Conversation()
        
        firstly {
            conversation.register(tag: "greg1", password: "asdfasdf24")
        }
        .then {
            conversation.finished
        }
        .done { _ in
            print("conversation over")
            completed.fulfill()
        }
        .catch { error in
            if let e = error as? ForstaError {
                print(e)
            } else {
                print(error)
            }
            XCTFail("What we've got here is a failure to communicate.")
        }
        wait(for: [completed], timeout: 10*60.0)
    }
    
    func testExample() {
        let completed=XCTestExpectation()
        let example = Example()
        
        firstly {
            example.go()
        }
        .done {
            completed.fulfill()
        }
        .catch { error in
            print(error)
        }
        wait(for: [completed], timeout: 10*60.0)
    }
    
    func testSyncStuff() {
        watchEverything()
        let completed=XCTestExpectation()
        let syncStuff = SyncStuff()
        
        firstly {
            syncStuff.go(userTag: "greg1", password: "asdfasdf24")
        }
        .done {
            completed.fulfill()
        }
        .catch { error in
            print(error)
        }
        wait(for: [completed], timeout: 10*60.0)
    }
}


class Conversation: SignalClientDelegate {
    let forsta = try! ForstaClient(MemoryKVStore())
    let (finished, finishedSeal) = Promise<Void>.pending()

    func register(tag: String, password: String) -> Promise<Void> {
        return firstly {
            forsta.atlas.authenticateViaPassword(userTag: tag, password: password)
        }
        .map { _ in
            self.forsta.signal.registerDevice(deviceLabel: "test new device conversation")
        }
        .then { task in
            task.complete
        }
        .map { _ in
            self.forsta.signal.delegates.add(self)
            try self.forsta.connect()
        }
    }

    // SignalClientDelegate.inboundMessage
    func inboundMessage(message: InboundMessage) {
        if message.payload.messageType! == .content {
            if message.payload.bodyPlain == "end" {
                forsta.disconnect()
                finishedSeal.fulfill(())
            }

            forsta.sendSyncReadReceipts([SyncReadReceipt(message.source.userId, message.timestamp)])
                .map { results in let _ = print("sent sync read receipts", results)
            }
            .map { _ in
                    let msg = Message(
                        messageType: .control,
                        threadId: message.payload.threadId!,
                        threadExpression: message.payload.threadExpression!
                    )
                    msg.payload.controlType = .readMark
                    msg.payload.readMark = message.timestamp
                    return msg
            }
            .then { readMark in
                self.forsta.send(readMark, to: [.user(message.source.userId)])
            }
            .map { results in
                let _ = print("\nsent a readMark", results)
            }
            .then {
                self.buildResponse(to: message)
            }
            .map { outbound in
                print("\n>>>", outbound)
                return outbound
            }
            .then { outbound in
                self.forsta.send(outbound, to: [.user(message.source.userId)])
            }
            .map { response in
                print("send result:", response)
            }
            .catch { error in
                XCTFail("send error \(error)")
            }
        }
    }

    func buildResponse(to inbound: InboundMessage) -> Promise<Message> {
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
                    return self.forsta.signal.uploadAttachment(data: newData, name: "new-\(info.name)", type: info.type, mtime: Date())
                }
                if try SignalCommonCrypto.random(bytes: 1)[0] < 80 {
                    uploads.append(self.forsta.signal.uploadAttachment(data: Data(base64Encoded: self.memeData)!, name: "meme.jpg", type: "image/jpeg", mtime: Date()))
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
    
    let memeData = "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"
}

class Example: SignalClientDelegate {
    let forsta = try! ForstaClient(MemoryKVStore())
    let (finished, finishedSeal) = Promise<Void>.pending()
    
    // This will authenticate with password credentials, register a new device,
    // connect with the Signal server, and return a Promise that will resolve
    // when the example conversation has completed.
    func go() -> Promise<Void> {
        return firstly {
            forsta.atlas.authenticateViaPassword(userTag: "greg1", password: "asdfasdf24")
        }
        .map { _ in
            self.forsta.signal.registerDevice(deviceLabel: "test new device conversation")
        }
        .then { task in
            task.complete
        }
        .then { _ -> Promise<Void> in
            self.forsta.signal.delegates.add(self)
            try self.forsta.connect()
            return self.finished
        }
    }
    
    // SignalClientDelegate.inboundMessage delegate method.
    // This will receive a message and immediately respond to the sender.
    func inboundMessage(message: InboundMessage) {
        if message.payload.messageType! == .content {
            let text = message.payload.bodyPlain ?? ""
            print("received text: \(text)")

            if text == "quit" {
                self.forsta.disconnect()
                finishedSeal.fulfill(())
            }
            
            // We'll cheat a little by treating the InboundMessage as our own
            // Sendable, simply modifying it in place and sending it back.
            // In a real application, you would use your own outgoing
            // message class conforming to Sendable.
            message.payload.sender = nil
            message.payload.messageId = UUID()
            message.timestamp = Date.timestamp
            message.payload.bodyPlain = "That's \(text.count) character(s)."

            print("Sending text for \(message.timestamp.millisecondsSince1970): \(message.payload.bodyPlain ?? "???")")

            firstly {
                self.forsta.send(message, to: [.user(message.source.userId)])
            }
            .map { info in
                print("transmission information:", info)
            }
            .catch { error in
                print("send error: \(error)")
                self.finishedSeal.reject(error)
            }
        }
    }
    
    // SignalClientDelegate.deliveryReceipt delegate method.
    // (The timestamps are how Signal clients identify messages.)
    func deliveryReceipt(receipt: DeliveryReceipt) {
        print(receipt)
    }
}

class SyncStuff: SignalClientDelegate {
    let forsta = try! ForstaClient(MemoryKVStore())
    let (finished, finishedSeal) = Promise<Void>.pending()
    
    func go(userTag: String, password: String) -> Promise<Void> {
        return firstly {
            forsta.atlas.authenticateViaPassword(userTag: userTag, password: password)
        }
        .map { _ in
            self.forsta.signal.registerDevice(deviceLabel: "test new device conversation")
        }
        .then { task in
            task.complete
        }
        .then {
            self.instigateSync()
        }
        .then { _ -> Promise<Void> in
            self.forsta.signal.delegates.add(self)
            try self.forsta.connect()
            return self.finished
        }
    }
    
    func instigateSync() -> Promise<Void> {
        let msg = Message(messageType: .control, threadExpression: "")
        msg.payload.controlType = .syncRequest
        msg.payload.data!.type = .contentHistory
        msg.payload.data!.knownMessages = []
        msg.payload.data!.knownThreads = []
        msg.payload.data!.knownContacts = [ForstaPayloadV1.KnownContact(id: self.forsta.signal.signalAddress!.userId, updated: Date.timestamp)]

        return firstly {
            self.forsta.atlas.getSignalAccountInfo()
        }
        .map { info in
            msg.payload.data!.devices = info.devices.map { $0.id }
        }
        .then { _ in
            self.forsta.send(msg, to: [])
        }
        .map { info in
            print("transmission info \(info)")
            return
        }
    }
    
    func inboundMessage(message: InboundMessage) {
        print("inboundMessage called with message @\(message.timestamp.millisecondsSince1970)")
        let text = message.payload.bodyPlain ?? ""

        if text == "quit" || text == "end" {
            self.forsta.disconnect()
            finishedSeal.fulfill(())
        }
    }
    
    func deliveryReceipt(receipt: DeliveryReceipt) {
        print("deliveryRecipt called with \(receipt)")
    }
}
