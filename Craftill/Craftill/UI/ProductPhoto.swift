import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers
#if os(macOS) || os(iOS)
import AVFoundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#endif

// ════════════════════════════════════════════════════════════
// 商品写真の追加（撮影・写真ライブラリ・ファイル選択）
// 編集画面からそのまま登録できる。保存先は ProductImageStore。
// ════════════════════════════════════════════════════════════

struct ProductPhotoSection: View {
    @EnvironmentObject var vm: AppViewModel

    /// 保存するファイル名（商品ID.jpg）。
    let fileName: String
    @Binding var pendingData: Data?
    @Binding var removeImage: Bool

    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFile = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var storedPreview: CGImage? = nil
    @State private var pendingPreview: CGImage? = nil

    private var previewImage: CGImage? {
        if pendingData != nil { return pendingPreview }
        if removeImage { return nil }
        return storedPreview
    }

    private var cameraAvailable: Bool {
        #if os(macOS) || os(iOS)
        return AVCaptureDevice.default(for: .video) != nil
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("商品写真").font(.caption).foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 12) {
                preview
                VStack(alignment: .leading, spacing: 8) {
                    Button("写真を追加") { showSourceDialog = true }
                        .buttonStyle(.app)
                        .frame(maxWidth: 220)
                        .confirmationDialog("写真の追加方法", isPresented: $showSourceDialog,
                                            titleVisibility: .visible) {
                            if cameraAvailable {
                                Button("カメラで撮影") { showCamera = true }
                            }
                            Button("写真ライブラリから選択") { showLibrary = true }
                            Button("ファイルから選択") { showFile = true }
                            Button("キャンセル", role: .cancel) {}
                        }
                    if previewImage != nil {
                        Button("写真を削除") {
                            pendingData = nil
                            pendingPreview = nil
                            removeImage = true
                        }
                        .buttonStyle(.app)
                        .frame(maxWidth: 220)
                    }
                    FieldHelp("登録した写真はこの端末に保存され、レジの商品タイルに表示されます。公開サイト用の画像は、別途 originals/ に置いて画像ビルドします。")
                }
            }
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    vm.message = "画像ファイルを読み込めませんでした"
                    return
                }
                apply(data)
            case .failure(let error):
                vm.message = "画像を選択できませんでした: \(error.localizedDescription)"
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .task(id: "\(fileName)|\(removeImage)") {
            if removeImage {
                storedPreview = nil
                return
            }
            guard let data = ProductImageStore.loadData(fileName: fileName) else {
                storedPreview = nil
                return
            }
            storedPreview = ProductImageStore.cgImage(from: data)
        }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            guard let data else {
                vm.message = "写真を読み込めませんでした"
                return
            }
            apply(data)
        }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraCaptureSheet { data in apply(data) }
        }
        #endif
    }

    @ViewBuilder
    private var preview: some View {
        if let image = previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
        } else {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                Text("写真なし").font(.caption)
            }
            .foregroundColor(.secondary)
            .frame(width: 120, height: 120)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(.gray))
        }
    }

    private func apply(_ data: Data) {
        guard let jpeg = ProductImageStore.normalizedJPEG(from: data) else {
            vm.message = "画像を読み込めませんでした（対応していない形式の可能性があります）"
            return
        }
        pendingData = jpeg
        pendingPreview = ProductImageStore.cgImage(from: jpeg)
        removeImage = false
    }
}

#if os(macOS) || os(iOS)
// MARK: - カメラ撮影

final class PhotoCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var status = "カメラを準備しています…"
    @Published var isReady = false
    @Published var capturedData: Data? = nil

    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "dev.craftill.photo-session")
    private var configured = false
    private var shouldRun = false

    func start() {
        shouldRun = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
                    }
                }
            }
        default:
            status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
        }
    }

    private func startSession() {
        guard shouldRun else { return }
        if !configured { configure() }
        guard configured else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.startRunning()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.shouldRun else { return }
                self.isReady = true
                self.status = ""
            }
        }
    }

    func stop() {
        shouldRun = false
        isReady = false
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        #if os(iOS)
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        #else
        let device = AVCaptureDevice.default(for: .video)
        #endif
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            status = "利用できるカメラが見つかりません"
            return
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            status = "撮影を開始できません"
            return
        }
        session.addOutput(output)
        configured = true
    }

    func capture() {
        guard isReady else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.status = "撮影に失敗しました: \(error.localizedDescription)"
            }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.status = "撮影した画像を取得できませんでした"
            }
            return
        }
        DispatchQueue.main.async {
            self.capturedData = data
        }
    }
}

struct CameraCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = PhotoCaptureController()
    let onCapture: (Data) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("商品写真を撮影").font(.headline)
            ZStack {
                CameraPreviewView(session: controller.session)
                    .background(Color.black)
                if !controller.status.isEmpty {
                    Text(controller.status)
                        .font(.callout)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.black.opacity(0.6))
                }
            }
            .frame(minWidth: 320, idealWidth: 640, maxWidth: 800,
                   minHeight: 300, idealHeight: 480, maxHeight: 600)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Button("キャンセル") { dismiss() }
                    .buttonStyle(.app)
                Button("撮影") { controller.capture() }
                    .buttonStyle(.appPrimary)
                    .disabled(!controller.isReady)
            }
        }
        .padding(20)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.capturedData) { _, data in
            guard let data else { return }
            onCapture(data)
            dismiss()
        }
    }
}

#if canImport(AppKit)
private final class CameraPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}
}
#elseif canImport(UIKit)
private final class CameraPreviewUIView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        layer.addSublayer(previewLayer)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
#endif
#endif
