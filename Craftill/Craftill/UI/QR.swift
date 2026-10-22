import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
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
                    #if canImport(AppKit)
                    Button("PNGで保存") { savePNG() }.buttonStyle(.app)
                    Button("印刷") { printLabels() }.buttonStyle(.appPrimary)
                    #elseif canImport(UIKit)
                    Button("共有") { sharePNG() }.buttonStyle(.app)
                    Button("印刷") { printLabels() }.buttonStyle(.appPrimary)
                    #endif
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

    private var renderContent: some View {
        QRGrid(products: targets, columns: 4)
            .padding(24)
            .frame(width: 760)
            .background(Color.white)
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
        let content = renderContent.frame(width: 720)
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
        let content = renderContent.frame(width: 720)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            vm.message = "QR画像を作れませんでした"
            return
        }
        let info = UIPrintInfo.printInfo()
        info.outputType = .photo
        info.jobName = "QRラベル"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
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
