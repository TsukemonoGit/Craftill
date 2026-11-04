import SwiftUI
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// 商品写真の保存先（必須）
// カメラ撮影・ファイル選択のどちらも、ここで選んだフォルダへだけ
// 「商品ID.jpg」で保存する。originals/ を選べば画像ビルドで使える。
// 未設定のまま写真を追加しようとした時は ImageFolderSetupSheet で選ばせる。
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
                        Text("カメラで撮影した写真も、ファイルから選んだ写真も、このフォルダに「商品ID.jpg」で保存します。フォルダに直接画像を置く場合も、ファイル名を「商品ID.jpg」にしてください。")
                            .font(.callout)
                        if !FileManager.default.fileExists(atPath: url.path) {
                            Text("このフォルダにアクセスできません。フォルダを選び直してください。")
                                .font(.callout)
                                .foregroundColor(.red)
                        }
                    } else {
                        InfoBox(text: ProductImageFolder.isConfigured
                                ? "設定済みのフォルダにアクセスできません"
                                : "未設定",
                                size: 14, tint: .yellow)
                        Text(ProductImageFolder.isConfigured
                             ? "フォルダが移動・削除された可能性があります。選び直してください。"
                             : "写真の保存にはフォルダが必要です。フォルダを選んでください。")
                            .font(.callout)
                    }

                    HStack(spacing: 10) {
                        Button("フォルダを選ぶ") { showPicker = true }
                            .buttonStyle(.appPrimary)
                    }

                    if currentURL != nil {
                        Button("既存の写真をこのフォルダへ書き出す") { exportExisting() }
                            .buttonStyle(.app)
                            .disabled(busy)
                        FieldHelp("フォルダを変更しても、既存の写真は自動では移動しません。このボタンで書き出せるのは旧版がアプリ内に残した写真だけです。変更前のフォルダに書き出した写真は、Finder／エクスプローラで手動で移動してください。")
                    }
                }

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

    private func exportExisting() {
        guard currentURL != nil else { return }
        busy = true
        defer { busy = false }

        var exported = 0
        var failed: [String] = []
        for product in vm.inventory {
            let name = product.bundledImageName
            // 現在の保存先を優先して読み、無いものだけ旧版のアプリ内コピーから拾う。
            // （旧コピーを優先すると、差し替え済みの新しい写真を古い写真で上書きする）
            guard let data = ProductImageStore.loadData(fileName: name) else { continue }
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

// ════════════════════════════════════════════════════════════
// 保存先フォルダの選択（写真追加の前に必要）
// 写真は選んだフォルダにだけ保存する。保存先が未設定のまま
// 「写真を追加」が押された時に表示し、選べばそのまま追加へ進む。
// ════════════════════════════════════════════════════════════

struct ImageFolderSetupSheet: View {
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var showPicker = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("商品写真の保存先を決めてください").font(.headline)
            Text("カメラで撮影した写真も、ファイルから選んだ写真も、このフォルダに「商品ID.jpg」で保存します。アプリ内には保存しません。フォルダに直接画像を置く場合も、ファイル名を「商品ID.jpg」にしてください。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundColor(.red)
            }
            HStack(spacing: 10) {
                Button("あとで") { onCancel() }
                    .buttonStyle(.app)
                Button("フォルダを選ぶ") { showPicker = true }
                    .buttonStyle(.appPrimary)
            }
        }
        .padding(24)
        .frame(minWidth: 320, idealWidth: 520, maxWidth: 600)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do {
                    try ProductImageFolder.set(url: url)
                    onDone()
                } catch {
                    errorText = "保存先を設定できませんでした: \(error.localizedDescription)"
                }
            case .failure(let error):
                // キャンセルはエラー表示しない（選び直せばよい）。
                let nsError = error as NSError
                if !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) {
                    errorText = "フォルダを選択できませんでした: \(error.localizedDescription)"
                }
            }
        }
    }
}
