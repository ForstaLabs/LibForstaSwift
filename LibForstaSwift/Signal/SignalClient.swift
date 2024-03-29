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
    // -MARK: Attributes
    
    /// The registered delegates for this Atlas client
    public let delegates = Delegates<SignalClientDelegate>()
    
    var atlasClient: AtlasClient
    var store: SignalStore
    
    var kvstore: KVStorageProtocol {
        get { return self.atlasClient.kvstore }
    }
    
    /// URL that Atlas gave us to use to reach our Signal server
    var serverUrl: String? {
        get { return _serverUrl.value }
        set(value) { _serverUrl.value = value }
    }
    private var _serverUrl: KVBacked<String>
    
    /// Our full Signal address (user ID & device ID)
    public var signalAddress: SignalAddress? {
        get { return _signalAddress.value }
        set(value) { _signalAddress.value = value }
    }
    private var _signalAddress: KVBacked<SignalAddress>
    
    /// The username that Signal server knows us as (currently it is the .description string of our SignalAddress)
    var signalServerUsername: String? {
        get { return _signalServerUsername.value }
        set(value) { _signalServerUsername.value = value }
    }
    private var _signalServerUsername: KVBacked<String>
    
    /// The random password we gave Signal server to authenticate future API calls
    var signalServerPassword: String? {
        get { return _signalServerPassword.value }
        set(value) { _signalServerPassword.value = value }
    }
    private var _signalServerPassword: KVBacked<String>
    
    /// The random secret we shared with Signal server for encrypting websocket traffic
    var signalingKey: Data? {
        get { return _signalingKey.value }
        set(value) { _signalingKey.value = value }
    }
    private var _signalingKey: KVBacked<Data>
    
    /// The public label we provided during Signal server registration for this device
    public var deviceLabel: String? {
        get { return _deviceLabel.value }
        set(value) { _deviceLabel.value = value }
    }
    private var _deviceLabel: KVBacked<String>
    
    // -MARK: Constructors
    
    ///
    /// Initialize this Signal client.
    ///
    /// - parameters:
    ///     - atlasClient: the associated AtlasClient for this SignalClient
    ///
    public init(atlasClient: AtlasClient) throws {
        self.atlasClient = atlasClient
        let kv = atlasClient.kvstore
        
        self._serverUrl = KVBacked(kvstore: kv, key: DNK.ssUrl)
        self._signalAddress = KVBacked(kvstore: kv, key: DNK.ssSignalAddress)
        self._signalServerUsername = KVBacked(kvstore: kv, key: DNK.ssUsername)
        self._signalServerPassword = KVBacked(kvstore: kv, key: DNK.ssPassword)
        self._signalingKey = KVBacked(kvstore: kv, key: DNK.ssSignalingKey)
        self._deviceLabel = KVBacked(kvstore: kv, key: DNK.ssDeviceLabel)
        
        self.store = try SignalStore(
            identityKeyStore: ForstaIdentityKeyStore(kvstore: kv),
            preKeyStore: ForstaPreKeyStore(kvstore: kv),
            sessionStore: ForstaSessionStore(kvstore: kv),
            signedPreKeyStore: ForstaSignedPreKeyStore(kvstore: kv),
            senderKeyStore: nil)
    }
    
    // -MARK: Registration
    
    ///
    /// Create a new identity key and create or replace the Signal server account.
    /// *Note that any existing devices asssociated with your account will be
    /// purged as a result of this action.  This should only be used for new
    /// accounts or when you need to start over.*
    ///
    /// - parameter deviceLabel: The public device name to store in the Signal server
    /// - returns: A Promise to indicate completion or an error condition
    ///
    public func registerAccount(deviceLabel: String) -> Promise<Void> {
        self.deviceLabel = deviceLabel
        var registrationId: UInt32
        
        do {
            signalingKey = try generateSignalingKey()
            signalServerPassword = try generatePassword()
            registrationId = try Signal.generateRegistrationId()
        } catch let error {
            return Promise.init(error: ForstaError("Unable to generate random bits for account registration.", cause: error))
        }
        
        return firstly { () -> Promise<JSON> in
            if self.signalingKey == nil { throw ForstaError(.configuration, "Signaling key not available.") }
            
            let data: [String: Any] = [
                "name": deviceLabel,
                "password": signalServerPassword!,
                "registrationId": registrationId,
                "signalingKey": self.signalingKey!.base64EncodedString(),
                "fetchesMessages": true,
                "supportsSms": false,
            ]
            
            return self.atlasClient.provisionSignalAccount(data)
        }
        .map(on: ForstaClient.workQueue) { result in
            guard
                let serverUrl = result["serverUrl"].string,
                let userId = UUID(uuidString: result["userId"].stringValue),
                let deviceId = result["deviceId"].uInt32 else {
                    throw ForstaError(.malformedResponse, "unexpected result from provisionAccount")
            }
            
            self.signalAddress = SignalAddress(userId: userId, deviceId: deviceId)
            self.serverUrl = serverUrl
            self.signalServerUsername = self.signalAddress?.description
            
            let identity = try Signal.generateIdentityKeyPair()
            self.store.forstaIdentityKeyStore.setIdentityKeyPair(identity: identity)
            if !self.store.forstaIdentityKeyStore.save(identity: identity.publicKey, for: SignalAddress(userId: userId, deviceId: deviceId)) {
                throw ForstaError(.storageError, "unable to store self identity key")
            }
            self.store.forstaIdentityKeyStore.setLocalRegistrationId(id: registrationId)
        }
        .then(on: ForstaClient.workQueue) {
            self.genKeystuffBundle()
        }
        .then(on: ForstaClient.workQueue) { bundle in
            self.request(.keys, method: .put, parameters: bundle)
        }
        .map(on: ForstaClient.workQueue) { (code, json) in
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
    
    ///
    /// Register a new device with an existing Signal server account.
    /// This uses Forsta's "autoprovisioning" procedure to
    /// safely transfer the private key information from a user's
    /// existing device to this new one.
    ///
    /// - parameter deviceLabel: This device's public name to store in the Signal server.
    /// - returns: An `AutoprovisionTask` that the caller can then wait
    ///            to `.complete` (a `Promise<Void>`), or optionally `.cancel()`.
    ///
    public func registerDevice(deviceLabel: String) -> AutoprovisionTask {
        return AutoprovisionTask(deviceLabel: deviceLabel, signalClient: self)
    }
    
    ///
    /// Respond positively to a provision request from a new foreign device.
    /// *WARNING: This will deliver your private identity key to the
    ///           requesting device!*
    ///
    /// - parameters:
    ///     - uuidString: the UUID (string-encoded) provided for provisioning
    ///     - ephemeralPublicKey: the ephemeral public key (33 bytes) provided by the new device
    ///     - userAgent: our own user agent string
    ///
    /// - returns: A `Promise<Bool>` that resolves upon completion.
    ///            (A resolution of `true` means our information was used;
    ///            `false` means another device handled it first.)
    ///
    public func linkDevice(uuidString: String, ephemeralPublicKey: Data, userAgent: String = "LibRelaySwift") -> Promise<Bool> {
        let ourIdentity = self.store.identityKeyStore.identityKeyPair()
        let ourAddress = self.signalAddress
        
        return
            self.request(.devices, urlParameters: "/provisioning/code")
            .then(on: ForstaClient.workQueue) { result -> Promise<(Int, JSON)> in
                let (code, json) = result
                if code != 200 {
                    throw ForstaError(.requestRejected, json)
                }
                if ourIdentity == nil || ourAddress == nil {
                    throw ForstaError(.configuration, "identity or address not available")
                }
                
                var message = Signal_ProvisionMessage()
                message.identityKeyPrivate = ourIdentity!.privateKey
                message.addr = ourAddress!.userId.lcString
                message.userAgent = userAgent
                message.provisioningCode = json["verificationCode"].stringValue
                
                let provisioningCipher = ProvisioningCipher()
                let (body, myEphemeralPublicKey) = try provisioningCipher.encrypt(theirPublicKey: ephemeralPublicKey,
                                                                                  plaintext: message.serializedData())
                var envelope = Signal_ProvisionEnvelope()
                envelope.body = body
                envelope.publicKey = myEphemeralPublicKey
                
                return self.request(.provisioning, urlParameters: "/\(uuidString)", method: .put,
                                    parameters: ["body": try envelope.serializedData().base64EncodedString()])
        }
        .map(on: ForstaClient.workQueue) { result in
            let (code, json) = result
            
            let handledByMe = code == 204
            
            // 404 means someone else handled it already.
            if !handledByMe && code != 404 {
                throw ForstaError(.requestRejected, json)
            }
            
            return handledByMe
        }
    }
    
    ///  Delete a device associated with the current Signal server account.
    public func deleteDevice(deviceId: UInt32) -> Promise<Void> {
        return
            self.request(.devices, urlParameters: "/\(deviceId)", method: .delete)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 204 { return }
                throw ForstaError(.requestRejected, json)
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
        let timestamp = messageBundles.count > 0
            ? messageBundles[0]["timestamp"] as? UInt64 ?? Date.timestamp.millisecondsSince1970
            : Date.timestamp.millisecondsSince1970
        
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
    
    /// Download an (encrypted) attachment by Signal attachment ID
    func downloadEncryptedAttachment(id: UInt64) -> Promise<Data> {
        return self.request(.attachment, urlParameters: "/\(id)", queue: ForstaClient.bgQueue)
            .map(on: ForstaClient.workQueue) { (code, json) in
                if code < 300 { return json["location"].stringValue }
                throw ForstaError(.requestRejected, json)
        }
        .then(on: ForstaClient.bgQueue) { location in
            self.request(location, headers: ["Content-Type": "application/octet-stream"])
        }
        .map(on: ForstaClient.bgQueue) { (code, data) in
            if code < 300 { return data }
            throw ForstaError(.requestRejected, String(data: data, encoding: .utf8)!)
        }
    }
    
    /// Upload an (encrypted) attachment
    func uploadEncryptedAttachment(body: Data) -> Promise<UInt64> {
        var id: UInt64?
        
        return self.request(.attachment)
            .map(on: ForstaClient.bgQueue) { (code, json) -> JSON in
                if code < 300 { return json }
                throw ForstaError(.requestRejected, json)
        }
        .then(on: ForstaClient.bgQueue) { json -> Promise<(Int, String)> in
            guard
                let theId = json["id"].uInt64,
                let location = json["location"].string else {
                    throw ForstaError(.requestRejected, "missing required elements from attachments endpoint response")
            }
            id = theId
            
            return self.request(location, data: body, headers: ["Content-Type": "application/octet-stream"])
        }
        .map(on: ForstaClient.bgQueue) { (code, string) in
            if code < 300 { return id! }
            throw ForstaError(.requestRejected, "\(code): \(string)")
        }
    }
    
    /// Download an attachment (uses an `AttachmentInfo` `.id` for retrieval and `.key` for decryption)
    public func downloadAttachment(_ attachmentInfo: AttachmentInfo) -> Promise<Data> {
        return self.downloadEncryptedAttachment(id: attachmentInfo.id)
            .map(on: ForstaClient.workQueue) { data in try SignalCommonCrypto.decryptAttachment(data: data, keys: attachmentInfo.key) }
            .map(on: ForstaClient.workQueue) { data in
                let hash = try SignalCommonCrypto.sha512(for: data)
                if attachmentInfo.hash != nil && hash != attachmentInfo.hash {
                    throw ForstaError(.invalidHash)
                }
                return data
        }
    }
    
    /// Upload an attachment (returns an `AttachmentInfo` with `.id` for later retrieval and `.key` for decryption)
    public func uploadAttachment(data: Data, name: String, type: String, mtime: Date) -> Promise<AttachmentInfo> {
        do {
            let keys = try SignalCommonCrypto.random(bytes: 64)
            let iv = try SignalCommonCrypto.random(bytes: 16)
            let encrypted = try SignalCommonCrypto.encryptAttachment(data: data, keys: keys, iv: iv)
            let hash = try SignalCommonCrypto.sha512(for: data)
            
            return self.uploadEncryptedAttachment(body: encrypted)
                .map(on: ForstaClient.workQueue) { id in AttachmentInfo(name: name, size: data.count, type: type, mtime: mtime, hash: hash, id: id, key: keys) }
        } catch let error {
            return Promise<AttachmentInfo>.init(error: ForstaError("unable to prepare for upload", cause: error))
        }
    }
    
    
    
    /// Get prekey bundle for a specific device
    func getKeysForAddr(_ addr: SignalAddress) -> Promise<[SessionPreKeyBundle]> {
        return getKeysForAddr(addr: addr.name, deviceId: UInt32(addr.deviceId))
    }
    
    /// Get prekey bundles for address (either all devices for the address, or only a specific device)
    func getKeysForAddr(addr: String, deviceId: UInt32? = nil) -> Promise<[SessionPreKeyBundle]> {
        let deviceStr = deviceId == nil ? "*" : String(deviceId!)
        return self.request(.keys, urlParameters: "/\(addr)/\(deviceStr)")
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
    
    // Register for push notifications
    public func registerForPushNotifications(pushToken: String, voipToken: String = "") -> Promise<Void> {
        let fields:[String: Any] = [
            "apnRegistrationId" : pushToken,
            "voipRegistrationId" : voipToken
        ]
        return request(.accounts,
                       urlParameters: "/apn",
                       method: .put,
                       parameters: fields,
                       queue: ForstaClient.workQueue)
            .map { (_, _) in /* just signal success */ }
    }
    
    /// Internal: Generate authorization header for Signal Server requests
    private func authHeader() -> [String: String] {
        if signalServerUsername != nil && signalServerPassword != nil {
            let up64 = "\(signalServerUsername!):\(signalServerPassword!)".data(using: .utf8)!.base64EncodedString()
            let auth = "Basic " + up64
            return ["Authorization": auth]
        } else {
            return [:]
        }
    }
    
    /// Internal: Basic Signal Server http request
    private func request(_ call: ServerCall,
                         urlParameters: String = "",
                         method: HTTPMethod = .get,
                         parameters: Parameters? = nil,
                         queue: DispatchQueue = ForstaClient.workQueue) -> Promise<(Int, JSON)> {
        guard serverUrl != nil else {
            return Promise(error: ForstaError(.configuration, "No signal server url available."))
        }
        
        return Promise { seal in
            queue.async {
                let headers = self.authHeader()
                Alamofire.request("\(self.serverUrl!)\(call.rawValue)\(urlParameters)", method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                    .responseJSON(queue: ForstaClient.workQueue) { response in
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
    }
    
    /// Internal: Basic http request to send raw data
    private func request(_ url: String,
                         data: Data,
                         headers: [String: String]? = nil,
                         queue: DispatchQueue = ForstaClient.workQueue) -> Promise<(Int, String)> {
        return Promise { seal in
            queue.async {
                Alamofire.upload(data, to: url, method: .put, headers: headers)
                    // .uploadProgress { progress in print("uploading:", progress) }
                    .responseString { response in
                        let statusCode = response.response?.statusCode ?? 500
                        switch response.result {
                        case .success(let str):
                            seal.fulfill((statusCode, str))
                        case .failure(let error):
                            return seal.reject(ForstaError(.requestFailure, cause: error))
                        }
                }
            }
        }
    }
    
    /// Internal: Basic http request to fetch raw data
    private func request(_ url: String,
                         headers: [String: String]? = nil,
                         parameters: [String: Any]? = nil,
                         queue: DispatchQueue = ForstaClient.workQueue) -> Promise<(Int, Data)> {
        return Promise { seal in
            queue.async {
                Alamofire.request(url, method: .get, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                    // .downloadProgress { progress in print("downloading:", progress) }
                    .responseData { response in
                        let statusCode = response.response?.statusCode ?? 500
                        switch response.result {
                        case .success(let data):
                            seal.fulfill((statusCode, data))
                        case .failure(let error):
                            return seal.reject(ForstaError(.requestFailure, cause: error))
                        }
                }
            }
        }
    }
    
    // -MARK: Utilities
    
    /// URL for the Signal server encrypted messaging socket
    func messagingSocketUrl() throws -> String {
        guard self.serverUrl != nil, self.signalServerUsername != nil, self.signalServerPassword != nil else {
            throw ForstaError(.configuration , "no server url, username, or password")
        }
        return "\(self.serverUrl!)/v1/websocket/?login=\(self.signalServerUsername!)&password=\(self.signalServerPassword!)"
    }
    
    /// URL for the Signal server provisioning socket
    func provisioningSocketUrl() throws -> String {
        guard self.serverUrl != nil else {
            throw ForstaError(.configuration , "no server url")
        }
        return "\(self.serverUrl!)/v1/websocket/provisioning/"
    }
    
    private func generatePassword() throws -> String {
        return try String(SignalCommonCrypto.random(bytes: 16).base64EncodedString().dropLast(2))
    }
    
    private func generateSignalingKey() throws -> Data {
        return try SignalCommonCrypto.random(bytes: 32 + 20)
    }
    
    // -MARK: Related Subtypes
    
    private class ProvisioningCipher {
        private var keyPair: KeyPair?
        
        func getPublicKey() throws -> Data {
            if keyPair == nil { self.keyPair = try Signal.generateIdentityKeyPair() }
            return self.keyPair!.publicKey
        }
        
        func decrypt(publicKey: Data, message: Data) throws -> Data {
            if keyPair == nil { throw SignalError.invalidKey }
            
            let version = message[0]
            let iv = message[1...16]
            let ivAndCyphertext = message[...(message.count-33)]
            let ciphertext = message[17...(message.count-33)]
            let mac = message[(message.count-32)...]
            
            if version != 1 { throw SignalError.invalidVersion }
            
            let ecRes = try SignalCommonCrypto.calculateAgreement(publicKeyData: publicKey.dropFirst(), privateKeyData: self.keyPair!.privateKey)
            let keys = try SignalCommonCrypto.deriveSecrets(input: ecRes, info: "TextSecure Provisioning Message".toData())
            try SignalCommonCrypto.verifyMAC(data: ivAndCyphertext, key: keys[1], expectedMAC: mac)
            let plaintext = try SignalCommonCrypto.decrypt(message: ciphertext, key: keys[0], iv: iv)
            
            return plaintext
        }
        
        public func encrypt(theirPublicKey: Data, plaintext: Data) throws -> (Data, Data) {
            let ourKeyPair = try Signal.generateIdentityKeyPair()
            let sharedSecret = try SignalCommonCrypto.calculateAgreement(publicKeyData: theirPublicKey.dropFirst(), privateKeyData: ourKeyPair.privateKey)
            let derivedSecret = try SignalCommonCrypto.deriveSecrets(input: sharedSecret, info: "TextSecure Provisioning Message".toData())
            let iv = try SignalCommonCrypto.random(bytes: 16)
            let encryptedMsg = try SignalCommonCrypto.encrypt(message: plaintext, key: derivedSecret[0], iv: iv)
            
            let data = Data([1]) + iv + encryptedMsg
            let mac = SignalCommonCrypto.calculateMAC(key: derivedSecret[1], data: data)
            
            return (data + mac, ourKeyPair.publicKey)
        }
    }
    
    /// Manage a requested autoprovision registration task for a new device
    public class AutoprovisionTask {
        private let provisioningCipher: ProvisioningCipher
        private let (waiter, waitSeal) = Promise<Signal_ProvisionEnvelope>.pending()
        private var userId: UUID? = nil
        private let signalClient: SignalClient
        private var wsr: WebSocketResource? = nil
        
        init(deviceLabel: String, signalClient: SignalClient) {
            self.signalClient = signalClient
            self.signalClient.deviceLabel = deviceLabel
            self.provisioningCipher = ProvisioningCipher()
            
            self.wsr = WebSocketResource(signalClient: self.signalClient, requestHandler: { request in
                if request.body == nil { self.waitSeal.reject(ForstaError(.unknown, "provisioning ws request \(request.verb) \(request.path) has no body")) }
                if request.path == "/v1/address" && request.verb == "PUT" {
                    do {
                        let proto = try Signal_ProvisioningUuid(serializedData: request.body!)
                        if !proto.hasUuid {
                            self.waitSeal.reject(ForstaError(.invalidProtoBuf, "missing provisioning uuid"))
                            return
                        }
                        self.signalClient.atlasClient.provisionSignalDevice(uuidString: proto.uuid,
                                                                            pubKeyString: try self.provisioningCipher.getPublicKey().base64EncodedString())
                            .catch { error in
                                self.waitSeal.reject(ForstaError("request to provision device failed", cause: error))
                        }
                    } catch let error {
                        self.waitSeal.reject(ForstaError("cannot decode provision uuid message", cause: error))
                    }
                } else if request.path == "/v1/message" && request.verb == "PUT" {
                    do {
                        let envelope = try Signal_ProvisionEnvelope(serializedData: request.body!)
                        self.waitSeal.fulfill(envelope)
                    } catch let error {
                        self.waitSeal.reject(ForstaError("cannot decrypt provision message", cause: error))
                    }
                } else {
                    let _ = request.respond(status: 404, message: "Not found")
                    self.waitSeal.reject(ForstaError(.unknown, "unexpected websocket request \(request.verb) \(request.path)"))
                }
            })
        }
        
        /// Cancel a device registration that is underway.
        public func cancel() {
            waitSeal.reject(ForstaError(.canceled, "registerDevice was canceled by caller"))
            wsr?.disconnect()
            wsr = nil
        }
        
        /// A `Promise<Void>` that resolves when device registration is complete.
        public var complete: Promise<Void> {
            var registrationId: UInt32
            var userId: UUID?
            
            do {
                self.signalClient.signalingKey = try self.signalClient.generateSignalingKey()
                self.signalClient.signalServerPassword = try self.signalClient.generatePassword()
                registrationId = try Signal.generateRegistrationId()
            } catch let error {
                return Promise.init(error: ForstaError("Unable to generate random bits for account registration.", cause: error))
            }
            
            return self.signalClient.atlasClient.getSignalAccountInfo()
                .then(on: ForstaClient.workQueue) { accountInfo -> Promise<Signal_ProvisionEnvelope> in
                    guard accountInfo.devices.count > 0 else {
                        throw ForstaError(ForstaError.ErrorType.configuration, "must use registerAccount for first device")
                    }
                    self.signalClient.serverUrl = accountInfo.serverUrl

                    self.wsr?.connect(url: try self.signalClient.provisioningSocketUrl())
                    userId = accountInfo.userId
                    print("(waiting on provisioning help to arrive)")
                    return self.waiter
            }
            .then(on: ForstaClient.workQueue) { envelope -> Promise<(Int, JSON)> in
                print("(provisioning help arrived)")
                let plaintext = try self.provisioningCipher.decrypt(publicKey: envelope.publicKey, message: envelope.body)
                let provisionMessage = try Signal_ProvisionMessage(serializedData: plaintext)
                let identity = try SignalCommonCrypto.generateKeyPairFromPrivateKey(privateKeyData: provisionMessage.identityKeyPrivate)
                self.signalClient.store.forstaIdentityKeyStore.setIdentityKeyPair(identity: identity)
                self.signalClient.store.forstaIdentityKeyStore.setLocalRegistrationId(id: registrationId)
                self.userId = UUID(uuidString: provisionMessage.addr)
                let expectedUserId = self.signalClient.atlasClient.authenticatedUserId
                if self.userId != expectedUserId {
                    throw ForstaError(.invalidId, "Security Violation: Foreign account sent us an identity key!")
                }
                if self.signalClient.signalingKey == nil { throw ForstaError(.configuration, "Signaling key not available.") }
                let provisioningCode = provisionMessage.provisioningCode
                
                let parms: [String: Any] = [
                    "signalingKey": self.signalClient.signalingKey!.base64EncodedString(),
                    "supportsSms": false,
                    "fetchesMessages": true,
                    "registrationId": registrationId,
                    "name": self.signalClient.deviceLabel ?? "no device label??"
                ]
                self.signalClient.signalServerUsername = self.userId!.lcString
                return self.signalClient.request(.devices,
                                                 urlParameters: "/\(provisioningCode)",
                    method: .put,
                    parameters: parms)
            }
            .map(on: ForstaClient.workQueue) { (code, json) in
                guard code == 200, let deviceId = json["deviceId"].uInt32 else {
                    throw ForstaError(.requestRejected, json)
                }
                self.signalClient.signalAddress = SignalAddress(userId: userId!, deviceId: deviceId)
                self.signalClient.signalServerUsername = self.signalClient.signalAddress?.description
                guard let myPubKey = self.signalClient.store.identityKeyStore.identityKeyPair()?.publicKey else {
                    throw ForstaError(.storageError, "unable to retrieve my identity key")
                }
                if self.signalClient.signalAddress == nil ||
                    !self.signalClient.store.forstaIdentityKeyStore.save(identity: myPubKey,
                                                                         for: self.signalClient.signalAddress!) {
                    throw ForstaError(.storageError, "unable to store self identity key")
                }
                
                self.wsr?.disconnect()
                self.wsr = nil
            }
            .then(on: ForstaClient.workQueue) { x in
                self.signalClient.genKeystuffBundle()
            }
            .then(on: ForstaClient.workQueue) { bundle in
                self.signalClient.request(.keys, method: .put, parameters: bundle)
            }
            .map(on: ForstaClient.workQueue) { (code, json) in
                if code == 204 { return }
                throw ForstaError(.requestFailure, "problem performing registerAccount: \(code), \(json)")
            }
        }
    }
    
    enum ServerCall: String {
        case accounts = "/v1/accounts"
        case devices = "/v1/devices"
        case keys = "/v2/keys"
        case messages = "/v1/messages"
        case attachment = "/v1/attachments"
        case provisioning = "/v1/provisioning"
    }
}

/// Important events for a Signal client that you can register to receive
public protocol SignalClientDelegate: class {
    /// An identity key changed on an incoming message
    func identityKeyChanged(address: SignalAddress)
    /// Incoming delivery receipt
    func deliveryReceipt(receipt: DeliveryReceipt)
    /// Incoming message
    func inboundMessage(message: InboundMessage)
    /// Incoming read receipts
    func syncReadReceipts(receipts: [SyncReadReceipt])
    /// Incoming queue is now empty
    func queueEmpty()
    /// Websocket connection to the Signal Server established
    func connected()
    /// Websocket connection to the Signal Server ended
    func disconnected(error: Error?)
}
extension SignalClientDelegate {
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func identityKeyChanged(address: SignalAddress) { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func deliveryReceipt(receipt: DeliveryReceipt) { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func inboundMessage(message: InboundMessage) { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func syncReadReceipts(receipts: [SyncReadReceipt]) { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func queueEmpty() { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func connected() { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    public func disconnected(error: Error?) { }
}
