//
//  ForstaError.swift
//  LibForstaSwift
//
//  Created by Greg Perkins on 4/24/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//
//  adapted from SignalProtocolSwift
//  Created by User on 07.10.17.
//  Copyright © 2017 User. All rights reserved.
//

import Foundation
import SwiftyJSON

/// All errors thrown by `LibForstaSwift` are `ForstaError` objects.
/// (adapted from the [LibSignalProtocolSwift](https://github.com/christophhagen/LibSignalProtocolSwift) error class)
public final class ForstaError: CustomStringConvertible, Error {

    /// The error type
    public let type: ErrorType

    /// A decribing message accompaning the error
    public let message: String?

    /// If the error occured in a subfunction, then this variable can be used to construct an error trace.
    public let cause: ForstaError?

    /// The function were the error occured
    public let function: String

    /// The file that the error occured in
    public let file: String

    /**
     Create a new `ForstaError`.
     - parameter type: The error type
     - parameter message: A decription of why the error occured
     - parameter cause: Optional error thrown by a subroutine
     - parameter file: A String describing the file where the error occured
     - parameter function: A String describing the function where the error occured
    */
    public init(_ type: ErrorType,
         _ message: String? = nil,
         cause: ForstaError? = nil,
         file: String = #file,
         function: String = #function) {
        self.type = type
        self.message = message
        self.cause = cause
        self.file = file
        self.function = function
    }

    /**
     Create a new `ForstaError` using an already exisiting `ForstaError` from a subroutine.
     - parameter message: A decription of why the error occured
     - parameter cause: The error thrown by the subroutine
     - parameter file: A String describing the file where the error occured
     - parameter function: A String describing the function where the error occured
     */
    public init(_ message: String,
         cause: ForstaError,
         file: String = #file,
         function: String = #function) {
        self.type = cause.type
        self.message = message
        self.cause = cause
        self.file = file
        self.function = function
    }

    /**
     Create a specific `ForstaError` with an `Error` as the annotating explanation.
     - parameter type: The error type
     - parameter cause: The error thrown by the subroutine
     - parameter file: A String describing the file where the error occured
     - parameter function: A String describing the function where the error occured
     */
    public convenience init(_ type: ErrorType,
         cause: Error,
         file: String = #file,
         function: String = #function) {
        self.init(type, cause.localizedDescription)
    }
    
    /**
     Create a specific `ForstaError` with JSON giving details.
     - parameter type: The error type
     - parameter message: The JSON details
     - parameter file: A String describing the file where the error occured
     - parameter function: A String describing the function where the error occured
     */
    public convenience init(_ type: ErrorType,
                            _ message: JSON,
                            file: String = #file,
                            function: String = #function) {
        self.init(type, message.rawString() ?? "{}")
    }

    /**
     Create a new `ForstaError` using an already exisiting `Error` from a subroutine.
     - parameter message: A decription of why the error occured
     - parameter cause: The error thrown by the subroutine
     - parameter file: A String describing the file where the error occured
     - parameter function: A String describing the function where the error occured
     */
    public convenience init(_ message: String,
                            cause: Error,
                            file: String = #file,
                            function: String = #function) {
        if let reason = cause as? ForstaError {
            self.init(message, cause: reason, file: file, function: function)
        } else {
            let reason = ForstaError(.unknown, cause.localizedDescription)
            self.init(message, cause: reason, file: file, function: function)
        }
    }

    /// A decription of the error, including all contained errors, without function and file names
    public var description: String {
        var output = shortDescription
        if let text = cause {
            output += "\n" + text.description
        }
        return output
    }

    /// A short decription of the error without the contained errors
    public var shortDescription: String {
        var output = type.rawValue + " error"
        if let text = message {
            output += ": " + text
        }
        return output
    }

    /// A decription of the error, including all contained errors, as well as function and file names
    public var longDescription: String {
        return type.rawValue + " error\n" + trace
    }

    /// The trace of the error which is used to build the `longDescription`
    private var trace: String {
        var output = ""
        if let text = message {
            output += "Reason: " + text
        }
        output += " \nTrace:\n" + file + ": " + function
        if let reason = cause {
            output += "\n" + reason.trace
        }
        return output
    }

    /// The description of the error
    public var localizedDescription: String {
        return description
    }
    
    /// The error's message converted to JSON (i.e., for .requestRejected), if possible
    public var json: JSON {
        return JSON(string: self.message ?? "{\"message\": \"<empty>\"}") ?? JSON(["message": self.message ?? "<empty>"])
    }
    
    //-MARK: Related Subypes
    
    /// The different types of errors that LibForstaSwift can throw.
    public enum ErrorType: String {
        /// Unknown errors should only be thrown of no other, more descriptive error type exists
        case unknown = "Unknown"
        
        /// The local storage implementation produced an error
        case storageError = "Storage"
        
        /// A message was received that was previously decrypted, or is too old
        case duplicateMessage = "Duplicate message"
        
        /// The message type does not match
        case invalidType = "Invalid type"
        
        /// An invalid key produced an error
        case invalidKey = "Invalid key"
        
        /// The initialization vector has the wrong length
        case invalidIV = "Invalid iv"
        
        /// The (key) id is invalid
        case invalidId = "Invalid Id"
        
        /// The authentication failed
        case invalidMac = "Invalid mac"
        
        /// Invalid hash
        case invalidHash = "Invalid hash"

        /// The message structure is invalid
        case invalidMessage = "Invalid message"
        
        /// The length of a message or stored object is incorrect
        case invalidLength = "Invalid length"
        
        /// A message from an older implementation of the protocol is received
        case legacyMessage = "Legacy message"
        
        /// No valid session exists for the address
        case noSession = "No session"
        
        /// The identity of the recipient is untrusted
        case untrustedIdentity = "Untrusted identity"
        
        /// The signature of the message is invalid
        case invalidSignature = "Invalid signature"
        
        /// A serialized record or message is not in valid protocol buffer format
        case invalidProtoBuf = "Invalid protoBuf"
        
        /// The identity of two fingerprints is not equal
        case fPIdentityMismatch = "Fingerprint identity mismatch"
        
        /// There is no crypto provider set
        case noCryptoProvider = "No crpyto provider"
        
        /// Random bytes could not be created
        case noRandomBytes = "No random bytes"
        
        /// There was an error calculating the HMAC of a message
        case hmacError = "HMAC error"
        
        /// There was an error calculating a digest
        case digestError = "Digest error"
        
        /// An error occured during encryption
        case encryptionError = "Encryption error"
        
        /// An error occured during decryption
        case decryptionError = "Decryption error"
        
        /// A JWT was malformed or expired
        case invalidJWT = "Invalid JWT"
        
        /// Request failure
        case requestFailure = "Request failure"
        
        /// Request rejected
        case requestRejected = "Request rejected"
        
        /// A request response was malformed
        case malformedResponse = "Malformed response"
        
        /// Necessary configuration was missing or wrong
        case configuration = "Configuration error"
        
        /// A transmission failed
        case transmissionFailure = "Transmission failure"
        
        /// Forsta Payload is invalid
        case invalidPayload = "Invalid payload"
        
        /// "Error" is due to a cancellation
        case canceled = "Canceled operation"
    }
}
