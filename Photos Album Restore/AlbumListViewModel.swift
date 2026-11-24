//
//  AlbumListViewModel.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/27/26.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AlbumListViewModel: ObservableObject {
    @Published var albums: [AlbumInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatusText: String = ""
    @Published var restorePlanSummary: RestorePlanSummary?
    @Published var restorePlanReportText: String = ""

    private let photoLibraryService = PhotoLibraryService()
    private let backupLibraryScanner = PhotosLibraryDatabaseScanner()

    var filteredAndSortedAlbums: [AlbumInfo] {
        var result = albums

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var selectedAlbums: [AlbumInfo] {
        albums.filter { $0.selected }
    }

    var selectedCount: Int {
        selectedAlbums.count
    }

    var allVisibleSelected: Bool {
        let visible = filteredAndSortedAlbums
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { $0.selected }
    }

    func loadAlbums() async {
        isLoading = true
        errorMessage = nil

        do {
            albums = try await photoLibraryService.fetchAlbums()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func toggleSelection(for album: AlbumInfo) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index].selected.toggle()
    }

    func setSelection(for album: AlbumInfo, selected: Bool) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index].selected = selected
    }

    func toggleSelectAllVisible() {
        let shouldSelect = !allVisibleSelected
        let visibleIDs = Set(filteredAndSortedAlbums.map { $0.id })

        for index in albums.indices {
            if visibleIDs.contains(albums[index].id) {
                albums[index].selected = shouldSelect
            }
        }
    }

    func clearSelection() {
        for index in albums.indices {
            albums[index].selected = false
        }
    }

    func openPhotosPrivacySettings() {
        photoLibraryService.openPhotosPrivacySettings()
    }
    
    func exportSelectedAlbumManifest() async {
        let selectedIDs = Set(
            selectedAlbums.compactMap { $0.collectionLocalIdentifier }
        )

        guard !selectedIDs.isEmpty else {
            errorMessage = "Bitte wähle mindestens ein normales Album aus."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Album Manifest"
        savePanel.nameFieldStringValue = "album_manifest.json"
        savePanel.allowedContentTypes = [.json]

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        isExporting = true
        exportProgress = 0
        exportStatusText = "Erstelle Album-Manifest…"

        do {
            let manifest = try await photoLibraryService.createAlbumManifest(
                selectedAlbumIDs: selectedIDs
            ) { progress, status in
                Task { @MainActor in
                    self.exportProgress = progress
                    self.exportStatusText = status
                }
            }

            exportStatusText = "Schreibe JSON-Datei…"

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(manifest)
            try data.write(to: url, options: [.atomic])

            exportProgress = 1
            exportStatusText = "Album-Manifest exportiert."
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }

    func exportBackupLibraryManifest() async {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Backup Photos Library"
        openPanel.message = "Choose the 2023 (or other) .photoslibrary backup. It will be read read-only via Photos.sqlite."
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.treatsFilePackagesAsDirectories = false
        if let photosLibraryType = UTType(filenameExtension: "photoslibrary") {
            openPanel.allowedContentTypes = [photosLibraryType]
        }

        guard openPanel.runModal() == .OK, let libraryURL = openPanel.url else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Backup Album Manifest"
        savePanel.nameFieldStringValue = "backup_album_manifest.json"
        savePanel.allowedContentTypes = [.json]

        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
            return
        }

        isExporting = true
        exportProgress = 0
        exportStatusText = "Scanne Backup-Mediathek…"
        errorMessage = nil

        do {
            let manifest = try await backupLibraryScanner.createAlbumManifest(
                libraryURL: libraryURL
            ) { progress, status in
                Task { @MainActor in
                    self.exportProgress = progress
                    self.exportStatusText = status
                }
            }

            exportStatusText = "Schreibe JSON-Datei…"

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(manifest)
            try data.write(to: outputURL, options: [.atomic])

            exportProgress = 1
            exportStatusText = "Backup-Manifest exportiert (\(manifest.albums.count) Alben)."
        } catch is CancellationError {
            exportStatusText = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }
    
    func exportCurrentAssetIndex() async {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Current Asset Index"
        savePanel.nameFieldStringValue = "current_asset_index.json"
        savePanel.allowedContentTypes = [.json]

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        isExporting = true
        exportProgress = 0
        exportStatusText = "Erstelle Current Asset Index…"

        do {
            let index = try await photoLibraryService.createCurrentAssetIndex { progress, status in
                Task { @MainActor in
                    self.exportProgress = progress
                    self.exportStatusText = status
                }
            }

            exportStatusText = "Schreibe JSON-Datei…"

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(index)
            try data.write(to: url, options: [.atomic])

            exportProgress = 1
            exportStatusText = "Current Asset Index exportiert."
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }
    
    func createRestorePlan() async {
        do {
            let manifestURL = try openJSONFilePanel(title: "Select Album Manifest JSON")
            let indexURL = try openJSONFilePanel(title: "Select Current Asset Index JSON")

            let savePanel = NSSavePanel()
            savePanel.title = "Save Restore Plan"
            savePanel.nameFieldStringValue = "restore_plan.json"
            savePanel.allowedContentTypes = [.json]

            guard savePanel.runModal() == .OK, let outputURL = savePanel.url else {
                return
            }

            isExporting = true
            exportProgress = 0
            exportStatusText = "Lade JSON-Dateien…"

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try decoder.decode(AlbumManifest.self, from: manifestData)

            let indexData = try Data(contentsOf: indexURL)
            let currentIndex = try decoder.decode(CurrentAssetIndex.self, from: indexData)

            exportProgress = 0.2
            exportStatusText = "Erstelle Matching-Index…"

            let matcher = AssetMatcher(currentAssets: currentIndex.assets)

            var albumPlans: [AlbumRestorePlan] = []
            var totalMatched = 0
            var totalUnmatched = 0
            var totalAmbiguous = 0

            for (albumIndex, album) in manifest.albums.enumerated() {
                var matchedIDs: [String] = []
                var unmatchedAssets: [AlbumManifestAsset] = []
                var ambiguousMatches: [AmbiguousAssetMatch] = []

                for asset in album.assets {
                    switch matcher.match(asset) {
                    case .single(let id):
                        matchedIDs.append(id)

                    case .ambiguous(let candidates):
                        ambiguousMatches.append(
                            AmbiguousAssetMatch(
                                oldAsset: asset,
                                candidateLocalIdentifiers: candidates
                            )
                        )

                    case .none:
                        unmatchedAssets.append(asset)
                    }
                }

                let uniqueMatchedIDs = Array(NSOrderedSet(array: matchedIDs)) as? [String] ?? matchedIDs

                totalMatched += uniqueMatchedIDs.count
                totalUnmatched += unmatchedAssets.count
                totalAmbiguous += ambiguousMatches.count

                albumPlans.append(
                    AlbumRestorePlan(
                        albumName: album.name,
                        albumPath: [album.name],
                        matchedAssetLocalIdentifiers: uniqueMatchedIDs,
                        unmatchedAssets: unmatchedAssets,
                        ambiguousMatches: ambiguousMatches
                    )
                )

                exportProgress = 0.2 + (0.7 * Double(albumIndex + 1) / Double(max(manifest.albums.count, 1)))
                exportStatusText = "Plane Album \(albumIndex + 1) von \(manifest.albums.count): \(album.name)"
            }

            let restorePlan = RestorePlan(
                generatedAt: Date(),
                albums: albumPlans
            )

            exportProgress = 0.95
            exportStatusText = "Schreibe Restore Plan…"

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601

            let outputData = try encoder.encode(restorePlan)
            try outputData.write(to: outputURL, options: [.atomic])

            restorePlanSummary = RestorePlanSummary(
                albumCount: albumPlans.count,
                matchedCount: totalMatched,
                unmatchedCount: totalUnmatched,
                ambiguousCount: totalAmbiguous
            )

            restorePlanReportText = makeDryRunReport(from: restorePlan)

            exportProgress = 1
            exportStatusText = "Restore Plan erstellt."
            isExporting = false

        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }
    
    private func openJSONFilePanel(title: String) throws -> URL {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }

        return url
    }

    private func makeDryRunReport(from plan: RestorePlan) -> String {
        var lines: [String] = []

        let totalMatched = plan.albums.reduce(0) { $0 + $1.matchedAssetLocalIdentifiers.count }
        let totalUnmatched = plan.albums.reduce(0) { $0 + $1.unmatchedAssets.count }
        let totalAmbiguous = plan.albums.reduce(0) { $0 + $1.ambiguousMatches.count }

        lines.append("DRY RUN REPORT")
        lines.append("")
        lines.append("Albums planned: \(plan.albums.count)")
        lines.append("Matched asset placements: \(totalMatched)")
        lines.append("Unmatched old assets: \(totalUnmatched)")
        lines.append("Ambiguous old assets: \(totalAmbiguous)")
        lines.append("")
        lines.append("No changes have been made to the Photos library.")
        lines.append("")

        for album in plan.albums {
            lines.append("Album: \(album.albumName)")
            lines.append("  Matched: \(album.matchedAssetLocalIdentifiers.count)")
            lines.append("  Unmatched: \(album.unmatchedAssets.count)")
            lines.append("  Ambiguous: \(album.ambiguousMatches.count)")

            if !album.unmatchedAssets.isEmpty {
                lines.append("  First unmatched examples:")
                for asset in album.unmatchedAssets.prefix(5) {
                    lines.append("    - \(asset.originalFilename ?? "unknown filename") | \(asset.creationDate?.description ?? "no date")")
                }
            }

            if !album.ambiguousMatches.isEmpty {
                lines.append("  First ambiguous examples:")
                for match in album.ambiguousMatches.prefix(5) {
                    lines.append("    - \(match.oldAsset.originalFilename ?? "unknown filename") | candidates: \(match.candidateLocalIdentifiers.count)")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
