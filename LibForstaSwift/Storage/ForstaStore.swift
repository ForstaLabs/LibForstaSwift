//
//  ForstaStore.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 5/28/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SignalProtocol

/// Default namespace storage keys
enum DNK: String, CustomStringConvertible {
    // Atlas server store keys
    /// The current JWT for authorizing Atlas calls
    case atlasCredential = "atlasCredential"
    /// The URL of the Atlas server we are authenticated against
    case atlasUrl = "atlasUrl"
    
    // Signal Server store keys
    /// URL that Atlas gave us to use to reach our Signal server
    case ssUrl = "signalServerUrl"
    /// The `SignalAddress` we have for our device on the Signal server
    case ssSignalAddress = "signalServerSignalAddress"
    /// The descriptive name we gave Signal server for this device registration
    case ssName = "signalServerName"
    /// The username that Signal server knows us as (currently it is the `.description` string of our `SignalAddress`)
    case ssUsername = "signalServerUsername"
    /// The random password we gave to Signal to authenticate future API calls
    case ssPassword = "signalServerPassword"
    /// The random secret we shared with Signal server for encrypting websocket traffic
    case ssSignalingKey = "signalServerSignalingKey"
    
    // Other
    /// Our private identity key
    case myPrivateIdentityKey = "myPrivateIdentityKey"
    /// Our public identity key
    case myPublicIdentityKey = "myPublicIdentityKey"
    /// The random registration ID we gave to the Signal server during registration
    case myRegistrationId = "myRegistrationId"
    
    /// Automatic conversion to String
    var description: String {
        return self.rawValue
    }
}

extension SignalStore {
    var forstaIdentityKeyStore: ForstaIdentityKeyStore {
        return self.identityKeyStore as! ForstaIdentityKeyStore
    }
    
    var forstaPreKeyStore: ForstaPreKeyStore {
        return self.preKeyStore as! ForstaPreKeyStore
    }
    
    var forstaSignedPreKeyStore: ForstaSignedPreKeyStore {
        return self.signedPreKeyStore as! ForstaSignedPreKeyStore
    }
    
    var kv: KVStorageProtocol {
        return self.forstaIdentityKeyStore.kvstore
    }
    
    func generateAndStorePreKeys(count: Int) throws -> [SessionPreKey] {
        var lastId = self.forstaPreKeyStore.lastId
        let preKeys = try Signal.generatePreKeys(start: lastId &+ 1, count: count)
        lastId = preKeys[preKeys.count - 1].id
        self.forstaPreKeyStore.lastId = lastId
        
        for preKey in preKeys {
            if !(try self.preKeyStore.store(preKey: preKey.data(), for: preKey.id)) {
                throw ForstaError(.storageError, "couldn't store new session prekey")
            }
        }
        
        return preKeys
    }
    
    func updateSignedPreKey() throws -> SessionSignedPreKey {
        guard let identity = self.identityKeyStore.identityKeyPair() else {
            throw ForstaError(.storageError, "couldn't retrieve self identity")
        }
        let lastPreKeyId = self.forstaPreKeyStore.lastId
        let signedPreKey = try Signal.generate(signedPreKey: lastPreKeyId, identity: identity, timestamp: 0)
        let _ = try self.forstaSignedPreKeyStore.store(signedPreKey: signedPreKey.data(), for: lastPreKeyId)
        self.forstaSignedPreKeyStore.lastId = lastPreKeyId
        
        return signedPreKey
    }
}

class ForstaIdentityKeyStore: IdentityKeyStore {
    let kvstore: KVStorageProtocol
    let ns = "IdentityKeys"
    
    init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
    }
    
    func identityKeyPair() -> KeyPair? {
        if let privateKeyData = kvstore.get(DNK.myPrivateIdentityKey), let publicKeyData = kvstore.get(DNK.myPublicIdentityKey) {
            return KeyPair(publicKey: publicKeyData, privateKey: privateKeyData)
        }

        return nil
    }
    
    func localRegistrationId() -> UInt32? {
        return kvstore.get(DNK.myRegistrationId)
    }
    
    func save(identity: Data?, for address: SignalAddress) -> Bool {
        if identity == nil {
            kvstore.remove(ns: ns, key: address)
        } else {
            kvstore.set(ns: ns, key: address, value: identity!)
        }
        
        return true
    }
    
    func isTrusted(identity: Data, for address: SignalAddress) -> Bool? {
        guard let savedIdentity = kvstore.get(ns: ns, key: address) else {
            return true // we don't have a key stored for them, so trust on first use
        }
        return savedIdentity == identity
    }
    

    // supplements to protocol
    
    func setIdentityKeyPair(identity: KeyPair?) {
        if identity != nil {
            kvstore.set(DNK.myPrivateIdentityKey, identity!.privateKey)
            kvstore.set(DNK.myPublicIdentityKey, identity!.publicKey)
        } else {
            kvstore.remove(DNK.myPrivateIdentityKey)
            kvstore.remove(DNK.myPublicIdentityKey)
        }
    }
    
    func setLocalRegistrationId(id: UInt32?) {
        if id != nil {
            kvstore.set(DNK.myRegistrationId, id!)
        } else {
            kvstore.remove(DNK.myRegistrationId)
        }
    }
}

class ForstaPreKeyStore: PreKeyStore {
    let kvstore: KVStorageProtocol
    let ns = "PreKeys"
    let lastIdKey = "LastPreKeyId"

    init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
    }
    
    func load(preKey: UInt32) -> Data? {
        return kvstore.get(ns: ns, key: preKey)
    }
    
    func store(preKey: Data, for id: UInt32) -> Bool {
        kvstore.set(ns: ns, key: id, value: preKey)
        return true
    }
    
    func contains(preKey: UInt32) -> Bool {
        return kvstore.has(ns: ns, key: preKey)
    }
    
    func remove(preKey: UInt32) -> Bool {
        kvstore.remove(ns: ns, key: preKey)
        return true
    }
    
    var lastId: UInt32 {
        get {
            return kvstore.get(lastIdKey) ?? 0
        }
        set(newValue) {
            kvstore.set(lastIdKey, newValue)
        }
    }
}

class ForstaSessionStore: SessionStore {
    let kvstore: KVStorageProtocol
    let sessionNs = "Sessions"
    let recordNs = "UserRecords"

    init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
    }
    
    func loadSession(for address: SignalAddress) -> (session: Data, userRecord: Data?)? {
        guard let session = kvstore.get(ns: sessionNs, key: address) else {
            return nil
        }
        return (session, kvstore.get(ns: recordNs, key: address))
    }
    
    func subDeviceSessions(for name: String) -> [Int32]? {
        return kvstore.keys(ns: sessionNs)
            .map { SignalAddress(description: $0) }
            .filter { $0?.name == name }
            .map { $0!.deviceId }
    }
    
    func store(session: Data, for address: SignalAddress, userRecord: Data?) -> Bool {
        kvstore.set(ns: sessionNs, key: address, value: session)
        if userRecord != nil {
            kvstore.set(ns: recordNs, key: address, value: userRecord!)
        }
        return true
    }
    
    func containsSession(for address: SignalAddress) -> Bool {
        return kvstore.has(ns: sessionNs, key: address)
    }
    
    func deleteSession(for address: SignalAddress) -> Bool? {
        let retval = kvstore.has(ns: sessionNs, key: address)
        kvstore.remove(ns: sessionNs, key: address)
        kvstore.remove(ns: recordNs, key: address)
        return retval
    }
    
    func deleteAllSessions(for name: String) -> Int? {
        return kvstore.keys(ns: sessionNs)
            .map { SignalAddress(description: $0) }
            .filter { $0?.name == name }
            .map { return deleteSession(for: $0!) }
            .count
    }
}

extension SessionStore {
    func subDeviceSessions(for userId: UUID) -> [Int32]? {
        return self.subDeviceSessions(for: userId.lcString)
    }
    func deleteAllSessions(for userId: UUID) -> Int? {
        return self.deleteAllSessions(for: userId.lcString)
    }
}

class ForstaSignedPreKeyStore: SignedPreKeyStore {
    let kvstore: KVStorageProtocol
    let ns = "SignedPreKeys"
    let lastIdKey = "LastSignedPreKeyId"

    init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
    }
    
    func load(signedPreKey: UInt32) -> Data? {
        return kvstore.get(ns: ns, key: signedPreKey)
    }
    
    func store(signedPreKey: Data, for id: UInt32) -> Bool {
        kvstore.set(ns: ns, key: id, value: signedPreKey)
        return true
    }
    
    func contains(signedPreKey: UInt32) -> Bool {
        return kvstore.has(ns: ns, key: signedPreKey)
    }
    
    func remove(signedPreKey: UInt32) -> Bool {
        kvstore.remove(ns: ns, key: signedPreKey)
        return true
    }
    
    func allIds() throws -> [UInt32] {
        return try kvstore.keys(ns: ns).map({
            guard let key = UInt32($0) else {
                throw ForstaError(.storageError, "uint32 key could not be parsed")
            }
            return key
        })
    }
    
    var lastId: UInt32 {
        get {
            return kvstore.get(lastIdKey) ?? 0
        }
        set(newValue) {
            kvstore.set(lastIdKey, newValue)
        }
    }
}
