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
    
    func testSomething() {

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
            let dataMessageObserver = NotificationCenter.default.addObserver(
                forName: .relayDataMessage,
                object: nil,
                queue: nil) { notification in
                    print(notification.userInfo?["dataMessage"])
                    connectAndReceive.fulfill()
            }
            defer { NotificationCenter.default.removeObserver(dataMessageObserver) }
            let wsr = WebSocketResource(signalClient: signalClient)
            let _ = MessageReceiver(signalClient: signalClient, webSocketResource: wsr)
            wsr.connect()
            wait(for: [connectAndReceive], timeout: 2 * 60.0)
            wsr.disconnect()
        } catch {
            XCTFail("surprising error")
        }
    }
}
