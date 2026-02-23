import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var headers: [BusinessHeader]
    @Bindable var project: Project
    @State private var pdfData: Data?
    @State private var isShowingShare = false
    @State private var pieceToDelete: Piece?
    @State private var isShowingDeleteProject = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionCard(title: "Project") {
                        VStack(spacing: 12) {
                            TextField("Project name", text: $project.name)
                                .textInputAutocapitalization(.words)
                            TextField("Project address", text: $project.address, axis: .vertical)
                                .lineLimit(1...3)
                            TextField("Project notes", text: $project.notes, axis: .vertical)
                                .lineLimit(3...6)
                            HStack(spacing: 12) {
                                Button("Export PDF") {
                                    generatePDF()
                                }
                                .buttonStyle(PillButtonStyle(isProminent: true))
                                Button("Delete Project") {
                                    isShowingDeleteProject = true
                                }
                                .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
                            }
                        }
                    }

                    SectionCard(title: "Pieces") {
                        VStack(spacing: 12) {
                            Button("Add Piece") {
                                addPiece()
                            }
                            .buttonStyle(PillButtonStyle(isProminent: true))

                            ForEach(groupedKeys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(key.materialName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.secondaryText)
                                    Text(key.thicknessLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.secondaryText)

                                    LazyVGrid(columns: gridColumns, spacing: 10) {
                                        ForEach(groupedPieces[key, default: []]) { piece in
                                            NavigationLink {
                                                PieceEditorView(piece: piece)
                                            } label: {
                                                PieceRow(piece: piece)
                                            }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button("Delete Piece", role: .destructive) {
                                                    pieceToDelete = piece
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                }
                .padding(20)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingShare) {
            if let pdfData {
                ProjectShareSheet(activityItems: [pdfData])
            }
        }
        .alert("Delete Piece?", isPresented: Binding(
            get: { pieceToDelete != nil },
            set: { if !$0 { pieceToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pieceToDelete {
                    project.pieces.removeAll { $0.id == pieceToDelete.id }
                    modelContext.delete(pieceToDelete)
                    self.pieceToDelete = nil
                    markUpdated()
                }
            }
            Button("Cancel", role: .cancel) {
                pieceToDelete = nil
            }
        } message: {
            Text("This will remove the piece and its details.")
        }
        .alert("Delete Project?", isPresented: $isShowingDeleteProject) {
            Button("Delete", role: .destructive) {
                modelContext.delete(project)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the project and all pieces.")
        }
        .onChange(of: project.name) { _, _ in
            markUpdated()
        }
        .onChange(of: project.notes) { _, _ in
            markUpdated()
        }
        .onChange(of: project.address) { _, _ in
            markUpdated()
        }
        .onAppear {
            ensureHeaderExists()
        }
    }

    private func addPiece() {
        let piece = Piece(name: "Piece \(project.pieces.count + 1)")
        if let lastMaterial = project.pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName {
            piece.materialName = lastMaterial
        }
        piece.project = project
        project.pieces.append(piece)
        modelContext.insert(piece)
        markUpdated()
    }

    private func markUpdated() {
        project.updatedAt = Date()
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

    private var groupedPieces: [PieceGroupKey: [Piece]] {
        Dictionary(grouping: project.pieces) { piece in
            PieceGroupKey(materialName: piece.materialName, thicknessLabel: piece.thickness.rawValue)
        }
    }

    private var groupedKeys: [PieceGroupKey] {
        groupedPieces.keys.sorted()
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }
}

private struct PieceGroupKey: Hashable, Comparable {
    let materialName: String
    let thicknessLabel: String

    static func < (lhs: PieceGroupKey, rhs: PieceGroupKey) -> Bool {
        if lhs.materialName == rhs.materialName {
            return lhs.thicknessLabel < rhs.thicknessLabel
        }
        return lhs.materialName < rhs.materialName
    }
}

private struct PieceRow: View {
    let piece: Piece

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(piece.name)
                    .foregroundStyle(Theme.primaryText)
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            Text("Qty \(piece.quantity)")
                .foregroundStyle(Theme.secondaryText)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProjectShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
