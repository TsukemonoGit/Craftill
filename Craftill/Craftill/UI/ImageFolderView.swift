import SwiftUI
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// 商品写真の保存先
// カメラ撮影・ファイル選択のどちらも、ここで選んだフォルダへ
// 「商品ID.jpg」で保存する。originals/ を選べば画像ビルドで使える。
// ════════════════════════════════════════════════════════════

struct ImageFolderView: View {
    @EnvironmentObject var vm: AppViewModel

    @State private var currentURL: URL? = ProductImageFolder.url
    @State private var showPicker = false
    @State private var busy = false

    var body: some View {
        AdminShell("画像の保存先") {
            VStack(alignment: .leading, spacing: 14) {
                Panel(title: "保存先フォルダ") {
                    if let url = currentURL {
                        InfoBox(text: url.path, size: 14, tint: .green)
                        Text("カメラで撮影した写真も、ファイルから選んだ写真も、このフォルダに「商品ID.jpg」で保存します。")
                            .font(.callout)
                        if !FileManager.default.fileExists(atPath: url.path) {
                            Text("このフォルダにアクセスできません。フォルダを選び直してください。")
                                .font(.callout)
                                .foregroundColor(.red)
                        }
                    } else {
                        InfoBox(text: ProductImageFolder.isConfigured
                                ? "設定済みのフォルダにアクセスできません"
                                : "アプリ内（既定）",
                                size: 14, tint: .yellow)
                        Text(ProductImageFolder.isConfigured
                             ? "フォルダを選び直してください。いまはアプリ内のコピーだけを使います。"
                             : "いまはアプリ内に保存しています。レジには表示されますが、公開サイト用の画像ビルドには使えません。")
                            .font(.callout)
                    }

                    HStack(spacing: 10) {
                        Button("フォルダを選ぶ") { showPicker = true }
                            .buttonStyle(.appPrimary)
                        if currentURL != nil || ProductImageFolder.isConfigured {
                            Button("既定に戻す") { resetFolder() }
                                .buttonStyle(.app)
                        }
                    }

                    if currentURL != nil {
                        Button("既存の写真をこのフォルダへ書き出す") { exportExisting() }
                            .buttonStyle(.app)
                            .disabled(busy)
                        FieldHelp("フォルダを変更しても、既存の写真は自動では移動しません。このボタンで、いまアプリにある写真をまとめて書き出せます。")
                    }
                }

                Panel(title: "ウェブサイト用の画像ビルド") {
                    FieldHelp("先に「CSV取り込み・書き出し」で商品マスタ CSV を書き出してください。リポジトリの originals/ を選ぶと、そのまま画像ビルドで使えます。")
                    Text("python3 scripts/build_images.py --csv <商品マスタCSV>")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    FieldHelp("別のフォルダを選んだ場合は、--originals にそのフォルダのパスを指定してください。")
                }

                FieldHelp("保存する写真は JPEG（長辺1600px）にそろえます。元のファイル形式のまま残したい場合は、originals/ に手で置いてください。")
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do {
                    try ProductImageFolder.set(url: url)
                    currentURL = ProductImageFolder.url
                    vm.message = "画像の保存先を変更しました"
                } catch {
                    vm.message = "保存先を設定できませんでした: \(error.localizedDescription)"
                }
            case .failure(let error):
                vm.message = "フォルダを選択できませんでした: \(error.localizedDescription)"
            }
        }
        .onAppear {
            ProductImageFolder.activate()
            currentURL = ProductImageFolder.url
        }
    }

    private func resetFolder() {
        ProductImageFolder.clear()
        currentURL = nil
        vm.message = "画像の保存先をアプリ内に戻しました"
    }

    private func exportExisting() {
        guard currentURL != nil else { return }
        busy = true
        defer { busy = false }

        var exported = 0
        var failed: [String] = []
        for product in vm.inventory {
            let name = product.bundledImageName
            guard let data = ProductImageStore.loadLocalData(fileName: name)
                ?? ProductImageStore.loadData(fileName: name) else { continue }
            do {
                try ProductImageStore.save(data, fileName: name)
                exported += 1
            } catch {
                failed.append(product.id)
            }
        }

        if failed.isEmpty {
            vm.message = "\(exported)件の写真を書き出しました"
        } else {
            vm.message = "\(exported)件を書き出しました（失敗: \(failed.joined(separator: ", "))）"
        }
    }
}
