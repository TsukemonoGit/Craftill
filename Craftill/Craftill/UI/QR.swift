import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
import PDFKit
#elseif canImport(UIKit)
import UIKit
#endif

// ════════════════════════════════════════════════════════════
// 商品IDのQR（P1-2）
// QRの中身は商品IDの文字列そのもの（例: KH-008）
// macOS / iPadOS の両方でビルドできるよう、画像型はCGImageで扱う。
// ════════════════════════════════════════════════════════════

enum QRCode {
    static func cgImage(for text: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let base = filter.outputImage else { return nil }
        let output = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(output, from: output.extent)
    }
}

struct QRImageView: View {
    let cgImage: CGImage

    var body: some View {
        #if canImport(AppKit)
        Image(nsImage: NSImage(cgImage: cgImage,
                               size: NSSize(width: cgImage.width, height: cgImage.height)))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
        #elseif canImport(UIKit)
        Image(uiImage: UIImage(cgImage: cgImage))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
        #endif
    }
}

struct QRLabelView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @AppStorage("qrShowName") private var showName = true

    // 印刷用ページ設定（A4縦, pt）
    private let pageSize = CGSize(width: 595.28, height: 841.89)
    private let pageMargin: CGFloat = 24
    private let rowSpacing: CGFloat = 12
    private let printColumns = 4
    private let maxRasterExportLabels = 240

    private var filteredProducts: [Product] {
        let filter = vm.qrListFilterTypeId
        let keyword = vm.qrListSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return vm.inventory.filter { p in
            let typeOK = filter.isEmpty || p.typeId == filter
            guard typeOK else { return false }
            guard !keyword.isEmpty else { return true }
            return p.id.lowercased().contains(keyword) || p.name.lowercased().contains(keyword)
        }
    }

    private var queueTargets: [Product] {
        vm.qrExpandedProducts
    }

    private var queueCountText: String {
        "\(vm.qrQueue.count)種類 / \(vm.qrTotalLabels)枚"
    }

    private var canRasterExport: Bool {
        !queueTargets.isEmpty && queueTargets.count <= maxRasterExportLabels
    }

    var body: some View {
        AdminShell("QRラベル作成（商品一覧）") {
            VStack(alignment: .leading, spacing: 12) {
                if let focus = vm.qrFocusProductId {
                    focusBanner(focus)
                }
                headerControls
                Text("QRの中身＝商品ID。ID文字も併記しています。印刷して商品に貼ったあと、商品の編集画面から写真を撮影・選択できます。公開サイト用は「画像の保存先」で originals/ を選ぶと、同じ写真がビルド用に保存されます。")
                    .font(.caption).foregroundColor(.secondary)

                if compact {
                    VStack(spacing: 12) {
                        listPanel
                        queuePanel
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        listPanel
                        queuePanel
                    }
                }

                previewPanel
            }
        }
        .onAppear { setupOnAppear() }
    }

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    filterControls
                    nameToggle
                    actionButtons
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    filterControls
                    nameToggle
                        .frame(maxWidth: 160, alignment: .leading)
                    Spacer(minLength: 8)
                    actionButtons
                }
            }
            Text("印刷キュー: \(queueCountText)")
                .font(.caption)
                .foregroundColor(.secondary)
            if !canRasterExport, !queueTargets.isEmpty {
                Text("PNG保存/共有は\(maxRasterExportLabels)枚まで。大量出力は「印刷」を使ってください。")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var filterControls: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("商品ID・商品名で検索", text: $vm.qrListSearchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("種類", selection: $vm.qrListFilterTypeId) {
                        Text("すべての種類").tag("")
                        ForEach(vm.types) { t in
                            Text(vm.tabLabel(t)).tag(t.typeId)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("商品ID・商品名で検索", text: $vm.qrListSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 380)
                    Picker("種類", selection: $vm.qrListFilterTypeId) {
                        Text("すべての種類").tag("")
                        ForEach(vm.types) { t in
                            Text(vm.tabLabel(t)).tag(t.typeId)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var listPanel: some View {
        Panel(title: "商品一覧（追加元）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Stepper(value: $vm.qrPendingCopies, in: 1...999) {
                        Text("追加枚数: \(vm.qrPendingCopies)")
                    }
                    Spacer(minLength: 8)
                    Button("絞り込み結果を各1枚追加") {
                        vm.addManyToQRQueue(productIds: filteredProducts.map(\.id), copies: 1)
                    }
                    .buttonStyle(.app)
                    Button("絞り込み結果を各\(vm.qrPendingCopies)枚追加") {
                        vm.addManyToQRQueue(productIds: filteredProducts.map(\.id), copies: vm.qrPendingCopies)
                    }
                    .buttonStyle(.app)
                }
                if filteredProducts.isEmpty {
                    Text("条件に合う商品がありません。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(filteredProducts) { product in
                                productRow(product)
                            }
                        }
                    }
                    .frame(minHeight: compact ? 220 : 300)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func productRow(_ product: Product) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.id)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text(product.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(vm.typeName(product.typeId))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("+1") { vm.addToQRQueue(productId: product.id, copies: 1) }
                .buttonStyle(.app)
            Button("+\(vm.qrPendingCopies)") {
                vm.addToQRQueue(productId: product.id, copies: vm.qrPendingCopies)
            }
            .buttonStyle(.appPrimary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
    }

    private var queuePanel: some View {
        Panel(title: "印刷キュー") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("キュー: \(queueCountText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Button("全削除") { vm.clearQRQueue() }
                        .buttonStyle(.app)
                        .disabled(vm.qrQueue.isEmpty)
                }
                if vm.qrQueue.isEmpty {
                    Text("まだキューがありません。商品一覧から追加してください。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.qrQueue) { item in
                                if let p = vm.inventory.first(where: { $0.id == item.productId }) {
                                    queueRow(product: p, item: item)
                                }
                            }
                        }
                    }
                    .frame(minHeight: compact ? 180 : 260)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func queueRow(product: Product, item: LabelPrintItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.id)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(product.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Stepper(value: Binding(
                get: { item.copies },
                set: { vm.setQRQueueCopies(productId: item.productId, copies: $0) }
            ), in: 1...999) {
                Text("\(item.copies)枚")
                    .font(.caption)
            }
            Button("削除") { vm.removeFromQRQueue(productId: item.productId) }
                .buttonStyle(.app)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プレビュー")
                .font(.headline)
            if queueTargets.isEmpty {
                Text("印刷キューが空です。")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    QRGrid(products: queueTargets, columns: compact ? 2 : 4, showName: showName)
                        .padding(8)
                }
                .frame(minHeight: compact ? 220 : 300)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
            }
        }
    }

    private var nameToggle: some View {
        Toggle("商品名を表示", isOn: $showName)
            .toggleStyle(.switch)
    }

    /// 登録直後の1商品だけを表示しているときの案内。
    private func focusBanner(_ id: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("登録した商品 \(id) をキューへ追加しました。").font(.callout.bold())
                Text("必要枚数に調整して印刷してください。写真は商品の編集画面から撮影・選択できます（公開サイト用は「画像の保存先」で originals/ を選択）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("フォーカス解除") { vm.qrFocusProductId = nil }
                .buttonStyle(.app)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4)))
    }

    @ViewBuilder
    private var actionButtons: some View {
        #if canImport(AppKit)
        Button("PNGで保存") { savePNG() }
            .buttonStyle(.app)
            .disabled(!canRasterExport)
        Button("印刷") { printLabels() }
            .buttonStyle(.appPrimary)
            .disabled(queueTargets.isEmpty)
        #elseif canImport(UIKit)
        Button("共有") { sharePNG() }
            .buttonStyle(.app)
            .disabled(!canRasterExport)
        Button("印刷") { printLabels() }
            .buttonStyle(.appPrimary)
            .disabled(queueTargets.isEmpty)
        #endif
    }

    private func setupOnAppear() {
        vm.normalizeQRQueue()
        vm.qrPendingCopies = min(max(1, vm.qrPendingCopies), 999)
        if let focus = vm.qrFocusProductId {
            if !vm.qrQueue.contains(where: { $0.productId == focus }) {
                vm.addToQRQueue(productId: focus, copies: 1)
            }
        }
    }

    private var renderContent: some View {
        QRGrid(products: queueTargets, columns: 4, showName: showName)
            .padding(24)
            .frame(width: 760)
            .background(Color.white)
    }

    // MARK: - ページ分割印刷（共通）

    /// 1ページ分のビュー。幅は用紙幅－左右余白。
    private func pageView(_ chunk: [Product]) -> some View {
        QRGrid(products: chunk, columns: printColumns, showName: showName)
            .frame(width: pageSize.width - pageMargin * 2, alignment: .topLeading)
            .background(Color.white)
    }

        /// 行単位でページ分割したPDFを生成する。ラベルはページをまたがない。
    /// 行ごとに高さを実測し、累積高さで1ページに入る行を決める
    /// （長いIDなどでラベル高さが行ごとに異なっても見切れない）。
    @MainActor
    private func makePDFData() -> Data? {
        let items = queueTargets
        guard !items.isEmpty else { return nil }

        let usableHeight = pageSize.height - pageMargin * 2

        // 行に分割
        let rows: [[Product]] = stride(from: 0, to: items.count, by: printColumns).map {
            Array(items[$0..<min($0 + printColumns, items.count)])
        }

        // 各行の高さを実測
        var heights: [CGFloat] = []
        for row in rows {
            let probe = ImageRenderer(content: pageView(row))
            var h: CGFloat = 0
            probe.render { size, _ in h = size.height }
            guard h > 0 else { return nil }
            heights.append(h)
        }

        // 累積高さでページに詰める
        var pages: [[Product]] = []
        var current: [Product] = []
        var currentHeight: CGFloat = 0
        for (row, h) in zip(rows, heights) {
            if current.isEmpty {
                current = row
                currentHeight = h
            } else if currentHeight + rowSpacing + h <= usableHeight {
                current += row
                currentHeight += rowSpacing + h
            } else {
                pages.append(current)
                current = row
                currentHeight = h
            }
        }
        if !current.isEmpty { pages.append(current) }

        // PDF生成
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        for chunk in pages {
            let renderer = ImageRenderer(content: pageView(chunk))
            renderer.render { size, draw in
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                // PDF座標は左下原点。上端揃えで配置する。
                ctx.translateBy(x: pageMargin, y: pageSize.height - pageMargin - size.height)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return data as Data
    }

    #if canImport(AppKit)
    @MainActor
    private func savePNG() {
        guard canRasterExport else {
            vm.message = "PNG保存は\(maxRasterExportLabels)枚までです（現在 \(queueTargets.count)枚）。大量出力は「印刷」を使ってください。"
            return
        }
        let renderer = ImageRenderer(content: renderContent)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            vm.message = "QR画像を作れませんでした"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qr-labels.png"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                vm.message = "保存しました: \(url.lastPathComponent)"
            } catch {
                vm.message = "保存に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func printLabels() {
        guard let pdfData = makePDFData(),
              let document = PDFDocument(data: pdfData) else {
            vm.message = "QR画像を作れませんでした"
            return
        }

        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.orientation = .portrait
        info.topMargin = 18
        info.bottomMargin = 18
        info.leftMargin = 18
        info.rightMargin = 18
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        guard let op = document.printOperation(for: info,
                                               scalingMode: .pageScaleToFit,
                                               autoRotate: false) else {
            vm.message = "印刷を開始できませんでした"
            return
        }
        op.showsPrintPanel = true
        op.run()
    }
    #elseif canImport(UIKit)
    @MainActor
    private func sharePNG() {
        guard canRasterExport else {
            vm.message = "共有は\(maxRasterExportLabels)枚までです（現在 \(queueTargets.count)枚）。大量出力は「印刷」を使ってください。"
            return
        }
        let renderer = ImageRenderer(content: renderContent)
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else {
            vm.message = "QR画像を作れませんでした"
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qr-labels.png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            vm.message = "保存に失敗しました: \(error.localizedDescription)"
            return
        }
        presentShareSheet(urls: [url])
        vm.message = "共有シートから「ファイルに保存」を選べます"
    }

    @MainActor
    private func printLabels() {
        guard let pdfData = makePDFData() else {
            vm.message = "QR画像を作れませんでした"
            return
        }
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = "QRラベル"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdfData
        if let root = topViewController() {
            controller.present(from: root.view.bounds, in: root.view,
                               animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    @MainActor
    private func presentShareSheet(urls: [URL]) {
        guard let root = topViewController() else { return }
        let av = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        root.present(av, animated: true)
    }

    @MainActor
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
    #endif
}

struct QRGrid: View {
    let products: [Product]
    let columns: Int
    var showName: Bool = true

    private var rows: [[Product]] {
        stride(from: 0, to: products.count, by: max(1, columns)).map {
            Array(products[$0..<min($0 + max(1, columns), products.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, p in
                        QRLabel(product: p, showName: showName)
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct QRLabel: View {
    let product: Product
    let showName: Bool

    /// 表示する商品名。非表示設定、または空（空白のみ含む）の場合は nil。
    private var displayName: String? {
        guard showName else { return nil }
        let trimmed = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }


    var body: some View {
        VStack(spacing: 4) {
            if let cgImage = QRCode.cgImage(for: product.id) {
                QRImageView(cgImage: cgImage)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
            }
            Text(product.id)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            if let name = displayName {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.7)))
    }
}