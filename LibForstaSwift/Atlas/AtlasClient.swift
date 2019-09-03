//
//  AtlasClient.swift
//  LibSignalSwift
//
//  Created by Greg Perkins on 4/18/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import Alamofire
import PromiseKit
import SwiftyJSON
import JWTDecode


///
/// Central class for interacting for the Forsta Atlas server.
///
/// You'll use this for Atlas authentication, user creation and manipulation,
/// tag creation and manipulation, and tag-math evaluation to resolve message
/// distributions.
///
/// It requires an object conforming to `KVStorageProtocol` so it can maintain
/// login sessions across invocations, etc.
///
public class AtlasClient {
    static let defaultPublicOrg = "forsta"
    static let defaultBaseUrl = "https://atlas-dev.forsta.io"
    
    /// The default public organization name
    public var defaultOrg = defaultPublicOrg
    /// The URL of the Atlas server we are dealing with
    /// (this will be persisted and restored if there is an active login session)
    public var baseUrl = defaultBaseUrl
    
    var kvstore: KVStorageProtocol
    
    var authenticatedUserJwt: String?
    var authenticatedUserId: UUID?
    
    /// predicate for whether this Atlas client is currently authenticated
    public var isAuthenticated: Bool {
        return self.authenticatedUserJwt != nil
    }
    
    ///
    /// Initialize this Atlas client.
    /// This will continue maintaining an auth session if possible.
    ///
    /// - parameter kvstore: a persistent key-value store
    ///
    public init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
        restore()
    }
    
    // -MARK: Public types for dealing with AtlasClient
    
    /// A user's current method of interactive authentication
    public enum AuthenticationMethod {
        /// Authenticate by providing a code that has sent by SMS: `authenticateViaCode(...)`
        case sms
        
        /// Authenticate by providing a password: `authenticateViaPassword(...)`
        case password
        
        /// Authenticate by providing a password and an authenticator code: `authenticateViaPasswordOtp(...)`
        case passwordOtp
    }
    
    /// The JSON blob detailing an authenticated user on Atlas
    public typealias AuthenticatedUser = JSON
    

    // -MARK: Authentication and JWT Maintenance
    
    ///
    /// Request a user's authentication method for the Atlas server.
    /// (This will trigger the transmission of an SMS code if applicable.)
    ///
    /// - parameter userTag: Tag for the user to authenticate as.
    ///                      It takes the form [@]user[:org].
    /// - returns: A `Promise` that resolves to an `AuthenticationMethod`
    ///            indicating how to complete authentiation.
    ///
    public func requestAuthentication(_ userTag: String) -> Promise<AuthenticationMethod> {
        let (user, org) = tagParts(userTag)
        
        return request("/v1/login/send/\(org)/\(user)")
            .map { (statusCode, json) in
                if statusCode == 409 {
                    if json["non_field_errors"].arrayValue.contains("totp auth required") {
                        return .passwordOtp
                    } else {
                        return .password
                    }
                } else if statusCode == 200 {
                    return .sms
                } else {
                    throw ForstaError(.requestRejected, json)
                }
                
        }
    }
    
    ///
    /// Authentication via SMS code
    ///
    /// - parameters:
    ///     - userTag: Tag for the user. It takes the form [@]user[:org].
    ///     -    code: SMS code that was sent to the user when `requestAuthentication` was called.
    /// - returns: A `Promise` that resolves to  an `AuthenticatedUser` `JSON` blob for the user
    ///
    public func authenticateViaCode(userTag: String, code: String) -> Promise<AuthenticatedUser> {
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
    /// - returns: A `Promise` that resolves to an `AuthenticatedUser` `JSON` blob for the user
    ///
    public func authenticateViaPassword(userTag: String, password: String) -> Promise<AuthenticatedUser> {
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
    /// - returns: A `Promise` that resolves to an `AuthenticatedUser` `JSON` blob for the user
    ///
    public func authenticateViaPasswordOtp(userTag: String, password: String, otp: String) -> Promise<AuthenticatedUser> {
        let creds = [
            "fq_tag": userTag,
            "password": password,
            "otp": otp
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via a `UserAuthToken`
    ///
    /// - parameter token: A `UserAuthToken` for the authenticating user.
    /// - returns: A `Promise` that resolves to an `AuthenticatedUser` `JSON` blob for the user
    ///
    public func authenticateViaUserAuthToken(token: String) -> Promise<AuthenticatedUser> {
        let creds = [
            "userauthtoken": token,
        ]
        return authenticate(creds)
    }
    
    ///
    /// Authentication via UserAuthToken
    ///
    /// - parameter jwt: A JWT proxy for the authenticating user.
    /// - returns: A `Promise` that resolves to an `AuthenticatedUser` `JSON` blob for the user
    ///
    public func authenticateViaJwtProxy(jwt: String) -> Promise<AuthenticatedUser> {
        let creds = [
            "jwtproxy": jwt,
        ]
        return authenticate(creds)
    }
    
    /// Internal: Hit the Atlas authentication endpoing
    /// with appropriate credentials for a concrete authentication method.
    private func authenticate(_ credentials: [String: String]) -> Promise<AuthenticatedUser> {
        return request("/v1/login/", method: .post, parameters: credentials)
            .map { (statusCode, json) in
                if statusCode == 200 {
                    let user = json["user"]
                    if self.setJwt(json["token"].stringValue) {
                        return user
                    } else {
                        throw ForstaError(.invalidJWT)
                    }
                } else {
                    throw ForstaError(.requestRejected, json)
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
            .map { (statusCode, json) in
                if statusCode == 200 {
                    if let jwt = json["token"].string {
                        return jwt
                    } else {
                        throw ForstaError(.malformedResponse, "missing JWT in refresh response")
                    }
                } else {
                    throw ForstaError(.requestRejected, json)
                }
        }
    }
    
    // -MARK: Invitation, User, and Org CRUD
    
    ///
    /// Administrator creation of a new user in the same organization.
    ///
    /// REQUIRED FIELDS: first_name, tag_slug
    ///
    /// ALERT: if tag_slug is already taken in the caller's org, the result will be a clunky 500 error
    ///
    /// - parameter fields: dictionary of optional and required fields for the new user
    ///
    /// - returns: A `Promise` that resolves to a `JSON` blob of the new user
    ///
    public func createUser(_ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/user/", method: .post, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 201 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Administrator update of a new user in the same organization.
    ///
    /// - parameters:
    ///     - id: the user's UUID
    ///     - fields: dictionary of (only) the fields to update in the user
    ///
    /// - returns: A `Promise` that resolves to a `JSON` blob of the updated user
    ///
    public func updateUser(_ id: String, _ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/user/\(id)/", method: .patch, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Request creation of a `UserAuthToken`
    ///
    /// - parameters:
    ///     - id: optional user ID (set this if caller is an admin getting a token for another user)
    ///     - description: optional description for this token
    ///
    /// - returns: A `Promise` that resolves to a `JSON` blob containing the `UserAuthToken`
    ///
    public func getUserAuthToken(userId: UUID? = nil, description: String? = nil) -> Promise<JSON> {
        var fields = [String:String]()
        if userId != nil { fields["userid"] = userId!.lcString }
        if description != nil { fields["description"] = description }
        
        return request("/v1/userauthtoken/", method: .post, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
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
    /// - returns: A `Promise` that resolves to the new user's fully-qualified tag string and userId GUID: `(tag, guid)`
    ///
    public func joinForsta(invitationToken: String? = nil,
                           _ fields: [String: Any]) -> Promise<(String, UUID)> {
        return request("/v1/join/\(invitationToken ?? "")", method: .post, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 200,
                    let nameTag = json["nametag"].string,
                    let orgSlug = json["orgslug"].string,
                    let jwt = json["jwt"].string {
                    if (!self.setJwt(jwt)) {
                        throw ForstaError(.invalidJWT, "user creation succeeded but setJwt failed")
                    }
                    return ("@\(nameTag):\(orgSlug)", self.authenticatedUserId!)
                }
                throw ForstaError(.requestRejected, json)
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
    /// - returns: a `Promise` that resolves to the `UUID` of
    ///            the pending user who was sent an invitation
    ///
    public func sendInvitation(_ fields: [String: Any]) -> Promise<UUID> {
        return request("/v1/invitation/", method: .post, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 200,
                    let userIdStr = json["invited_user_id"].string,
                    let userId = UUID(uuidString: userIdStr) {
                    return userId
                }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Revoke a pending invitation.
    ///
    /// - parameter pendingUserId: the user ID of the pending invited user
    ///
    /// - returns: a Promise that resolves upon completion of the task
    ///
    public func revokeInvitation(_ pendingUserId: UUID) -> Promise<Void> {
        return request("/v1/invitation/\(pendingUserId.lcString)", method: .delete)
            .map { (statusCode, json) in
                if statusCode == 204 { return () }
                throw ForstaError(.requestRejected, json)
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
    /// - returns: a Promise that resolves to `JSON` containing accumulated field
    ///            values for prefilling a form leading to a `joinForsta()`
    ///
    public func getInvitationInfo(_ invitationToken: String) -> Promise<JSON> {
        return request("/v1/invitation/\(invitationToken)", method: .get)
            .map { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    
    // -MARK: Tag and User Directory Services
    
    ///
    /// Take a tag expression (i.e "@foo + @bar - (@joe + @sarah)") and resolve
    /// it to its current user membership.
    ///
    /// - parameter expression: a `String` tag expression
    /// - returns: a `Promise` resolving to a `JSON` blob with the results of the tag math evaluation
    ///
    public func resolveTagExpression(_ expression: String) -> Promise<JSON> {
        return resolveTagExpressionBatch([expression])
            .map { result in
                let res = result.arrayValue
                if res.count > 0 {
                    return res[0]
                } else {
                    throw ForstaError(.malformedResponse, "tagmath resolution with no result")
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
    /// - returns: a `Promise` resolving to a `[JSON]` with the results of the tag math evaluations
    ///
    public func resolveTagExpressionBatch(_ expressions: [String]) -> Promise<JSON> {
        return request("/v1/tagmath/", method: .post, parameters: ["expressions": expressions])
            .map { (statusCode, json) in
                if statusCode == 200 { return json["results"] }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Get user objects based on a list of user IDs.
    /// First try to get it from the (more verbose) `/user` endpoint
    /// for users in the same org, then fall back to the (more lightweight)
    /// `/directory/user` public directory for those in other orgs.
    ///
    /// - parameters:
    ///    - userIds: Array of user ID `UUID`s to look up.
    ///    - onlyPublicDirectory: Optional boolean to only use the
    ///      Forsta public directory. E.g. only return lightweight user objects.
    ///
    /// - returns: A `Promise` resolving to a `JSON` array of the users' information
    ///
    public func getUsers(userIds: [UUID], onlyPublicDirectory: Bool = false) -> Promise<[JSON]> {
        var missing = Set(userIds);
        var users: [JSON] = []
        
        let idList = userIds.map({ $0.lcString }).joined(separator: ",")
        
        return (onlyPublicDirectory ? Promise.value((200, JSON(["results": []]))) : request("/v1/user/?id_in=" + idList))
            .map { (statusCode, json) in
                if (statusCode != 200) { throw ForstaError(.requestRejected, json) }
                for user in json["results"].arrayValue {
                    users.append(user)
                    if let id = UUID(uuidString: user["id"].stringValue) {
                        missing.remove(id)
                    }
                }
            }.then { () -> Promise<[JSON]> in
                if missing.count == 0 {
                    return Promise.value(users)
                } else {
                    return self.request("/v1/directory/user/?id_in=" + Array(missing).map({ $0.lcString }).joined(separator: ","))
                        .map { (statusCode, json) in
                            if (statusCode != 200) { throw ForstaError(.requestRejected, json) }
                            for user in json["results"].arrayValue {
                                users.append(user)
                            }
                            return users
                    }
                }
        }
    }
    
    /// Internal: get all pages for a url
    private func allResults(url: String, previous: [JSON] = []) -> Promise<[JSON]> {
        print("allResults called for \(url)")
        return request(url)
            .then { result -> Promise<[JSON]> in
                let (statusCode, json) = result
                if statusCode == 200 {
                    let next = json["next"].string
                    let combined = previous + json["results"].arrayValue
                    if next == nil {
                        return Promise<[JSON]>.value(combined)
                    } else {
                        return self.allResults(url: next!, previous: combined)
                    }
                }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Get all user objects in this org based on an optional search/filter query string.
    /// Retrieves from the `/v1/user` endpoint. This will retrieve
    /// *all* pages of results.
    ///
    /// - parameter q: Optional query search/filter string.
    ///                No query string means retreive **all** users.
    /// - returns: A `Promise` resolving to a `JSON` array of
    ///            retrieved users' information
    ///
    public func getUsers(q: String? = nil) -> Promise<[JSON]> {
        let url = "/v1/user/\(q == nil ? "" : "?q=\(q!)")"
        return allResults(url: url)
    }
    
    ///
    /// Get all tag objects for this org.
    /// Retrieves from the `/v1/tag` endpoint. This will retrieve
    /// *all* pages of results.
    ///
    /// - returns: A `Promise` resolving to a `JSON` array of
    ///            retrieved tags' information
    ///
    public func getTags(q: String? = nil) -> Promise<[JSON]> {
        let url = "/v1/tag/\(q == nil ? "" : "?q=\(q!)")"
        return allResults(url: url)
    }

    // -MARK: Signal Server Assistance
    
    ///
    /// Request provisioning assistance from any existing devices.
    ///
    /// - returns: `Promise` resolving to results bundled in a `JSON`.
    ///
    public func provisionDevice() -> Promise<JSON> {
        return request("/v1/provision/request", method: .post)
            .map { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Provision/refresh a new Signal Server account.
    ///
    /// - returns: `Promise` resolving to results bundled in a `JSON`.
    ///
    public func provisionAccount(_ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/provision/account", method: .put, parameters: fields)
            .map { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// The current set of known devices for the authenticated account.
    ///
    /// - returns: `Promise` resolving to an `JSON` array of device(s) info.
    ///
    public func getDevices() -> Promise<[JSON]> {
        return request("/v1/provision/account")
            .map { (statusCode, json) in
                if statusCode == 200 { return json["devices"].arrayValue }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    // -MARK: Utility Routines
    
    ///
    /// Breaks a tag into (normalized) user and org slug parts.
    ///
    /// - parameter tag: a string shaped like [@]user[:org]
    /// - returns: a tuple of (user, org) slug `String`s --
    ///            trimmed, lowercased, @-stripped (also, a
    ///            missing org will default to `self.defaultOrg`)
    ///
    public func tagParts(_ tag: String) -> (String, String) {
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
            let headers = isAuthenticated ? ["Authorization": "JWT \(authenticatedUserJwt!)"] : nil
            let fullUrl = url.starts(with: "http") ? url : "\(baseUrl)\(url)"
            Alamofire.request(fullUrl, method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { response in
                    let statusCode = response.response?.statusCode ?? 500
                    switch response.result {
                    case .success(let data):
                        let json = JSON(data)
                        return seal.fulfill((statusCode, json))
                    case .failure(let error):
                        return seal.reject(ForstaError(.requestFailure, cause: error))
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
    
    /// Internal: Restore JWT and baseUrl from kvstore, if possible.
    private func restore() {
        self.baseUrl = kvstore.get(DNK.atlasUrl) ?? AtlasClient.defaultBaseUrl
        
        if let jwt: String = kvstore.get(DNK.atlasCredential) {
            if !setJwt(jwt) { expireJwt() }
        }
    }
}
