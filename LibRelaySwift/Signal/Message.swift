//
//  Message.swift
//  LibRelaySwift
//
//  Created by Greg Perkins on 8/5/19.
//  Copyright © 2019 Forsta, Inc. All rights reserved.
//

import Foundation
import PromiseKit
import SwiftyJSON
import Starscream
import SignalProtocol


class Message {
    public var body: JSON?
    public var recipients = [SignalAddress]()
    
    func toProto() -> Relay_Content {
        var dm = Relay_DataMessage()
        
        if self.body != nil {
            dm.body = self.body!.rawString([.castNilToNSNull: true])!
        }
        
        var content = Relay_Content()
        content.dataMessage = dm
        
        /*
         if (this.attachmentPointers && this.attachmentPointers.length) {
         data.attachments = this.attachmentPointers;
         }
         if (this.flags) {
         data.flags = this.flags;
         }
         if (this.expiration) {
         data.expireTimer = this.expiration;
         }
         */
        
        return content;
    }
}
