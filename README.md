LibForstaSwift: Forsta Messaging in Swift
========
Signal-based Swift library for end-to-end encrypted messaging on the [Forsta](https://forsta.io) platform.


[![License](https://img.shields.io/npm/l/librelay.svg)](https://github.com/ForstaLabs/LibForstaSwift)
[![Change Log](https://img.shields.io/badge/change-log-blue.svg)](https://github.com/ForstaLabs/LibForstaSwift/blob/master/CHANGELOG.md)
[![Docs](https://img.shields.io/badge/docs-api-lightgrey.svg)](https://forstalabs.github.io/LibForstaSwift/index.html)


About
--------
This is a Swift library used to communicate with the Forsta messaging
platform.  The underlying protocol is based on the Signal end-to-end
crypto system.  The primary differences surround how device provisioning 
is accomplished and the [custom JSON messaging payload]( <https://goo.gl/eX7gyC>).


Storage
--------
LibForstaSwift requires a secure persistent namespace-key-value backing store 
adhering to the  `KVStorageProtocol`.  It is used for holding crypto key 
material, messaging session information, and server session information.  
This allows your application to stop and restart, picking up where it left 
off in its relationships with Forsta servers and other messaging clients.


Authenticating and Registering
-------
PREREQUISITE: To use LibForstaSwift you must first have a valid Forsta account.  
You can sign up for free at <https://app.forsta.io/join>. 
```
import LibForstaSwift
...

let forsta = Forsta(kvstore)

forsta.atlas.authenticateViaPassword(userTag: "@fred:acme", password: "password42")
.then { _ in
    forsta.signal.registerAccount(name: "swifty fred")
}
.done {
    print("Signal account registered -- ready to send and receive messages.")
}
.catch { error in
    print("Trouble authenticating and registering:", error)
}
```

Message Receiving
-------

tbd


Message Sending
-------

tbd


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
* Copyright 2017-2019 Forsta Inc.
