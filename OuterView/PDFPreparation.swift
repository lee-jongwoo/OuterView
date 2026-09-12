import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PassageImage: View {
    let path: String?
    var data: Data? = nil
    var body: some View {
        if let image = loadedImage {
            Image(nsImage: image).resizable().scaledToFit()
                .accessibilityLabel("Passage image")
        } else {
            ContentUnavailableView("Passage unavailable", systemImage: "doc.questionmark",
                                   description: Text("Edit the set to replace its passage image."))
        }
    }
    private var loadedImage: NSImage? {
        if let data { return NSImage(data: data) }
        guard let path, let url = try? AssetStorage.applicationStorage().url(for: path) else { return nil }
        return NSImage(contentsOf: url)
    }
}

enum PDFPreparationError: LocalizedError {
    case unreadable, locked, noSelection
    var errorDescription: String? {
        switch self {
        case .unreadable: "This PDF could not be opened or rendered. Try another PDF."
        case .locked: "This PDF is password protected. Unlock it in Preview and save an unlocked copy first."
        case .noSelection: "Drag a rectangle over the passage before using the crop."
        }
    }
}

/// Cropping uses the already rendered page, so rotation and page-box offsets
/// match exactly what the user sees. Selection coordinates run from top-left.
enum PassageCrop {
    static func png(image: NSImage, selection: CGRect) throws -> Data {
        guard let cgImage = image.representations.compactMap({ ($0 as? NSBitmapImageRep)?.cgImage }).first
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PDFPreparationError.unreadable
        }
        let rect = selection.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width > 0.005, rect.height > 0.005 else { throw PDFPreparationError.noSelection }
        let pixels = CGRect(x: rect.minX * CGFloat(cgImage.width), y: rect.minY * CGFloat(cgImage.height),
                            width: rect.width * CGFloat(cgImage.width), height: rect.height * CGFloat(cgImage.height)).integral
        guard let cropped = cgImage.cropping(to: pixels),
              let data = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
            throw PDFPreparationError.unreadable
        }
        return data
    }
}

struct PDFCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var document: PDFDocument?
    let receive: (Data) -> Void
    @State private var pageIndex = 0
    @State private var selection = CGRect.zero
    @State private var image: NSImage?
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Crop Passage").font(.title2.bold())
                Spacer()
                Button("Choose PDF…") { importing = true }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use Crop") {
                    do {
                        guard let image else { throw PDFPreparationError.unreadable }
                        receive(try PassageCrop.png(image: image, selection: selection))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(image == nil || selection.width < 0.005 || selection.height < 0.005)
            }
            HStack {
                Button("Previous Page", systemImage: "chevron.left") { pageIndex -= 1; renderPage() }.disabled(pageIndex == 0)
                Text("Page \(document == nil ? 0 : pageIndex + 1) of \(document?.pageCount ?? 0)").monospacedDigit()
                Button("Next Page", systemImage: "chevron.right") { pageIndex += 1; renderPage() }
                    .disabled(pageIndex + 1 >= (document?.pageCount ?? 0))
                Spacer()
                Text("Drag to select one passage. Drag again to replace the selection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let image {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                        Rectangle().fill(Color.accentColor.opacity(0.15))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: selection.width * size.width, height: selection.height * size.height)
                            .offset(x: selection.minX * size.width, y: selection.minY * size.height)
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        let start = CGPoint(x: min(max(value.startLocation.x / size.width, 0), 1),
                                            y: min(max(value.startLocation.y / size.height, 0), 1))
                        let end = CGPoint(x: min(max(value.location.x / size.width, 0), 1),
                                          y: min(max(value.location.y / size.height, 0), 1))
                        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                           width: abs(end.x - start.x), height: abs(end.y - start.y))
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.background(Color.gray.opacity(0.15))
            } else {
                ContentUnavailableView("Choose your handout", systemImage: "doc.richtext",
                                       description: Text("Open a PDF, select a page, then drag over the passage."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20).frame(width: 900, height: 720)
        .onAppear { renderPage(); if document == nil { importing = true } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let loaded = PDFDocument(data: try Data(contentsOf: url)), loaded.pageCount > 0 else { throw PDFPreparationError.unreadable }
                guard !loaded.isLocked else { throw PDFPreparationError.locked }
                document = loaded
                pageIndex = 0
                renderPage()
            } catch { self.error = error.localizedDescription }
        }
        .alert("PDF Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func renderPage() {
        selection = .zero
        guard let page = document?.page(at: pageIndex) else { image = nil; return }
        image = page.thumbnail(of: CGSize(width: 2400, height: 2400), for: .cropBox)
    }
}
