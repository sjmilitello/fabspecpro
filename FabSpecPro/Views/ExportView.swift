import SwiftUI
import SwiftData

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
                                .textInputAutocapitalization(.words)
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
            }
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingShare) {
                if let pdfData {
                    ShareSheet(activityItems: [pdfData])
                }
            }
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
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
