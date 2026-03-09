#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#endif
import SwiftUI

enum PDFRenderer {
    // Set to a points-per-inch value to preview true-scale output. Set to nil to use adaptive scaling.
    private static let pdfScaleOverridePointsPerInch: CGFloat? = nil
    private static let basePointsPerInch: CGFloat = 72.0 / 12.0
    private static let drawingLeftInset: CGFloat = 50

    static func render(project: Project, header: BusinessHeader) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        
        // Ensure we're on main thread for UIKit rendering
        assert(Thread.isMainThread, "PDF rendering must happen on main thread")
        
        // Capture all SwiftData model data BEFORE entering the PDF rendering closure
        // This prevents Swift exclusivity violations when the closure accesses model data
        let pieces = Array(project.pieces)
        let projectName = project.name
        let projectAddress = project.address
        let projectDate = project.updatedAt
        let projectNotes = project.notes
        let headerData: HeaderData = (
            businessName: header.businessName,
            phone: header.phone,
            email: header.email,
            address: header.address,
            logoData: header.logoData
        )
        
        // Pre-compute all piece rendering data to avoid SwiftData access during rendering
        let pieceRenderData = precomputePieceData(from: pieces, pageSize: pageSize)
        let totalPages = computeTotalPagesFromRenderData(pieceData: pieceRenderData, pageSize: pageSize)
        
        // Pre-compute edge legend from pieces
        let edgeLegend = computeEdgeLegend(from: pieces)
        
        // Use CGContext directly instead of UIGraphicsPDFRenderer closure to avoid SwiftData exclusivity issues
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        
        let leftMargin: CGFloat = 24

        // Use a class to hold mutable state to avoid Swift exclusivity issues
        // with nested functions capturing variables that are also passed as inout
        let state = RenderState()

        func beginPage() {
            pdfContext.beginPDFPage(nil)
            #if canImport(UIKit)
            // Flip coordinate system to match UIKit (origin at top-left)
            pdfContext.translateBy(x: 0, y: pageSize.height)
            pdfContext.scaleBy(x: 1, y: -1)
            #else
            // macOS also needs coordinate flip for consistency
            pdfContext.translateBy(x: 0, y: pageSize.height)
            pdfContext.scaleBy(x: 1, y: -1)
            #endif
            state.yOffset = 24
            let headerHeight = drawHeaderFromData(
                in: pdfContext,
                headerData: headerData,
                projectName: projectName,
                projectAddress: projectAddress,
                projectDate: projectDate,
                pageSize: pageSize,
                pageIndex: state.pageIndex,
                totalPages: totalPages
            )
            drawFooterPageCount(in: pdfContext, pageSize: pageSize, pageIndex: state.pageIndex, totalPages: totalPages)
            state.yOffset = 24 + headerHeight + 10
        }

        beginPage()
        renderContentFromRenderDataWithState(
            context: pdfContext,
            pieceData: pieceRenderData,
            projectNotes: projectNotes,
            edgeLegend: edgeLegend,
            headerData: headerData,
            pageSize: pageSize,
            leftMargin: leftMargin,
            totalPages: totalPages,
            state: state,
            beginPage: beginPage
        )
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        return pdfData as Data
    }
    
    // Type alias for pre-extracted header data to avoid SwiftData access in closures
    private typealias HeaderData = (
        businessName: String,
        phone: String,
        email: String,
        address: String,
        logoData: Data?
    )
    
    // Pre-computed rendering data for a piece to avoid SwiftData access in closures
    private struct PieceRenderData {
        let materialName: String
        let thicknessRaw: String
        let path: Path
        let displaySize: CGSize
        let layout: PieceLayout
        let piece: Piece // Keep reference for drawing functions
    }
    
    private static func precomputePieceData(from pieces: [Piece], pageSize: CGSize) -> [PieceRenderData] {
        let columnWidth = pageSize.width - 48
        let baseScale = pdfScaleOverridePointsPerInch ?? basePointsPerInch
        let maxBlockHeight = pageSize.height - 60 - 140
        
        return pieces.map { piece in
            let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return PieceRenderData(
                materialName: trimmed.isEmpty ? "Material" : trimmed,
                thicknessRaw: piece.thickness.rawValue,
                path: ShapePathBuilder.path(for: piece),
                displaySize: ShapePathBuilder.displaySize(for: piece),
                layout: blockLayout(for: piece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: maxBlockHeight),
                piece: piece
            )
        }
    }
    
    private static func computeEdgeLegend(from pieces: [Piece]) -> [String] {
        let pairs = pieces.flatMap { piece in
            piece.edgeAssignments.compactMap { assignment -> (String, String)? in
                let code = assignment.treatmentAbbreviation
                let name = assignment.treatmentName
                return code.isEmpty || name.isEmpty ? nil : (code, name)
            }
        }
        let unique = Dictionary(grouping: pairs, by: { $0.0 })
            .values
            .compactMap { $0.first }
            .sorted { $0.0 < $1.0 }
        return unique.map { "\($0.0) - \($0.1)" }
    }
    
    private static func computeTotalPagesFromRenderData(pieceData: [PieceRenderData], pageSize: CGSize) -> Int {
        var pageCount = 1
        var yOffset: CGFloat = 140
        let headerHeight: CGFloat = 18
        let blockSpacing: CGFloat = 6
        let thicknessGroupSpacing: CGFloat = 12
        
        let materialGrouped = Dictionary(grouping: pieceData) { $0.materialName }
        let sortedMaterials = materialGrouped.keys.sorted()
        
        for materialKey in sortedMaterials {
            if yOffset + 28 > pageSize.height - 60 {
                pageCount += 1
                yOffset = 140
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { $0.thicknessRaw }
            let sortedThickness = thicknessGrouped.keys.sorted()
            
            for thicknessKey in sortedThickness {
                let piecesInGroup = thicknessGrouped[thicknessKey] ?? []
                guard let firstPieceData = piecesInGroup.first else { continue }
                let headerAndBlock = headerHeight + firstPieceData.layout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    pageCount += 1
                    yOffset = 140
                }
                yOffset += headerHeight
                
                for pd in piecesInGroup {
                    if yOffset + pd.layout.blockHeight > pageSize.height - 60 {
                        pageCount += 1
                        yOffset = 140
                    }
                    yOffset += pd.layout.blockHeight + blockSpacing
                }
                
                // Match the spacing added after each thickness group in renderContentFromRenderDataWithState
                yOffset += thicknessGroupSpacing
            }
        }
        return pageCount
    }
    
    private static func renderContentFromRenderData(
        context: CGContext,
        pieceData: [PieceRenderData],
        projectNotes: String,
        headerData: HeaderData,
        pageSize: CGSize,
        leftMargin: CGFloat,
        totalPages: Int,
        yOffset: inout CGFloat,
        pageIndex: inout Int,
        beginPage: () -> Void
    ) {
        let blockSpacing: CGFloat = 6
        let headerHeight: CGFloat = 18

        let materialGrouped = Dictionary(grouping: pieceData) { $0.materialName }
        let sortedMaterials = materialGrouped.keys.sorted()

        for (_, materialKey) in sortedMaterials.enumerated() {
            if yOffset + 28 > pageSize.height - 60 {
                #if !canImport(UIKit)
                context.endPDFPage()
                #endif
                pageIndex += 1
                beginPage()
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { $0.thicknessRaw }
            let sortedThickness = thicknessGrouped.keys.sorted()

            for thicknessKey in sortedThickness {
                let piecesInGroup = thicknessGrouped[thicknessKey] ?? []
                guard let firstPieceData = piecesInGroup.first else { continue }
                let headerAndBlock = headerHeight + firstPieceData.layout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    #if !canImport(UIKit)
                    context.endPDFPage()
                    #endif
                    pageIndex += 1
                    beginPage()
                }

                drawSectionHeader(
                    in: context,
                    title: "\(materialKey) - \(thicknessKey)",
                    origin: CGPoint(x: leftMargin, y: yOffset + 4),
                    maxWidth: pageSize.width - (leftMargin * 2)
                )
                yOffset += headerHeight

                for pd in piecesInGroup {
                    let layout = pd.layout
                    if yOffset + layout.blockHeight > pageSize.height - 60 {
                        #if !canImport(UIKit)
                        context.endPDFPage()
                        #endif
                        pageIndex += 1
                        beginPage()
                    }

                    let xOffset: CGFloat = leftMargin
                    let drawingRect = CGRect(
                        x: xOffset + layout.drawingRect.origin.x,
                        y: yOffset + layout.drawingRect.origin.y,
                        width: layout.drawingRect.width,
                        height: layout.drawingRect.height
                    )
                    drawPieceBlock(
                        in: context,
                        piece: pd.piece,
                        origin: CGPoint(x: xOffset, y: yOffset),
                        size: pd.displaySize,
                        drawingRect: drawingRect,
                        pieceHeaderY: yOffset + layout.pieceHeaderY,
                        topMeasurementY: yOffset + layout.topMeasurementY,
                        bottomMeasurementY: yOffset + layout.bottomMeasurementY,
                        notesY: yOffset + layout.notesY,
                        topEdgeLabelY: layout.topEdgeLabelY.map { yOffset + $0 },
                        bottomEdgeLabelY: layout.bottomEdgeLabelY.map { yOffset + $0 }
                    )

                    yOffset += layout.blockHeight + blockSpacing
                }
            }
        }
    }
    
    // Reference type for mutable state to avoid Swift exclusivity issues
    final class RenderState {
        var yOffset: CGFloat = 20
        var pageIndex: Int = 1
    }
    
    private static func renderContentFromRenderDataWithState(
        context: CGContext,
        pieceData: [PieceRenderData],
        projectNotes: String,
        edgeLegend: [String],
        headerData: HeaderData,
        pageSize: CGSize,
        leftMargin: CGFloat,
        totalPages: Int,
        state: RenderState,
        beginPage: () -> Void
    ) {
        let blockSpacing: CGFloat = 6
        let headerHeight: CGFloat = 18

        let materialGrouped = Dictionary(grouping: pieceData) { $0.materialName }
        let sortedMaterials = materialGrouped.keys.sorted()

        for (materialIndex, materialKey) in sortedMaterials.enumerated() {
            if state.yOffset + 28 > pageSize.height - 60 {
                #if canImport(UIKit)
                context.endPDFPage()
                #endif
                state.pageIndex += 1
                beginPage()
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { $0.thicknessRaw }
            let sortedThickness = thicknessGrouped.keys.sorted()

            for thicknessKey in sortedThickness {
                let piecesInGroup = thicknessGrouped[thicknessKey] ?? []
                guard let firstPieceData = piecesInGroup.first else { continue }
                let headerAndBlock = headerHeight + firstPieceData.layout.blockHeight
                if state.yOffset + headerAndBlock > pageSize.height - 60 {
                    #if canImport(UIKit)
                    context.endPDFPage()
                    #endif
                    state.pageIndex += 1
                    beginPage()
                }

                drawSectionHeader(
                    in: context,
                    title: "\(materialKey) - \(thicknessKey)",
                    origin: CGPoint(x: leftMargin, y: state.yOffset + 4),
                    maxWidth: pageSize.width - (leftMargin * 2)
                )
                state.yOffset += headerHeight

                for pd in piecesInGroup {
                    let layout = pd.layout
                    if state.yOffset + layout.blockHeight > pageSize.height - 60 {
                        #if canImport(UIKit)
                        context.endPDFPage()
                        #endif
                        state.pageIndex += 1
                        beginPage()
                    }

                    let xOffset: CGFloat = leftMargin
                    let drawingRect = CGRect(
                        x: xOffset + layout.drawingRect.origin.x,
                        y: state.yOffset + layout.drawingRect.origin.y,
                        width: layout.drawingRect.width,
                        height: layout.drawingRect.height
                    )
                    drawPieceBlock(
                        in: context,
                        piece: pd.piece,
                        origin: CGPoint(x: xOffset, y: state.yOffset),
                        size: pd.displaySize,
                        drawingRect: drawingRect,
                        pieceHeaderY: state.yOffset + layout.pieceHeaderY,
                        topMeasurementY: state.yOffset + layout.topMeasurementY,
                        bottomMeasurementY: state.yOffset + layout.bottomMeasurementY,
                        notesY: state.yOffset + layout.notesY,
                        topEdgeLabelY: layout.topEdgeLabelY.map { state.yOffset + $0 },
                        bottomEdgeLabelY: layout.bottomEdgeLabelY.map { state.yOffset + $0 }
                    )

                    state.yOffset += layout.blockHeight + blockSpacing
                }
                
                state.yOffset += 12
            }
            
            // Draw project notes and edge legend after the last material group
            if materialIndex == sortedMaterials.count - 1 {
                drawNotes(in: context, notes: projectNotes, edgeLegend: edgeLegend, origin: CGPoint(x: leftMargin, y: state.yOffset), maxWidth: pageSize.width - (leftMargin * 2))
            }
        }
    }
    
    private static func computeTotalPagesFromPieces(pieces: [Piece], pageSize: CGSize) -> Int {
        let columnWidth = pageSize.width - 48
        let baseScale = pdfScaleOverridePointsPerInch ?? basePointsPerInch
        var pageCount = 1
        var yOffset: CGFloat = 140
        let headerHeight: CGFloat = 18
        
        let materialGrouped = Dictionary(grouping: pieces) { piece in
            let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Material" : trimmed
        }
        let sortedMaterials = materialGrouped.keys.sorted()
        
        for materialKey in sortedMaterials {
            if yOffset + 28 > pageSize.height - 60 {
                pageCount += 1
                yOffset = 140
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { piece in
                piece.thickness.rawValue
            }
            let sortedThickness = thicknessGrouped.keys.sorted()
            
            for thicknessKey in sortedThickness {
                let piecesInGroup = thicknessGrouped[thicknessKey] ?? []
                guard let firstPiece = piecesInGroup.first else { continue }
                let firstLayout = blockLayout(for: firstPiece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                let headerAndBlock = headerHeight + firstLayout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    pageCount += 1
                    yOffset = 140
                }
                yOffset += headerHeight
                
                for piece in piecesInGroup {
                    let layout = blockLayout(for: piece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                    if yOffset + layout.blockHeight > pageSize.height - 60 {
                        pageCount += 1
                        yOffset = 140
                    }
                    yOffset += layout.blockHeight + 6
                }
            }
        }
        return pageCount
    }
    
    private static func drawHeaderFromData(
        in context: CGContext,
        headerData: HeaderData,
        projectName: String,
        projectAddress: String,
        projectDate: Date,
        pageSize: CGSize,
        pageIndex: Int,
        totalPages: Int
    ) -> CGFloat {
        let headerOriginY: CGFloat = 24
        let headerRect = CGRect(x: 24, y: headerOriginY, width: pageSize.width - 48, height: pageIndex == 1 ? 100 : 50)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: projectDate)

        if pageIndex == 1 {
            var textX: CGFloat = headerRect.minX + 12
            var headerHeight: CGFloat = 0
            if let logoData = headerData.logoData, let image = PlatformImage(data: logoData) {
                let logoRect = CGRect(x: headerRect.minX + 12, y: headerRect.minY + 12, width: 64, height: 64)
                #if canImport(UIKit)
                UIGraphicsPushContext(context)
                image.draw(in: logoRect)
                UIGraphicsPopContext()
                #else
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: logoRect)
                }
                #endif
                textX = logoRect.maxX + 12
                headerHeight = max(headerHeight, logoRect.maxY - headerOriginY)
            }

            let bodyFontSize: CGFloat = 12
            let emphasisFontSize: CGFloat = bodyFontSize + 2
            drawText(headerData.businessName, in: context, frame: CGRect(x: textX, y: headerRect.minY + 12, width: 300, height: 18), font: .boldSystemFont(ofSize: emphasisFontSize))
            headerHeight = max(headerHeight, (headerRect.minY + 12 + 18) - headerOriginY)
            let contactLines = [
                headerData.address.trimmingCharacters(in: .whitespacesAndNewlines),
                headerData.email.trimmingCharacters(in: .whitespacesAndNewlines),
                headerData.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ].filter { !$0.isEmpty }
            var contactY = headerRect.minY + 30
            for line in contactLines {
                let width: CGFloat = line == headerData.address ? 420 : 300
                drawText(line, in: context, frame: CGRect(x: textX, y: contactY, width: width, height: 14), font: .systemFont(ofSize: bodyFontSize))
                contactY += 16
            }
            headerHeight = max(headerHeight, (contactY - 2) - headerOriginY)

            let projectInfoX = headerRect.maxX - 220
            let projectInfoWidth: CGFloat = 200
            drawText("Project: \(projectName)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 12, width: projectInfoWidth, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize), alignment: .left)
            headerHeight = max(headerHeight, (headerRect.minY + 12 + 16) - headerOriginY)
            if !projectAddress.isEmpty {
                drawText("Address: \(projectAddress)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 30, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                drawText("Date: \(dateString)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 46, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                headerHeight = max(headerHeight, (headerRect.minY + 46 + 14) - headerOriginY)
            } else {
                drawText("Date: \(dateString)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 30, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                headerHeight = max(headerHeight, (headerRect.minY + 30 + 14) - headerOriginY)
            }
            return headerHeight + 8
        } else {
            let bodyFontSize: CGFloat = 12
            let emphasisFontSize: CGFloat = bodyFontSize + 2
            drawText(headerData.businessName, in: context, frame: CGRect(x: headerRect.minX + 12, y: headerRect.minY + 12, width: 300, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize))
            drawText("Project: \(projectName)", in: context, frame: CGRect(x: headerRect.maxX - 220, y: headerRect.minY + 12, width: 200, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize), alignment: .left)
            return 12 + 16 + 8
        }
    }
    
    private static func renderContentFromPieces(
        context: CGContext,
        pieces: [Piece],
        projectNotes: String,
        headerData: HeaderData,
        pageSize: CGSize,
        leftMargin: CGFloat,
        totalPages: Int,
        yOffset: inout CGFloat,
        pageIndex: inout Int,
        beginPage: () -> Void
    ) {
        let columnWidth = pageSize.width - (leftMargin * 2)
        let blockSpacing: CGFloat = 6
        let headerHeight: CGFloat = 18
        let baseScale = pdfScaleOverridePointsPerInch ?? basePointsPerInch

        let materialGrouped = Dictionary(grouping: pieces) { piece in
            let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Material" : trimmed
        }
        let sortedMaterials = materialGrouped.keys.sorted()

        for (_, materialKey) in sortedMaterials.enumerated() {
            if yOffset + 28 > pageSize.height - 60 {
                #if !canImport(UIKit)
                context.endPDFPage()
                #endif
                pageIndex += 1
                beginPage()
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { piece in
                piece.thickness.rawValue
            }
            let sortedThickness = thicknessGrouped.keys.sorted()

            for thicknessKey in sortedThickness {
                let piecesInGroup = thicknessGrouped[thicknessKey] ?? []
                guard let firstPiece = piecesInGroup.first else { continue }
                let firstLayout = blockLayout(for: firstPiece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                let headerAndBlock = headerHeight + firstLayout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    #if !canImport(UIKit)
                    context.endPDFPage()
                    #endif
                    pageIndex += 1
                    beginPage()
                }

                drawSectionHeader(
                    in: context,
                    title: "\(materialKey) - \(thicknessKey)",
                    origin: CGPoint(x: leftMargin, y: yOffset + 4),
                    maxWidth: pageSize.width - (leftMargin * 2)
                )
                yOffset += headerHeight

                for piece in piecesInGroup {
                    let layout = blockLayout(for: piece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                    if yOffset + layout.blockHeight > pageSize.height - 60 {
                        #if !canImport(UIKit)
                        context.endPDFPage()
                        #endif
                        pageIndex += 1
                        beginPage()
                    }

                    let xOffset: CGFloat = leftMargin
                    let drawingRect = CGRect(
                        x: xOffset + layout.drawingRect.origin.x,
                        y: yOffset + layout.drawingRect.origin.y,
                        width: layout.drawingRect.width,
                        height: layout.drawingRect.height
                    )
                    drawPieceBlock(
                        in: context,
                        piece: piece,
                        origin: CGPoint(x: xOffset, y: yOffset),
                        size: ShapePathBuilder.displaySize(for: piece),
                        drawingRect: drawingRect,
                        pieceHeaderY: yOffset + layout.pieceHeaderY,
                        topMeasurementY: yOffset + layout.topMeasurementY,
                        bottomMeasurementY: yOffset + layout.bottomMeasurementY,
                        notesY: yOffset + layout.notesY,
                        topEdgeLabelY: layout.topEdgeLabelY.map { yOffset + $0 },
                        bottomEdgeLabelY: layout.bottomEdgeLabelY.map { yOffset + $0 }
                    )

                    yOffset += layout.blockHeight + blockSpacing
                }
            }
        }
    }
    
    private static func renderContent(
        context: CGContext,
        project: Project,
        header: BusinessHeader,
        pageSize: CGSize,
        leftMargin: CGFloat,
        totalPages: Int,
        yOffset: inout CGFloat,
        pageIndex: inout Int,
        beginPage: () -> Void
    ) {
        let columnWidth = pageSize.width - (leftMargin * 2)
        let blockSpacing: CGFloat = 6
        let headerHeight: CGFloat = 18
        let baseScale = pdfScaleOverridePointsPerInch ?? basePointsPerInch

        let materialGrouped = Dictionary(grouping: project.pieces) { piece in
            let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Material" : trimmed
        }
        let sortedMaterials = materialGrouped.keys.sorted()

        for (materialIndex, materialKey) in sortedMaterials.enumerated() {
            if yOffset + 28 > pageSize.height - 60 {
                #if !canImport(UIKit)
                context.endPDFPage()
                #endif
                pageIndex += 1
                beginPage()
            }
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { piece in
                piece.thickness.rawValue
            }
            let sortedThickness = thicknessGrouped.keys.sorted()

            for thicknessKey in sortedThickness {
                let pieces = thicknessGrouped[thicknessKey] ?? []
                guard let firstPiece = pieces.first else { continue }
                let firstLayout = blockLayout(for: firstPiece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                let headerAndBlock = headerHeight + firstLayout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    #if !canImport(UIKit)
                    context.endPDFPage()
                    #endif
                    pageIndex += 1
                    beginPage()
                }

                drawSectionHeader(
                    in: context,
                    title: "\(materialKey) - \(thicknessKey)",
                    origin: CGPoint(x: leftMargin, y: yOffset + 4),
                    maxWidth: pageSize.width - (leftMargin * 2)
                )
                yOffset += headerHeight

                for piece in pieces {
                    let layout = blockLayout(for: piece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 140)
                    if yOffset + layout.blockHeight > pageSize.height - 60 {
                        #if !canImport(UIKit)
                        context.endPDFPage()
                        #endif
                        pageIndex += 1
                        beginPage()
                    }

                    let xOffset: CGFloat = leftMargin
                    let drawingRect = CGRect(
                        x: xOffset + layout.drawingRect.origin.x,
                        y: yOffset + layout.drawingRect.origin.y,
                        width: layout.drawingRect.width,
                        height: layout.drawingRect.height
                    )
                    drawPieceBlock(
                        in: context,
                        piece: piece,
                        origin: CGPoint(x: xOffset, y: yOffset),
                        size: CGSize(width: CGFloat(columnWidth), height: layout.blockHeight),
                        drawingRect: drawingRect,
                        pieceHeaderY: yOffset + layout.pieceHeaderY,
                        topMeasurementY: yOffset + layout.topMeasurementY,
                        bottomMeasurementY: yOffset + layout.bottomMeasurementY,
                        notesY: yOffset + layout.notesY,
                        topEdgeLabelY: layout.topEdgeLabelY.map { yOffset + $0 },
                        bottomEdgeLabelY: layout.bottomEdgeLabelY.map { yOffset + $0 }
                    )

                    yOffset += layout.blockHeight + blockSpacing
                }

                yOffset += 12
            }

            if materialIndex == sortedMaterials.count - 1 {
                let legend = edgeLegend(for: project)
                drawNotes(in: context, notes: project.notes, edgeLegend: legend, origin: CGPoint(x: leftMargin, y: yOffset), maxWidth: pageSize.width - (leftMargin * 2))
            }
        }
    }

    private static func drawHeader(in context: CGContext, header: BusinessHeader, projectName: String, projectAddress: String, projectDate: Date, pageSize: CGSize, pageIndex: Int, totalPages: Int) -> CGFloat {
        let headerOriginY: CGFloat = 24
        let headerRect = CGRect(x: 24, y: headerOriginY, width: pageSize.width - 48, height: pageIndex == 1 ? 100 : 50)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: projectDate)

        if pageIndex == 1 {
            var textX: CGFloat = headerRect.minX + 12
            var headerHeight: CGFloat = 0
            if let logoData = header.logoData, let image = PlatformImage(data: logoData) {
                let logoRect = CGRect(x: headerRect.minX + 12, y: headerRect.minY + 12, width: 64, height: 64)
                #if canImport(UIKit)
                context.saveGState()
                context.translateBy(x: logoRect.minX, y: logoRect.maxY)
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                image.draw(in: CGRect(origin: .zero, size: logoRect.size))
                UIGraphicsPopContext()
                context.restoreGState()
                #else
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.saveGState()
                    // Flip for image drawing (images need to be flipped back)
                    context.translateBy(x: logoRect.minX, y: logoRect.maxY)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(cgImage, in: CGRect(origin: .zero, size: logoRect.size))
                    context.restoreGState()
                }
                #endif
                textX = logoRect.maxX + 12
                headerHeight = max(headerHeight, logoRect.maxY - headerOriginY)
            }

            let bodyFontSize: CGFloat = 12
            let emphasisFontSize: CGFloat = bodyFontSize + 2
            drawText(header.businessName, in: context, frame: CGRect(x: textX, y: headerRect.minY + 12, width: 300, height: 18), font: .boldSystemFont(ofSize: emphasisFontSize))
            headerHeight = max(headerHeight, (headerRect.minY + 12 + 18) - headerOriginY)
            let contactLines = [
                header.address.trimmingCharacters(in: .whitespacesAndNewlines),
                header.email.trimmingCharacters(in: .whitespacesAndNewlines),
                header.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ].filter { !$0.isEmpty }
            var contactY = headerRect.minY + 30
            for line in contactLines {
                let width: CGFloat = line == header.address ? 420 : 300
                drawText(line, in: context, frame: CGRect(x: textX, y: contactY, width: width, height: 14), font: .systemFont(ofSize: bodyFontSize))
                contactY += 16
            }
            headerHeight = max(headerHeight, (contactY - 2) - headerOriginY)

            let projectInfoX = headerRect.maxX - 220
            let projectInfoWidth: CGFloat = 200
            drawText("Project: \(projectName)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 12, width: projectInfoWidth, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize), alignment: .left)
            headerHeight = max(headerHeight, (headerRect.minY + 12 + 16) - headerOriginY)
            if !projectAddress.isEmpty {
                drawText("Address: \(projectAddress)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 30, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                drawText("Date: \(dateString)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 46, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                headerHeight = max(headerHeight, (headerRect.minY + 46 + 14) - headerOriginY)
            } else {
                drawText("Date: \(dateString)", in: context, frame: CGRect(x: projectInfoX, y: headerRect.minY + 30, width: projectInfoWidth, height: 14), font: .systemFont(ofSize: bodyFontSize), alignment: .left)
                headerHeight = max(headerHeight, (headerRect.minY + 30 + 14) - headerOriginY)
            }
            return headerHeight + 8
        } else {
            let bodyFontSize: CGFloat = 12
            let emphasisFontSize: CGFloat = bodyFontSize + 2
            drawText(header.businessName, in: context, frame: CGRect(x: headerRect.minX + 12, y: headerRect.minY + 12, width: 300, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize))
            drawText("Project: \(projectName)", in: context, frame: CGRect(x: headerRect.maxX - 220, y: headerRect.minY + 12, width: 200, height: 16), font: .boldSystemFont(ofSize: emphasisFontSize), alignment: .left)
            return 12 + 16 + 8
        }
    }

    private static func headerHeight(for header: BusinessHeader, projectName: String, projectAddress: String, projectDate: Date, pageIndex: Int) -> CGFloat {
        var height: CGFloat = 0
        if pageIndex == 1 {
            height = max(height, 12 + 18)
            if header.logoData != nil {
                height = max(height, 12 + 64)
            }
            let contactLines = [
                header.address.trimmingCharacters(in: .whitespacesAndNewlines),
                header.email.trimmingCharacters(in: .whitespacesAndNewlines),
                header.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            ].filter { !$0.isEmpty }
            if !contactLines.isEmpty {
                height = max(height, 30 + CGFloat(contactLines.count - 1) * 16 + 14)
            }
            height = max(height, 12 + 16)
            if !projectAddress.isEmpty {
                height = max(height, 46 + 14)
            } else {
                height = max(height, 30 + 14)
            }
        } else {
            height = max(height, 12 + 16)
        }
        return height + 8
    }

    private static func drawFooterPageCount(in context: CGContext, pageSize: CGSize, pageIndex: Int, totalPages: Int) {
        let bodyFontSize: CGFloat = 12
        let footerHeight: CGFloat = 14
        let footerY = pageSize.height - 20 - footerHeight
        let footerRect = CGRect(x: 0, y: footerY, width: pageSize.width, height: footerHeight)
        drawText("Page \(pageIndex) of \(totalPages)", in: context, frame: footerRect, font: .systemFont(ofSize: bodyFontSize), alignment: .center)
    }

    private static func drawPieceBlock(in context: CGContext, piece: Piece, origin: CGPoint, size: CGSize, drawingRect: CGRect, pieceHeaderY: CGFloat, topMeasurementY: CGFloat, bottomMeasurementY: CGFloat, notesY: CGFloat, topEdgeLabelY: CGFloat?, bottomEdgeLabelY: CGFloat?) {
        let blockRect = CGRect(origin: origin, size: size)
        _ = blockRect

        drawPieceDrawing(in: context, piece: piece, rect: drawingRect, pieceHeaderY: pieceHeaderY, topMeasurementY: topMeasurementY, bottomMeasurementY: bottomMeasurementY, notesY: notesY, topEdgeLabelY: topEdgeLabelY, bottomEdgeLabelY: bottomEdgeLabelY)
    }

    private struct PieceLayout {
        let blockHeight: CGFloat
        let drawingRect: CGRect
        let pieceHeaderY: CGFloat
        let topMeasurementY: CGFloat
        let bottomMeasurementY: CGFloat
        let notesY: CGFloat
        let topEdgeLabelY: CGFloat?
        let bottomEdgeLabelY: CGFloat?
    }

    private static func blockLayout(for piece: Piece, columnWidth: CGFloat, scale: CGFloat, maxBlockHeight: CGFloat) -> PieceLayout {
        let size = ShapePathBuilder.displaySize(for: piece)
        let leftPadding: CGFloat = drawingLeftInset
        let rightPadding = min(max(columnWidth * 0.16, 32), 110)
        let expanded = expandedDisplayBounds(for: piece)
        let headerTextHeight: CGFloat = 12
        let headerGapToPieceHeader: CGFloat = 6
        let pieceHeaderToTopMeasurementGap: CGFloat = 14
        let topMeasurementToEdgeGap: CGFloat = 4
        let bottomMeasurementToEdgeGap: CGFloat = 6
        let minTopMargin: CGFloat = 10
        let noteOffsetMultiplier: CGFloat = 7.6
        let notesLineHeight: CGFloat = 12
        let measurementHeight: CGFloat = 12
        let pieceHeaderHeight: CGFloat = 12

        let cutoutLines = cutoutNoteLines(for: piece)
        let pieceLines = pieceNoteLines(for: piece)
        let notesScaleFont = PlatformFont.systemFont(ofSize: 9, weight: .semibold)
        let pageWidth: CGFloat = 612
        let leftMargin: CGFloat = 24
        let centerPadding: CGFloat = 20
        let notesColumnWidth = (pageWidth - (leftMargin * 2) - centerPadding) / 2
        let cutoutWrapped = wrapLinesByWidth(cutoutLines, maxWidth: notesColumnWidth, font: notesScaleFont)
        let pieceWrapped = wrapLinesByWidth(pieceLines, maxWidth: notesColumnWidth, font: notesScaleFont)
        let maxLines = max(cutoutWrapped.count, pieceWrapped.count)
        let notesHeight = maxLines == 0 ? 0 : (CGFloat(maxLines) * notesLineHeight)
        let usableWidth = max(columnWidth - leftPadding - rightPadding, 10)
        let allowedWidthScale = usableWidth / max(size.width, 1)
        let fixedHeightBase = notesHeight + (rightPadding * 0.25)
        let variableHeight = size.height + noteOffsetMultiplier
        let allowedHeightScale = (maxBlockHeight - fixedHeightBase) / max(variableHeight, 1)
        let resolvedScale = min(scale, allowedWidthScale, allowedHeightScale)
        let expandedTopPt = expanded.minY * resolvedScale
        let expandedBottomPt = expanded.maxY * resolvedScale
        let topEdgeLabelPt = edgeLabelYPoint(piece: piece, size: size, scale: resolvedScale, expandedTop: expandedTopPt, expandedBottom: expandedBottomPt, isTop: true)
        let bottomEdgeLabelPt = edgeLabelYPoint(piece: piece, size: size, scale: resolvedScale, expandedTop: expandedTopPt, expandedBottom: expandedBottomPt, isTop: false)
        let topMeasurementY0 = topEdgeLabelPt - topMeasurementToEdgeGap - measurementHeight
        let pieceHeaderY0 = topMeasurementY0 - pieceHeaderToTopMeasurementGap - pieceHeaderHeight
        let pieceHeaderLineY0 = pieceHeaderY0 - headerGapToPieceHeader - headerTextHeight
        let requiredTopPadding = minTopMargin - pieceHeaderLineY0
        let topPadding = max(rightPadding * 0.55, requiredTopPadding)
        let drawingWidth = size.width * resolvedScale
        let drawingHeight = size.height * resolvedScale

        let drawingRect = CGRect(
            x: leftPadding,
            y: topPadding,
            width: drawingWidth,
            height: drawingHeight
        )

        let expandedBottom = drawingRect.minY + expanded.maxY * resolvedScale
        let topEdgeLabelY = topPadding + topEdgeLabelPt
        let bottomEdgeLabelY = topPadding + bottomEdgeLabelPt
        let topMeasurementY = topPadding + topMeasurementY0
        let pieceHeaderY = topPadding + pieceHeaderY0
        let bottomMeasurementY = bottomEdgeLabelY + bottomMeasurementToEdgeGap
        
        // BULLETPROOF: Calculate where notes should START (below ALL visual content)
        // 1. Shape bottom (including expanded bounds for curves)
        let shapeBottom = expandedBottom
        // 2. Bottom edge label: drawn at drawingRect.minY + size.height * scale + 12, plus label height 12
        let edgeLabelBottom = drawingRect.minY + drawingHeight + 12 + 12
        // 3. Bottom measurement text
        let measurementBottom = bottomMeasurementY + measurementHeight
        // 4. Quantity label: drawn at offsetY + (size.height * scale / 2) + 6, so extends to about center + 6
        let qtyLabelBottom = drawingRect.minY + drawingHeight / 2 + 6 + 12
        
        // Notes must start BELOW all visual content with proper padding
        let visualContentBottom = max(shapeBottom, edgeLabelBottom, measurementBottom, qtyLabelBottom)
        let notesPadding: CGFloat = 8
        let notesY = visualContentBottom + notesPadding
        
        // Notes bottom
        let notesBottom = notesY + notesHeight
        
        // Add padding before the next section header
        let sectionPadding: CGFloat = 12
        let blockHeight = max(80, notesBottom + sectionPadding)
        
        return PieceLayout(blockHeight: blockHeight, drawingRect: drawingRect, pieceHeaderY: pieceHeaderY, topMeasurementY: topMeasurementY, bottomMeasurementY: bottomMeasurementY, notesY: notesY, topEdgeLabelY: topEdgeLabelY, bottomEdgeLabelY: bottomEdgeLabelY)
    }

    private static func drawSectionHeader(in context: CGContext, title: String, origin: CGPoint, maxWidth: CGFloat) {
        let headerRect = CGRect(x: origin.x, y: origin.y, width: maxWidth, height: 20)
        context.saveGState()
        context.setFillColor(PlatformColor(white: 0.92, alpha: 1).cgColor)
        context.fill(headerRect)
        context.restoreGState()
        drawText(title, in: context, frame: headerRect.insetBy(dx: 8, dy: 2), font: .systemFont(ofSize: 12, weight: .bold))
    }

    private static func drawSubheader(in context: CGContext, title: String, origin: CGPoint, maxWidth: CGFloat) {
        let headerRect = CGRect(x: origin.x, y: origin.y, width: maxWidth, height: 16)
        context.saveGState()
        context.setFillColor(PlatformColor(white: 0.95, alpha: 1).cgColor)
        context.fill(headerRect)
        context.restoreGState()
        drawText(title, in: context, frame: headerRect.insetBy(dx: 8, dy: 1), font: .systemFont(ofSize: 11, weight: .semibold))
    }

    private static func drawPieceDrawing(in context: CGContext, piece: Piece, rect: CGRect, pieceHeaderY: CGFloat, topMeasurementY: CGFloat, bottomMeasurementY: CGFloat, notesY: CGFloat, topEdgeLabelY: CGFloat?, bottomEdgeLabelY: CGFloat?) {
        let size = ShapePathBuilder.displaySize(for: piece)
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let expanded = expandedDisplayBounds(for: piece)
        let minLeftMargin: CGFloat = 24
        let leftLabelPadding: CGFloat = drawingLeftInset + 24
        var offsetX = rect.minX
        let expandedLeft = offsetX + expanded.minX * scale
        let leftmostWithLabels = expandedLeft - leftLabelPadding
        if leftmostWithLabels < minLeftMargin {
            offsetX += minLeftMargin - leftmostWithLabels
        }
        let offsetY = rect.minY

        let path = ShapePathBuilder.path(for: piece)
        var transform = CGAffineTransform(translationX: offsetX, y: offsetY)
        transform = transform.scaledBy(x: scale, y: scale)
        let cgPath = path.cgPath.copy(using: &transform) ?? path.cgPath

        context.saveGState()
        context.setStrokeColor(PlatformColor.black.cgColor)
        context.setLineWidth(1.5)
        context.addPath(cgPath)
        context.strokePath()

        for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 && !isEffectiveNotch(cutout: cutout, size: size) {
            let displayCutout = displayCutout(for: cutout)
            let angleCuts = localAngleCuts(for: cutout, piece: piece)
            let cornerRadii = localCornerRadii(for: cutout, piece: piece)
            let cutoutPath = ShapePathBuilder.cutoutPath(displayCutout, angleCuts: angleCuts, cornerRadii: cornerRadii)
            var cutoutTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
            cutoutTransform = cutoutTransform.scaledBy(x: scale, y: scale)
            if let scaled = cutoutPath.cgPath.copy(using: &cutoutTransform) {
                context.addPath(scaled)
                context.strokePath()
            }
        }

        drawNotchDimensionLabels(in: context, piece: piece, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY)
        drawCutoutDimensionLabels(in: context, piece: piece, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY)
        drawEdgeLabels(in: context, piece: piece, rect: rect, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY)
        drawDimensionLabels(in: context, piece: piece, rect: rect, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY, pieceHeaderY: pieceHeaderY, topMeasurementY: topMeasurementY, bottomMeasurementY: bottomMeasurementY)
        drawCutoutNotes(in: context, piece: piece, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY, noteY: notesY)
        context.restoreGState()
    }

    private static func drawNotchDimensionLabels(in context: CGContext, piece: Piece, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let notches = piece.cutouts.filter { isEffectiveNotch(cutout: $0, size: size) && $0.centerX >= 0 && $0.centerY >= 0 }
        guard !notches.isEmpty else { return }
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)

        for notch in notches {
            let displayCutout = displayCutout(for: notch)
            let metricsInfo = notchInteriorEdgeMetrics(cutout: notch, size: size, polygon: polygon)
            var widthValue = metricsInfo?.width ?? CGFloat(notch.width)
            var lengthValue = metricsInfo?.length ?? CGFloat(notch.height)

            let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
            let halfWidth = displayCutout.width / 2
            let halfHeight = displayCutout.height / 2
            let minX = center.x - halfWidth
            let maxX = center.x + halfWidth
            let minY = center.y - halfHeight
            let maxY = center.y + halfHeight
            let edgeEpsilon: CGFloat = 0.01

            // Determine which edges the notch touches in display coordinates
            let touchesDisplayLeft = minX <= edgeEpsilon
            let touchesDisplayRight = maxX >= size.width - edgeEpsilon
            let touchesDisplayTop = minY <= edgeEpsilon
            let touchesDisplayBottom = maxY >= size.height - edgeEpsilon

            // Check for curves on touched edges and add "to Apex" suffix
            // Curves are stored with display edge positions
            // For left/right edge notches, the horizontal distance (lengthValue) is affected by the curve
            // For top/bottom edge notches, the vertical distance (widthValue) is affected by the curve
            var widthFromApex = false
            var lengthFromApex = false

            if touchesDisplayLeft {
                // Left edge notch - check for curve on left edge
                if let curve = piece.curve(for: .left), curve.radius > 0 {
                    let curveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    lengthValue += curveDepth
                    lengthFromApex = true
                }
            } else if touchesDisplayRight {
                // Right edge notch - check for curve on right edge
                if let curve = piece.curve(for: .right), curve.radius > 0 {
                    let curveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    lengthValue += curveDepth
                    lengthFromApex = true
                }
            }

            if touchesDisplayTop {
                // Top edge notch - check for curve on top edge
                if let curve = piece.curve(for: .top), curve.radius > 0 {
                    let curveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    widthValue += curveDepth
                    widthFromApex = true
                }
            } else if touchesDisplayBottom {
                // Bottom edge notch - check for curve on bottom edge
                if let curve = piece.curve(for: .bottom), curve.radius > 0 {
                    let curveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    widthValue += curveDepth
                    widthFromApex = true
                }
            }

            let widthText = MeasurementParser.formatInches(Double(widthValue))
            let heightText = MeasurementParser.formatInches(Double(lengthValue))

            let widthPx = displayCutout.width * scale
            let heightPx = displayCutout.height * scale
            let centerCanvas = CGPoint(x: offsetX + center.x * scale, y: offsetY + center.y * scale)
            let rectCanvas = CGRect(
                x: centerCanvas.x - widthPx / 2,
                y: centerCanvas.y - heightPx / 2,
                width: widthPx,
                height: heightPx
            )
            let pieceRect = CGRect(x: offsetX, y: offsetY, width: size.width * scale, height: size.height * scale)
            let padX: CGFloat = 8
            let padY: CGFloat = 4
            let canvasEdgeEpsilon: CGFloat = 0.5

            let widthCenterY = (metricsInfo?.widthCenterY ?? center.y) * scale + offsetY
            let lengthCenterX = (metricsInfo?.lengthCenterX ?? center.x) * scale + offsetX

            // Standard positioning for non-apex labels
            let widthX: CGFloat
            if rectCanvas.minX <= pieceRect.minX + canvasEdgeEpsilon {
                widthX = min(rectCanvas.maxX + padX, pieceRect.maxX - padX)
            } else if rectCanvas.maxX >= pieceRect.maxX - canvasEdgeEpsilon {
                widthX = max(rectCanvas.minX - padX, pieceRect.minX + padX)
            } else {
                widthX = min(rectCanvas.maxX + padX, pieceRect.maxX - padX)
            }

            let heightY: CGFloat
            if rectCanvas.minY <= pieceRect.minY + canvasEdgeEpsilon {
                heightY = min(rectCanvas.maxY + padY, pieceRect.maxY - padY)
            } else if rectCanvas.maxY >= pieceRect.maxY - canvasEdgeEpsilon {
                heightY = max(rectCanvas.minY - padY, pieceRect.minY + padY)
            } else {
                heightY = min(rectCanvas.maxY + padY, pieceRect.maxY - padY)
            }

            // Draw width label (for top/bottom edge notches - widthFromApex)
            // Position: to the right of the notch edge
            if widthFromApex {
                // Two-line label: "X\" to" on top, "Apex" below
                // Position to the right of the notch interior edge (left-aligned)
                let apexPadX: CGFloat = 2
                let apexX = rectCanvas.maxX + apexPadX
                let line1 = "\(widthText)\" to"
                let line2 = "Apex"
                let labelY = widthCenterY
                let lineSpacing: CGFloat = 10
                drawText(line1, in: context, frame: CGRect(x: apexX, y: labelY - lineSpacing / 2 - 6, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .left)
                drawText(line2, in: context, frame: CGRect(x: apexX, y: labelY + lineSpacing / 2 - 6, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .left)
            } else {
                let widthLabel = "\(widthText)\""
                drawText(widthLabel, in: context, frame: CGRect(x: widthX - 20, y: widthCenterY - 6, width: 40, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
            }

            // Draw length label (for left/right edge notches - lengthFromApex)
            // Position: below the notch
            if lengthFromApex {
                // Two-line label: "X\" to" on top, "Apex" below
                // Position below the notch interior edge
                let apexPadY: CGFloat = 10
                let apexY = rectCanvas.maxY + apexPadY
                let line1 = "\(heightText)\" to"
                let line2 = "Apex"
                let labelX = lengthCenterX
                let lineSpacing: CGFloat = 10
                drawText(line1, in: context, frame: CGRect(x: labelX - 30, y: apexY - lineSpacing / 2 - 6, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
                drawText(line2, in: context, frame: CGRect(x: labelX - 30, y: apexY + lineSpacing / 2 - 6, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
            } else {
                let lengthLabel = "\(heightText)\""
                drawText(lengthLabel, in: context, frame: CGRect(x: lengthCenterX - 20, y: heightY - 6, width: 40, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
            }
        }
    }

    private static func drawCutoutDimensionLabels(in context: CGContext, piece: Piece, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        // Get cutouts that are NOT notches (interior holes)
        let cutouts = piece.cutouts.filter { !isEffectiveNotch(cutout: $0, size: size) && $0.centerX >= 0 && $0.centerY >= 0 && $0.kind != .circle }
        guard !cutouts.isEmpty else { return }

        for cutout in cutouts {
            let displayCutout = displayCutout(for: cutout)
            let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
            let halfWidth = displayCutout.width / 2
            let halfHeight = displayCutout.height / 2

            // Use the raw cutout dimensions
            let widthValue = CGFloat(displayCutout.width)
            let lengthValue = CGFloat(displayCutout.height)

            let widthText = MeasurementParser.formatInches(Double(widthValue))
            let lengthText = MeasurementParser.formatInches(Double(lengthValue))

            // Convert to canvas coordinates
            let centerCanvas = CGPoint(x: offsetX + center.x * scale, y: offsetY + center.y * scale)
            let halfWidthCanvas = halfWidth * scale
            let halfHeightCanvas = halfHeight * scale

            // Padding from cutout edge
            let padding: CGFloat = 2

            // Width label - centered horizontally above the cutout
            let widthLabel = "\(widthText)\""
            let widthY = centerCanvas.y - halfHeightCanvas - padding - 12
            drawText(widthLabel, in: context, frame: CGRect(x: centerCanvas.x - 30, y: widthY, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)

            // Length label - centered vertically to the left of the cutout
            let lengthLabel = "\(lengthText)\""
            let lengthX = centerCanvas.x - halfWidthCanvas - padding - 40
            drawText(lengthLabel, in: context, frame: CGRect(x: lengthX, y: centerCanvas.y - 6, width: 40, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .right)
        }
    }

    private static func notchInteriorEdgeMetrics(cutout: Cutout, size: CGSize, polygon: [CGPoint]) -> (width: CGFloat, length: CGFloat, widthCenterY: CGFloat, lengthCenterX: CGFloat)? {
        guard polygon.count >= 2 else { return nil }
        let displayCutout = displayCutout(for: cutout)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let minX = displayCutout.centerX - halfWidth
        let maxX = displayCutout.centerX + halfWidth
        let minY = displayCutout.centerY - halfHeight
        let maxY = displayCutout.centerY + halfHeight
        let edgeEpsilon: CGFloat = 0.01

        let touchesLeft = minX <= edgeEpsilon
        let touchesRight = maxX >= size.width - edgeEpsilon
        let touchesTop = minY <= edgeEpsilon
        let touchesBottom = maxY >= size.height - edgeEpsilon

        let interiorX: CGFloat?
        if touchesLeft {
            interiorX = maxX
        } else if touchesRight {
            interiorX = minX
        } else {
            interiorX = nil
        }

        let interiorY: CGFloat?
        if touchesTop {
            interiorY = maxY
        } else if touchesBottom {
            interiorY = minY
        } else {
            interiorY = nil
        }

        var verticalLen: CGFloat = 0
        var verticalCenterY: CGFloat = displayCutout.centerY
        if let interiorX {
            verticalLen = segmentLengthOnLine(points: polygon, isVertical: true, value: interiorX, rangeMin: minY, rangeMax: maxY)
            if verticalLen > 0 {
                verticalCenterY = segmentCenterOnLine(points: polygon, isVertical: true, value: interiorX, rangeMin: minY, rangeMax: maxY)
            }
        }
        var horizontalLen: CGFloat = 0
        var horizontalCenterX: CGFloat = displayCutout.centerX
        if let interiorY {
            horizontalLen = segmentLengthOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            if horizontalLen > 0 {
                horizontalCenterX = segmentCenterOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            }
        }

        guard verticalLen > 0 || horizontalLen > 0 else { return nil }
        return (width: verticalLen > 0 ? verticalLen : CGFloat(displayCutout.height),
                length: horizontalLen > 0 ? horizontalLen : CGFloat(displayCutout.width),
                widthCenterY: verticalCenterY,
                lengthCenterX: horizontalCenterX)
    }

    private static func segmentLengthOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
        let eps: CGFloat = 0.01
        var total: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            if isVertical {
                guard abs(a.x - value) < eps, abs(b.x - value) < eps else { continue }
                let segMin = min(a.y, b.y)
                let segMax = max(a.y, b.y)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    total += overlapMax - overlapMin
                }
            } else {
                guard abs(a.y - value) < eps, abs(b.y - value) < eps else { continue }
                let segMin = min(a.x, b.x)
                let segMax = max(a.x, b.x)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    total += overlapMax - overlapMin
                }
            }
        }
        return total
    }

    private static func segmentCenterOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
        let eps: CGFloat = 0.01
        var weightedSum: CGFloat = 0
        var total: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            if isVertical {
                guard abs(a.x - value) < eps, abs(b.x - value) < eps else { continue }
                let segMin = min(a.y, b.y)
                let segMax = max(a.y, b.y)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    let len = overlapMax - overlapMin
                    let mid = (overlapMin + overlapMax) / 2
                    weightedSum += mid * len
                    total += len
                }
            } else {
                guard abs(a.y - value) < eps, abs(b.y - value) < eps else { continue }
                let segMin = min(a.x, b.x)
                let segMax = max(a.x, b.x)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    let len = overlapMax - overlapMin
                    let mid = (overlapMin + overlapMax) / 2
                    weightedSum += mid * len
                    total += len
                }
            }
        }
        guard total > 0 else { return (rangeMin + rangeMax) / 2 }
        return weightedSum / total
    }

    private static func drawEdgeLabels(in context: CGContext, piece: Piece, rect: CGRect, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let angleSegments = ShapePathBuilder.angleSegments(for: piece)
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let boundarySegments = ShapePathBuilder.boundarySegments(for: piece)
        let segmentCounts = Dictionary(grouping: boundarySegments, by: { $0.edge }).mapValues { $0.count }
        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard assignment.cutoutEdge == nil, assignment.angleEdgeId == nil else { continue }
            if let segmentEdge = assignment.segmentEdge {
                if let segment = boundarySegments.first(where: { $0.edge == segmentEdge.edge && $0.index == segmentEdge.index }) {
                    let point = segmentEdgeNotationPoint(segment: segment, piece: piece, scale: scale, offsetX: offsetX, offsetY: offsetY)
                    drawText(code, in: context, frame: CGRect(x: point.x - 16, y: point.y - 8, width: 32, height: 12), font: .systemFont(ofSize: 10, weight: .bold), alignment: .center)
                }
                continue
            }
            if piece.shape == .rectangle, (segmentCounts[assignment.edge] ?? 0) > 1 {
                continue
            }
            let point = edgeLabelPoint(edge: assignment.edge, piece: piece, shape: piece.shape, curves: piece.curvedEdges, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY, cutouts: piece.cutouts)
            drawText(code, in: context, frame: CGRect(x: point.x - 16, y: point.y - 8, width: 32, height: 12), font: .systemFont(ofSize: 10, weight: .bold), alignment: .center)
        }

        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard let angleId = assignment.angleEdgeId else { continue }
            guard let segment = angleSegments.first(where: { $0.id == angleId }) else { continue }
            let center = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
            let offsetDistance = 8 / max(scale, 0.01)
            let adjusted = offsetOutsidePolygon(
                point: center,
                segmentStart: segment.start,
                segmentEnd: segment.end,
                polygon: polygon,
                distance: offsetDistance
            )
            let centerX = offsetX + adjusted.x * scale
            let centerY = offsetY + adjusted.y * scale
            drawText(code, in: context, frame: CGRect(x: centerX - 16, y: centerY - 8, width: 32, height: 12), font: .systemFont(ofSize: 10, weight: .bold), alignment: .center)
        }

        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard let cutoutEdge = assignment.cutoutEdge else { continue }
            guard let cutout = piece.cutouts.first(where: { $0.id == cutoutEdge.id }) else { continue }
            guard cutout.centerX >= 0 && cutout.centerY >= 0 else { continue }
            guard isInteriorNotchEdge(cutout: cutout, edge: cutoutEdge.edge, pieceSize: size) else { continue }
            let point = cutoutEdgeLabelPoint(cutout: cutout, edge: cutoutEdge.edge, size: size, scale: scale, offsetX: offsetX, offsetY: offsetY, polygon: polygon)
            drawText(code, in: context, frame: CGRect(x: point.x - 12, y: point.y - 7, width: 24, height: 12), font: .systemFont(ofSize: 9, weight: .bold), alignment: .center)
        }
    }

    private static func isInteriorNotchEdge(cutout: Cutout, edge: EdgePosition, pieceSize: CGSize) -> Bool {
        let displayCutout = displayCutout(for: cutout)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let minX = displayCutout.centerX - halfWidth
        let maxX = displayCutout.centerX + halfWidth
        let minY = displayCutout.centerY - halfHeight
        let maxY = displayCutout.centerY + halfHeight
        let edgeEpsilon: CGFloat = 0.01

        switch edge {
        case .left:
            return minX > edgeEpsilon
        case .right:
            return maxX < pieceSize.width - edgeEpsilon
        case .top:
            return minY > edgeEpsilon
        case .bottom:
            return maxY < pieceSize.height - edgeEpsilon
        default:
            return true
        }
    }

    private static func isEffectiveNotch(cutout: Cutout, size: CGSize) -> Bool {
        if cutout.isNotch { return true }
        guard cutout.kind != .circle else { return false }
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let minX = cutout.centerX - halfWidth
        let maxX = cutout.centerX + halfWidth
        let minY = cutout.centerY - halfHeight
        let maxY = cutout.centerY + halfHeight
        let eps: CGFloat = 0.01
        return minX <= eps || minY <= eps || maxX >= size.width - eps || maxY >= size.height - eps
    }

    /// Returns the position for a segment's edge notation label (like "PE"), accounting for curved edges
    private static func segmentEdgeNotationPoint(segment: BoundarySegment, piece: Piece, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        
        // Handle curved edges - calculate point on curve and offset from there
        if let curve = piece.curve(for: segment.edge), curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            let size = ShapePathBuilder.displaySize(for: piece)
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if piece.shape == .rectangle {
                switch segment.edge {
                case .top:
                    geometry = (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
                case .right:
                    geometry = (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
                case .bottom:
                    geometry = (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
                case .left:
                    geometry = (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
                default:
                    geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
                }
            } else {
                geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
            }
            if let geometry {
                // Calculate t parameter for where segment midpoint falls on edge
                let denom: CGFloat
                let t: CGFloat
                switch segment.edge {
                case .top, .bottom, .legA:
                    denom = geometry.end.x - geometry.start.x
                    t = denom == 0 ? 0.5 : (mid.x - geometry.start.x) / denom
                case .left, .right, .legB:
                    denom = geometry.end.y - geometry.start.y
                    t = denom == 0 ? 0.5 : (mid.y - geometry.start.y) / denom
                case .hypotenuse:
                    let total = distance(geometry.start, geometry.end)
                    t = total == 0 ? 0.5 : distance(geometry.start, mid) / total
                }
                let clampedT = min(max(t, 0), 1)
                let control = controlPoint(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                // Edge notation uses smaller offset (6) compared to dimension labels
                let offsetDistance = 6 / max(scale, 0.01)
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let outward = normalized(CGPoint(x: curvePoint.x - center.x, y: curvePoint.y - center.y))
                let adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance,
                    preferInside: false,
                    preferredDirection: outward
                )
                return CGPoint(x: offsetX + adjusted.x * scale, y: offsetY + adjusted.y * scale)
            }
        }
        
        // Non-curved edges - use simple direction offset
        let baseOffset = 6 / max(scale, 0.01)
        let direction: CGPoint
        switch segment.edge {
        case .top:
            direction = CGPoint(x: 0, y: -1)
        case .bottom:
            direction = CGPoint(x: 0, y: 1)
        case .left:
            direction = CGPoint(x: -1, y: 0)
        case .right:
            direction = CGPoint(x: 1, y: 0)
        default:
            direction = CGPoint(x: 0, y: -1)
        }
        let adjusted = CGPoint(x: mid.x + direction.x * baseOffset, y: mid.y + direction.y * baseOffset)
        return CGPoint(x: offsetX + adjusted.x * scale, y: offsetY + adjusted.y * scale)
    }

    /// Returns the position for a segment's dimension label (like "5 in"), accounting for curved edges
    private static func segmentLabelPoint(segment: BoundarySegment, piece: Piece, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        
        // Handle curved edges - calculate point on curve and offset from there
        if let curve = piece.curve(for: segment.edge), curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            let size = ShapePathBuilder.displaySize(for: piece)
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if piece.shape == .rectangle {
                switch segment.edge {
                case .top:
                    geometry = (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
                case .right:
                    geometry = (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
                case .bottom:
                    geometry = (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
                case .left:
                    geometry = (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
                default:
                    geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
                }
            } else {
                geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
            }
            if let geometry {
                // Calculate t parameter for where segment midpoint falls on edge
                let denom: CGFloat
                let t: CGFloat
                switch segment.edge {
                case .top, .bottom, .legA:
                    denom = geometry.end.x - geometry.start.x
                    t = denom == 0 ? 0.5 : (mid.x - geometry.start.x) / denom
                case .left, .right, .legB:
                    denom = geometry.end.y - geometry.start.y
                    t = denom == 0 ? 0.5 : (mid.y - geometry.start.y) / denom
                case .hypotenuse:
                    let total = distance(geometry.start, geometry.end)
                    t = total == 0 ? 0.5 : distance(geometry.start, mid) / total
                }
                let clampedT = min(max(t, 0), 1)
                let control = controlPoint(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                // Measurement labels need more offset than edge notations (which use 6)
                // to create clear separation between them
                let curveBaseOffset = CGFloat(segment.edge == .hypotenuse ? 12 : 8) / max(scale, 0.01)
                var curveOffsetDistance = curveBaseOffset
                if segment.edge == .top || segment.edge == .bottom {
                    // Add extra offset for top/bottom to separate from edge notations
                    curveOffsetDistance += 10 / max(scale, 0.01)
                }
                if segment.edge == .left || segment.edge == .right {
                    curveOffsetDistance += (20 / max(scale, 0.01))
                }
                let outward = normalized(geometry.normal)
                var adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: curveOffsetDistance,
                    preferInside: false,
                    preferredDirection: outward
                )
                if pointIsInsidePolygon(adjusted, polygon: polygon) {
                    adjusted = CGPoint(
                        x: curvePoint.x - outward.x * curveOffsetDistance,
                        y: curvePoint.y - outward.y * curveOffsetDistance
                    )
                }
                return CGPoint(x: offsetX + adjusted.x * scale, y: offsetY + adjusted.y * scale)
            }
        }
        
        // Non-curved edges - use simple direction offset
        let baseOffset = 12 / max(scale, 0.01)
        let sideBoost = 18 / max(scale, 0.01)
        let extraPadding = 10 / max(scale, 0.01)
        let direction: CGPoint
        switch segment.edge {
        case .top:
            direction = CGPoint(x: 0, y: -1)
        case .bottom:
            direction = CGPoint(x: 0, y: 1)
        case .left:
            direction = CGPoint(x: -1, y: 0)
        case .right:
            direction = CGPoint(x: 1, y: 0)
        default:
            direction = CGPoint(x: 0, y: -1)
        }
        let offsetDistance = (segment.edge == .left || segment.edge == .right)
            ? (baseOffset + sideBoost + extraPadding + (10 / max(scale, 0.01)))
            : baseOffset
        let adjusted = CGPoint(x: mid.x + direction.x * offsetDistance, y: mid.y + direction.y * offsetDistance)
        return CGPoint(x: offsetX + adjusted.x * scale, y: offsetY + adjusted.y * scale)
    }

    private static func edgeLabelPoint(edge: EdgePosition, piece: Piece, shape: ShapeKind, curves: [CurvedEdge], size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, cutouts: [Cutout] = []) -> CGPoint {
        let width = size.width * scale
        let height = size.height * scale
        let curveMap = Dictionary(grouping: curves, by: { $0.edge }).compactMapValues { $0.first }

        if shape == .circle {
            let center = CGPoint(x: offsetX + width / 2, y: offsetY + height / 2)
            let radiusY = height / 2
            return CGPoint(x: center.x, y: center.y - radiusY - 6)
        }

        if shape == .rectangle, curveMap[edge]?.radius == nil {
            let sideMetrics = rectangleSideMetrics(for: piece)
            if let sideMetric = sideMetrics[edge] {
                let centerX = offsetX + sideMetric.center.x * scale
                let centerY = offsetY + sideMetric.center.y * scale
                switch edge {
                case .top:
                    return CGPoint(x: centerX, y: offsetY - 6)
                case .bottom:
                    return CGPoint(x: centerX, y: offsetY + height + 6)
                case .left:
                    return CGPoint(x: offsetX - 6, y: centerY)
                case .right:
                    return CGPoint(x: offsetX + width + 6, y: centerY)
                default:
                    break
                }
            }
        }

        if shape == .quarterCircle && edge == .hypotenuse {
            let center = CGPoint(x: offsetX, y: offsetY)
            let radius = width
            let direction = normalized(CGPoint(x: 1, y: 1))
            return CGPoint(x: center.x + direction.x * (radius + 6), y: center.y + direction.y * (radius + 6))
        }

        if let curve = curveMap[edge], curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            if let geometry = edgeGeometryFromPolygon(edge: edge, polygon: polygon, shape: shape, baseBounds: baseBounds) {
                let control = controlPoint(for: geometry, curve: curve)
                let mid = quadBezierPoint(t: 0.5, start: geometry.start, control: control, end: geometry.end)
                let baseOffset: CGFloat = edge == .hypotenuse ? 10 : 6
                var offsetDistance = baseOffset / max(scale, 0.01)
                if edge == .bottom {
                    offsetDistance += 4 / max(scale, 0.01)
                }
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let direction = normalized(CGPoint(x: mid.x - center.x, y: mid.y - center.y))
                let adjusted = offsetRelativeToPolygon(
                    point: mid,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance,
                    preferInside: false,
                    preferredDirection: direction
                )
                return CGPoint(x: adjusted.x * scale + offsetX, y: adjusted.y * scale + offsetY)
            }
        }

        switch edge {
        case .top:
            return CGPoint(x: offsetX + width / 2, y: offsetY - 6)
        case .right:
            return CGPoint(x: offsetX + width + 6, y: offsetY + height / 2)
        case .bottom:
            return CGPoint(x: offsetX + width / 2, y: offsetY + height + 12)
        case .left:
            return CGPoint(x: offsetX - 6, y: offsetY + height / 2)
        case .hypotenuse:
            return CGPoint(x: offsetX + width * 0.6, y: offsetY + height * 0.6)
        case .legA:
            return CGPoint(x: offsetX + width / 2, y: offsetY - 6)
        case .legB:
            return CGPoint(x: offsetX - 6, y: offsetY + height / 2)
        }
    }

    private static func edgeGeometry(for edge: EdgePosition, size: CGSize) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        let width = size.width
        let height = size.height
        switch edge {
        case .top:
            return (CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: 0, y: -1))
        case .right:
            return (CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 1, y: 0))
        case .bottom:
            return (CGPoint(x: width, y: height), CGPoint(x: 0, y: height), CGPoint(x: 0, y: 1))
        case .left:
            return (CGPoint(x: 0, y: height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
        case .legA:
            return (CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: 0, y: -1))
        case .legB:
            return (CGPoint(x: 0, y: height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
        case .hypotenuse:
            return (CGPoint(x: width, y: 0), CGPoint(x: 0, y: height), CGPoint(x: 0.7, y: 0.7))
        }
    }

    private static func edgeLabelYDisplay(piece: Piece, size: CGSize, expanded: CGRect, isTop: Bool) -> CGFloat? {
        var bestY: CGFloat?
        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard assignment.cutoutEdge == nil, assignment.angleEdgeId == nil else { continue }
            let point = edgeLabelPoint(edge: assignment.edge, piece: piece, shape: piece.shape, curves: piece.curvedEdges, size: size, scale: 1, offsetX: 0, offsetY: 0, cutouts: piece.cutouts)
            if isTop {
                guard point.y <= expanded.minY + 1 else { continue }
                bestY = min(bestY ?? point.y, point.y)
            } else {
                guard point.y >= expanded.maxY - 1 else { continue }
                bestY = max(bestY ?? point.y, point.y)
            }
        }
        return bestY
    }

    private static func edgeGeometryFromPolygon(edge: EdgePosition, polygon: [CGPoint], shape: ShapeKind, baseBounds: CGRect?) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        guard polygon.count >= 2 else { return nil }
        let bounds = polygonBounds(polygon)
        let hypotenuseBounds = baseBounds ?? bounds
        let eps: CGFloat = 0.01

        var best: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestDiagonal: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegA: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegB: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegADistance: CGFloat?
        var bestLegBDistance: CGFloat?
        var bestDiagonalDistance: CGFloat?
        let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))

        for i in 0..<polygon.count {
            let start = polygon[i]
            let end = polygon[(i + 1) % polygon.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = distance(start, end)
            if length <= 0.0001 { continue }

            let isHorizontal = abs(dy) < eps
            let isVertical = abs(dx) < eps

            if shape == .rightTriangle {
                if isHorizontal {
                    let distanceToLeg = abs(((start.y + end.y) / 2) - bounds.minY)
                    if bestLegA == nil || distanceToLeg < (bestLegADistance ?? .greatestFiniteMagnitude) ||
                        (abs(distanceToLeg - (bestLegADistance ?? .greatestFiniteMagnitude)) < 0.001 && length > (bestLegA?.length ?? 0)) {
                        bestLegA = (start, end, length)
                        bestLegADistance = distanceToLeg
                    }
                } else if isVertical {
                    let distanceToLeg = abs(((start.x + end.x) / 2) - bounds.minX)
                    if bestLegB == nil || distanceToLeg < (bestLegBDistance ?? .greatestFiniteMagnitude) ||
                        (abs(distanceToLeg - (bestLegBDistance ?? .greatestFiniteMagnitude)) < 0.001 && length > (bestLegB?.length ?? 0)) {
                        bestLegB = (start, end, length)
                        bestLegBDistance = distanceToLeg
                    }
                } else {
                    let distanceToHypotenuse = (pointLineDistance(point: start, a: CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY), b: CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY))
                        + pointLineDistance(point: end, a: CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY), b: CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY))) / 2
                    if bestDiagonal == nil || distanceToHypotenuse < (bestDiagonalDistance ?? .greatestFiniteMagnitude) {
                        bestDiagonal = (start, end, length)
                        bestDiagonalDistance = distanceToHypotenuse
                    }
                }
                continue
            }

            switch edge {
            case .top:
                if isHorizontal, abs(((start.y + end.y) / 2) - bounds.minY) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .bottom:
                if isHorizontal, abs(((start.y + end.y) / 2) - bounds.maxY) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .left:
                if isVertical, abs(((start.x + end.x) / 2) - bounds.minX) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .right:
                if isVertical, abs(((start.x + end.x) / 2) - bounds.maxX) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            default:
                break
            }
        }

        if shape == .rightTriangle {
            func outwardNormal(for segment: (start: CGPoint, end: CGPoint)) -> CGPoint {
                let dx = segment.end.x - segment.start.x
                let dy = segment.end.y - segment.start.y
                var normal = normalized(CGPoint(x: dy, y: -dx))
                let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
                let toMid = CGPoint(x: mid.x - center.x, y: mid.y - center.y)
                if normal.x * toMid.x + normal.y * toMid.y < 0 {
                    normal = CGPoint(x: -normal.x, y: -normal.y)
                }
                return normal
            }
            switch edge {
            case .legA:
                if let segment = bestLegA {
                    return (segment.start, segment.end, outwardNormal(for: (segment.start, segment.end)))
                }
                return nil
            case .legB:
                if let segment = bestLegB {
                    return (segment.start, segment.end, outwardNormal(for: (segment.start, segment.end)))
                }
                return nil
            case .hypotenuse:
                if let diag = bestDiagonal {
                    let normal = outwardNormal(for: (diag.start, diag.end))
                    return (diag.start, diag.end, normal)
                }
                return nil
            default:
                break
            }
        }

        guard let segment = best else { return nil }
        let normal: CGPoint
        switch edge {
        case .top:
            normal = CGPoint(x: 0, y: -1)
        case .bottom:
            normal = CGPoint(x: 0, y: 1)
        case .left:
            normal = CGPoint(x: -1, y: 0)
        case .right:
            normal = CGPoint(x: 1, y: 0)
        case .legA:
            normal = CGPoint(x: 0, y: -1)
        case .legB:
            normal = CGPoint(x: -1, y: 0)
        case .hypotenuse:
            normal = normalized(CGPoint(x: segment.end.y - segment.start.y, y: -(segment.end.x - segment.start.x)))
        }
        return (segment.start, segment.end, normal)
    }

    private static func controlPoint(for geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), curve: CurvedEdge) -> CGPoint {
        let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
        let direction: CGFloat = curve.isConcave ? -1 : 1
        let normal = normalized(geometry.normal)
        return CGPoint(x: mid.x + normal.x * curve.radius * 2 * direction, y: mid.y + normal.y * curve.radius * 2 * direction)
    }

    private static func quadBezierPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let oneMinus = 1 - t
        let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * end.x
        let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(sqrt(point.x * point.x + point.y * point.y), 0.0001)
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func polygonBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func segmentIsOnHypotenuse(start: CGPoint, end: CGPoint, bounds: CGRect) -> Bool {
        let a = CGPoint(x: bounds.maxX, y: bounds.minY)
        let b = CGPoint(x: bounds.minX, y: bounds.maxY)
        let tolerance: CGFloat = 1.0
        return pointLineDistance(point: start, a: a, b: b) <= tolerance &&
            pointLineDistance(point: end, a: a, b: b) <= tolerance
    }

    private static func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(sqrt(dx * dx + dy * dy), 0.0001)
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / denom
    }

    private static func cutoutEdgeLabelPoint(cutout: Cutout, edge: EdgePosition, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, polygon: [CGPoint]) -> CGPoint {
        let displayCutout = displayCutout(for: cutout)
        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let padding = 6 / max(scale, 0.01)

        if cutout.kind == .circle {
            let point = center
            return CGPoint(x: offsetX + point.x * scale, y: offsetY + point.y * scale)
        }

        if let metricsInfo = notchInteriorEdgeMetrics(cutout: cutout, size: size, polygon: polygon) {
            let point: CGPoint
            switch edge {
            case .left:
                point = CGPoint(x: center.x - halfWidth, y: metricsInfo.widthCenterY)
            case .right:
                point = CGPoint(x: center.x + halfWidth, y: metricsInfo.widthCenterY)
            case .top:
                point = CGPoint(x: metricsInfo.lengthCenterX, y: center.y - halfHeight)
            case .bottom:
                point = CGPoint(x: metricsInfo.lengthCenterX, y: center.y + halfHeight)
            default:
                point = CGPoint(x: center.x, y: center.y)
            }
            let adjusted = offsetOutsidePolygon(
                point: point,
                segmentStart: segmentStartPoint(for: edge, cutout: displayCutout),
                segmentEnd: segmentEndPoint(for: edge, cutout: displayCutout),
                polygon: polygon,
                distance: padding
            )
            return CGPoint(x: offsetX + adjusted.x * scale, y: offsetY + adjusted.y * scale)
        }

        // For interior cutouts (not notches), position label inside the cutout centered on the edge
        let minX = center.x - halfWidth
        let maxX = center.x + halfWidth
        let minY = center.y - halfHeight
        let maxY = center.y + halfHeight
        let point: CGPoint

        switch edge {
        case .top:
            point = CGPoint(x: center.x, y: minY + padding)
        case .bottom:
            point = CGPoint(x: center.x, y: maxY - padding)
        case .left:
            point = CGPoint(x: minX + padding, y: center.y)
        case .right:
            point = CGPoint(x: maxX - padding, y: center.y)
        default:
            point = CGPoint(x: center.x, y: minY + padding)
        }

        // Interior cutouts should have labels inside, so don't offset outside
        return CGPoint(x: offsetX + point.x * scale, y: offsetY + point.y * scale)
    }

    private static func segmentStartPoint(for edge: EdgePosition, cutout: Cutout) -> CGPoint {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        switch edge {
        case .left:
            return CGPoint(x: center.x - halfWidth, y: center.y - halfHeight)
        case .right:
            return CGPoint(x: center.x + halfWidth, y: center.y - halfHeight)
        case .top:
            return CGPoint(x: center.x - halfWidth, y: center.y - halfHeight)
        case .bottom:
            return CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        default:
            return center
        }
    }

    private static func segmentEndPoint(for edge: EdgePosition, cutout: Cutout) -> CGPoint {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        switch edge {
        case .left:
            return CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        case .right:
            return CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        case .top:
            return CGPoint(x: center.x + halfWidth, y: center.y - halfHeight)
        case .bottom:
            return CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        default:
            return center
        }
    }

    private static func offsetOutsidePolygon(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint, polygon: [CGPoint], distance: CGFloat) -> CGPoint {
        offsetRelativeToPolygon(
            point: point,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            polygon: polygon,
            distance: distance,
            preferInside: false,
            preferredDirection: nil
        )
    }

    private static func offsetRelativeToPolygon(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint, polygon: [CGPoint], distance: CGFloat, preferInside: Bool, preferredDirection: CGPoint?) -> CGPoint {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let candidateA = CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
        let candidateB = CGPoint(x: point.x - normal.x * distance, y: point.y - normal.y * distance)
        let insideA = pointIsInsidePolygon(candidateA, polygon: polygon)
        let insideB = pointIsInsidePolygon(candidateB, polygon: polygon)
        if preferInside {
            if let preferredDirection {
                let dir = normalized(preferredDirection)
                let dotA = (candidateA.x - point.x) * dir.x + (candidateA.y - point.y) * dir.y
                let dotB = (candidateB.x - point.x) * dir.x + (candidateB.y - point.y) * dir.y
                let preferred = dotA >= dotB ? candidateA : candidateB
                let alternate = dotA >= dotB ? candidateB : candidateA
                let preferredInside = dotA >= dotB ? insideA : insideB
                let alternateInside = dotA >= dotB ? insideB : insideA
                if preferredInside { return preferred }
                if alternateInside { return alternate }
                return preferred
            }
            if insideA && insideB {
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let distA = hypot(candidateA.x - center.x, candidateA.y - center.y)
                let distB = hypot(candidateB.x - center.x, candidateB.y - center.y)
                return distA >= distB ? candidateA : candidateB
            }
            if insideA { return candidateA }
            if insideB { return candidateB }
            let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
            let distA = hypot(candidateA.x - center.x, candidateA.y - center.y)
            let distB = hypot(candidateB.x - center.x, candidateB.y - center.y)
            return distA <= distB ? candidateA : candidateB
        }
        if let preferredDirection {
            let dir = normalized(preferredDirection)
            let dotA = (candidateA.x - point.x) * dir.x + (candidateA.y - point.y) * dir.y
            let dotB = (candidateB.x - point.x) * dir.x + (candidateB.y - point.y) * dir.y
            let preferred = dotA >= dotB ? candidateA : candidateB
            let alternate = dotA >= dotB ? candidateB : candidateA
            let preferredOutside = dotA >= dotB ? !insideA : !insideB
            let alternateOutside = dotA >= dotB ? !insideB : !insideA
            if preferredOutside { return preferred }
            if alternateOutside { return alternate }
            return preferred
        }
        return insideA ? candidateB : candidateA
    }

    private static func pointIsInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersect = ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.000001) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func curveOutset(for edge: EdgePosition, piece: Piece) -> CGFloat {
        piece.curvedEdges
            .filter { $0.edge == edge && !$0.isConcave }
            .map { CGFloat($0.radius) }
            .max() ?? 0
    }

    private static func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func expandedDisplayBounds(for piece: Piece) -> CGRect {
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        // For shapes without polygon points (circle, quarterCircle), use displaySize directly
        guard !polygon.isEmpty else {
            let size = ShapePathBuilder.displaySize(for: piece)
            return CGRect(origin: .zero, size: size)
        }
        var bounds = bounds(for: polygon)
        let convexCurves = piece.curvedEdges.filter { $0.radius > 0 && !$0.isConcave }
        if convexCurves.isEmpty { return bounds }
        let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
        for curve in convexCurves {
            guard let geometry = edgeGeometryFromPolygon(edge: curve.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds) else { continue }
            let control = controlPoint(for: geometry, curve: curve)
            for index in 0...24 {
                let t = CGFloat(index) / 24
                let point = quadBezierPoint(t: t, start: geometry.start, control: control, end: geometry.end)
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        }
        return bounds
    }

    private static func curvedDisplaySize(for piece: Piece) -> CGSize {
        let expanded = expandedDisplayBounds(for: piece)
        return CGSize(width: expanded.width, height: expanded.height)
    }

    private static func edgeLabelYPoint(piece: Piece, size: CGSize, scale: CGFloat, expandedTop: CGFloat, expandedBottom: CGFloat, isTop: Bool) -> CGFloat {
        var bestY: CGFloat? = nil
        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard assignment.cutoutEdge == nil, assignment.angleEdgeId == nil else { continue }
            let point = edgeLabelPoint(
                edge: assignment.edge,
                piece: piece,
                shape: piece.shape,
                curves: piece.curvedEdges,
                size: size,
                scale: scale,
                offsetX: 0,
                offsetY: 0,
                cutouts: piece.cutouts
            )
            if isTop {
                guard point.y <= expandedTop + 1 else { continue }
                bestY = min(bestY ?? point.y, point.y)
            } else {
                guard point.y >= expandedBottom - 1 else { continue }
                bestY = max(bestY ?? point.y, point.y)
            }
        }
        if isTop {
            return bestY ?? expandedTop
        }
        return bestY ?? expandedBottom
    }

    private static func drawDimensionLabels(in context: CGContext, piece: Piece, rect: CGRect, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, pieceHeaderY: CGFloat, topMeasurementY: CGFloat, bottomMeasurementY: CGFloat) {
        let curvedSize = curvedDisplaySize(for: piece)
        let curvedWidthText = MeasurementParser.formatInches(Double(curvedSize.width))
        let curvedHeightText = MeasurementParser.formatInches(Double(curvedSize.height))
        let lengthLabel = "\(curvedWidthText)\""
        let depthLabel = "\(curvedHeightText)\""
        let expanded = expandedDisplayBounds(for: piece)
        let left = offsetX + expanded.minX * scale
        let right = offsetX + expanded.maxX * scale

        let widthText = curvedHeightText
        let heightText = curvedWidthText
        let rawName = piece.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameLine = rawName.isEmpty ? "Piece" : rawName
        let headerLine = "\(nameLine) - \(widthText) in W x \(heightText) in L"
        let headerX = rect.minX - drawingLeftInset + 19
        let pageWidth: CGFloat = 612
        let rightMargin: CGFloat = 24
        let headerWidth = pageWidth - rightMargin - headerX
        drawText(headerLine, in: context, frame: CGRect(x: headerX, y: pieceHeaderY, width: headerWidth, height: 12), font: .boldSystemFont(ofSize: 11), alignment: .left)

        if piece.shape == .circle {
            // Match DrawingCanvasView positioning for circles
            let lengthLabelPadding: CGFloat = 28
            let widthLabelPadding: CGFloat = 42
            let top = offsetY + expanded.minY * scale
            let topLabelCenterY = top - lengthLabelPadding
            let lengthFrame = CGRect(x: offsetX + (size.width * scale / 2) - 30, y: topLabelCenterY - 6, width: 60, height: 12)
            // Position width label centered at (left - widthLabelPadding, centerY)
            let labelWidth: CGFloat = 64
            let leftLabelCenterX = left - widthLabelPadding
            let widthFrame = CGRect(x: leftLabelCenterX - labelWidth / 2, y: offsetY + (size.height * scale / 2) - 6, width: labelWidth, height: 12)
            drawText(lengthLabel, in: context, frame: lengthFrame, font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
            drawText(depthLabel, in: context, frame: widthFrame, font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
        } else if piece.shape == .rectangle {
            drawSegmentDimensionLabels(in: context, piece: piece, scale: scale, offsetX: offsetX, offsetY: offsetY)
            let sideMetrics = rectangleSideMetrics(for: piece)
            
            // Get boundary segments to check which edges have multiple segments
            // When an edge has multiple segments, drawSegmentDimensionLabels already shows individual measurements
            // so we should NOT show a cumulative measurement for that edge
            let boundarySegments = ShapePathBuilder.boundarySegments(for: piece)
            let segmentCounts = Dictionary(grouping: boundarySegments, by: { $0.edge }).mapValues { $0.count }
            let leftSegmentCount = segmentCounts[.left] ?? 1
            let topSegmentCount = segmentCounts[.top] ?? 1
            
            // Only show left edge measurement if it's a single segment (no notches on left edge)
            // Match DrawingCanvasView: label center at (left - widthLabelPadding, centerY)
            // widthLabelPadding = 42 in DrawingCanvasView
            let widthLabelPadding: CGFloat = 42
            let labelWidth: CGFloat = 64
            let leftLabelCenterX = left - widthLabelPadding
            let leftLabelFrameX = leftLabelCenterX - labelWidth / 2
            if leftSegmentCount == 1 {
                if let leftMetric = sideMetrics[.left] {
                    let widthText = "\(MeasurementParser.formatInches(Double(leftMetric.length)))\""
                    let centerY = offsetY + leftMetric.center.y * scale
                    drawText(widthText, in: context, frame: CGRect(x: leftLabelFrameX, y: centerY - 6, width: labelWidth, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
                } else {
                    drawText(depthLabel, in: context, frame: CGRect(x: leftLabelFrameX, y: offsetY + (size.height * scale / 2) - 6, width: labelWidth, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
                }
            }

            // Only show top edge measurement if it's a single segment (no notches on top edge)
            // Match DrawingCanvasView: label center at (centerX, top - lengthLabelPadding)
            // lengthLabelPadding = 28 in DrawingCanvasView
            let lengthLabelPadding: CGFloat = 28
            let top = offsetY + expanded.minY * scale
            let topLabelCenterY = top - lengthLabelPadding
            let topLabelFrameY = topLabelCenterY - 6  // half of 12pt label height
            if topSegmentCount == 1 {
                if let topMetric = sideMetrics[.top] {
                    let lengthText = "\(MeasurementParser.formatInches(Double(topMetric.length)))\""
                    let centerX = offsetX + topMetric.center.x * scale
                    drawText(lengthText, in: context, frame: CGRect(x: centerX - 30, y: topLabelFrameY, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
                } else {
                    drawText(lengthLabel, in: context, frame: CGRect(x: offsetX + (size.width * scale / 2) - 30, y: topLabelFrameY, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
                }
            }


        } else {
            // For other shapes (triangles, etc.), match DrawingCanvasView positioning
            let lengthLabelPadding: CGFloat = 28
            let widthLabelPadding: CGFloat = 42
            let top = offsetY + expanded.minY * scale
            let topLabelCenterY = top - lengthLabelPadding
            let leftLabelCenterX = left - widthLabelPadding
            drawText(lengthLabel, in: context, frame: CGRect(x: offsetX + (size.width * scale / 2) - 30, y: topLabelCenterY - 6, width: 60, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
            drawText(depthLabel, in: context, frame: CGRect(x: leftLabelCenterX - 32, y: offsetY + (size.height * scale / 2) - 6, width: 64, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .center)
        }
        drawText("Qty \(piece.quantity)", in: context, frame: CGRect(x: right + 72, y: offsetY + (size.height * scale / 2) - 6, width: 44, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), alignment: .left)
    }

    private static func drawSegmentDimensionLabels(in context: CGContext, piece: Piece, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        guard !segments.isEmpty else { return }
        let grouped = Dictionary(grouping: segments, by: { $0.edge })
        
        // Check which edges have actual notches touching them
        let size = ShapePathBuilder.displaySize(for: piece)
        let edgesWithNotches = edgesThatHaveNotches(piece: piece, size: size)
        
        for (edge, edgeSegments) in grouped where edgeSegments.count > 1 {
            // Only show segment labels if this edge has an actual notch
            // Skip edges where segments are only created by curve spans
            guard edgesWithNotches.contains(edge) else { continue }
            
            for segment in edgeSegments {
                let lengthValue: CGFloat
                if edge == .top || edge == .bottom {
                    lengthValue = abs(segment.end.x - segment.start.x)
                } else {
                    lengthValue = abs(segment.end.y - segment.start.y)
                }
                let text = "\(MeasurementParser.formatInches(Double(lengthValue)))\""
                let point = segmentLabelPoint(segment: segment, piece: piece, scale: scale, offsetX: offsetX, offsetY: offsetY)
                drawText(text, in: context, frame: CGRect(x: point.x - 30, y: point.y - 6, width: 60, height: 12), font: .systemFont(ofSize: 8, weight: .semibold), alignment: .center)
            }
        }
    }
    
    /// Returns the set of edges that have notches touching them
    private static func edgesThatHaveNotches(piece: Piece, size: CGSize) -> Set<EdgePosition> {
        var edges = Set<EdgePosition>()
        let eps: CGFloat = 0.01
        
        for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            guard isEffectiveNotch(cutout: cutout, size: size) else { continue }
            let displayCutout = displayCutout(for: cutout)
            let halfWidth = displayCutout.width / 2
            let halfHeight = displayCutout.height / 2
            let minX = displayCutout.centerX - halfWidth
            let maxX = displayCutout.centerX + halfWidth
            let minY = displayCutout.centerY - halfHeight
            let maxY = displayCutout.centerY + halfHeight
            
            // Check which edges this notch touches
            if minY <= eps { edges.insert(.top) }
            if maxY >= size.height - eps { edges.insert(.bottom) }
            if minX <= eps { edges.insert(.left) }
            if maxX >= size.width - eps { edges.insert(.right) }
        }
        
        return edges
    }

    private struct SideMetric {
        let length: CGFloat
        let center: CGPoint
    }

    private static func rectangleSideMetrics(for piece: Piece) -> [EdgePosition: SideMetric] {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard points.count >= 2 else { return [:] }
        let eps: CGFloat = 0.001
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        var lengths: [EdgePosition: CGFloat] = [.top: 0, .bottom: 0, .left: 0, .right: 0]
        var weightedCenters: [EdgePosition: CGPoint] = [.top: .zero, .bottom: .zero, .left: .zero, .right: .zero]

        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            if abs(dy) < eps {
                if abs(a.y - minY) < eps {
                    let len = abs(dx)
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: minY)
                    lengths[.top, default: 0] += len
                    weightedCenters[.top, default: .zero].x += mid.x * len
                    weightedCenters[.top, default: .zero].y += mid.y * len
                } else if abs(a.y - maxY) < eps {
                    let len = abs(dx)
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: maxY)
                    lengths[.bottom, default: 0] += len
                    weightedCenters[.bottom, default: .zero].x += mid.x * len
                    weightedCenters[.bottom, default: .zero].y += mid.y * len
                }
            } else if abs(dx) < eps {
                if abs(a.x - minX) < eps {
                    let len = abs(dy)
                    let mid = CGPoint(x: minX, y: (a.y + b.y) / 2)
                    lengths[.left, default: 0] += len
                    weightedCenters[.left, default: .zero].x += mid.x * len
                    weightedCenters[.left, default: .zero].y += mid.y * len
                } else if abs(a.x - maxX) < eps {
                    let len = abs(dy)
                    let mid = CGPoint(x: maxX, y: (a.y + b.y) / 2)
                    lengths[.right, default: 0] += len
                    weightedCenters[.right, default: .zero].x += mid.x * len
                    weightedCenters[.right, default: .zero].y += mid.y * len
                }
            }
        }

        var metrics: [EdgePosition: SideMetric] = [:]
        for edge in [EdgePosition.top, .bottom, .left, .right] {
            let total = lengths[edge, default: 0]
            guard total > 0 else { continue }
            let weighted = weightedCenters[edge, default: .zero]
            let center = CGPoint(x: weighted.x / total, y: weighted.y / total)
            metrics[edge] = SideMetric(length: total, center: center)
        }
        return metrics
    }

    private static func drawCutoutNotes(in context: CGContext, piece: Piece, size: CGSize, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, noteY: CGFloat) {
        let cutoutLines = cutoutNoteLines(for: piece)
        let pieceLines = pieceNoteLines(for: piece)
        let lines = cutoutLines + pieceLines
        guard !lines.isEmpty else { return }
        let pageWidth: CGFloat = 612
        let leftMargin: CGFloat = 24
        let centerPadding: CGFloat = 20
        let availableWidth = pageWidth - (leftMargin * 2)
        let columnWidth = (availableWidth - centerPadding) / 2
        let leftX = leftMargin
        let rightX = leftMargin + columnWidth + centerPadding
        let cutoutWrapped = wrapLinesByWidth(cutoutLines, maxWidth: columnWidth, font: .systemFont(ofSize: 9, weight: .semibold))
        let pieceWrapped = wrapLinesByWidth(pieceLines, maxWidth: columnWidth, font: .systemFont(ofSize: 9, weight: .semibold))
        for (index, line) in cutoutWrapped.enumerated() {
            let y = noteY + CGFloat(index) * 12
            drawLabelledLine(line, in: context, x: leftX, y: y, width: columnWidth)
        }
        for (index, line) in pieceWrapped.enumerated() {
            let y = noteY + CGFloat(index) * 12
            drawLabelledLine(line, in: context, x: rightX, y: y, width: columnWidth, alignment: .right)
        }
    }

    private static func cutoutNoteLines(for piece: Piece) -> [String] {
        let visibleCutouts = piece.cutouts.filter { $0.centerX >= 0 && $0.centerY >= 0 }
        let holes = visibleCutouts.filter { !isEffectiveNotch(cutout: $0, size: ShapePathBuilder.pieceSize(for: piece)) }
        var lines: [String] = []
        // Curves are stored with display edge positions
        let displayLeftCurveOffset = curveEdgeOffset(piece: piece, edge: .left)
        let displayTopCurveOffset = curveEdgeOffset(piece: piece, edge: .top)

        for cutout in holes {
            let label: String
            if cutout.kind == .circle {
                label = abs(cutout.width - cutout.height) < 0.001 ? "Circle Cutout" : "Oval Cutout"
            } else {
                label = abs(cutout.width - cutout.height) < 0.001 ? "Square Cutout" : "Rectangular Cutout"
            }
            let displayCutout = displayCutout(for: cutout)
            let widthText = MeasurementParser.formatInches(cutout.width)
            let heightText = MeasurementParser.formatInches(cutout.height)
            let sizeText = "\(widthText)\" Wide x \(heightText)\" Long"
            let fromLeftValue = max(displayCutout.centerX + displayLeftCurveOffset, 0)
            let fromTopValue = max(displayCutout.centerY + displayTopCurveOffset, 0)
            let fromLeft = MeasurementParser.formatInches(fromLeftValue)
            let fromTop = MeasurementParser.formatInches(fromTopValue)
            // Add "Apex" suffix when curve affects the measurement
            let leftSuffix = displayLeftCurveOffset != 0 ? " Apex" : ""
            let topSuffix = displayTopCurveOffset != 0 ? " Apex" : ""
            lines.append("\(label): \(sizeText) - \(fromLeft)\" From Left\(leftSuffix) to Center, \(fromTop)\" From Top\(topSuffix) to Center")
        }

        return lines
    }

    private static func curveEdgeOffset(piece: Piece, edge: EdgePosition) -> Double {
        guard piece.shape == .rectangle else { return 0 }
        guard let curve = piece.curve(for: edge), curve.radius > 0 else { return 0 }
        return curve.isConcave ? -curve.radius : curve.radius
    }

    private static func pieceNoteLines(for piece: Piece) -> [String] {
        let notes = piece.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return [] }
        return ["Notes: \(notes)"]
    }

    private static func letter(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + (index % 26))!
        return String(Character(scalar))
    }

    private static func wrapLines(_ lines: [String], maxLength: Int) -> [String] {
        var wrapped: [String] = []
        for line in lines {
            if line.count <= maxLength {
                wrapped.append(line)
                continue
            }
            let words = line.split(separator: " ")
            var current = ""
            for word in words {
                let next = current.isEmpty ? String(word) : "\(current) \(word)"
                if next.count > maxLength {
                    wrapped.append(current)
                    current = String(word)
                } else {
                    current = next
                }
            }
            if !current.isEmpty {
                wrapped.append(current)
            }
        }
        return wrapped
    }

    private static func drawLabelledLine(_ line: String, in context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, alignment: NSTextAlignment = .left) {
        let fontSize: CGFloat = 9
        if let colonRange = line.range(of: ":"), alignment != .right {
            let label = String(line[..<colonRange.upperBound])
            let rest = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let labelWidth = textWidth(label, font: .systemFont(ofSize: fontSize, weight: .bold))
            let restWidth = rest.isEmpty ? 0 : textWidth(rest, font: .systemFont(ofSize: fontSize, weight: .semibold))
            let gap: CGFloat = rest.isEmpty ? 0 : 4
            let totalWidth = labelWidth + restWidth + gap

            if alignment == .right {
                if totalWidth > width {
                    drawText(line, in: context, frame: CGRect(x: x, y: y, width: width, height: 14), font: .systemFont(ofSize: fontSize, weight: .semibold), alignment: .right)
                    return
                }
                let startX = x + width - totalWidth
                if !rest.isEmpty {
                    drawText(rest, in: context, frame: CGRect(x: startX, y: y, width: restWidth, height: 14), font: .systemFont(ofSize: fontSize, weight: .semibold))
                }
                drawText(label, in: context, frame: CGRect(x: startX + restWidth + gap, y: y, width: labelWidth, height: 14), font: .systemFont(ofSize: fontSize, weight: .bold))
                return
            }

            drawText(label, in: context, frame: CGRect(x: x, y: y, width: width, height: 14), font: .systemFont(ofSize: fontSize, weight: .bold))
            let restX = min(x + labelWidth + 4, x + width)
            let restDrawWidth = max(0, (x + width) - restX)
            if !rest.isEmpty && restDrawWidth > 0 {
                drawText(rest, in: context, frame: CGRect(x: restX, y: y, width: restDrawWidth, height: 14), font: .systemFont(ofSize: fontSize, weight: .semibold))
            }
            return
        }

        drawText(line, in: context, frame: CGRect(x: x, y: y, width: width, height: 14), font: .systemFont(ofSize: fontSize, weight: .semibold), alignment: alignment)
    }

    private static func textWidth(_ text: String, font: PlatformFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private static func wrapLinesByWidth(_ lines: [String], maxWidth: CGFloat, font: PlatformFont) -> [String] {
        var wrapped: [String] = []
        for line in lines {
            if textWidth(line, font: font) <= maxWidth {
                wrapped.append(line)
                continue
            }
            let words = line.split(separator: " ")
            var current = ""
            for word in words {
                let next = current.isEmpty ? String(word) : "\(current) \(word)"
                if textWidth(next, font: font) > maxWidth, !current.isEmpty {
                    wrapped.append(current)
                    current = String(word)
                } else {
                    current = next
                }
            }
            if !current.isEmpty {
                wrapped.append(current)
            }
        }
        return wrapped
    }

    private static func edgeLegend(for project: Project) -> [String] {
        let pairs = project.pieces.flatMap { piece in
            piece.edgeAssignments.compactMap { assignment -> (String, String)? in
                let code = assignment.treatmentAbbreviation
                let name = assignment.treatmentName
                return code.isEmpty || name.isEmpty ? nil : (code, name)
            }
        }
        let unique = Dictionary(grouping: pairs, by: { $0.0 })
            .values
            .compactMap { $0.first }
            .sorted { $0.0 < $1.0 }
        return unique.map { "\($0.0) - \($0.1)" }
    }

    private static func drawNotes(in context: CGContext, notes: String, edgeLegend: [String], origin: CGPoint, maxWidth: CGFloat) {
        let inset: CGFloat = 15
        let headerRect = CGRect(x: origin.x, y: origin.y + 10, width: maxWidth, height: 18)
        context.saveGState()
        context.setFillColor(PlatformColor(white: 0.92, alpha: 1).cgColor)
        context.fill(headerRect)
        context.restoreGState()
        drawText("Project Notes:", in: context, frame: headerRect.insetBy(dx: 8, dy: 2), font: .systemFont(ofSize: 11, weight: .bold))
        var y = headerRect.maxY + 8
        if !notes.isEmpty {
            drawText(notes, in: context, frame: CGRect(x: origin.x + inset, y: y, width: maxWidth - inset, height: 60), font: .systemFont(ofSize: 11))
            y += 70
        }
        if !edgeLegend.isEmpty {
            for line in edgeLegend {
                drawText(line, in: context, frame: CGRect(x: origin.x + inset, y: y, width: maxWidth - inset, height: 12), font: .systemFont(ofSize: 10))
                y += 16
            }
        }
    }

    private static func drawText(_ text: String, in context: CGContext, frame: CGRect, font: PlatformFont, alignment: NSTextAlignment = .left) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        
        #if canImport(UIKit)
        // Push the CGContext as the current UIKit graphics context
        UIGraphicsPushContext(context)
        attributed.draw(in: frame)
        UIGraphicsPopContext()
        #else
        // On macOS, use NSGraphicsContext
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        attributed.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        #endif
    }

    private static func displayCutout(for cutout: Cutout) -> Cutout {
        Cutout(kind: cutout.kind, width: cutout.height, height: cutout.width, centerX: cutout.centerY, centerY: cutout.centerX, isNotch: cutout.isNotch)
    }

    private static func cutoutCornerRange(for cutout: Cutout, piece: Piece) -> Range<Int>? {
        ShapePathBuilder.cutoutCornerRanges(for: piece)
            .first { $0.cutout.id == cutout.id }?
            .range
    }

    private static func localAngleCuts(for cutout: Cutout, piece: Piece) -> [AngleCut] {
        guard let range = cutoutCornerRange(for: cutout, piece: piece) else { return [] }
        return piece.angleCuts.compactMap { cut in
            guard range.contains(cut.anchorCornerIndex) else { return nil }
            let local = AngleCut(
                anchorCornerIndex: cut.anchorCornerIndex - range.lowerBound,
                anchorOffset: cut.anchorOffset,
                secondaryCornerIndex: cut.secondaryCornerIndex,
                secondaryOffset: cut.secondaryOffset,
                usesSecondPoint: cut.usesSecondPoint,
                angleDegrees: cut.angleDegrees
            )
            local.id = cut.id
            return local
        }
    }

    private static func localCornerRadii(for cutout: Cutout, piece: Piece) -> [CornerRadius] {
        guard let range = cutoutCornerRange(for: cutout, piece: piece) else { return [] }
        return piece.cornerRadii.compactMap { radius in
            guard range.contains(radius.cornerIndex) else { return nil }
            let local = CornerRadius(cornerIndex: radius.cornerIndex - range.lowerBound, radius: radius.radius, isInside: radius.isInside)
            local.id = radius.id
            return local
        }
    }


    private static func computeTotalPages(project: Project, header: BusinessHeader, pageSize: CGSize) -> Int {
        let leftMargin: CGFloat = 24
        let columnWidth = pageSize.width - (leftMargin * 2)
        let blockSpacing: CGFloat = 6
        let materialHeaderHeight: CGFloat = 18
        var yOffset: CGFloat = 24 + headerHeight(for: header, projectName: project.name, projectAddress: project.address, projectDate: project.updatedAt, pageIndex: 1) + 10
        var pageIndex = 1
        let baseScale = pdfScaleOverridePointsPerInch ?? basePointsPerInch

        let materialGrouped = Dictionary(grouping: project.pieces) { piece in
            let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Material" : trimmed
        }
        let sortedMaterials = materialGrouped.keys.sorted()

        for materialKey in sortedMaterials {
            let thicknessGrouped = Dictionary(grouping: materialGrouped[materialKey] ?? []) { piece in
                piece.thickness.rawValue
            }
            let sortedThickness = thicknessGrouped.keys.sorted()

            for thicknessKey in sortedThickness {
                let pieces = thicknessGrouped[thicknessKey] ?? []
                guard let firstPiece = pieces.first else { continue }
                let firstLayout = blockLayout(for: firstPiece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 130)
                let headerAndBlock = materialHeaderHeight + firstLayout.blockHeight
                if yOffset + headerAndBlock > pageSize.height - 60 {
                    pageIndex += 1
                    yOffset = 24 + headerHeight(for: header, projectName: project.name, projectAddress: project.address, projectDate: project.updatedAt, pageIndex: pageIndex) + 10
                }
                yOffset += materialHeaderHeight

                for piece in pieces {
                    let layout = blockLayout(for: piece, columnWidth: columnWidth, scale: baseScale, maxBlockHeight: pageSize.height - 60 - 130)
                    if yOffset + layout.blockHeight > pageSize.height - 60 {
                        pageIndex += 1
                        yOffset = 24 + headerHeight(for: header, projectName: project.name, projectAddress: project.address, projectDate: project.updatedAt, pageIndex: pageIndex) + 10
                    }

                    yOffset += layout.blockHeight + blockSpacing
                }

                yOffset += 12
            }
        }

        return pageIndex
    }
}
