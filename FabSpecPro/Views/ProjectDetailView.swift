import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum PieceViewMode: String, CaseIterable {
    case list = "List"
    case image = "Image"
}

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var headers: [BusinessHeader]
    @Query private var pieceDefaults: [PieceDefaults]
    @Bindable var project: Project
    @State private var pdfData: Data?
    @State private var isShowingShare = false
    @State private var pieceToDelete: Piece?
    @State private var selectedPiece: Piece?
    @State private var isShowingDeleteProject = false
    @State private var viewMode: PieceViewMode = .list
    @State private var isGeneratingPDF = false
    
    /// Access pieces through the project relationship to avoid SwiftData exclusivity violations
    /// when generating PDFs (which also accesses piece data)
    private var pieces: [Piece] {
        project.pieces
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionCard(title: "Project") {
                        VStack(spacing: 12) {
                            TextField("Project name", text: $project.name, prompt: Text("Project name").foregroundStyle(Theme.secondaryText))
                                .foregroundStyle(Theme.primaryText)
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.words)
                                #endif
                            TextField("Project address", text: $project.address, prompt: Text("Project address").foregroundStyle(Theme.secondaryText), axis: .vertical)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1...3)
                            TextField("Project notes", text: $project.notes, prompt: Text("Project notes").foregroundStyle(Theme.secondaryText), axis: .vertical)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(3...6)
                            HStack(spacing: 12) {
                                Button {
                                    generatePDF()
                                } label: {
                                    if isGeneratingPDF {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.primaryText))
                                    } else {
                                        Text("Export PDF")
                                    }
                                }
                                .buttonStyle(PillButtonStyle(isProminent: true))
                                .disabled(isGeneratingPDF)
                                Button("Delete Project") {
                                    isShowingDeleteProject = true
                                }
                                .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
                            }
                        }
                    }

                    SectionCard(title: "Pieces") {
                        VStack(spacing: 12) {
                            HStack {
                                Button("Add Piece") {
                                    addPiece()
                                }
                                .buttonStyle(PillButtonStyle(isProminent: true))
                                
                                Spacer()
                                
                                Picker("View", selection: $viewMode) {
                                    ForEach(PieceViewMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                            }

                            ForEach(groupedKeys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(key.materialName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.secondaryText)
                                    Text(key.thicknessLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.secondaryText)

                                    LazyVGrid(columns: viewMode == .list ? gridColumns : imageGridColumns, spacing: 10) {
                                        ForEach(groupedPieces[key, default: []]) { piece in
                                            Button {
                                                selectedPiece = piece
                                            } label: {
                                                if viewMode == .list {
                                                    PieceRow(piece: piece)
                                                } else {
                                                    PieceImageRow(piece: piece)
                                                }
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
            .dismissKeyboardOnSwipe()
        }
        .navigationTitle(project.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedPiece) { piece in
            PieceEditorView(piece: piece) { newPiece in
                selectedPiece = newPiece
            }
        }
#if canImport(UIKit)
        .sheet(isPresented: $isShowingShare) {
            if let pdfData {
                ProjectShareSheet(activityItems: [pdfData])
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
        .alert("Delete Piece?", isPresented: Binding(
            get: { pieceToDelete != nil },
            set: { if !$0 { pieceToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pieceToDelete {
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
        let nextIndex = pieces.count + 1
        let piece = Piece(name: "Piece \(nextIndex)")
        
        // Apply defaults if available
        if let defaults = pieceDefaults.first {
            // Use default material if set, otherwise fall back to last used material
            if !defaults.defaultMaterialName.isEmpty {
                piece.materialName = defaults.defaultMaterialName
            } else {
                let lastMaterial = pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName
                if let lastMaterial {
                    piece.materialName = lastMaterial
                }
            }
            
            // Apply other basic defaults
            if let thickness = MaterialThickness(rawValue: defaults.defaultThickness) {
                piece.thickness = thickness
            }
            if let shape = ShapeKind(rawValue: defaults.defaultShape) {
                piece.shape = shape
            }
            piece.widthText = defaults.defaultWidth
            piece.heightText = defaults.defaultHeight
            piece.quantity = defaults.defaultQuantity
        } else {
            // Fallback: use last material if no defaults
            let lastMaterial = pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName
            if let lastMaterial {
                piece.materialName = lastMaterial
            }
        }
        
        piece.project = project
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
        guard !isGeneratingPDF else { return }
        
        isGeneratingPDF = true
        
        // Use a small delay to allow the loading indicator to appear before blocking the main thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Generate PDF synchronously on main thread - required for SwiftData access
            pdfData = PDFRenderer.render(project: project, header: header)
            isGeneratingPDF = false
            isShowingShare = true
        }
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

    private var groupedPieces: [PieceGroupKey: [Piece]] {
        Dictionary(grouping: pieces) { piece in
            PieceGroupKey(materialName: piece.materialName, thicknessLabel: piece.thickness.rawValue)
        }
    }

    private var groupedKeys: [PieceGroupKey] {
        groupedPieces.keys.sorted()
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }
    
    private var imageGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10)]
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

private struct PieceImageRow: View {
    @Bindable var piece: Piece
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Piece name header in upper left, quantity on right
            HStack {
                Text(piece.name)
                    .foregroundStyle(Theme.primaryText)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Qty \(piece.quantity)")
                    .foregroundStyle(Theme.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            
            // Full drawing canvas in read-only mode - shows measurements and edge notations
            DrawingCanvasView(piece: piece, selectedTreatment: nil, isReadOnly: true)
                .frame(height: calculateDrawingHeight())
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func calculateDrawingHeight() -> CGFloat {
        let size = ShapePathBuilder.displaySize(for: piece)
        let aspectRatio = size.height / max(size.width, 1)
        // Larger base height for better visibility
        // Taller pieces get more height, wider pieces get less
        let baseHeight: CGFloat = 260
        let minHeight: CGFloat = 220
        let maxHeight: CGFloat = 360
        let adjustedHeight = baseHeight * max(0.85, min(1.3, aspectRatio))
        return min(max(adjustedHeight, minHeight), maxHeight)
    }
}

#if canImport(UIKit)
private struct ProjectShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif
