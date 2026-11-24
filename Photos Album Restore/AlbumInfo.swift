//
//  AlbumInfo.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/27/26.
//

import Foundation

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
    let collectionLocalIdentifier: String?
    var selected: Bool

    static let notInAnyAlbumID = "__not_in_any_album__"
    static let allMediaID = "__all_media__"

    var isSpecialAlbum: Bool {
        id == Self.notInAnyAlbumID || id == Self.allMediaID
    }
}
