//
//  SignalClient.swift
//  LibSignalSwift
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
public class SignalClient {
    let crypto = SignalCommonCrypto()
    var atlasClient: AtlasClient
    var store: SignalStore

    var kvstore: KVStorageProtocol {
        get {
            return self.atlasClient.kvstore
        }
    }
    var serverUrl: String?
    var signalServerUsername: String?
    var password: String?
    
    ///
    /// Initialize this Signal client.
    ///
    /// - parameters:
    ///     - atlasClient: the associated AtlasClient for this SignalClient
    ///
    public init(atlasClient: AtlasClient) throws {
        self.atlasClient = atlasClient
        let kv = atlasClient.kvstore
        self.serverUrl = kv.get(DNK.ssUrl)
        self.signalServerUsername = kv.get(DNK.ssUsername)
        self.password = kv.get(DNK.ssPassword)
        self.store = try SignalStore(
            identityKeyStore: ForstaIdentityKeyStore(kvstore: kv),
            preKeyStore: ForstaPreKeyStore(kvstore: kv),
            sessionStore: ForstaSessionStore(kvstore: kv),
            signedPreKeyStore: ForstaSignedPreKeyStore(kvstore: kv),
            senderKeyStore: nil)
    }
    
    /// Retrieve my address from the kvstore (or return nil if not available)
    public func myAddress() -> SignalAddress? {
        guard let address = self.kvstore.get(DNK.ssSignalAddress) as SignalAddress? else {
            return nil
        }
        return address
    }

    private func generatePassword() throws -> String {
        return try String(crypto.random(bytes: 16).base64EncodedString().dropLast(2))
    }
    
    private func generateSignalingKey() throws -> Data {
        return try crypto.random(bytes: 32 + 20)
    }
    
    private class ProvisioningCipher {
        var keyPair: KeyPair?
        
        func getPublicKey() throws -> Data {
            if keyPair == nil { self.keyPair = try Signal.generateIdentityKeyPair() }
            return self.keyPair!.publicKey
        }
    }
    
    /*
    public func registerDevice() -> Promise<Void> {
        let provisioningCipher = ProvisioningCipher()
        var pubKey: String? = nil
        
        return firstly {
            pubKey = (try provisioningCipher.getPublicKey()).base64EncodedString()
            return self.atlasClient.getDevices()
        }
            .map { devices in
                if devices.count == 0 {
                    throw ForstaError(.requestRejected, JSON(["error": "No existing devices, use registerAccount()."]))
                }
                return try provisioningCipher.getPublicKey()
            }
            .done { pubKey in
                return pubKey
        }
        return Promise<Void>(error: ForstaError(.unknown, "wut"))
    }
 */
    
    /// Create a new identity key and create or replace the signal account.
    /// Note that any existing devices asssociated with your account will be
    /// purged as a result of this action.  This should only be used for new
    /// accounts or when you need to start over.
    ///
    /// - parameter name: The public name to store in the Signal server.
    /// - returns: A Promise to indicate completion or an error condition
    public func registerAccount(name: String) -> Promise<Void> {
        var signalingKey: Data
        var signalServerPassword: String
        var registrationId: UInt32
        do {
            signalingKey = try generateSignalingKey()
            signalServerPassword = try generatePassword()
            registrationId = try Signal.generateRegistrationId()
        } catch let error {
            return Promise.init(error: ForstaError("Unable to generate random bits for account registration.", cause: error))
        }
        
        return firstly { () -> Promise<JSON> in
            let data: [String: Any] = [
                "name": name,
                "password": signalServerPassword,
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
                    let userId = UUID(uuidString: result["userId"].stringValue),
                    let deviceId = result["deviceId"].uInt32 else {
                        throw ForstaError(.malformedResponse, "unexpected result from provisionAccount")
                }
                
                let mySignalAddress = SignalAddress(userId: userId, deviceId: deviceId)
                
                let identity = try Signal.generateIdentityKeyPair()
                self.store.forstaIdentityKeyStore.setIdentityKeyPair(identity: identity)
                if !self.store.forstaIdentityKeyStore.save(identity: identity.publicKey, for: SignalAddress(userId: userId, deviceId: deviceId)) {
                    throw ForstaError(.storageError, "unable to store self identity key")
                }
                self.store.forstaIdentityKeyStore.setLocalRegistrationId(id: registrationId)

                self.kvstore.set(DNK.ssUrl, serverUrl)
                self.serverUrl = serverUrl
                self.kvstore.set(DNK.ssUsername, mySignalAddress.description)
                self.signalServerUsername = mySignalAddress.description
                self.kvstore.set(DNK.ssPassword, signalServerPassword)
                self.password = signalServerPassword
                
                self.kvstore.set(DNK.ssSignalAddress, mySignalAddress)
                self.kvstore.set(DNK.ssName, name)
                self.kvstore.set(DNK.ssSignalingKey, signalingKey)
            }
            .then {
                self.genKeystuffBundle()
            }
            .then { bundle in
                self.request(.keys, method: .put, parameters: bundle)
            }
            .map { (code, json) in
                if code == 204 { return }
                throw ForstaError(.requestFailure, "problem performing registerAccount: \(code), \(json)")
        }
    }
    
    private func genKeystuffBundle() -> Promise<[String: Any]> {
        do {
            guard let identity = self.store.identityKeyStore.identityKeyPair() else {
                throw ForstaError(.storageError, "unable to retrieve self identity")
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
    
    
    /// Request delivery of an encrypted message to a specific device
    func deliverToDevice(address: SignalAddress, messageBundle: [String: Any]) -> Promise<(Int, JSON)> {
        return self.request(
            .messages,
            urlParameters: "/\(address.name)/\(address.deviceId)",
            method: .put,
            parameters: messageBundle)
    }
    
    /// Request delivery of an encrypted message to all of a user's devices
    func deliverToUser(userId: UUID, messageBundles: [[String: Any]]) -> Promise<(Int, JSON)> {
        guard messageBundles.count > 0,
            let timestamp = messageBundles[0]["timestamp"] as? UInt64 else {
                return Promise<(Int, JSON)>(error: ForstaError(.requestRejected, JSON(["message": "malformed message bundles, no timestamp available"])))
        }
        let parameters: [String: Any] = [
            "messages": messageBundles,
            "timestamp": timestamp
        ]
        return self.request(
            .messages,
            urlParameters: "/\(userId.lcString)",
            method: .put,
            parameters: parameters)
    }
    
    /// Get prekey bundle for a specific device
    func getKeysForAddr(_ addr: SignalAddress) -> Promise<[SessionPreKeyBundle]> {
        return getKeysForAddr(addr: addr.name, deviceId: UInt32(addr.deviceId))
    }
    
    /// Get prekey bundles for address (either all devices for the address, or only a specific device)
    func getKeysForAddr(addr: String, deviceId: UInt32? = nil) -> Promise<[SessionPreKeyBundle]> {
        let deviceStr = deviceId == nil ? "*" : String(deviceId!)
        return self.request(.keys, urlParameters: "/\(addr)/\(deviceStr)")
            .map { (statusCode, json) in
                if statusCode == 200 {
                    guard
                        let devices = json["devices"].array,
                        let identityKeyBase64 = json["identityKey"].string,
                        let identityKey = Data(base64Encoded: identityKeyBase64) else {
                            throw ForstaError(.malformedResponse, "identitykey data decoding problem")
                    }
                    var bundles = [SessionPreKeyBundle]()
                    for device in devices {
                        guard
                            let registrationId = device["registrationId"].uInt32,
                            let deviceId = device["deviceId"].int32 else {
                                throw ForstaError(.malformedResponse, "no prekeys bundle deviceId")
                        }
                        guard
                            let preKeyId = device["preKey"]["keyId"].uInt32,
                            let preKeyBase64 = device["preKey"]["publicKey"].string,
                            let preKey = Data(base64Encoded: preKeyBase64) else {
                                throw ForstaError(.malformedResponse, "invalid prekey")
                        }
                        guard
                            let signedPreKeyId = device["signedPreKey"]["keyId"].uInt32,
                            let signedPreKeyBase64 = device["signedPreKey"]["publicKey"].string,
                            let signedPreKey = Data(base64Encoded: signedPreKeyBase64),
                            let signatureBase64 = device["signedPreKey"]["signature"].string,
                            let signature = Data(base64Encoded: signatureBase64) else {
                                throw ForstaError(.malformedResponse, "invalid signed prekey")
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
                    throw ForstaError(.requestRejected, json)
                }
        }
    }

    /// Internal: Generate authorization header for Signal Server requests
    private func authHeader() -> [String: String] {
        if signalServerUsername != nil && password != nil {
            let up64 = "\(signalServerUsername!):\(password!)".data(using: .utf8)!.base64EncodedString()
            let auth = "Basic " + up64
            return ["Authorization": auth]
        } else {
            return [:]
        }
    }
    
    /// Internal: Basic Signal Server http request that returns a `Promise` of `(statuscode, JSON)`
    private func request(_ call: ServerCall, urlParameters: String = "", method: HTTPMethod = .get, parameters: Parameters? = nil) -> Promise<(Int, JSON)> {
        guard serverUrl != nil else {
            return Promise(error: ForstaError(.configuration, "No signal server url available."))
        }
        
        return Promise { seal in
            let headers = authHeader()
            Alamofire.request("\(serverUrl!)\(call.rawValue)\(urlParameters)", method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { response in
                    let statusCode = response.response?.statusCode ?? 500
                    switch response.result {
                    case .success(let data):
                        let json = JSON(data)
                        seal.fulfill((statusCode, json))
                    case .failure(let error):
                        return seal.reject(ForstaError(.requestFailure, cause: error))
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
