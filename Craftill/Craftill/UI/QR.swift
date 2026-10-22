import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// ════════════════════════════════════════════════════════════
// 商品IDのQR（P1-2）
// QRの中身は商品IDの文字列そのもの（例: KH-008）
// ════════════════════════════════════════════════════════════

enum QRCode {
    static func image(for text: String, scale: CGFloat = 10) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let base = filter.outputImage else { return nil }
        let output = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

struct QRLabelView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var scopeAll = true
    @State private var typeId = ""

    private var targets: [Product] {
        guard !scopeAll, !typeId.isEmpty else { return vm.inventory }
        return vm.inventory.filter { $0.typeId == typeId }
    }

    var body: some View {
        AdminShell("QRラベル") {
            VStack(alignment: .leading, spacing: 12) {
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
                    Button("PNGで保存") { savePNG() }.buttonStyle(.app)
                    Button("印刷") { printLabels() }.buttonStyle(.appPrimary)
                }
                Text("QRの中身＝商品ID。ID文字も併記しています。印刷して各商品に貼ってください。")
                    .font(.caption).foregroundColor(.secondary)

                ScrollView {
                    QRGrid(products: targets, columns: 4)
                        .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
            }
        }
        .onAppear { if typeId.isEmpty { typeId = vm.types.first?.typeId ?? "" } }
    }

    @MainActor
    private func savePNG() {
        let content = QRGrid(products: targets, columns: 4)
            .padding(24)
            .frame(width: 760)
            .background(Color.white)

        let renderer = ImageRenderer(content: content)
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
        let content = QRGrid(products: targets, columns: 4)
            .padding(24)
            .frame(width: 720)
            .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            vm.message = "QR画像を作れませんでした"
            return
        }

        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 720,
                                             height: max(1, image.size.height * 720 / max(1, image.size.width))))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown

        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.orientation = .portrait
        info.topMargin = 18
        info.bottomMargin = 18
        info.leftMargin = 18
        info.rightMargin = 18
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = true
        op.run()
    }
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
            if let image = QRCode.image(for: product.id) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
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
