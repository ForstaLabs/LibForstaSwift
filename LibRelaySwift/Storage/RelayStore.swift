//
//  RelayStore.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 5/28/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import SignalProtocol

/// Default namespace storage keys
enum DNK: String {
    // Atlas server store keys
    case atlasCredential = "atlasCredential"
    case atlasUrl = "atlasUrl"
    
    // Signal Server store keys
    case ssUrl = "signalServerUrl"
    case ssAddress = "signalServerAddress"
    case ssDeviceId = "signalServerDeviceId"
    case ssName = "signalServerName"
    case ssUsername = "signalServerUsername"
    case ssPassword = "signalServerPassword"
    case ssSignalingKey = "signalServerSignalingKey"
    
    // Other
    case myPrivateIdentityKey = "myPrivateIdentityKey"
    case myPublicIdentityKey = "myPublicIdentityKey"
    case myRegistrationId = "myRegistrationId"
}

extension SignalStore {
    var relayIdentityKeyStore: RelayIdentityKeyStore {
        return self.identityKeyStore as! RelayIdentityKeyStore
    }
    
    var relayPreKeyStore: RelayPreKeyStore {
        return self.preKeyStore as! RelayPreKeyStore
    }
    
    var relaySignedPreKeyStore: RelaySignedPreKeyStore {
        return self.signedPreKeyStore as! RelaySignedPreKeyStore
    }
    
    var kv: KVStorageProtocol {
        return self.relayIdentityKeyStore.kvstore
    }
    
    func generateAndStorePreKeys(count: Int) throws -> [SessionPreKey] {
        var lastId = self.relayPreKeyStore.lastId
        let preKeys = try Signal.generatePreKeys(start: lastId &+ 1, count: count)
        lastId = preKeys[preKeys.count - 1].id
        self.relayPreKeyStore.lastId = lastId
        
        for preKey in preKeys {
            if !(try self.preKeyStore.store(preKey: preKey.data(), for: preKey.id)) {
                throw LibRelayError.internalError(why: "couldn't store new session prekey")
            }
        }
        
        return preKeys
    }
    
    func updateSignedPreKey() throws -> SessionSignedPreKey {
        guard let identity = self.identityKeyStore.identityKeyPair() else {
            throw LibRelayError.internalError(why: "unable to retrieve self identity")
        }
        var lastPreKeyId = self.relayPreKeyStore.lastId
        let signedPreKey = try Signal.generate(signedPreKey: lastPreKeyId, identity: identity, timestamp: 0)
        self.relaySignedPreKeyStore.lastId = signedPreKey.id
        
        return signedPreKey
    }
}

class RelayIdentityKeyStore: IdentityKeyStore {
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

class RelayPreKeyStore: PreKeyStore {
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

class RelaySessionStore: SessionStore {
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
        return (kvstore.keys(ns: sessionNs) as! [SignalAddress])
            .filter { $0.name == name }
            .map { $0.deviceId }
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
        return (kvstore.keys(ns: sessionNs) as! [SignalAddress])
            .filter { $0.name == name }
            .map { return deleteSession(for: $0) }
            .count
    }
}

class RelaySignedPreKeyStore: SignedPreKeyStore {
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
        return kvstore.keys(ns: ns) as! [UInt32]
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
