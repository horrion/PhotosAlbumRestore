//
//  AlbumManifest.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/30/26.
//

import Foundation

struct AlbumManifest: Codable {
    let generatedAt: Date
    let albums: [AlbumManifestAlbum]
}

struct AlbumManifestAlbum: Codable, Identifiable {
    var id: String { collectionLocalIdentifier }
    
    let name: String
    let collectionLocalIdentifier: String
    let assets: [AlbumManifestAsset]
}

struct AlbumManifestAsset: Codable, Identifiable {
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
