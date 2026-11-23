// ExportMeshButton.swift
// Mesquette — Share / save a completed GenerationRecord mesh

import SwiftUI
import ShapERuntime
import UniformTypeIdentifiers

/// Export control for a completed generation (OBJ + USDZ).
struct ExportMeshButton: View {
    let record: GenerationRecord

    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var showError = false

#if os(macOS)
    @State private var exportDocument: ExportFileDocument?
    @State private var showSavePanel = false
#else
    @State private var shareItems: [Any] = []
    @State private var showShare = false
#endif

    var body: some View {
        Menu {
            Button {
                Task { await export(.usdz) }
            } label: {
                Label("Export USDZ", systemImage: MeshExportFormat.usdz.systemImage)
            }
            Button {
                Task { await export(.obj) }
            } label: {
                Label("Export OBJ + MTL", systemImage: MeshExportFormat.obj.systemImage)
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
        }
        .disabled(isExporting || !canExport)
        .help(canExport ? "Export mesh for use in other apps" : "Mesh not ready")
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
#if os(macOS)
        .fileExporter(
            isPresented: $showSavePanel,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .usdz,
            defaultFilename: exportDocument?.defaultFilename ?? "mesh"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
                showError = true
            }
            exportDocument = nil
        }
#else
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
#endif
    }

    private var canExport: Bool {
        if case .completed = record.status, record.latestMesh != nil {
            return true
        }
        return false
    }

    @MainActor
    private func export(_ format: MeshExportFormat) async {
        guard let mesh = record.latestMesh else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let dir = try MeshExporter.exportsDirectory()
            let name = MeshExporter.suggestedFileName(
                prompt: record.prompt,
                id: record.id,
                format: format
            )
            let url = dir.appendingPathComponent(name)
            let delivered = try await Task.detached(priority: .userInitiated) { () -> URL in
                try MeshExporter.export(mesh, to: url)
                if format == .obj {
                    return try MeshExporter.packageWavefrontExport(objURL: url)
                }
                return url
            }.value

#if os(macOS)
            // Offer a save panel so the user can pick a permanent location;
            // file is also kept under Application Support/Exports.
            exportDocument = ExportFileDocument(
                fileURL: delivered,
                contentType: format == .obj ? .zip : format.contentType
            )
            showSavePanel = true
#else
            shareItems = [delivered]
            showShare = true
#endif
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - File document (macOS save panel)

#if os(macOS)
import UniformTypeIdentifiers

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.usdz, .wavefrontOBJ, .zip, .data] }

    let fileURL: URL
    let contentType: UTType

    var defaultFilename: String { fileURL.deletingPathExtension().lastPathComponent }

    init(fileURL: URL, contentType: UTType) {
        self.fileURL = fileURL
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Copy the already-exported file into the user-chosen destination.
        let data = try Data(contentsOf: fileURL)
        return .init(regularFileWithContents: data)
    }
}
#endif

// MARK: - Share sheet (iOS / visionOS)

#if os(iOS) || os(visionOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
