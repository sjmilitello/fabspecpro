import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ProjectsListView()
            .task {
                remapCornerIndicesIfNeeded()
            }
    }

    private func remapCornerIndicesIfNeeded() {
        let key = "didRemapCornerIndicesV1"
        if UserDefaults.standard.bool(forKey: key) {
            return
        }
        let descriptor = FetchDescriptor<Piece>()
        guard let pieces = try? modelContext.fetch(descriptor) else { return }
        for piece in pieces {
            let count = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false).count
            guard count > 0 else { continue }
            for angle in piece.angleCuts where angle.anchorCornerIndex >= 0 {
                let old = angle.anchorCornerIndex % count
                angle.anchorCornerIndex = (count - old) % count
            }
            for radius in piece.cornerRadii where radius.cornerIndex >= 0 {
                let old = radius.cornerIndex % count
                radius.cornerIndex = (count - old) % count
            }
        }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
