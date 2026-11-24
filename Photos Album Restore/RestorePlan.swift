//
//  RestorePlan.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/30/26.
//

import Foundation

struct RestorePlan: Codable {
    let generatedAt: Date
    let albums: [AlbumRestorePlan]
}

struct AlbumRestorePlan: Codable, Identifiable {
    var id: String { albumPath.joined(separator: "/") }

    let albumName: String
    let albumPath: [String]
    let matchedAssetLocalIdentifiers: [String]
    let unmatchedAssets: [AlbumManifestAsset]
    let ambiguousMatches: [AmbiguousAssetMatch]
}

struct AmbiguousAssetMatch: Codable {
    let oldAsset: AlbumManifestAsset
    let candidateLocalIdentifiers: [String]
}

struct RestorePlanSummary {
    let albumCount: Int
    let matchedCount: Int
    let unmatchedCount: Int
    let ambiguousCount: Int
}
