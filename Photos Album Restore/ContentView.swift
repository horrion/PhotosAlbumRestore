//
//  ContentView.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/27/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AlbumListViewModel()
    @State private var sortOrder = [KeyPathComparator(\AlbumInfo.name)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else {
                VStack(spacing: 0) {

                        albumTable

                        if !viewModel.restorePlanReportText.isEmpty {

                            Divider()

                            dryRunReportView

                        }

                    }
            }

            if viewModel.isExporting {
                exportProgressView
                Divider()
            }

            footer
        }
        .frame(minWidth: 850, minHeight: 550)
        .task {
            await viewModel.loadAlbums()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.loadAlbums() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }

            Button {
                viewModel.toggleSelectAllVisible()
            } label: {
                Label(
                    viewModel.allVisibleSelected ? "Deselect visible" : "Select visible",
                    systemImage: viewModel.allVisibleSelected ? "checkmark.square.fill" : "checkmark.square"
                )
            }

            Button {
                viewModel.clearSelection()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .disabled(viewModel.selectedCount == 0 || viewModel.isExporting)

            Spacer()

            TextField("Search albums", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
        .padding(12)
    }

    
    

    private var albumTable: some View {
        Table(viewModel.filteredAndSortedAlbums.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Selected") { album in
                Toggle("", isOn: Binding(
                    get: { album.selected },
                    set: { newValue in
                        viewModel.setSelection(for: album, selected: newValue)
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(70)

            TableColumn("Album", value: \.name) { album in
                HStack {
                    Image(systemName: album.isSpecialAlbum ? "tray.full" : "rectangle.stack")
                        .foregroundStyle(.secondary)

                    Text(album.name)
                        .lineLimit(1)
                }
            }

            TableColumn("Items", value: \.count) { album in
                Text(album.count.formatted())
                    .monospacedDigit()
            }
            .width(100)

            TableColumn("Identifier") { album in
                Text(album.collectionLocalIdentifier ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Reading Photos library…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(.orange)

            Text("Could not read Photos library")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)

            Button("Open Photos Privacy Settings") {
                viewModel.openPhotosPrivacySettings()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var exportProgressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView(value: viewModel.exportProgress)
                    .frame(width: 250)

                Text("\(Int(viewModel.exportProgress * 100)) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.exportStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var dryRunReportView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dry Run Report")
                    .font(.headline)

                Spacer()

                Button("Clear Report") {
                    viewModel.restorePlanReportText = ""
                    viewModel.restorePlanSummary = nil
                }
            }

            ScrollView {
                Text(viewModel.restorePlanReportText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 180)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text("Albums: \(viewModel.albums.count.formatted())")
            Text("Selected: \(viewModel.selectedCount.formatted())")
            Spacer()

            Button("Scan Backup Library…") {
                Task {
                    await viewModel.exportBackupLibraryManifest()
                }
            }
            .disabled(viewModel.isExporting)
            .help("Read albums from a .photoslibrary on disk (SQLite), without switching Photos libraries.")

            Button("Manifest from System Library") {
                Task {
                    await viewModel.exportSelectedAlbumManifest()
                }
            }
            .disabled(viewModel.selectedCount == 0 || viewModel.isExporting)
            .help("Export selected albums from the currently open System Photo Library via PhotoKit.")

            Button("Export Current Asset Index") {
                Task {
                    await viewModel.exportCurrentAssetIndex()
                }
            }
            .disabled(viewModel.isExporting)

            Button("Create Restore Plan") {
                Task {
                    await viewModel.createRestorePlan()
                }
            }
            .disabled(viewModel.isExporting)

            Button("Restore Albums") {
                // Later step
            }
            .disabled(true)
        }
        .padding(12)
        .font(.callout)
    }
}
