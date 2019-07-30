//
//  SignalClient.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 5/22/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import Alamofire
import PromiseKit
import SwiftyJSON
import SignalProtocol

///
///  Interface for the Signal server.  The signal server handles the exchange of
///  encrypted messages and the brokering of public keys.
///
class SignalClient {
    let crypto = SignalCommonCrypto()
    var atlasClient: AtlasClient
    var store: SignalStore

    var kvstore: KVStorageProtocol {
        get {
            return self.atlasClient.kvstore
        }
    }
    var serverUrl: String?
    var username: String?
    var password: String?
    
    ///
    /// Initialize this Signal client.
    ///
    /// - parameters:
    ///     - atlasClient: the associated AtlasClient for this SignalClient
    ///
    init(atlasClient: AtlasClient) throws {
        self.atlasClient = atlasClient
        let kv = atlasClient.kvstore
        self.serverUrl = kv.get(DNK.ssUrl)
        self.username = kv.get(DNK.ssUsername)
        self.password = kv.get(DNK.ssPassword)
        self.store = try SignalStore(
            identityKeyStore: RelayIdentityKeyStore(kvstore: kv),
            preKeyStore: RelayPreKeyStore(kvstore: kv),
            sessionStore: RelaySessionStore(kvstore: kv),
            signedPreKeyStore: RelaySignedPreKeyStore(kvstore: kv),
            senderKeyStore: nil)
    }
    

    func generatePassword() throws -> String {
        return try String(crypto.random(bytes: 16).base64EncodedString().dropLast(2))
    }
    
    func generateSignalingKey() throws -> Data {
        return try crypto.random(bytes: 32 + 20)
    }
    
    func verifyMAC(data: Data, key: Data, expectedMAC: Data) throws {
        let calculatedMAC = crypto.hmacSHA256(for: data, with: key)
        if calculatedMAC[..<expectedMAC.count] != expectedMAC {
            throw LibRelayError.internalError(why: "Bad MAC")
        }
    }

    func decryptWebSocketMessage(message: Data, signalingKey: Data) throws -> Data {
        guard signalingKey.count == 52 else {
            throw LibRelayError.internalError(why: "Invalid signalKey length.")
        }
        guard message.count >= 1 + 16 + 10 else {
            throw LibRelayError.internalError(why: "Invalid message length.")
        }
        guard message[0] == 1 else {
            throw LibRelayError.internalError(why: "Invalid message version number \(message[0]).")
        }
        
        let aesKey = signalingKey[0...31]
        let macKey = signalingKey[32...32+19]
        let iv = message[1...16]
        let ciphertext = message[1+16...message.count-11]
        let ivAndCyphertext = message[0...message.count-11]
        let mac = message[(message.count-10)...]
        
        try verifyMAC(data: ivAndCyphertext, key: macKey, expectedMAC: mac)
        return try crypto.decrypt(message: ciphertext, with: .AES_CBCwithPKCS5, key: aesKey, iv: iv)
    }

    
    func registerAccount(name: String) -> Promise<(Int, JSON)> {
        var signalingKey: Data
        var password: String
        var registrationId: UInt32
        do {
            signalingKey = try generateSignalingKey()
            password = try generatePassword()
            registrationId = try Signal.generateRegistrationId()
        } catch {
            return Promise.init(error: LibRelayError.internalError(why: "Unable to generate random bits for account registration."))
        }
        
        return firstly { () -> Promise<JSON> in
            let data: [String: Any] = [
                "name": name,
                "password": password,
                "registrationId": registrationId,
                "signalingKey": signalingKey.base64EncodedString(),
                "fetchesMessages": true,
                "supportsSms": false,
            ]
            
            return self.atlasClient.provisionAccount(data)
            }
            .map { result in
                guard
                    let serverUrl = result["serverUrl"].string,
                    let userId = result["userId"].string,
                    let deviceId = result["deviceId"].uInt32 else {
                        throw LibRelayError.internalError(why: "unexpected result from provisionAccount")
                }
                
                let username = raddr(userId, deviceId)
                
                let identity = try Signal.generateIdentityKeyPair()
                self.store.relayIdentityKeyStore.setIdentityKeyPair(identity: identity)
                if !self.store.relayIdentityKeyStore.save(identity: identity.publicKey, for: SignalAddress(userId: userId, deviceId: deviceId)) {
                    throw LibRelayError.internalError(why: "unable to store self identity key")
                }
                self.store.relayIdentityKeyStore.setLocalRegistrationId(id: registrationId)

                self.kvstore.set(DNK.ssUrl, serverUrl)
                self.serverUrl = serverUrl
                self.kvstore.set(DNK.ssUsername, username)
                self.username = username
                self.kvstore.set(DNK.ssPassword, password)
                self.password = password
                
                self.kvstore.set(DNK.ssAddress, userId)
                self.kvstore.set(DNK.ssDeviceId, deviceId)
                self.kvstore.set(DNK.ssName, name)
                self.kvstore.set(DNK.ssSignalingKey, signalingKey)
            }
            .then {
                self.genKeystuffBundle()
            }
            .then { bundle in
                self.request(.keys, method: .put, parameters: bundle)
        }
    }
    
    func genKeystuffBundle() -> Promise<[String: Any]> {
        do {
            guard let identity = self.store.identityKeyStore.identityKeyPair() else {
                throw LibRelayError.internalError(why: "unable to retrieve self identity")
            }
            let preKeys = try self.store.generateAndStorePreKeys(count: 100)
            let signedPreKey = try self.store.updateSignedPreKey()

            let signedPreKeyBundle: [String: Any] = [
                "keyId":  signedPreKey.id,
                "publicKey": signedPreKey.keyPair.publicKey.base64EncodedString(),
                "signature": signedPreKey.signature.base64EncodedString()
            ]
            
            // final registration bundle appropriate for the signal server
            let bundle: [String: Any] = [
                "preKeys": preKeys.map {
                    ["keyId": $0.id,
                     "publicKey": $0.keyPair.publicKey.base64EncodedString()]
                },
                "identityKey": identity.publicKey.base64EncodedString(),
                "signedPreKey": signedPreKeyBundle
            ]
            

            return Promise.value(bundle)
        } catch let error {
            return Promise.init(error: error)
        }
    }
    
    
    func deliverToDevice(address: SignalAddress, parameters: [String: Any]) -> Promise<(Int, JSON)> {
        return self.request(
            .messages,
            urlParameters: "/\(address.name)/\(address.deviceId)",
            method: .put,
            parameters: parameters)
    }
    
    
    func getKeysForAddr(addr: String, deviceId: UInt32? = nil) -> Promise<[SessionPreKeyBundle]> {
        let deviceStr = deviceId == nil ? "*" : String(deviceId!)
        return self.request(.keys, urlParameters: "/\(addr)/\(deviceStr)")
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    guard
                        let devices = json["devices"].array,
                        let identityKeyBase64 = json["identityKey"].string,
                        let identityKey = Data(base64Encoded: identityKeyBase64) else {
                            throw LibRelayError.internalError(why: "malformed prekeys response")
                    }
                    var bundles = [SessionPreKeyBundle]()
                    for device in devices {
                        guard
                            let registrationId = device["registrationId"].uInt32,
                            let deviceId = device["deviceId"].int32 else {
                                throw LibRelayError.internalError(why: "malformed prekeys bundle")
                        }
                        guard
                            let preKeyId = device["preKey"]["keyId"].uInt32,
                            let preKeyBase64 = device["preKey"]["publicKey"].string,
                            let preKey = Data(base64Encoded: preKeyBase64) else {
                                throw LibRelayError.internalError(why: "invalid prekey")
                        }
                        guard
                            let signedPreKeyId = device["signedPreKey"]["keyId"].uInt32,
                            let signedPreKeyBase64 = device["signedPreKey"]["publicKey"].string,
                            let signedPreKey = Data(base64Encoded: signedPreKeyBase64),
                            let signatureBase64 = device["signedPreKey"]["signature"].string,
                            let signature = Data(base64Encoded: signatureBase64) else {
                                throw LibRelayError.internalError(why: "invalid signed prekey")
                        }
                        bundles.append(SessionPreKeyBundle(
                            registrationId: registrationId,
                            deviceId: deviceId,
                            preKeyId: preKeyId,
                            preKey: preKey,
                            signedPreKeyId: signedPreKeyId,
                            signedPreKey: signedPreKey,
                            signature: signature,
                            identityKey: identityKey))
                    }
                    return bundles
                } else {
                    throw LibRelayError.requestRejected(why: json)
                }
        }
        /*
        res.identityKey = relay.util.StringView.base64ToBytes(res.identityKey);
        for (const device of res.devices) {
            if (!validateResponse(device, {signedPreKey: 'object'}) ||
                !validateResponse(device.signedPreKey, {publicKey: 'string', signature: 'string'})) {
                throw new Error("Invalid signedPreKey");
            }
            if (device.preKey) {
                if (!validateResponse(device, {preKey: 'object'}) ||
                    !validateResponse(device.preKey, {publicKey: 'string'})) {
                    throw new Error("Invalid preKey");
                }
                device.preKey.publicKey = relay.util.StringView.base64ToBytes(device.preKey.publicKey);
            }
            device.signedPreKey.publicKey = relay.util.StringView.base64ToBytes(device.signedPreKey.publicKey);
            device.signedPreKey.signature = relay.util.StringView.base64ToBytes(device.signedPreKey.signature);
        }
        return res;
        */
    }

    private func authHeader() -> [String: String] {
        if username != nil && password != nil {
            let up64 = "\(username!):\(password!)".data(using: .utf8)!.base64EncodedString()
            let auth = "Basic " + up64
            return ["Authorization": auth]
        } else {
            return [:]
        }
    }
    
    /// Internal: Basic Atlas http request that returns a `Promise` of `(statuscode, JSON)`
    private func request(_ call: ServerCall, urlParameters: String = "", method: HTTPMethod = .get, parameters: Parameters? = nil) -> Promise<(Int, JSON)> {
        guard serverUrl != nil else {
            return Promise(error: LibRelayError.internalError(why: "No signal server url available."))
        }
        
        return Promise { seal in
            let headers = authHeader()
            Alamofire.request("\(serverUrl!)\(call.rawValue)\(urlParameters)", method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                // .debugLog()
                .responseJSON { response in
                    let statusCode = response.response?.statusCode ?? 500
                    switch response.result {
                    case .success(let data):
                        let json = JSON(data)
                        seal.fulfill((statusCode, json))
                    case .failure(let error):
                        return seal.reject(LibRelayError.requestFailure(why: error))
                    }
            }
        }
    }
    
    enum ServerCall: String {
        case accounts = "/v1/accounts"
        case devices = "/v1/devices"
        case keys = "/v2/keys"
        case messages = "/v1/messages"
        case attachment = "/v2/attachments"
    }
    
}
