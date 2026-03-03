import SwiftUI
import SwiftData
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
                            Button("Generate PDF") {
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
        isShowingShare = true
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
