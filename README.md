LibForstaSwift: Forsta Messaging in Swift
========
A Swift library for end-to-end encrypted messaging using the [Forsta](https://forsta.io) platform.


[![License](https://img.shields.io/npm/l/librelay.svg)](https://github.com/ForstaLabs/LibForstaSwift)
[![Change Log](https://img.shields.io/badge/change-log-blue.svg)](https://github.com/ForstaLabs/LibForstaSwift/blob/master/CHANGELOG.md)
[![Docs](https://img.shields.io/badge/docs-api-lightgrey.svg)](https://forstalabs.github.io/LibForstaSwift/index.html)


About
--------
This is a Swift library for communicating using the [Forsta](<https://forsta.io>) 
messaging platform.  The underlying protocol is based on the Signal end-to-end
crypto system.  The primary differences between Signal and Forsta surround how 
users are addressed, how device provisioning is accomplished, and the 
[custom JSON messaging payload]( <https://goo.gl/eX7gyC>) Forsta uses to support
a richer set of messaging functionality.

*Note that this library is used for sending and receiving end-to-end encrypted messages, 
and for communicating with Forsta's Atlas server about users and the tags used to refer to them. 
It does NOT persist messages, or cache user or tag information, or present any user interfaces 
(those would be important aspects of a server-based bot client or a full messaging app that are
outside the scope of this library).*

Please visit the [current API documentation online](https://forstalabs.github.io/LibForstaSwift/index.html)
for more details.

Storage
--------
LibForstaSwift requires a secure persistent namespace-key-value backing store 
adhering to the  `KVStorageProtocol`.  It is used for holding crypto key 
material, messaging session information, and server session information.  
This allows your application to stop and restart, picking up where it left 
off in its relationships with Forsta servers and other messaging clients.


Example
-------
PREREQUISITE: To use LibForstaSwift you must first have a valid Forsta account. 
You can sign up for free at <https://app.forsta.io/join>. 

Here is a simplified example of a chat-bot that responds to any incoming message 
with a line about how long that message was.

```swift
import LibForstaSwift

class Example: SignalClientDelegate {
    let forsta = try! ForstaClient(MyKVStore())
    let (finished, finishedSeal) = Promise<Void>.pending()

    // This will authenticate with password credentials, register a new device,
    // connect with the Signal server, and return a Promise that will resolve
    // when the example conversation has completed.
    func go() -> Promise<Void> {
        return firstly {
            forsta.atlas.authenticateViaPassword(userTag: "@me:my.org", password: "mypassword")
        }
        .map { _ in
            self.forsta.signal.registerDevice(deviceLabel: "swift chat bot")
        }
        .then { task in
            task.complete
        }
        .then { _ -> Promise<Void> in
            self.forsta.signal.delegates.add(self)
            try self.forsta.connect()
            return self.finished
        }
    }

    // This is a delegate method that is called with inbound messages.
    // We'll just print the text and immediately respond to the sender.
    func inboundMessage(message: InboundMessage) {
        if message.payload.messageType! == .content {
            let text = message.payload.bodyPlain ?? ""
            print("received text: \(text)")

            if text == "quit" {
                self.forsta.disconnect()
                finishedSeal.fulfill(())
            }

            // We'll cheat a little by treating the InboundMessage as our own
            // Sendable, simply modifying it in place and sending it back.
            // In a real application, you would use your own outgoing
            // message class conforming to Sendable.
            message.payload.sender = nil
            message.payload.messageId = UUID()
            message.timestamp = Date.timestamp
            message.payload.bodyPlain = "That's \(text.count) character(s)."

            print("Sending with timestamp \(message.timestamp.millisecondsSince1970): \(message.payload.bodyPlain ?? "???")")

            firstly {
                self.forsta.send(message, to: [.user(message.source.userId)])
            }
            .map { info in
                print("transmission information:", info)
            }
            .catch { error in
                print("send error: \(error)")
                self.finishedSeal.reject(error)
            }
        }
    }

    // This is a delegate method that is called with delivery receipts
    // handed up by the Signal server.
    func deliveryReceipt(receipt: DeliveryReceipt) {
        print(receipt)
    }
}

```

Cryptography Notice
--------
This library uses cryptographic libraries. The country in which you
currently reside may have restrictions on the import, possession, use, and/or
re-export to another country, of encryption software.  BEFORE using any
encryption software, please check your country's laws, regulations and
policies concerning the import, possession, or use, and re-export of
encryption software, to see if this is permitted.  See
<https://www.wassenaar.org/> for more information.

The U.S. Government Department of Commerce, Bureau of Industry and Security
(BIS), has classified this software as Export Commodity Control Number (ECCN)
5D002.C.1, which includes information security software using or performing
cryptographic functions with asymmetric algorithms.  The form and manner of
this distribution makes it eligible for export under the License Exception ENC
Technology Software Unrestricted (TSU) exception (see the BIS Export
Administration Regulations, Section 740.13) for both object code and source code.


License
--------
Licensed under the GPLv3: http://www.gnu.org/licenses/gpl-3.0.html

* Copyright 2014-2016 Open Whisper Systems
* Copyright 2017-2019 Forsta, Inc.
