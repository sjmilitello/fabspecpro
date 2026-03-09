import SwiftUI
import SwiftData
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var headers: [BusinessHeader]
    @State private var pdfData: Data?
    @State private var isShowingPreview = false
    @State private var isShowingShare = false

    @Bindable var project: Project

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionCard(title: "Project") {
                            TextField("Project name", text: $project.name)
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.words)
                                #endif
                        }

                        SectionCard(title: "Export") {
                            Button("Preview PDF") {
                                generatePDF()
                            }
                            .buttonStyle(PillButtonStyle(isProminent: true))
                        }
                    }
                    .padding(20)
                }
                .dismissKeyboardOnSwipe()
            }
            .navigationTitle("Export PDF")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #endif
            }
            .sheet(isPresented: $isShowingPreview) {
                if let pdfData {
                    PDFPreviewView(pdfData: pdfData, projectName: project.name)
                }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isShowingShare) {
                if let pdfData {
                    ShareSheet(activityItems: [pdfData])
                }
            }
            #else
            .onChange(of: isShowingShare) { _, newValue in
                if newValue, let pdfData {
                    showMacShareSheet(data: pdfData)
                    isShowingShare = false
                }
            }
            #endif
            .onAppear {
                ensureHeaderExists()
            }
        }
    }

    private var currentHeader: BusinessHeader? {
        headers.first
    }

    private func ensureHeaderExists() {
        if headers.isEmpty {
            let header = BusinessHeader()
            modelContext.insert(header)
        }
    }

    private func generatePDF() {
        guard let header = currentHeader else { return }
        pdfData = PDFRenderer.render(project: project, header: header)
        isShowingPreview = true
    }
    
    #if !canImport(UIKit)
    private func showMacShareSheet(data: Data) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(project.name).pdf")
        try? data.write(to: tempURL)
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
    #endif
}

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif

// MARK: - PDF Preview View

struct PDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let pdfData: Data
    let projectName: String
    @State private var isShowingShare = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                PDFKitView(data: pdfData)
            }
            .navigationTitle("PDF Preview")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMacShareSheet()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                #endif
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isShowingShare) {
                ShareSheet(activityItems: [pdfData])
            }
            #endif
        }
    }
    
    #if !canImport(UIKit)
    private func showMacShareSheet() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(projectName).pdf")
        try? pdfData.write(to: tempURL)
        
        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
    #endif
}

// MARK: - PDFKit View

#if canImport(UIKit)
struct PDFKitView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            uiView.document = document
        }
    }
}
#else
struct PDFKitView: NSViewRepresentable {
    let data: Data
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        }
    }
}
#endif
