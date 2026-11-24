//
//  CurrentAssetIndex.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/30/26.
//

import Foundation

struct CurrentAssetIndex: Codable {
    let generatedAt: Date
    let assets: [CurrentAssetRecord]
}

struct CurrentAssetRecord: Codable, Identifiable {
    var id: String { localIdentifier }

    let localIdentifier: String
    let mediaType: String
    let originalFilename: String?
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double?
}
