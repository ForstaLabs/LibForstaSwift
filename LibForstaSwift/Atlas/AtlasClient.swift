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
    // -MARK: Attributes

    static let defaultPublicOrg = "forsta"
    static let defaultServerUrl = "https://atlas-dev.forsta.io"
    
    var kvstore: KVStorageProtocol
    
    /// The registered delegates for this Atlas client
    public let delegates = Delegates<AtlasClientDelegate>()

    private var _defaultOrg: KVBacked<String>
    /// The default public organization name (added to unqualified login tags)
    public var defaultOrg: String? {
        get { return _defaultOrg.value }
        set(value) { _defaultOrg.value = value }
    }

    private var _serverUrl: KVBacked<String>
    /// The URL of the Atlas server we are using
    public var serverUrl: String? {
        get { return _serverUrl.value }
        set(value) { _serverUrl.value = value }
    }

    /// The current authenticated user UUID
    public var authenticatedUserId: UUID?

    /// predicate for whether this Atlas client is currently authenticated
    public var isAuthenticated: Bool {
        return self.authenticatedUserJwt != nil
    }
    
    private var _authenticatedUserJwt: KVBacked<String>
    /// The current authenticated user JWT (will be automatically set and maintained)
    public var authenticatedUserJwt: String? {
        get { return _authenticatedUserJwt.value }
        set(value) {
            _authenticatedUserJwt.value = value
            if value != nil { maintainJwt() }
        }
    }
    
    // -MARK: Constructors

    ///
    /// Initialize this Atlas client.
    /// This will resume maintaining an auth session, if possible.
    ///
    /// - parameter kvstore: a persistent key-value store
    ///
    public init(kvstore: KVStorageProtocol) {
        self.kvstore = kvstore
        self._serverUrl = KVBacked(kvstore: kvstore, key: DNK.atlasServerUrl, initial: AtlasClient.defaultServerUrl)
        self._authenticatedUserJwt = KVBacked(kvstore: kvstore, key: DNK.atlasCredential)
        self._defaultOrg = KVBacked(kvstore: kvstore, key: DNK.atlasDefaultOrg, initial: AtlasClient.defaultPublicOrg)

        // restart maintenance of the current JWT, if there is one
        if let jwt = self.authenticatedUserJwt { self.authenticatedUserJwt = jwt }
    }
    
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
        let (user, org) = tagParts(userTag)
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
        let (user, org) = tagParts(userTag)
        let creds = [
            "fq_tag": "\(user):\(org)",
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
        let (user, org) = tagParts(userTag)
        let creds = [
            "fq_tag": "\(user):\(org)",
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 {
                    let user = json["user"]
                    self.authenticatedUserJwt = json["token"].stringValue
                    if self.isAuthenticated {
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
            .done { newJwt in self.authenticatedUserJwt = newJwt }
            .catch { err in self.expireJwt() }
    }
    
    /// Internal: Request a refreshed JWT token from Atlas.
    private func requestJwtRefresh(_ jwt: String) -> Promise<String> {
        return request("/v1/api-token-refresh/", method: .post, parameters: ["token": jwt])
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
    
    // -MARK: Invitation, Conversation, User, and Org CRUD
    
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 201 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Administrator update of a new user in the same organization.
    ///
    /// - parameters:
    ///     - userId: the user's UUID
    ///     - patchFields: dictionary of (only) the fields to update in the user
    ///
    /// - returns: A `Promise` that resolves to a `JSON` blob of the updated user
    ///
    public func updateUser(_ userId: UUID, _ patchFields: [String: Any]) -> Promise<JSON> {
        return request("/v1/user/\(userId.lcString)/", method: .patch, parameters: patchFields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Request creation of a UserAuthToken
    ///
    /// - parameters:
    ///     - userId: optional user ID to create the token for a user other than self (requires being an org admin)
    ///     - description: optional description for this token
    ///
    /// - returns: A `Promise` that resolves to a tuple of the token's ID and the UserAuthToken
    ///
    public func createUserAuthToken(userId: UUID? = nil, description: String? = nil) -> Promise<(UUID, String)> {
        var fields = [String:String]()
        if userId != nil { fields["userid"] = userId!.lcString }
        if description != nil { fields["description"] = description }
        
        return request("/v1/userauthtoken/", method: .post, parameters: fields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 {
                    guard
                        let idRaw = json["id"].string,
                        let id = UUID(uuidString: idRaw),
                        let token = json["token"].string else {
                            throw ForstaError(.malformedResponse, "UserAuthToken creation missing expected component(s)")
                    }
                    return (id, token)
                }
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
    /// - returns: A `Promise` that resolves to a tuple of the new user's fully-qualified tag string and userId UUID: `(tag, uuid)`
    ///
    public func joinForsta(invitationToken: String? = nil,
                           _ fields: [String: Any]) -> Promise<(String, UUID)> {
        return request("/v1/join/\(invitationToken ?? "")", method: .post, parameters: fields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200,
                    let nameTag = json["nametag"].string,
                    let orgSlug = json["orgslug"].string,
                    let jwt = json["jwt"].string {
                    self.authenticatedUserJwt = jwt
                    if !self.isAuthenticated {
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    public class ConversationInfo {
        public var threadId: UUID
        public var distribution: String
        public var creatorId: UUID
        public var orgId: UUID
        public var userIds: [UUID]
        public var expires: Date
        public var token: String
        public var created: Date
        
        public init(
            threadId: UUID,
            distribution: String,
            creatorId: UUID,
            orgId: UUID,
            userIds: [UUID],
            expires: Date,
            token: String,
            created: Date) {
            self.token = token
            self.threadId = threadId
            self.distribution = distribution
            self.creatorId = creatorId
            self.orgId = orgId
            self.userIds = userIds
            self.expires = expires
            self.created = created
        }
    }
    
    ///
    /// Generate a Conversation.
    ///
    /// - parameters:
    ///     - captcha: reCaptcha's output, required if not currently signed in
    ///     - threadId: optional thread id (defaults to a random uuid4)
    ///     - distribution: optional starting distribution (defaults to empty, or self if signed in)
    ///     - expires: optional expiration datetime (defaults to 1 day from now)
    ///
    /// - returns: a `Promise` that resolves to a `ConversationInfo`
    ///
    public func createConversation(captcha: String? = nil,
                                   threadId: UUID? = nil,
                                   distribution: String? = nil,
                                   expires: Date? = nil) -> Promise<ConversationInfo> {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime,
                             .withColonSeparatorInTimeZone, .withFractionalSeconds]
        var fields = [String: Any]()
        if captcha != nil { fields["captcha"] = captcha }
        if threadId != nil { fields["thread_id"] = threadId!.lcString }
        if distribution != nil { fields["distribution"] = distribution }
        if expires != nil { fields["expires"] = fmt.string(from: expires!) }
        
        return request("/v1/conversation/", method: .post, parameters: fields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode != 200 { throw ForstaError(.requestRejected, json) }
                guard
                    let rawThreadId = json["thread_id"].string,
                    let threadId = UUID(uuidString: rawThreadId),
                    let distribution = json["distribution"].string,
                    let rawCreatorId = json["creator_id"].string,
                    let creatorId = UUID(uuidString: rawCreatorId),
                    let rawOrgId = json["org_id"].string,
                    let orgId = UUID(uuidString: rawOrgId),
                    let rawUserIds = json["user_ids"].array,
                    let rawExpires = json["expires"].string,
                    let expiresDate = fmt.date(from: rawExpires),
                    let token = json["token"].string,
                    let rawCreated = json["created"].string,
                    let createdDate = fmt.date(from: rawCreated) else {
                        throw ForstaError(.malformedResponse, "conversation creation missing expected component(s)")
                }
                let userIds = rawUserIds.map { UUID(uuidString: $0.stringValue) }.filter { $0 != nil }.map { $0! }
                let info = ConversationInfo(threadId: threadId,
                                            distribution: distribution,
                                            creatorId: creatorId,
                                            orgId: orgId,
                                            userIds: userIds,
                                            expires: expiresDate,
                                            token: token,
                                            created: createdDate)
                return info
        }
    }
    
    ///
    /// Get information about a Conversation (if the requesting user is its creator)
    ///
    /// - parameters:
    ///     - conversationToken: An existing Conversation's token
    ///
    /// - returns: a `Promise` that resolves to a `ConversationInfo`
    ///
    public func getConversationInfo(_ conversationToken: String) -> Promise<ConversationInfo> {
        return request("/v1/conversation/\(conversationToken)", method: .get)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode != 200 { throw ForstaError(.requestRejected, json) }
                
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime,
                                     .withColonSeparatorInTimeZone, .withFractionalSeconds]
                guard
                    let rawThreadId = json["thread_id"].string,
                    let threadId = UUID(uuidString: rawThreadId),
                    let distribution = json["distribution"].string,
                    let rawCreatorId = json["creator_id"].string,
                    let creatorId = UUID(uuidString: rawCreatorId),
                    let rawOrgId = json["org_id"].string,
                    let orgId = UUID(uuidString: rawOrgId),
                    let rawUserIds = json["user_ids"].array,
                    let rawExpires = json["expires"].string,
                    let expiresDate = fmt.date(from: rawExpires),
                    let rawCreated = json["created"].string,
                    let createdDate = fmt.date(from: rawCreated) else {
                        throw ForstaError(.malformedResponse, "conversation creation missing expected component(s)")
                }
                let userIds = rawUserIds.map { UUID(uuidString: $0.stringValue) }.filter { $0 != nil }.map { $0! }
                let info = ConversationInfo(threadId: threadId,
                                            distribution: distribution,
                                            creatorId: creatorId,
                                            orgId: orgId,
                                            userIds: userIds,
                                            expires: expiresDate,
                                            token: conversationToken,
                                            created: createdDate)
                return info
        }
    }
    
    ///
    /// Join a Conversation.
    /// If not authenticated with Atlas, this will cause an ephemeral user to be created
    /// and this AtlasClient will begin maintaining a JWT for it.
    ///
    /// - parameters:
    ///     - conversationToken: An existing Conversation's token
    ///     - firstName: optional first name (used if an ephemeral user is created, defaults to Anonymous)
    ///     - lastName: optional last name (used if an ephemeral user is created)
    ///     - email: optional email (used if an ephemeral user is created)
    ///     - phone: optional phone (used if an ephemeral user is created)
    ///
    /// - returns: a `Promise` that resolves to a `ConversationInfo`
    ///
    public func joinConversation(_ conversationToken: String,
                                 firstName: String? = nil,
                                 lastName: String? = nil,
                                 email: String? = nil,
                                 phone: String? = nil) -> Promise<ConversationInfo> {
        var fields = [String: Any]()
        if firstName != nil { fields["first_name"] = firstName }
        if lastName != nil { fields["last_name"] = lastName }
        if email != nil { fields["email"] = email }
        if phone != nil { fields["phone"] = phone }

        return request("/v1/conversation/\(conversationToken)", method: .post, parameters: fields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode != 200 { throw ForstaError(.requestRejected, json) }
                
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime,
                                     .withColonSeparatorInTimeZone, .withFractionalSeconds]
                guard
                    let rawThreadId = json["thread_id"].string,
                    let threadId = UUID(uuidString: rawThreadId),
                    let distribution = json["distribution"].string,
                    let rawCreatorId = json["creator_id"].string,
                    let creatorId = UUID(uuidString: rawCreatorId),
                    let rawOrgId = json["org_id"].string,
                    let orgId = UUID(uuidString: rawOrgId),
                    let rawUserIds = json["user_ids"].array,
                    let rawExpires = json["expires"].string,
                    let expiresDate = fmt.date(from: rawExpires),
                    let rawCreated = json["created"].string,
                    let createdDate = fmt.date(from: rawCreated) else {
                        throw ForstaError(.malformedResponse, "conversation join missing expected component(s)")
                }
                let userIds = rawUserIds.map { UUID(uuidString: $0.stringValue) }.filter { $0 != nil }.map { $0! }
                let info = ConversationInfo(threadId: threadId,
                                            distribution: distribution,
                                            creatorId: creatorId,
                                            orgId: orgId,
                                            userIds: userIds,
                                            expires: expiresDate,
                                            token: conversationToken,
                                            created: createdDate)
                if !self.isAuthenticated {
                    guard let jwt = json["jwt"].string else {
                        throw ForstaError(.malformedResponse, "conversation join missing expected jwt")
                    }
                    self.authenticatedUserJwt = jwt
                }
                return info
        }
    }
    

    // -MARK: Tag and User Directory Services
    
    ///
    /// Takes an array of tag expressions (i.e "@foo + @bar - (@joe + @sarah)") and resolves
    /// them to their current user memberships.
    ///
    /// - parameter expressions: an array of `String` tag expressions
    /// - returns: a `Promise` resolving to a matching array of `TagExpressionResolution`s
    ///
    public func resolveTagExpressions(_ expressions: [String]) -> Promise<[TagExpressionResolution]> {
        return request("/v1/tagmath/", method: .post, parameters: ["expressions": expressions])
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode != 200 { throw ForstaError(.requestRejected, json) }
                return try json["results"].arrayValue.map { item in
                    guard
                        let pretty = item["pretty"].string,
                        let universal = item["universal"].string,
                        let usersRaw = item["userids"].array,
                        let monitorsRaw = item["monitorids"].array,
                        let includedTagsRaw = item["includedTagids"].array,
                        let excludedTagsRaw = item["excludedTagids"].array,
                        let warningsRaw = item["warnings"].array else {
                            throw ForstaError(.malformedResponse, "tagmath resolution missing expected component(s)")
                    }
                    
                    let users = usersRaw.map { id in UUID(uuidString: id.stringValue) }.filter { id in id != nil }.map { id in id! }
                    let monitors = monitorsRaw.map { id in UUID(uuidString: id.stringValue) }.filter { id in id != nil }.map { id in id! }
                    let includedTags = includedTagsRaw.map { id in UUID(uuidString: id.stringValue) }.filter { id in id != nil }.map { id in id! }
                    let excludedTags = excludedTagsRaw.map { id in UUID(uuidString: id.stringValue) }.filter { id in id != nil }.map { id in id! }
                    guard
                        users.count == usersRaw.count,
                        monitors.count == monitorsRaw.count,
                        includedTags.count == includedTagsRaw.count,
                        excludedTags.count == excludedTagsRaw.count else {
                            throw ForstaError(.malformedResponse, "tagmath resolution malformed uuid(s)")
                    }

                    let warnings = try warningsRaw.map { warn -> TagExpressionResolution.Warning in
                        guard let position = warn["position"].uInt,
                            let sourceRaw = warn["source"].string,
                            let source = TagExpressionResolution.Warning.Source(rawValue: sourceRaw),
                            let kindRaw = warn["kind"].string,
                            let kind = TagExpressionResolution.Warning.Kind(rawValue: kindRaw),
                            let length = warn["length"].uInt,
                            let cue = warn["cue"].string else {
                                throw ForstaError(.malformedResponse, "tagmath resolution warning missing expected component(s)")
                        }
                        return TagExpressionResolution.Warning(source: source,
                                                               kind: kind,
                                                               cue: cue,
                                                               position: position,
                                                               length: length)
                    }
                    
                    return TagExpressionResolution(pretty: pretty,
                                                   universal: universal,
                                                   users: users,
                                                   monitors: monitors,
                                                   includedTags: includedTags,
                                                   excludedTags: excludedTags,
                                                   warnings: warnings)
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
    ///    - userIds: Array of user ID `UUID`s to look up.
    ///    - onlyPublicDirectory: Optional boolean to only use the
    ///      Forsta public directory. E.g. only return lightweight user objects.
    ///
    /// - returns: A `Promise` resolving to a `JSON` array of the users' information
    ///
    public func getUsers(userIds: [UUID], onlyPublicDirectory: Bool = false) -> Promise<[JSON]> {
        var missing = Set(userIds)
        var users: [JSON] = []
        
        let idList = userIds.map({ $0.lcString }).joined(separator: ",")
        
        return (onlyPublicDirectory ? Promise.value((200, JSON(["results": []]))) : request("/v1/user/?id_in=" + idList))
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if (statusCode != 200) { throw ForstaError(.requestRejected, json) }
                for user in json["results"].arrayValue {
                    users.append(user)
                    if let id = UUID(uuidString: user["id"].stringValue) {
                        missing.remove(id)
                    }
                }
            }.then(on: ForstaClient.workQueue) { () -> Promise<[JSON]> in
                if missing.count == 0 {
                    return Promise.value(users)
                } else {
                    return self.request("/v1/directory/user/?id_in=" + Array(missing).map({ $0.lcString }).joined(separator: ","))
                        .map(on: ForstaClient.workQueue) { (statusCode, json) in
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
        return request(url)
            .then(on: ForstaClient.workQueue) { result -> Promise<[JSON]> in
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
    public func getTags() -> Promise<[JSON]> {
        return allResults(url: "/v1/tag/")
    }

    // -MARK: Atlas Calls for Signal Server Assistance
    
    ///
    /// Request provisioning assistance from any existing devices.
    ///
    /// - parameter uuidString: provisioning UUID string provided by Signal server
    /// - parameter pubKeyString: base64-encoded public key to use in encrypting provisioning secrets for me
    ///
    /// - returns: `Promise` resolving to results bundled in a `JSON`
    ///
    public func provisionSignalDevice(uuidString: String, pubKeyString: String) -> Promise<JSON> {
        return request("/v1/provision/request",
                       method: .post,
                       parameters: [ "uuid": uuidString,
                                     "key": pubKeyString ])
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Provision/refresh a new Signal Server account.
    ///
    /// - returns: `Promise` resolving to results bundled in a `JSON`.
    ///
    public func provisionSignalAccount(_ fields: [String: Any]) -> Promise<JSON> {
        return request("/v1/provision/account", method: .put, parameters: fields)
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 { return json }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Retrieve information about the current Signal server account and its devices.
    ///
    public func getSignalAccountInfo() -> Promise<SignalAccountInfo> {
        return request("/v1/provision/account")
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 {
                    guard
                        let userIdRaw = json["userId"].string,
                        let userId = UUID(uuidString: userIdRaw),
                        let serverUrl = json["serverUrl"].string,
                        let devicesRaw = json["devices"].array else {
                            throw ForstaError(.malformedResponse, "missing expected account info components")
                    }
                    let devices = try devicesRaw.map { device throws -> SignalAccountInfo.DeviceInfo in
                        guard
                            let id = device["id"].uInt32,
                            let label = device["name"].string,
                            let lastSeenRaw = device["lastSeen"].uInt64,
                            let createdRaw = device["created"].uInt64 else {
                                throw ForstaError(.malformedResponse, "missing expected device info components")
                        }
                        return SignalAccountInfo.DeviceInfo(id: id,
                                                            label: label,
                                                            lastSeen: Date(millisecondsSince1970: lastSeenRaw),
                                                            created: Date(millisecondsSince1970: createdRaw))
                    }

                    return SignalAccountInfo(userId: userId, serverUrl: serverUrl, devices: devices)
                }
                throw ForstaError(.requestRejected, json)
        }
    }
    
    ///
    /// Retrieve information about our WebRTC TURN servers.
    ///
    /// - returns: `Promise` resolving to an array of `JSON` with TURN server info.
    ///
    public func getRtcTurnServersInfo() -> Promise<[JSON]> {
        return request("/v1/rtc/servers")
            .map(on: ForstaClient.workQueue) { (statusCode, json) in
                if statusCode == 200 { return json.arrayValue }
                throw ForstaError(.requestRejected, json)
        }
    }

    // -MARK: Utilities
    
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
        
        let parts = "\(tag):\(defaultOrg!)"
            .lowercased()
            .components(separatedBy: ":")
            .map { s in s.trimmingCharacters(in: trimmables) }
        
        return (parts[0], parts[1])
    }
    
    /// Internal: Basic Atlas http request that returns a `Promise` of `(statuscode, JSON)`
    private func request(_ url: String, method: HTTPMethod = .get, parameters: Parameters? = nil) -> Promise<(Int, JSON)> {
        return Promise { seal in
            let headers = isAuthenticated ? ["Authorization": "JWT \(authenticatedUserJwt!)"] : nil
            let fullUrl = url.starts(with: "http") ? url : "\(serverUrl!)\(url)"
            Alamofire.request(fullUrl, method: method, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON(queue: ForstaClient.workQueue) { response in
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
    private func maintainJwt() {
        do {
            guard let jwt = authenticatedUserJwt else { return }
            
            let decodedJwt = try decode(jwt: jwt)
            guard let timestamp = decodedJwt.body["exp"] as? Double,
                timestamp > Date().timeIntervalSince1970 else {
                    print("warning: jwt missing expiration or in the past")
                    expireJwt()
                    return
            }
            
            guard let id = decodedJwt.body["user_id"] as? String,
                let uuid = UUID(uuidString: id) else {
                    print("warning: malformed jwt, missing user_id")
                    expireJwt()
                    return
            }

            self.authenticatedUserId = uuid
            NotificationCenter.broadcast(.atlasCredentialSet, ["jwt": jwt])
            self.delegates.notify { $0.credentialSet(jwt: jwt) }
            
            let halfDead = DispatchTime.now() + DispatchTimeInterval.seconds(Int(timestamp - Date().timeIntervalSince1970) / 2)
            DispatchQueue.main.asyncAfter(deadline: halfDead) { self.refreshJwt() }
        } catch {
            expireJwt()
        }
    }
    
    /// Internal: Clear all traces of a stashed JWT and broadcast that event.
    private func expireJwt() {
        self.authenticatedUserJwt = nil
        self.authenticatedUserId = nil
        NotificationCenter.broadcast(.atlasCredentialExpired, nil)
        self.delegates.notify { $0.credentialExpired() }
    }
    
    // -MARK: Related Subtypes
    
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
    
    /// Account info reported by Signal server
    public struct SignalAccountInfo {
        /// The user's ID
        public let userId: UUID
        /// The server URL to use for Signal requests
        public let serverUrl: String
        /// The current set of devices
        public let devices: [DeviceInfo]
        
        /// Device info reported by Signal server
        public struct DeviceInfo {
            /// The device id
            public let id: UInt32
            /// The device label ("name")
            public let label: String
            /// Datetime last seen
            public let lastSeen: Date
            /// Creation datetime
            public let created: Date
        }
    }

    /// Results of evaluating a tag expression
    public struct TagExpressionResolution {
        /// The "pretty" version of this evaluated expression (simplified, human-readable with slug strings, qualified for the evaluating user's organization)
        public let pretty: String
        /// The "universal" version of this evaluated expression (simplified, uses absolute tag IDs rather than slug strings)
        public let universal: String
        /// The users this expression resolves to
        public let users: [UUID]
        /// The monitors that were included in the resolution
        public let monitors: [UUID]
        /// The tags which were "positively" used in the expression (i.e., added)
        public let includedTags: [UUID]
        /// The tags which were "negatively" used in the expression (i.e., subtracted)
        public let excludedTags: [UUID]
        /// Warnings about lexing, parsing, or evaluation issues
        public let warnings: [Warning]
        
        /// Warning about tag-math resolution
        public struct Warning {
            /// the general category of this warning
            public let source: Source
            /// general categories that the kinds of warnings fall into
            public enum Source: String {
                /// a lexical warning (like extra text that is being ignored)
                case lex
                /// a parsing warning (like noting an implicit union or unbalanced parens)
                case parse
                /// a parsing warning (like noting an unrecognized tag)
                case eval
            }
            /// the kind of this warning
            public let kind: Kind
            /// various kinds of tag-math resolution warnings
            public enum Kind: String {
                /// superficial lexical adjustments (`.lex` source)
                case trimmed
                /// serious lexical adjustments that could be surprising (`.lex` source)
                case ignored
                /// random text understood as a union operator (`.parse` source)
                case implicitUnion = "implicit union"
                /// unexpected item(s) necessitating recovery-guesses (`.parse` source)
                case unexpected
                /// unbalanced parens necessitating recovery-guesses (`.parse` source)
                case unbalanced
                /// unknown tag (`.eval` source)
                case unrecognized
            }
            /// a hint to show to a user (usually an offending snippet of the input)
            public let cue: String
            /// offset into the original input of the warning
            public let position: UInt
            /// length of the text in the original input causing the warning
            public let length: UInt
        }
    }
}


/// Important events for an Atlas client that you can register to receive
public protocol AtlasClientDelegate: class {
    /// The authenticated user's credential has expired.
    func credentialExpired()
    /// The authenticated user's credential has been set (either by authenticating, or by the JWT being refreshed)
    func credentialSet(jwt: String)
}
extension AtlasClientDelegate {
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    func credentialExpired() { }
    /// Default no-op implementation so you aren't forced to include one in your delegate class
    func credentialSet(jwt: String) { }
}
