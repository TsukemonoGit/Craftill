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
    @State private var scopeAll = true
    @State private var typeId = ""

    // 印刷用ページ設定（A4縦, pt）
    private let pageSize = CGSize(width: 595.28, height: 841.89)
    private let pageMargin: CGFloat = 24
    private let rowSpacing: CGFloat = 12
    private let printColumns = 4

    private var targets: [Product] {
        // 商品登録直後は、登録した商品のラベルだけを表示する。
        if let focus = vm.qrFocusProductId {
            return vm.inventory.filter { $0.id == focus }
        }
        guard !scopeAll, !typeId.isEmpty else { return vm.inventory }
        return vm.inventory.filter { $0.typeId == typeId }
    }

    var body: some View {
        AdminShell("QRラベル") {
            VStack(alignment: .leading, spacing: 12) {
                if let focus = vm.qrFocusProductId {
                    focusBanner(focus)
                    HStack(spacing: 10) { actionButtons }
                } else if compact {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("全商品", isOn: $scopeAll)
                            .toggleStyle(.switch)
                        Picker("種類", selection: $typeId) {
                            ForEach(vm.types) { t in Text(t.name).tag(t.typeId) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(scopeAll)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            actionButtons
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Toggle("全商品", isOn: $scopeAll)
                            .toggleStyle(.switch)
                            .frame(maxWidth: 160, alignment: .leading)
                        Picker("種類", selection: $typeId) {
                            ForEach(vm.types) { t in Text(t.name).tag(t.typeId) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        .disabled(scopeAll)
                        Spacer(minLength: 8)
                        actionButtons
                    }
                }
                Text("QRの中身＝商品ID。ID文字も併記しています。印刷して商品に貼ったあと、商品の編集画面から写真を撮影・選択できます。公開サイト用は「画像の保存先」で originals/ を選ぶと、同じ写真がビルド用に保存されます。")
                    .font(.caption).foregroundColor(.secondary)

                ScrollView {
                    QRGrid(products: targets, columns: compact ? 2 : 4)
                        .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
            }
        }
        .onAppear { if typeId.isEmpty { typeId = vm.types.first?.typeId ?? "" } }
    }

    @ViewBuilder
    private var actionButtons: some View {
        #if canImport(AppKit)
        Button("PNGで保存") { savePNG() }.buttonStyle(.app)
        Button("印刷") { printLabels() }.buttonStyle(.appPrimary)
        #elseif canImport(UIKit)
        Button("共有") { sharePNG() }.buttonStyle(.app)
        Button("印刷") { printLabels() }.buttonStyle(.appPrimary)
        #endif
    }

    /// 登録直後の1商品だけを表示しているときの案内。
    private func focusBanner(_ id: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("登録した商品 \(id) のラベルを表示しています。").font(.callout.bold())
                Text("印刷して商品に貼ってください。写真は商品の編集画面から撮影・選択できます（公開サイト用は「画像の保存先」で originals/ を選択）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("全商品を表示") { vm.qrFocusProductId = nil }
                .buttonStyle(.app)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4)))
    }

    private var renderContent: some View {
        QRGrid(products: targets, columns: 4)
            .padding(24)
            .frame(width: 760)
            .background(Color.white)
    }

    // MARK: - ページ分割印刷（共通）

    /// 1ページ分のビュー。幅は用紙幅－左右余白。
    private func pageView(_ chunk: [Product]) -> some View {
        QRGrid(products: chunk, columns: printColumns)
            .frame(width: pageSize.width - pageMargin * 2, alignment: .topLeading)
            .background(Color.white)
    }

    /// 行単位でページ分割したPDFを生成する。ラベルはページをまたがない。
    @MainActor
    private func makePDFData() -> Data? {
        let items = targets
        guard !items.isEmpty else { return nil }

        let usableHeight = pageSize.height - pageMargin * 2

        // 1行分の高さを実測する。
        var rowHeight: CGFloat = 0
        let probe = ImageRenderer(content: pageView(Array(items.prefix(printColumns))))
        probe.render { size, _ in rowHeight = size.height }
        guard rowHeight > 0 else { return nil }

        let rowsPerPage = max(1, Int((usableHeight + rowSpacing) / (rowHeight + rowSpacing)))
        let perPage = rowsPerPage * printColumns

        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        for start in stride(from: 0, to: items.count, by: perPage) {
            let chunk = Array(items[start..<min(start + perPage, items.count)])
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

    private var rows: [[Product]] {
        stride(from: 0, to: products.count, by: max(1, columns)).map {
            Array(products[$0..<min($0 + max(1, columns), products.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { p in
                        QRLabel(product: p)
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
            Text(product.name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.7)))
    }
}