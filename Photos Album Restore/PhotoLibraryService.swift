//
//  PhotoLibraryService.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/27/26.
//

import Foundation
import Photos
import AppKit

actor PhotoLibraryService {

    enum PhotoLibraryServiceError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Zugriff auf die Fotos-Mediathek wurde nicht erlaubt."
            }
        }
    }

    func requestAccess() async throws {
        if #available(macOS 11.0, *) {
            let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

            if currentStatus == .authorized {
                return
            }

            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

            guard newStatus == .authorized else {
                throw PhotoLibraryServiceError.accessDenied
            }
        } else {
            let currentStatus = PHPhotoLibrary.authorizationStatus()

            if currentStatus == .authorized {
                return
            }

            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard newStatus == .authorized else {
                throw PhotoLibraryServiceError.accessDenied
            }
        }
    }

    func fetchAlbums() async throws -> [AlbumInfo] {
        try await requestAccess()

        var albumData: [AlbumInfo] = []
        var allMediaIdentifiers = Set<String>()
        var mediaInAlbums = Set<String>()

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true

        let allMedia = PHAsset.fetchAssets(with: fetchOptions)
        allMedia.enumerateObjects { asset, _, _ in
            allMediaIdentifiers.insert(asset.localIdentifier)
        }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)

            assets.enumerateObjects { asset, _, _ in
                mediaInAlbums.insert(asset.localIdentifier)
            }

            let title = collection.localizedTitle ?? "Unknown"

            albumData.append(
                AlbumInfo(
                    id: collection.localIdentifier,
                    name: title,
                    count: assets.count,
                    collectionLocalIdentifier: collection.localIdentifier,
                    selected: false
                )
            )
        }

        let orphanedMediaCount = allMediaIdentifiers.subtracting(mediaInAlbums).count

        albumData.append(
            AlbumInfo(
                id: AlbumInfo.notInAnyAlbumID,
                name: "Not in any album",
                count: orphanedMediaCount,
                collectionLocalIdentifier: nil,
                selected: false
            )
        )

        albumData.append(
            AlbumInfo(
                id: AlbumInfo.allMediaID,
                name: "All Media Items",
                count: allMediaIdentifiers.count,
                collectionLocalIdentifier: nil,
                selected: false
            )
        )

        return albumData.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated func openPhotosPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func createAlbumManifest(selectedAlbumIDs: Set<String>? = nil, progressHandler: @escaping (Double, String) -> Void) async throws -> AlbumManifest {
        try await requestAccess()
        
        var manifestAlbums: [AlbumManifestAlbum] = []
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true
        
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )
        
        let totalCollections = collections.count
        var processedCollections = 0
        
        collections.enumerateObjects { collection, _, _ in
            if let selectedAlbumIDs, !selectedAlbumIDs.contains(collection.localIdentifier) {
                return
            }
            
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            var manifestAssets: [AlbumManifestAsset] = []
            
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                let originalFilename = resources.first?.originalFilename
                
                manifestAssets.append(
                    AlbumManifestAsset(
                        localIdentifier: asset.localIdentifier,
                        mediaType: Self.mediaTypeString(asset.mediaType),
                        originalFilename: originalFilename,
                        creationDate: asset.creationDate,
                        modificationDate: asset.modificationDate,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        duration: asset.mediaType == .video ? asset.duration : nil
                    )
                )
            }
            
            manifestAlbums.append(
                AlbumManifestAlbum(
                    name: collection.localizedTitle ?? "Unknown",
                    collectionLocalIdentifier: collection.localIdentifier,
                    assets: manifestAssets
                )
            )
            
            processedCollections += 1

            let progress = totalCollections > 0
                ? Double(processedCollections) / Double(totalCollections)
                : 1.0

            progressHandler(
                progress,
                "Scanne Album \(processedCollections) von \(totalCollections): \(collection.localizedTitle ?? "Unknown")"
            )
        }
        
        return AlbumManifest(
            generatedAt: Date(),
            albums: manifestAlbums
        )
    }

    nonisolated static func mediaTypeString(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
    
    func createCurrentAssetIndex(
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> CurrentAssetIndex {
        try await requestAccess()

        var assetRecords: [CurrentAssetRecord] = []

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        let totalAssets = allAssets.count

        allAssets.enumerateObjects { asset, index, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let originalFilename = resources.first?.originalFilename

            assetRecords.append(
                CurrentAssetRecord(
                    localIdentifier: asset.localIdentifier,
                    mediaType: Self.mediaTypeString(asset.mediaType),
                    originalFilename: originalFilename,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    duration: asset.mediaType == .video ? asset.duration : nil
                )
            )

            if index % 100 == 0 || index + 1 == totalAssets {
                let progress = totalAssets > 0
                    ? Double(index + 1) / Double(totalAssets)
                    : 1.0

                progressHandler(
                    progress,
                    "Scanne Asset \(index + 1) von \(totalAssets)"
                )
            }
        }

        return CurrentAssetIndex(
            generatedAt: Date(),
            assets: assetRecords
        )
    }
}
