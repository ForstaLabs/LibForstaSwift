//
//  LibForstaSwiftTests.swift
//  LibForstaSwiftTests
//
//  Created by Greg Perkins on 4/17/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import XCTest
import PromiseKit
import SwiftyJSON
import OneTimePassword
import Base32

@testable import LibForstaSwift

let dummyTwilioNumber = "+15005550006"

let testBaseUrl = "http://localhost:8000"
let testOrgSlug = "test.org.\(String(Int.random(in: 1000..<10000)))"
var (testOrgReady, testOrgReadyResolver) = Promise<Void>.pending()

let totpSecret = "4242424242424242"
let totpGenerator = setupTotp()
var passwordUserAuthToken = "tbd"

func setupTotp() -> Token? {
    guard let secretData = MF_Base32Codec.data(fromBase32String: totpSecret),
        !secretData.isEmpty else {
            print("Invalid secret")
            return nil
    }
    
    guard let generator = Generator(
        factor: .timer(period: 30),
        secret: secretData,
        algorithm: .sha1,
        digits: 6) else {
            print("Invalid generator parameters")
            return nil
    }
    
    let token = Token(name: "me", issuer: "forsta", generator: generator)
    return token
}

class AtlasClientTests: XCTestCase {
    //
    // NOTE: These tests require a local Atlas server that has a public domain, listening on port 8000
    // also, you will need to set the following env variables for the JWT-Proxy authentication to succeed:
    /*
export JWT_PROXY_PUBLIC_KEY='LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUF6S1RsVy93NnkrMnphOU80K0JWbwpVZTBVNURIK1QzWXpNK3F4OG9aS245Y2ZrSmtOeG1TZDJGRTF2S01zNnNVdFFBTm1JWEpTUGMvVEQ2cEdpQmpTCmxlbWxxcjRpWTJTNTNFanQzZFJsaXN1N1R5WDIyazBIb2hKdjdUUEZhNVdJYmtuS3F0N0tzUnhReGM0MWs0aEgKTXA4aDBBemN3MWdTUXJPWkhLTXBpNU9ncVlzMmZtTjlXV1JzZGk4d3NzMjlQOWZJbEMyTU15TDJTaGd6eDBWTQp4cWxvcWtMblhrVkpHbTlUK3dHOTVEMWp2b21RQWtBN1o0NHhGenNRSzUrTDYzVS94V1JDNzZXVTk5Um5kMXBhCm00S1pmY2lqQzRnMXozUk5BZjl5UERDWVZpeURPZVZVS0FRdEZDNW95OTZNOFEwdGJ1VEx6emVhaG9BYk1xM1IKN3dJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0t'
export JWT_PROXY_ISSUER='sherpany'
export JWT_PROXY_AUDIENCE='atlas'
    */
    //
    // testCredentialRefresh() and testSMSAuthentication require customization of the server code (see their comments)
    //
    
    override static func setUp() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Admin",
                          "tag_slug": "admin",
                          "password": "asdfasdf24",
                          "org_name": "Test Org",
                          "org_slug": testOrgSlug])
            .map { result in
                let (fullTag, _) = result
                XCTAssert(fullTag == "@admin:"+testOrgSlug)
            }
            .then {
                atlas.createUser(["first_name": "SMS", "tag_slug": "sms"])
            }
            .then { _ in
                atlas.createUser(["first_name": "Password", "tag_slug": "password", "password": "asdfasdf24"])
            }
            .then { passUser in
                atlas.getUserAuthToken(userId: passUser["id"].stringValue)
            }
            .map { tokenInfo in
                passwordUserAuthToken = tokenInfo["token"].stringValue
                XCTAssert(passwordUserAuthToken.count > 20)
            }
            .then {
                atlas.createUser(["first_name": "Twofactor", "tag_slug": "twofactor", "password": "asdfasdf24"])
            }
            .then { twofactor -> Promise<JSON> in
                let otpString = totpGenerator?.currentPassword ?? "ugh"
                return atlas.updateUser(twofactor["id"].stringValue, [
                    "password_proof": "asdfasdf24",
                    "new_totp_secret": totpSecret,
                    "totp_proof": otpString])
            }
            .done { updatedTwofactor in
                // finally, create user with specific ID for JWT-PROXY authentication
                // (it is okay if this fails because the user already exists in the db;
                // the authentication test will still work)
                // ... and then resolve the test org as ready
                let _ = atlas.createUser(["first_name": "JWT-Proxy", "tag_slug": "jwt.proxy", "id": "5a5f4ce3-c202-4cd7-9ef5-cec6e7b2dc09"])
                    .ensure {
                        testOrgReadyResolver.fulfill(())
                }
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
                XCTFail("test org creation failed")
                testOrgReadyResolver.reject(ForstaError("can't create test org", cause: error))
            }
    }

    override func setUp() {
        let expectation = XCTestExpectation(description: "test org ready")
        let _ = testOrgReady.done { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testTagParts() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        atlas.defaultOrg = "yobaby"
        
        var (n1, o1) = atlas.tagParts("foo")
        XCTAssert(n1 == "foo")
        XCTAssert(o1 == "yobaby")
        
        (n1, o1) = atlas.tagParts("@Foo")
        XCTAssert(n1 == "foo")
        XCTAssert(o1 == "yobaby")
        
        (n1, o1) = atlas.tagParts("foo:bar")
        XCTAssert(n1 == "foo")
        XCTAssert(o1 == "bar")
        
        (n1, o1) = atlas.tagParts(" @Foo : Bar ")
        XCTAssert(n1 == "foo")
        XCTAssert(o1 == "bar")
        
        (n1, o1) = atlas.tagParts("")
        XCTAssert(n1 == "")
        XCTAssert(o1 == "yobaby")
        
        (n1, o1) = atlas.tagParts(" :bar ")
        XCTAssert(n1 == "")
        XCTAssert(o1 == "bar")
    }
    
    func testRequestAuthentication() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        var expectations:[XCTestExpectation] = []

        let goodCases = [
            "@sms:\(testOrgSlug)" : AtlasAuthenticationMethod.sms,
            "@password:\(testOrgSlug)" : AtlasAuthenticationMethod.password,
            "@twofactor:\(testOrgSlug)" : AtlasAuthenticationMethod.passwordOtp
        ]

        for (userTag, expectedResult) in goodCases {
            let expectation = XCTestExpectation(description: "requestAuthentication \(userTag)")
            expectations.append(expectation)
            
            atlas.requestAuthentication(userTag)
                .done { result in
                    XCTAssert(result == expectedResult)
                }
                .catch { error in
                    XCTFail(error.localizedDescription)
                }
                .finally {
                    expectation.fulfill()
            }
        }
        
        let expectation2 = XCTestExpectation(description: "requestAuthentication @unknown")
        expectations.append(expectation2)
        
        atlas.requestAuthentication("@unknown:\(testOrgSlug)")
            .done { result in
                XCTFail("should have failed to find the user")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["non_field_errors"].arrayValue.contains("unknown user"))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                expectation2.fulfill()
        }
        
        atlas.baseUrl += "/v1/whatevs/"
        let expectation3 = XCTestExpectation(description: "requestAuthentication 3")
        expectations.append(expectation3)
        
        atlas.requestAuthentication("@sms:\(testOrgSlug)")
            .done { result in
                XCTFail("should have failed to find the domain")
            }
            .catch { error in
                XCTAssert(((error as? ForstaError)?.type ?? .unknown) == ForstaErrorType.requestFailure)
            }
            .finally {
                expectation3.fulfill()
        }

        atlas.baseUrl = "https://nobodys.server.anywhere.foobar/"
        let expectation4 = XCTestExpectation(description: "requestAuthentication 3")
        expectations.append(expectation4)
        
        atlas.requestAuthentication("@sms:\(testOrgSlug)")
            .done { result in
                XCTFail("should have failed to find the domain")
            }
            .catch { error in
                XCTAssert(((error as? ForstaError)?.type ?? .unknown) == ForstaErrorType.requestFailure)
            }
            .finally {
                expectation4.fulfill()
        }

        wait(for: expectations, timeout: 10.0)
    }
    
    func testAuthentication() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectation1 = XCTestExpectation(description: "auth via password")
        
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                expectation1.fulfill()
        }
        
        let expectation2 = XCTestExpectation(description: "failed auth via password, bad pw")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "wrong pw")
            .done { result in
                XCTFail("password authentication should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["password"].arrayValue.contains("invalid password"))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                expectation2.fulfill()
        }
        
        let expectation3 = XCTestExpectation(description: "failed auth via password, bad user")
        atlas.authenticateViaPassword(userTag: "@unknown:\(testOrgSlug)", password: "asdfasdf24")
            .done { result in
                XCTFail("password authentication should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["password"].arrayValue.contains("invalid password"))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                expectation3.fulfill()
        }
        
        let expectation4 = XCTestExpectation(description: "auth via userauthtoken")
        atlas.authenticateViaUserAuthToken(token: passwordUserAuthToken)
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("userauthtoken authentication failed")
            }
            .finally {
                expectation4.fulfill()
        }
        
        let expectation5 = XCTestExpectation(description: "auth via full password+totp")
        atlas.requestAuthentication("@twofactor:\(testOrgSlug)")
            .then { authMethod -> Promise<AuthenticatedAtlasUser> in
                XCTAssert(authMethod == .passwordOtp)
                let otpString = totpGenerator?.currentPassword ?? "ugh"
                return atlas.authenticateViaPasswordOtp(userTag: "@twofactor:\(testOrgSlug)", password: "asdfasdf24", otp: otpString)
            }.done { user in
                XCTAssert(user["first_name"].stringValue == "Twofactor")
            }.catch { error in
                print("FAILURE: \(error)")
                XCTFail("two factor authentication failed")
            }.finally {
                expectation5.fulfill()
        }
        
        let validJwt = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzUxMiJ9.eyJqdGkiOiI0NzIyMTIzNS1jNzg1LTRjODEtOGFlYS02MmQwZTZlNWNmNzEiLCJ0eXAiOiJhY2Nlc3MiLCJ2ZXIiOiIyLjIiLCJ1aWQiOiI1YTVmNGNlMy1jMjAyLTRjZDctOWVmNS1jZWM2ZTdiMmRjMDkiLCJpYXQiOjE1NTc1MTk1ODksIm5iZiI6MTU1NzUxOTU4OSwiZXhwIjoyMTg4MjM5NTg5LCJpc3MiOiJzaGVycGFueSIsImF1ZCI6ImF0bGFzIn0.o__QwzZANp1ddiCRpdMCHHd3qCCklDwVPWoj3c4TFf-HoRPE3_X_tRaCe2jvVvIJHZluOOXoPve8wmEwV24GvRmfjrzQa8LJlGKnWGKH1qvB3iTPTasoYoK5xHP5nmKOe2BzsPK1LDxWeQ_UAx5yX-ah9ojF3WenLNC96Ur7KQdYFJNNuA4MzxB3EdHRd5s_kyfNk2VHBcVuZEyp4zf-Xj5FxJ37ySk9hkJzeMRAQxkbIVSb1xZ14_8sCB2IPOVqYRlNjdt1-xxaVst6uFdrcM_emNb53WgykUn53k7r0yKOuq7FnfH3_KpRHRBtYLjtuMeTE1WNzsP1zmKKCof0Jw"

        let expectation6 = XCTestExpectation(description: "auth via jwt-proxy")
        atlas.authenticateViaJwtProxy(jwt: validJwt)
            .done { user in
                XCTAssert(user["first_name"].stringValue == "JWT-Proxy")
            }
            .catch { error in
                XCTFail("jwt-proxy authentication failed")
            }
            .finally {
                expectation6.fulfill()
        }
        
        let expiredJwt = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzUxMiJ9.eyJqdGkiOiIwMDRmNWE4Yi1mYjY3LTQ2MTEtODFiZS1jNWIxYWI0MmE1ZDMiLCJ0eXAiOiJhY2Nlc3MiLCJ2ZXIiOiIyLjIiLCJ1aWQiOiI1YTVmNGNlMy1jMjAyLTRjZDctOWVmNS1jZWM2ZTdiMmRjMDkiLCJpYXQiOjE1MTQ3NjQ4MDAsIm5iZiI6MTUxNDc2NDgwMCwiZXhwIjoxNTE0NzY0ODYwLCJpc3MiOiJzaGVycGFueSIsImF1ZCI6ImF0bGFzIn0.EWWl-WrRWAhiBOreHHhrd_sBf7jQ3hGmi4rekuMdOz3l_VUqg_Y-Su1-ZOiyPIMQ2KQg82er9hYL4M1TzIuW_G8XJVWJLhkMq0tGcqGvGkbSX_CVVCeJ3eJtZDlaYC9Bx_zptr-3HF2uGfPaANW0xuIqFkkAC5wiyRNOE-clJB3B_Nczy0ASaUUZaFzpAYF73Qfh7SvpspkkoOJvfA4SCV25h9NULQvjNH06gCKmZe6EAZ_XW4clA-SLwsVtQ9fyfi37PC9jvZ3x2xJqz83t-EZRZSTQYnYb5YUbB0k71cTBRpswElo2nApgIpmHjV2w23Ibo8aix0d1L4ENKC-mMw"

        let expectation7 = XCTestExpectation(description: "failed auth via jwt-proxy")
        atlas.authenticateViaJwtProxy(jwt: expiredJwt)
            .done { user in
                XCTFail("invalid jwt-proxy authentication should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["non_field_errors"].arrayValue.contains("invalid auth"))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                expectation7.fulfill()
        }

        wait(for: [expectation1, expectation2, expectation3, expectation4, expectation5, expectation6, expectation7], timeout: 10.0)
    }
    
    func testAtlasClientRestore() {
        let kvstore = MemoryKVStore()
        let atlas = AtlasClient(kvstore: kvstore)
        atlas.baseUrl = testBaseUrl
        
        XCTAssert(!kvstore.has(ns: kvstore.defaultNamespace, key: DNK.atlasCredential))
        XCTAssert(atlas.authenticatedUserId == nil)
        XCTAssert(atlas.authenticatedUserJwt == nil)
        
        let expectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssert(atlas.authenticatedUserId != nil)
        XCTAssert(atlas.authenticatedUserJwt != nil)
        XCTAssert(kvstore.has(ns: kvstore.defaultNamespace, key: DNK.atlasCredential))
        
        let expectation2 = XCTestExpectation(description: "credential-set notification")
        let setObserver = NotificationCenter.default.addObserver(
            forName: .atlasCredentialSet,
            object: nil,
            queue: nil) { notification in expectation2.fulfill() }
        
        let atlas2 = AtlasClient(kvstore: atlas.kvstore)
        wait(for: [expectation2], timeout: 10.0)
        NotificationCenter.default.removeObserver(setObserver)

        XCTAssert(atlas.authenticatedUserId == atlas2.authenticatedUserId)
        XCTAssert(atlas.authenticatedUserJwt == atlas2.authenticatedUserJwt)
        
        let expectation3 = XCTestExpectation(description: "credential-expired notification")
        let expiredObserver = NotificationCenter.default.addObserver(
            forName: .atlasCredentialExpired,
            object: nil,
            queue: nil) { notification in expectation3.fulfill() }
        
        kvstore.set(DNK.atlasCredential, "nonsense jwt".data(using: .utf8)!)
        let atlas3 = AtlasClient(kvstore: atlas2.kvstore)
        wait(for: [expectation3], timeout: 10.0)
        NotificationCenter.default.removeObserver(expiredObserver)
        
        XCTAssert(!kvstore.has(ns: kvstore.defaultNamespace, key: DNK.atlasCredential))
        XCTAssert(atlas3.authenticatedUserId == nil)
        XCTAssert(atlas3.authenticatedUserJwt == nil)
    }
    
    func testTagExpressionResolution() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        
        let expectation2 = XCTestExpectation(description: "resolve tag expression")
        atlas.resolveTagExpression("@sms + @twofactor")
            .done { result in
                XCTAssert(result["userids"].arrayValue.count == 2)
            }
            .catch { error in
                XCTFail("resolve tag expression failed \(error)")
            }
            .finally {
                expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 5.0)
    }
    
    func testTagExpressionBatchResolution() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        
        let expectation2 = XCTestExpectation(description: "resolve tag expression")
        atlas.resolveTagExpressionBatch(["@sms + @twofactor", "@sms", "@sms + @password + @twofactor"])
            .done { result in
                XCTAssert(result.arrayValue.count == 3)
                XCTAssert(result[0]["userids"].arrayValue.count == 2)
                XCTAssert(result[1]["userids"].arrayValue.count == 1)
                XCTAssert(result[2]["userids"].arrayValue.count == 3)
            }
            .catch { error in
                XCTFail("resolve tag expression failed \(error)")
            }
            .finally {
                expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 5.0)
    }
    
    func testGetUsers() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectAuth = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                expectAuth.fulfill()
        }
        wait(for: [expectAuth], timeout: 5.0)
        
        let expectTags = XCTestExpectation(description: "resolve tag expression")
        var userIds: [String] = []
        atlas.resolveTagExpression("@sms + @twofactor + @password")
            .done { result in
                userIds = result["userids"].arrayValue.map { s in s.stringValue }
                XCTAssert(userIds.count == 3, "should have three users")
            }.catch { error in
                XCTFail("resolve tag expression failed \(error)")
            }.finally {
                expectTags.fulfill()
        }
        wait(for: [expectTags], timeout: 5.0)
        
        let expectUsers = XCTestExpectation(description: "resolve tag expression")
        var users1: [JSON] = []
        atlas.getUsers(userIds: userIds).done { result in
            users1 = result
            XCTAssert(result.count == 3)
            }.catch { error in
            }.finally {
                expectUsers.fulfill()
        }
        wait(for: [expectUsers], timeout: 5.0)
        
        let expectUsers2 = XCTestExpectation(description: "resolve tag expression")
        var users2: [JSON] = []
        atlas.getUsers(userIds: userIds, onlyPublicDirectory: true).done { result in
            users2 = result
            XCTAssert(result.count == 3)
            }.catch { error in
            }.finally {
                expectUsers2.fulfill()
        }
        wait(for: [expectUsers2], timeout: 5.0)
        
        XCTAssert(users1.contains { x in x["first_name"].stringValue == "Password" })
        XCTAssert(users1.contains { x in x["first_name"].stringValue == "SMS" })
        XCTAssert(users1.contains { x in x["first_name"].stringValue == "Twofactor" })

        XCTAssert(users2.contains { x in x["first_name"].stringValue == "Password" })
        XCTAssert(users2.contains { x in x["first_name"].stringValue == "SMS" })
        XCTAssert(users2.contains { x in x["first_name"].stringValue == "Twofactor" })

        XCTAssert(users1[0]["address"].dictionary != nil)
        XCTAssert(users2[0]["address"].dictionary == nil)
    }

    func testGetDevices() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .map { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .then {
                atlas.getDevices()
            }
            .done { devices in
                XCTAssert(devices.count == 0)
            }.catch { error in
                XCTFail("error authenticating and getting devices \(error)")
            }.finally {
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testUserAndOrgCreation() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let uniquifier = String(Int.random(in: 1000..<10000)) // so I don't have to keep resetting my local db
        
        var setCount = 0
        let setObserver = NotificationCenter.default.addObserver(
            forName: .atlasCredentialSet,
            object: nil,
            queue: nil) { notification in setCount += 1 }
        
        let successfulCreation = XCTestExpectation(description: "user+org creation")
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Foo",
                          "tag_slug": "foo",
                          "password": "asdfasdf24",
                          "org_name": "Bar",
                          "org_slug": "bar" + uniquifier])
            .done { result in
                let (fullTag, _) = result
                XCTAssert(fullTag == "@foo:bar" + uniquifier)
            }
            .catch { error in
                XCTFail("creation failed")
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
            }
            .finally {
                successfulCreation.fulfill()
        }
        
        wait(for: [successfulCreation], timeout: 5.0)
        
        let duplicateCreation = XCTestExpectation(description: "duplicate creation")
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Foo",
                          "tag_slug": "foo",
                          "password": "asdfasdf24",
                          "org_name": "Bar",
                          "org_slug": "bar" + uniquifier])
            .done { result in
                XCTFail("creation should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["org_slug"].arrayValue.contains("Already in use."))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                duplicateCreation.fulfill()
        }
        
        wait(for: [duplicateCreation], timeout: 5.0)
        
        let publicCreation = XCTestExpectation(description: "public creation")
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Joe Schmoe",
                          "tag_slug": "joe" + uniquifier,
                          "password": "asdfasdf24"])
            .done { result in
                let (fullTag, _) = result
                XCTAssert(fullTag == "@joe\(uniquifier):forsta")
            }
            .catch { error in
                XCTFail("creation failed")
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
            }
            .finally {
                publicCreation.fulfill()
        }
        wait(for: [publicCreation], timeout: 5.0)
        
        let publicCreationFailure = XCTestExpectation(description: "public creation failure")
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Joe Schmoe",
                          "tag_slug": "joe" + uniquifier,
                          "password": "asdfasdf24"])
            .done { result in
                XCTFail("creation should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["tag_slug"].arrayValue.contains("Already in use."))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                publicCreationFailure.fulfill()
        }
        wait(for: [publicCreationFailure], timeout: 5.0)
        
        let unknownInvitationFailure = XCTestExpectation(description: "unknown invitation failure")
        atlas.joinForsta(invitationToken: "deadbeef",
                         ["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Doesn't Matter",
                          "tag_slug": "joe.deadbeef",
                          "password": "asdfasdf24"])
            .done { result in
                XCTFail("creation should have failed")
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    XCTAssert(ferr.json["non_field_errors"].arrayValue.contains("Invitation not found: deadbeef"))
                } else {
                    XCTFail("surprising error")
                }
            }
            .finally {
                unknownInvitationFailure.fulfill()
        }
        wait(for: [unknownInvitationFailure], timeout: 5.0)
        
        XCTAssert(setCount == 2)
        NotificationCenter.default.removeObserver(setObserver)
    }

    func testAdminCRUD() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let uniquifier = String(Int.random(in: 1000..<10000)) // so I don't have to keep resetting my local db
        
        let successfulCreation = XCTestExpectation(description: "user+org creation")
        atlas.joinForsta(["captcha": "doesn't matter locally",
                          "email": "nobody@qwerwerwerewrwr4314324qewre.com",
                          "fullname": "Foo",
                          "tag_slug": "foo",
                          "password": "asdfasdf24",
                          "org_name": "Bar",
                          "org_slug": "bar" + uniquifier])
            .done { result in
                let (fullTag, _) = result
                XCTAssert(fullTag == "@foo:bar" + uniquifier)
            }
            .catch { error in
                XCTFail("creation failed")
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
            }
            .finally {
                successfulCreation.fulfill()
        }
        
        wait(for: [successfulCreation], timeout: 5.0)
        
        let userCreation = XCTestExpectation(description: "user creation")
        var newUserId: String?
        atlas.createUser(["first_name": "Baz", "tag_slug": "baz"])
            .done { result in
                XCTAssert(result["first_name"].stringValue == "Baz")
                newUserId = result["id"].stringValue
                XCTAssert(newUserId!.count > 0)
                
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    print(ferr)
                    XCTFail()
                }
                XCTFail("surprising error")
            }
            .finally {
                userCreation.fulfill()
        }
        wait(for: [userCreation], timeout: 5.0)
        
        let userUpdate = XCTestExpectation(description: "user update")
        atlas.updateUser(newUserId ?? "", ["last_name": "Bar"])
            .done { result in
                XCTAssert(result["first_name"].stringValue == "Baz")
                XCTAssert(result["last_name"].stringValue == "Bar")
                XCTAssert(result["id"].stringValue.count > 0)
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
                XCTFail("surprising error")
            }
            .finally {
                userUpdate.fulfill()
        }
        wait(for: [userUpdate], timeout: 5.0)
    }
    
    func testInvitations() {
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        let expectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .map { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .then {
                atlas.sendInvitation(["phone":dummyTwilioNumber, "first_name": "Foo", "last_name": "Bar"])
            }
            .then { pendingUserId in
                atlas.revokeInvitation(pendingUserId)
            }
            .then {
                atlas.sendInvitation(["phone":dummyTwilioNumber, "first_name": "Baz", "last_name": "Foo"])
            }
            .done { pendingUserId in
                XCTAssert(pendingUserId.count > 0)
            }
            .catch { error in
                if let ferr = error as? ForstaError {
                    print(ferr)
                }
                XCTFail("surprising error")
            }.finally {
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testSMSAuthentication() {
        //
        // Local server must be customized in ccsm_api/ccsm_user/models.py
        // to make gen_login_token set the token value to "424242"
        //
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        let userTag = "@sms:\(testOrgSlug)"
        atlas.baseUrl = testBaseUrl
        
        let expectation = XCTestExpectation(description: "auth via full sms")
        atlas.requestAuthentication(userTag)
            .map { authMethod in
                XCTAssert(authMethod == .sms)
            }
            .then { _ in
                atlas.authenticateViaCode(userTag: userTag, code: "424242")
            }
            .done { user in
                XCTAssert(user["first_name"].stringValue == "SMS")
            }
            .catch { error in
                XCTFail("sms authentication failed")
            }
            .finally {
                expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testCredentialRefresh() {
        //
        // Local server must be customized in ccsm_api/ccsm_api/settings.py with:
        // 'JWT_EXPIRATION_DELTA': datetime.timedelta(minutes=1),
        // 'JWT_REFRESH_EXPIRATION_DELTA': datetime.timedelta(minutes=2),
        //
        let atlas = AtlasClient(kvstore: MemoryKVStore())
        atlas.baseUrl = testBaseUrl
        
        var setCount = 0
        let setObserver = NotificationCenter.default.addObserver(
            forName: .atlasCredentialSet,
            object: nil,
            queue: nil) { notification in
                setCount += 1
                print("CREDENTIAL SET COUNT: \(setCount)")
        }
        
        let expiredExpectation = XCTestExpectation(description: "credential-expired notification")
        let expiredObserver = NotificationCenter.default.addObserver(
            forName: .atlasCredentialExpired,
            object: nil,
            queue: nil) { notification in
                print("CREDENTIAL EXPIRED")
                expiredExpectation.fulfill()
        }
        
        let authExpectation = XCTestExpectation(description: "auth via password")
        atlas.authenticateViaPassword(userTag: "@password:\(testOrgSlug)", password: "asdfasdf24")
            .done { user in
                XCTAssert(user["first_name"].stringValue == "Password")
            }
            .catch { error in
                XCTFail("password authentication failed")
            }
            .finally {
                authExpectation.fulfill()
        }
        
        wait(for: [authExpectation, expiredExpectation], timeout: 60.0*3)
        XCTAssert(setCount > 4)
        NotificationCenter.default.removeObserver(setObserver)
        NotificationCenter.default.removeObserver(expiredObserver)
    }
}
