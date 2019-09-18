//
//  SignalCommonCrypto.swift
//  SignalProtocolSwift
//
//  Created by User on 11.11.17.
//  Copyright © 2017 User. All rights reserved.
//

import Foundation
import CommonCrypto
import SignalProtocol

/// `SignalCommonCrypto` struct adopted from the
/// [LibSignalProtocolSwift](https://github.com/christophhagen/LibSignalProtocolSwift)
/// project (lightly modified)
public struct SignalCommonCrypto {
    /**
     Create a number of random bytes
     - parameter bytes: The number of random bytes to create
     - returns: An array of `bytes` length with random numbers
     - throws: `SignalError.noRandomBytes`
     */
    static public func random(bytes: Int) throws -> Data {
        let random = [UInt8](repeating: 0, count: bytes)
        let result = SecRandomCopyBytes(nil, bytes, UnsafeMutableRawPointer(mutating: random))

        guard result == errSecSuccess else {
            throw ForstaError(.noRandomBytes, "Error getting random bytes: \(result)")
        }
        return Data(random)
    }

    /**
     Create a HMAC authentication for a given message
     - parameter message: The input message to create the HMAC for
     - parameter salt: The salt for the HMAC
     - returns: The HMAC
     */
    static public func hmacSHA256(for message: Data, with salt: Data) -> Data {
        var context = CCHmacContext()

        let bytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeMutablePointer(to: &context) { (ptr: UnsafeMutablePointer<CCHmacContext>) in
            // Pointer to salt
            salt.withUnsafeBytes { ptr2 in
                let saltPtr = ptr2.baseAddress!
                // Pointer to message
                message.withUnsafeBytes { ptr3 in
                    let messagePtr = ptr3.baseAddress!
                    // Authenticate
                    CCHmacInit(ptr, CCHmacAlgorithm(kCCHmacAlgSHA256), saltPtr, salt.count)
                    CCHmacUpdate(ptr, messagePtr, message.count)
                    CCHmacFinal(ptr, UnsafeMutableRawPointer(mutating: bytes))
                }
            }
        }

        return Data(bytes)
    }

    /**
     Create a SHA512 digest for a given message
     - parameter message: The input message to create the digest for
     - returns: The digest
     - throws: `SignalError.digestError`
     */
    static public func sha512(for message: Data) throws -> Data {
        guard message.count > 0 else {
            throw ForstaError(.invalidMessage, "Message length is 0")
        }
        var context = CC_SHA512_CTX()
        return try withUnsafeMutablePointer(to: &context) { contextPtr in
            CC_SHA512_Init(contextPtr)
            // Pointer to message
            let result: Int32 = message.withUnsafeBytes {ptr2 in
                let messagePtr = ptr2.baseAddress!
                return CC_SHA512_Update(contextPtr, messagePtr, CC_LONG(message.count))
            }
            guard result == 1 else {
                throw ForstaError(.digestError, "Error on SHA512 Update: \(result)")
            }
            var md = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
            let result2: Int32 = md.withUnsafeMutableBytes { ptr4 in
                let a = ptr4.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return CC_SHA512_Final(a, contextPtr)
            }
            guard result2 == 1 else {
                throw ForstaError(.digestError, "Error on SHA512 Final: \(result)")
            }
            return md
        }
    }
    
    /**
     Encrypt a message with AES
     - parameter message: The input message to encrypt
     - parameter cipher: THe encryption scheme to use
     - parameter key: The key for encryption (`kCCKeySizeAES256` bytes)
     - parameter iv: The initialization vector (`kCCBlockSizeAES128` bytes)
     - returns: The encrypted message
     - throws: `SignalError.encryptionError`
     */
    static public func encrypt(message: Data, with cipher: SignalEncryptionScheme = .AES_CBCwithPKCS5, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw ForstaError(.invalidKey, "Invalid key length")
        }
        guard message.count > 0 else {
            throw ForstaError(.invalidMessage, "Message length is 0")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw ForstaError(.invalidIV, "The length of the IV is not correct")
        }
        switch cipher {
        case .AES_CBCwithPKCS5:
            return try process(cbc: message, key: key, iv: iv, encrypt: true)
        case .AES_CTRnoPadding:
            return try encrypt(ctr: message, key: key, iv: iv)
        }
    }

    /**
     Decrypt a message with AES
     - parameter message: The input message to decrypt
     - parameter cipher: THe encryption scheme to use
     - parameter key: The key for decryption (`kCCKeySizeAES256` bytes)
     - parameter iv: The initialization vector (`kCCBlockSizeAES128` bytes)
     - returns: The decrypted message
     - throws: `SignalError.decryptionError`
     */
    static public func decrypt(message: Data, with cipher: SignalEncryptionScheme = .AES_CBCwithPKCS5, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw ForstaError(.invalidKey, "Invalid key length")
        }
        guard message.count > 0 else {
            throw ForstaError(.invalidMessage, "Message length is 0")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw ForstaError(.invalidIV, "The length of the IV is not correct")
        }
        switch cipher {
        case .AES_CBCwithPKCS5:
            return try process(cbc: message, key: key, iv: iv, encrypt: false)
        case .AES_CTRnoPadding:
            return try decrypt(ctr: message, key: key, iv: iv)
        }
    }

    // -MARK: Encryption helper functions

    /**
     Process (encrypt/decrypt) a message with AES in CBC mode and pkcs7 padding.
     - parameter message: The input message to process
     - parameter key: The key for encryption/decryption (`kCCKeySizeAES128` bytes)
     - parameter iv: The initialization vector
     - parameter encrypt: `true` if encrypting, `false` if decrypting
     - returns: The encrypted/decrypted message
     - throws: `SignalError.encryptionError`, `SignalError.decryptionError`
     */
    static private func process(cbc message: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        let operation = encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
        // Create output memory that can fit the output data
        let dataLength = message.count + kCCBlockSizeAES128
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: dataLength, alignment: MemoryLayout<UInt8>.alignment)
        defer { ptr.deallocate() }

        var dataOutMoved: Int = 0
        // Pointer to key
        let status: Int32 = key.withUnsafeBytes { ptr1 in
            let keyPtr = ptr1.baseAddress!
            // Pointer to IV
            return iv.withUnsafeBytes { ptr2 in
                let ivPtr = ptr2.baseAddress!
                // Pointer to message
                return message.withUnsafeBytes { ptr3 in
                    let messagePtr = ptr3.baseAddress!
                    // Options
                    let algorithm = CCAlgorithm(kCCAlgorithmAES)
                    let padding = CCOptions(kCCOptionPKCS7Padding)
                    // Encrypt
                    return CCCrypt(operation, algorithm, padding, keyPtr, key.count, ivPtr,
                                   messagePtr, message.count, ptr, dataLength, &dataOutMoved)
                }
            }
        }
        guard status == kCCSuccess else {
            if encrypt {
                throw ForstaError(.encryptionError, "AES (CBC mode) encryption error: \(status)")
            } else {
                throw ForstaError(.decryptionError, "AES (CBC mode) decryption error: \(status)")
            }
        }

        // Convert the pointers to data
        let typedPointer = ptr.bindMemory(to: UInt8.self, capacity: dataOutMoved)
        let typedBuffer = UnsafeMutableBufferPointer(start: typedPointer, count: dataOutMoved)
        return Data(typedBuffer)
    }

    /**
     Encrypt a message with AES in CTR mode and no padding.
     - parameter message: The input message to encrypt
     - parameter key: The key for encryption
     - parameter iv: The initialization vector
     - returns: The encrypted message
     - throws: `SignalError.encryptionError`
     */
    static private func encrypt(ctr message: Data, key: Data, iv: Data) throws -> Data {
        return try process(ctr: message, key: key, iv: iv, encrypt: true)
    }

    /**
     Decrypt a message with AES in CTR mode and no padding.
     - parameter message: The input message to decrypt
     - parameter key: The key for decryption
     - parameter iv: The initialization vector
     - returns: The decrypted message
     - throws: `SignalError.decryptionError`
     */
    static private func decrypt(ctr message: Data, key: Data, iv: Data) throws -> Data {
        return try process(ctr: message, key: key, iv: iv, encrypt: false)
    }

    /**
     Process (encrypt/decrypt) a message with AES in CTR mode and no padding.
     - parameter message: The input message to process
     - parameter key: The key for encryption/decryption
     - parameter iv: The initialization vector
     - parameter encrypt: `true` if encrypting, `false` if decrypting
     - returns: The encrypted/decrypted message
     - throws: `SignalError.encryptionError`, `SignalError.decryptionError`
     */
    static private func process(ctr message: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        var cryptoRef: CCCryptorRef? = nil
        
        var status: Int32 = key.withUnsafeBytes { ptr1 in
            let keyPtr = ptr1.baseAddress!
            // Pointer to IV
            return iv.withUnsafeBytes { ptr2 in
                let ivPtr = ptr2.baseAddress!
                let operation = encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
                let mode = CCMode(kCCModeCTR)
                let algorithm = CCAlgorithm(kCCAlgorithmAES)
                let padding = CCPadding(ccNoPadding)
                let options = CCModeOptions(kCCModeOptionCTR_BE)
                return CCCryptorCreateWithMode(
                    operation, mode, algorithm, padding, ivPtr, keyPtr, key.count,
                    nil, 0, 0, options , &cryptoRef)
            }
        }

        // Release the reference before the method returns or throws an error
        defer { CCCryptorRelease(cryptoRef) }

        guard status == kCCSuccess, let ref = cryptoRef else {
            if encrypt {
                throw ForstaError(.encryptionError, "AES (CTR mode) encryption init error: \(status)")
            } else {
                throw ForstaError(.decryptionError, "AES (CTR mode) Decryption init error: \(status)")
            }
        }

        let outputLength = CCCryptorGetOutputLength(ref, message.count, true)
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: outputLength, alignment: MemoryLayout<UInt8>.alignment)
        // Release the memory before the method returns or throws an error
        defer { ptr.deallocate() }

        var updateMovedLength = 0
        status = withUnsafeMutablePointer(to: &updateMovedLength) { updatedPtr in
            message.withUnsafeBytes { ptr3 in
                let messagePtr = ptr3.baseAddress!
                return CCCryptorUpdate(ref, messagePtr, message.count, ptr, outputLength, updatedPtr)
            }
        }
        guard updateMovedLength <= outputLength else {
            throw ForstaError(.encryptionError, "Updated bytes \(updateMovedLength) for \(outputLength) total bytes")
        }
        guard status == kCCSuccess else {
            if encrypt {
                throw ForstaError(.encryptionError, "AES (CTR mode) encryption update error: \(status)")
            } else {
                throw ForstaError(.decryptionError, "AES (CTR mode) Decryption update error: \(status)")
            }
        }

        let available = outputLength - updateMovedLength
        let ptr2 = ptr.advanced(by: updateMovedLength)
        var finalMovedLength: Int = 0
        status = withUnsafeMutablePointer(to: &finalMovedLength) {
                CCCryptorFinal(ref, ptr2, available, $0)
        }
        let finalLength = updateMovedLength + finalMovedLength
        guard status == kCCSuccess else {
            if encrypt {
                throw ForstaError(.encryptionError, "AES (CTR mode) encryption update error: \(status)")
            } else {
                throw ForstaError(.decryptionError, "AES (CTR mode) Decryption update error: \(status)")
            }
        }
        // For decryption, the final length can be less due to padding
        if encrypt && finalLength != outputLength {
            throw ForstaError(.encryptionError, "AES (CTR mode): Output length not correct \(finalLength), \(outputLength), \(updateMovedLength), \(finalMovedLength)")
        }
        return toArray(from: ptr, count: finalLength)
    }

    /**
     Create an array from an unsafe pointer.
     - parameter ptr: Pointer to initialized storage
     - parameter count: The length of the array
     - returns: The created array
    */
    static private func toArray(from ptr: UnsafeMutableRawPointer, count: Int) -> Data {
        let typedPointer = ptr.bindMemory(to: UInt8.self, capacity: count)
        let typedBuffer = UnsafeMutableBufferPointer(start: typedPointer, count: count)
        return Data(typedBuffer)
    }
}

/**
 Specifies the type of algorithm to use for encryption and decryption.
 */
public enum SignalEncryptionScheme {
    /// Encrypt/decrypt with AES in CBC mode with PKCS5 padding
    case AES_CBCwithPKCS5
    /// Encrypt/decrypt with AES in CTR mode with no padding
    case AES_CTRnoPadding
}

extension SignalCommonCrypto {
    /// Calculate a message MAC
    static func calculateMAC(key: Data, data: Data) -> Data {
        return hmacSHA256(for: data, with: key)
    }

    /// Verify a message MAC
    static public func verifyMAC(data: Data, key: Data, expectedMAC: Data) throws {
        let calculatedMAC = calculateMAC(key: key, data: data)
        if calculatedMAC[..<expectedMAC.count] != expectedMAC {
            throw ForstaError(.invalidMac)
        }
    }
    
    /// RFC 5869 key derivation
    static public func deriveSecrets(input: Data, salt: Data = Data(count: 32), info: Data, chunks: Int = 2) throws -> [Data] {
        if chunks < 1 { return [] }
        
        // Salts always end up being 32 bytes
        if salt.count != 32 {
            throw ForstaError(.invalidLength, "Got salt of incorrect length")
        }
        
        let PRK = calculateMAC(key: salt, data: input)
        var infoArray = Data(count: info.count + 1 + 32)
        infoArray.replaceSubrange(32...(infoArray.count-2), with: info)
        infoArray[infoArray.count-1] = 1
        var signed = [calculateMAC(key: PRK, data: infoArray[32...])]
        
        for i in 2...chunks {
            infoArray.replaceSubrange(...31, with: signed[i-2])
            infoArray[infoArray.count-1] = UInt8(i)
            signed.append(calculateMAC(key: PRK, data: infoArray));
        }
        
        return signed;
    }
    
    /// Calculate an ECDH agreement.
    ///
    /// - parameter publicKeyData: The curve25519 (typically remote party's) 32-byte public key data
    /// - parameter privateKeyData: The curve25519 (typically your) 32-byte private key data
    /// - returns: a 32-bit shared secret on success, throwing on failure
    static public func calculateAgreement(publicKeyData: Data, privateKeyData: Data) throws -> Data {
        return try Utility.curve25519Donna(secret: privateKeyData, basepoint: publicKeyData)
    }
    
    /// Generates a Curve25519 keypair.
    ///
    /// - parameter privateKeyData: The curve25519 (typically your) 32-byte private key data
    /// - returns: the full `KeyPair`
    static public func generateKeyPairFromPrivateKey(privateKeyData: Data) throws -> KeyPair {
        var basepoint = Data(count: 32)
        basepoint[0] = 9
        
        let pubKeyData = try Utility.curve25519Donna(secret: privateKeyData, basepoint: basepoint)
        
        return KeyPair(publicKey: Data([5]) + pubKeyData, privateKey: privateKeyData)
    }
    
    /// Decrypt attachment data
    static public func decryptAttachment(data: Data, keys: Data) throws -> Data {
        if (keys.count != 64) {
            throw ForstaError(.invalidLength, "Got invalid length attachment keys")
        }
        if (data.count < 16 + 32) {
            throw ForstaError(.invalidLength, "Got invalid length attachment")
        }
        
        let aes_key = keys[0...31]
        let mac_key = keys[32...63]
        
        let iv = data[0...15]
        let ciphertext = data[16..<(data.count-32)]
        let ivAndCiphertext = data[0..<(data.count-32)]
        let mac = data[(data.count-32)..<data.count]
        
        try verifyMAC(data: ivAndCiphertext, key: mac_key, expectedMAC: mac)
        return try decrypt(message: ciphertext, key: aes_key, iv: iv)
    }
    
    /// Encrypt attachment data
    static public func encryptAttachment(data: Data, keys: Data, iv: Data) throws -> Data {
        if (keys.count != 64) {
            throw ForstaError(.invalidLength, "Got invalid length attachment keys")
        }
        if (iv.count != 16) {
            throw ForstaError(.invalidLength, "Got invalid length attachment iv")
        }
        
        let aes_key = keys[0...31]
        let mac_key = keys[32...63]
        
        let ciphertext = try encrypt(message: data, key: aes_key, iv: iv)
        let ivAndCiphertext = iv + ciphertext

        let mac = calculateMAC(key: mac_key, data: ivAndCiphertext)
        return ivAndCiphertext + mac
    }
}
