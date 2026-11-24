//
//  AssetMatcher.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/30/26.
//

import Foundation

enum AssetMatchResult {
    case single(String)
    case ambiguous([String])
    case none
}

struct AssetMatcher {
    private let currentAssets: [CurrentAssetRecord]
    private let byLocalIdentifier: [String: CurrentAssetRecord]
    private let bySignature: [String: [CurrentAssetRecord]]

    init(currentAssets: [CurrentAssetRecord]) {
        self.currentAssets = currentAssets

        self.byLocalIdentifier = Dictionary(
            uniqueKeysWithValues: currentAssets.map { ($0.localIdentifier, $0) }
        )

        var signatureMap: [String: [CurrentAssetRecord]] = [:]

        for asset in currentAssets {
            for signature in Self.signatures(
                mediaType: asset.mediaType,
                originalFilename: asset.originalFilename,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration
            ) {
                signatureMap[signature, default: []].append(asset)
            }
        }

        self.bySignature = signatureMap
    }

    func match(_ oldAsset: AlbumManifestAsset) -> AssetMatchResult {
        if let currentAsset = byLocalIdentifier[oldAsset.localIdentifier] {
            return .single(currentAsset.localIdentifier)
        }

        var candidates = Set<String>()

        for signature in Self.signatures(
            mediaType: oldAsset.mediaType,
            originalFilename: oldAsset.originalFilename,
            creationDate: oldAsset.creationDate,
            modificationDate: oldAsset.modificationDate,
            pixelWidth: oldAsset.pixelWidth,
            pixelHeight: oldAsset.pixelHeight,
            duration: oldAsset.duration
        ) {
            for candidate in bySignature[signature] ?? [] {
                candidates.insert(candidate.localIdentifier)
            }
        }

        if candidates.count == 1, let only = candidates.first {
            return .single(only)
        }

        if candidates.count > 1 {
            return .ambiguous(Array(candidates).sorted())
        }

        return .none
    }

    private static func signatures(
        mediaType: String,
        originalFilename: String?,
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: Double?
    ) -> [String] {
        var signatures: [String] = []

        let filename = originalFilename?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let creation = creationDate.map { roundedDateString($0, seconds: 2) } ?? "nil"
        let modification = modificationDate.map { roundedDateString($0, seconds: 2) } ?? "nil"
        let durationString = duration.map { String(format: "%.1f", $0) } ?? "nil"

        if !filename.isEmpty {
            signatures.append([
                "strong",
                mediaType,
                filename,
                creation,
                "\(pixelWidth)",
                "\(pixelHeight)",
                durationString
            ].joined(separator: "|"))
        }

        signatures.append([
            "date-dim",
            mediaType,
            creation,
            "\(pixelWidth)",
            "\(pixelHeight)",
            durationString
        ].joined(separator: "|"))

        if !filename.isEmpty {
            signatures.append([
                "file-mod-dim",
                mediaType,
                filename,
                modification,
                "\(pixelWidth)",
                "\(pixelHeight)"
            ].joined(separator: "|"))
        }

        return signatures
    }

    private static func roundedDateString(_ date: Date, seconds: TimeInterval) -> String {
        let rounded = Date(
            timeIntervalSince1970: (date.timeIntervalSince1970 / seconds).rounded() * seconds
        )

        return ISO8601DateFormatter().string(from: rounded)
    }
}
