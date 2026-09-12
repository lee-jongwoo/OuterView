//
//  Item.swift
//  OuterView
//
//  Created by 이종우 on 9/12/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
