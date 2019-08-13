//
//  AtlasClient.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 4/18/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import Alamofire
import PromiseKit
import SwiftyJSON
import JWTDecode

// MARK: Global Constants

let defaultPublicOrg = "forsta"
let defaultBaseUrl = "https://atlas-dev.forsta.io"

// MARK:- Externally Visible Types

enum AtlasAuthenticationMethod {
    case sms          // by SMS code
    case password     // by password
    case passwordOtp  // by password + Authenticator code
}
typealias AuthenticatedAtlasUser = JSON
typealias InvitedAtlasPendingUserId = String


///
///  Interface for the Forsta Atlas server.  Atlas provides user and tag management.
///
class AtlasClient {
    var defaultOrg = defaultPublicOrg
    var baseUrl = defaultBaseUrl
    
    var kvstore: KVStorageProtocol
    
    var authenticatedUserJwt: String?
    var authenticatedUserId: UUID?
    
    /// predicate for whether this Atlas client is currently authenticated
    var isAuthenticated: Bool {
        return self.authenticatedUserJwt != nil
    }

    ///
    /// Initialize this Atlas client.
    /// This will continue maintaining an auth session if possible.
    ///
    /// - parameter kvstore: a persistent key-value store
    ///
    init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
        restore()
    }

    /// Internal: Restore JWT and baseUrl from kvstore, if possible.
    private func restore() {
        self.baseUrl = kvstore.get(DNK.atlasUrl) ?? defaultBaseUrl
        
        if let jwt: String = kvstore.get(DNK.atlasCredential) {
            if !setJwt(jwt) { expireJwt() }
        }
    }

    // MARK:- Authentication and JWT Maintenance
    
    ///
    /// Request a user's authentication method for the Atlas server.
    /// (This will trigger the transmission of an SMS code if applicable.)
    ///
    /// - parameter userTag: Tag for the user to authenticate as.
    ///                      It takes the form [@]user[:org].
    /// - returns: A promise that resolves to an AuthCompletionType indicating
    ///            how to complete authentiation.
    ///
    func requestAuthentication(_ userTag: String) -> Promise<AtlasAuthenticationMethod> {
        let (user, org) = tagParts(userTag)
        
        return request("/v1/login/send/\(org)/\(user)")
            .map { result in
                let (statusCode, json) = result
                if statusCode == 409 {
                    if json["non_field_errors"].arrayValue.contains("totp auth required") {
                        return .passwordOtp
                    } else {
                        return .password
                    }
                } else if statusCode == 200 {
                    return .sms
                } else {
                    throw LibForstaError.requestRejected(why:json)
                }
                
        }
    }
    
    ///
    /// Authentication via SMS code
    ///
    /// - parameters:
    ///     - userTag: Tag for the user. It takes the form [@]user[:org].
    ///     -    code: SMS code that was sent to the user when `requestAuthentication` was called.
    /// - returns: A `Promise` that either fails with a `LibRelayError` or succeeds
    ///            with an `AuthenticatedAtlasUser` `JSON` blob for the user
    ///
    func authenticateViaCode(userTag: String, code: String) -> Promise<AuthenticatedAtlasUser> {
        let (user, org) = tagParts(userTag);
        let creds = [
            "authtoken": "\(org):\(user):\(code)"
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via password
    ///
    /// - parameters:
    ///     -  userTag: Tag for the user. It takes the form [@]user[:org].
    ///     - password: The user's password.
    /// - returns: A `Promise` that either fails with a `LibRelayError` or succeeds
    ///            with an `AuthenticatedAtlasUser` `JSON` blob for the user
    ///
    func authenticateViaPassword(userTag: String, password: String) -> Promise<AuthenticatedAtlasUser> {
        let creds = [
            "fq_tag": userTag,
            "password": password
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via password + authenticator code
    ///
    /// - parameters:
    ///     -  userTag: Tag for the user. It takes the form [@]user[:org].
    ///     - password: The user's password.
    ///     -      otp: The current Authenticator code for the user.
    /// - returns: A `Promise` that either fails with a `LibRelayError` or succeeds
    ///            with an `AuthenticatedAtlasUser` `JSON` blob for the user
    ///
    func authenticateViaPasswordOtp(userTag: String, password: String, otp: String) -> Promise<AuthenticatedAtlasUser> {
        let creds = [
            "fq_tag": userTag,
            "password": password,
            "otp": otp
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via UserAuthToken
    ///
    /// - parameter token: A UserAuthToken for the authenticating user.
    /// - returns: A `Promise` that either fails with a `LibRelayError` or succeeds
    ///            with an `AuthenticatedAtlasUser` `JSON` blob for the user
    ///
    func authenticateViaUserAuthToken(token: String) -> Promise<AuthenticatedAtlasUser> {
        let creds = [
            "userauthtoken": token,
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via UserAuthToken
    ///
    /// - parameter jwt: A JWT proxy for the authenticating user.
    /// - returns: A `Promise` that either fails with a `LibRelayError` or succeeds
    ///            with an `AuthenticatedAtlasUser` `JSON` blob for the user
    ///
    func authenticateViaJwtProxy(jwt: String) -> Promise<AuthenticatedAtlasUser> {
        let creds = [
            "jwtproxy": jwt,
        ]
        return authenticate(creds)
    }

    /// Internal: Hit the Atlas authentication endpoing
    /// with appropriate credentials for a concrete authentication method.
    private func authenticate(_ credentials: [String: String]) -> Promise<AuthenticatedAtlasUser> {
        return request("/v1/login/", method: .post, parameters: credentials)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    let user = json["user"]
                    if self.setJwt(json["token"].stringValue) {
                        return user
                    } else {
                        throw LibForstaError.internalError(why: "malformed or expired jwt")
                    }
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }
    
    /// Internal: Attempt to use Atlas to refresh the current JWT.
    private func refreshJwt() {
        guard let oldJwt = self.authenticatedUserJwt else { return }
        self.requestJwtRefresh(oldJwt)
            .done { newJwt in if !self.setJwt(newJwt) { self.expireJwt() } }
            .catch { err in self.expireJwt() }
    }
    
    /// Internal: Request a refreshed JWT token from Atlas.
    private func requestJwtRefresh(_ jwt: String) -> Promise<String> {
        return request("/v1/api-token-refresh/", method: .post, parameters: ["token": jwt])
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    if let jwt = json["token"].string {
                        return jwt
                    } else {
                        throw LibForstaError.internalError(why: "malformed refresh response")
                    }
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }
    
    // MARK:- Invitation, User, and Org CRUD
    
    ///
    /// Administrator creation of a new user in the same organization.
    ///
    /// REQUIRED FIELDS: first_name, tag_slug
    ///
    /// ALERT: if tag_slug is already taken in the caller's org, the result will be a clunky 500 error
    ///
    /// - parameter fields: dictionary of optional and required fields for the new user
    ///
    /// - returns: `JSON` object of the new user
    ///
    func createUser(_ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/user/", method: .post, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 201 {
                    return json
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }
    
    ///
    /// Administrator update of a new user in the same organization.
    ///
    /// - parameters:
    ///     - id: the user's UUID
    ///     - fields: dictionary of (only) the fields to update in the user
    ///
    /// - returns: `JSON` object of the updated user
    ///
    func updateUser(_ id: String, _ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/user/\(id)/", method: .patch, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }

    ///
    /// Request creation of a UserAuthToken
    ///
    /// - parameters:
    ///     - id: optional user ID (set this if caller is an admin getting a token for another user)
    ///     - description: optional description for this token
    ///
    /// - returns: `JSON` object containing the UserAuthToken
    ///
    func getUserAuthToken(userId: String? = nil, description: String? = nil) -> Promise<JSON> {
        var fields = [String:String]()
        if userId != nil { fields["userid"] = userId }
        if description != nil { fields["description"] = description }
        
        return request("/v1/userauthtoken/", method: .post, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }
   
    ///
    /// Unauthenticated creation of an account (and an org for it, optionally).
    /// On success, this also sets the JWT for this `AtlasClient`.
    ///
    /// Required fields:
    /// - "captcha": reCaptcha's output
    /// - "phone": The new user's phone number
    /// - "email": The new user's email address
    /// - "fullname": The new user's full name
    /// - "tag_slug": The new user's usertag slug text
    /// - "password": The new user's password text
    ///
    /// Optional fields (only define these if you are creating a new org):
    /// - "org_name": Full name of the new org
    /// - "org_slug": Slug text for the new org
    ///
    /// - parameters:
    ///     - invitationToken: Optional invitation token that was obtained from /v1/invitation
    ///     - fields: dictionary of the fields to define the new user and possibly org
    ///
    /// - returns: The new user's fully-qualified tag and the userId GUID: `(tag, guid)`
    ///
    func joinForsta(invitationToken: String? = nil,
                    _ fields: [String: Any]) -> Promise<(String, UUID)> {
        return request("/v1/join/\(invitationToken ?? "")", method: .post, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200,
                    let nameTag = json["nametag"].string,
                    let orgSlug = json["orgslug"].string,
                    let jwt = json["jwt"].string {
                    if (!self.setJwt(jwt)) {
                        throw LibForstaError.internalError(why: "user creation succeeded but setJwt failed")
                    }
                    return ("@\(nameTag):\(orgSlug)", self.authenticatedUserId!)
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }
    
    ///
    /// Generate an invitation from Atlas. Repeated invitations for the same person
    /// (currently identified via phone number) will return the same pending user ID.
    ///
    /// - parameter fields: dictionary of the fields giving informatino about the invited user
    ///
    /// Possible fields:
    /// - "phone": The new user's phone number (required)
    /// - "email": The new user's email address (optional)
    /// - "first_name": The new user's first name (optional)
    /// - "last_name": The new user's last name (optional)
    /// - "message": Supplementary message for invitation (optional)
    ///
    /// - returns: a Promise of the ID for the pending user who was sent an invitation
    ///
    func sendInvitation(_ fields: [String: Any]) -> Promise<InvitedAtlasPendingUserId> {
        return request("/v1/invitation/", method: .post, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200, let userId = json["invited_user_id"].string {
                    return userId
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }
    
    ///
    /// Revoke a pending invitation.
    ///
    /// - parameter pendingUserId: the user ID of the pending invited user
    ///
    /// - returns: a Promise of the JSON containing accumulated field values for the information  for the pending user who was sent an invitation
    ///
    func revokeInvitation(_ pendingUserId: String) -> Promise<Void> {
        return request("/v1/invitation/\(pendingUserId)", method: .delete)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 204 { return () }
                throw LibForstaError.requestRejected(why: json)
        }
    }
    
    ///
    /// Get information about an invitation via its token. (This is intended to help
    /// clients present pre-filled forms for joining based on what Atlas has been
    /// given about them, perhaps accumulated across several invitation requests
    /// to Atlas.)
    ///
    /// - parameter invitationToken: the token for the invitation
    ///
    /// - returns: a Promise of the JSON containing accumulated field values
    ///            for prefilling a form leading to a `joinForsta()`
    ///
    func getInvitationInfo(_ invitationToken: String) -> Promise<JSON> {
        return request("/v1/invitation/\(invitationToken)", method: .get)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json
                }
                throw LibForstaError.requestRejected(why: json)
        }
    }
    
    
    // MARK:- Tag and User Directory Services

    ///
    /// Take a tag expression (i.e "@foo + @bar - (@joe + @sarah)") and resolve
    /// it to its current user membership.
    ///
    /// - parameter expression: a `String` tag expression
    /// - returns: resolution structure containing cool stuff
    ///
    func resolveTagExpression(_ expression: String) -> Promise<JSON> {
        return resolveTagExpressionBatch([expression])
            .map { result in
                let res = result.arrayValue
                if res.count > 0 {
                    return res[0]
                } else {
                    throw LibForstaError.internalError(why: "malformed tagmath resolution response")
                }
        }
    }
    
    ///
    /// This is the batch version of `resolveTagExpression` with an array
    /// of tag expressions. The results are in the same order as the input array
    /// and invalid responses will be set to undefined.
    ///
    /// - parameter expressions: the `[String]` of tag expressions
    /// - returns: array of resolutions of cool stuff
    ///
    func resolveTagExpressionBatch(_ expressions: [String]) -> Promise<JSON> {
        return request("/v1/tagmath/", method: .post, parameters: ["expressions": expressions])
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json["results"]
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }
    
    ///
    /// Get user objects based on a list of user IDs.
    /// First try to get it from the (more verbose) `/user` endpoint
    /// for users in the same org, then fall back to the (more lightweight)
    /// `/directory/user` public directory for those in other orgs.
    ///
    /// - parameters:
    ///    - userIds: Array of user ID `Strings` to look up.
    ///    - onlyPublicDirectory: Optional boolean to only use the
    ///      Forsta public directory. E.g. only return lightweight user objects.
    ///
    /// - returns: Array of user `JSON` objects.
    ///
    func getUsers(userIds: [String], onlyPublicDirectory: Bool = false) -> Promise<[JSON]> {
        var missing = Set(userIds);
        var users: [JSON] = []
        
        return (onlyPublicDirectory ? Promise.value((200, JSON(["result": []]))) : request("/v1/user/?id_in=" + userIds.joined(separator: ",")))
            .map { result in
                let (statusCode, json) = result
                if (statusCode != 200) { throw LibForstaError.requestRejected(why: json) }
                for user in json["results"].arrayValue {
                    users.append(user)
                    missing.remove(user["id"].stringValue)
                }
            }.then { () -> Promise<[JSON]> in
                if missing.count == 0 {
                    return Promise.value(users)
                } else {
                    return self.request("/v1/directory/user/?id_in=" + Array(missing).joined(separator: ","))
                        .map { result in
                            let (statusCode, json) = result
                            if (statusCode != 200) { throw LibForstaError.requestRejected(why: json) }
                            for user in json["results"].arrayValue {
                                users.append(user)
                            }
                            return users
                    }
                }
        }
    }
    
    
    // MARK:- Signal Server Assistance
    
    ///
    /// Request provisioning assistance from any existing devices.
    ///
    /// - returns: `Promise` resolving to an array of `JSON`.
    ///
    func provisionDevice() -> Promise<JSON> {
        return request("/v1/provision/request", method: .post)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }

    ///
    /// Provision/refresh a new Signal Server account.
    ///
    /// - returns: `Promise` resolving to an array of `JSON`.
    ///
    func provisionAccount(_ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/provision/account", method: .put, parameters: fields)
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }
    
    ///
    /// The current set of known devices for the authenticated account.
    ///
    /// - returns: `Promise` resolving to an array of `JSON` device info.
    ///
    func getDevices() -> Promise<[JSON]> {
        return request("/v1/provision/account")
            .map { result in
                let (statusCode, json) = result
                if statusCode == 200 {
                    return json["devices"].arrayValue
                } else {
                    throw LibForstaError.requestRejected(why: json)
                }
        }
    }

    // MARK:- Utility Routines
    
    ///
    /// Breaks a tag into (normalized) user and org slug parts.
    ///
    /// - parameter tag: a string shaped like [@]user[:org]
    /// - returns: a tuple of (user, org) slug `String`s --
    ///            trimmed, lowercased, @-stripped (also, a
    ///            missing org will default to `self.defaultOrg`)
    ///
    func tagParts(_ tag: String) -> (String, String) {
        let trimmables = CharacterSet(charactersIn: "@ \t\n")
        
        let parts = "\(tag):\(defaultOrg)"
            .lowercased()
            .components(separatedBy: ":")
            .map { s in s.trimmingCharacters(in: trimmables) }
        
        return (parts[0], parts[1])
    }
    
    /// Internal: Basic Atlas http request that returns a `Promise` of `(statuscode, JSON)`
    private func request(_ url: String, method: HTTPMethod = .get, parameters: Parameters? = nil) -> Promise<(Int, JSON)> {
        return Promise { seal in
            let headers = isAuthenticated ? ["Authorization": "JWt \(authenticatedUserJwt!)"] : nil
            Alamofire.request("\(baseUrl)\(url)", method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { response in
                    let statusCode = response.response?.statusCode ?? 500
                    switch response.result {
                    case .success(let data):
                        let json = JSON(data)
                        return seal.fulfill((statusCode, json))
                    case .failure(let error):
                        return seal.reject(LibForstaError.requestFailure(why: error))
                    }
            }
        }
    }
    
    /// Internal: Check JWT for freshness, stash it for current and future use,
    /// broadcast that event, and set up refreshes based on it's expiration date.
    private func setJwt(_ jwt: String) -> Bool {
        do {
            let decodedJwt = try decode(jwt: jwt)
            let timestamp = decodedJwt.body["exp"] as! Double
            if timestamp < Date().timeIntervalSince1970 { return false; }
            
            self.kvstore.set(DNK.atlasCredential, jwt)
            self.kvstore.set(DNK.atlasUrl, self.baseUrl)

            guard let id = decodedJwt.body["user_id"] as? String else {
                print("warning: malformed jwt, missing user_id")
                return false
            }
            self.authenticatedUserId = UUID(uuidString: id)
            self.authenticatedUserJwt = jwt
            
            NotificationCenter.broadcast(.atlasCredentialSet, ["jwt": jwt])
            
            let halfDead = DispatchTime.now() + DispatchTimeInterval.seconds(Int(timestamp - Date().timeIntervalSince1970) / 2)
            DispatchQueue.main.asyncAfter(deadline: halfDead) { self.refreshJwt() }
            
            return true
        } catch {
            return false
        }
    }
    
    /// Internal: Clear all traces of a stashed JWT and broadcast that event.
    private func expireJwt() {
        self.authenticatedUserJwt = nil
        self.authenticatedUserId = nil
        self.kvstore.remove(DNK.atlasCredential)
        NotificationCenter.broadcast(.atlasCredentialExpired, nil)
    }
}
