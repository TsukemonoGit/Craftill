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
    /// 親画面で見出しを出す場合は false にする。
    var showsTitle = true

    @State private var showSourceDialog = false
    @State private var showDeleteConfirm = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFile = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var storedPreview: CGImage? = nil
    @State private var pendingPreview: CGImage? = nil
    @State private var showCropper = false
    @State private var cropSourceImage: CGImage? = nil

    private let cropAspectRatio: CGFloat = 3.0 / 2.0

    private var previewImage: CGImage? {
        if pendingData != nil { return pendingPreview }
        return storedPreview
    }

    /// アプリから削除できる写真か（同梱画像は読み取り専用）。
    private var isRuntimeImage: Bool {
        if pendingData != nil { return true }
        if removeImage { return false }
        return ProductImageStore.hasRuntimeImage(fileName: fileName)
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
            if showsTitle {
                Text("商品写真").font(.caption).foregroundColor(.secondary)
            }
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
                    if isRuntimeImage {
                        Button("写真を削除") { showDeleteConfirm = true }
                            .buttonStyle(.app)
                            .frame(maxWidth: 220)
                            .confirmationDialog("写真を削除しますか？", isPresented: $showDeleteConfirm,
                                                titleVisibility: .visible) {
                                Button("削除", role: .destructive) {
                                    pendingData = nil
                                    pendingPreview = nil
                                    removeImage = true
                                }
                                Button("キャンセル", role: .cancel) {}
                            } message: {
                                Text("保存先フォルダ（originals/ など）のファイルも削除します。")
                            }
                    }
                    if previewImage != nil && !isRuntimeImage {
                        FieldHelp("この写真はアプリに同梱されています。差し替えるには originals/ の原本を変更して画像ビルドしてください。")
                    }
                    FieldHelp("登録した写真は切り取り範囲を確認して保存します。保存後はレジの商品タイルに表示されます。「画像の保存先」で originals/ を選ぶと、公開サイト用の画像ビルドにもそのまま使えます。")
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
                presentCropper(with: data)
            case .failure(let error):
                vm.message = "画像を選択できませんでした: \(error.localizedDescription)"
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .task(id: "\(fileName)|\(removeImage)") {
            // 削除中でも、同梱画像があればそれを表示する（同梱画像は削除できない）。
            let url = removeImage
                ? bundledOnlyImageURL(named: fileName)
                : bundledImageURL(named: fileName)
            guard let url, let data = try? Data(contentsOf: url) else {
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
            presentCropper(with: data)
        }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraCaptureSheet { data in presentCropper(with: data) }
        }
        #endif
        .sheet(isPresented: $showCropper, onDismiss: {
            cropSourceImage = nil
        }) {
            if let image = cropSourceImage {
                ProductPhotoCropSheet(image: image, aspectRatio: cropAspectRatio) { cropped in
                    commitCropped(cropped)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 80)
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
        } else {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                Text("写真なし").font(.caption)
            }
            .foregroundColor(.secondary)
            .frame(width: 120, height: 80)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(.gray))
        }
    }

    private func presentCropper(with data: Data) {
        guard let cgImage = ProductImageStore.decodedCGImage(from: data) else {
            vm.message = "画像を読み込めませんでした（対応していない形式の可能性があります）"
            return
        }
        cropSourceImage = cgImage
        showCropper = true
    }

    private func commitCropped(_ cropped: CGImage) {
        guard let jpeg = ProductImageStore.jpegData(from: cropped, maxPixel: 1600, quality: 0.85) else {
            vm.message = "切り取り画像を保存できませんでした"
            return
        }
        pendingData = jpeg
        pendingPreview = ProductImageStore.cgImage(from: jpeg)
        removeImage = false
        showCropper = false
    }
}

private struct ProductPhotoCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: CGImage
    let aspectRatio: CGFloat
    let onConfirm: (CGImage) -> Void

    @State private var canvasSize: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private var minZoom: CGFloat {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return 1 }
        let fit = fittedImageSize(in: canvasSize)
        let crop = cropRect(in: canvasSize)
        let neededX = crop.width / max(1, fit.width)
        let neededY = crop.height / max(1, fit.height)
        return max(1, neededX, neededY)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("写真の切り取り")
                .font(.headline)
            Text("見せたい位置に合わせて、拡大・移動して保存します。")
                .font(.caption)
                .foregroundColor(.secondary)
            GeometryReader { geo in
                let size = geo.size
                let fit = fittedImageSize(in: size)
                let crop = cropRect(in: size)
                let effectiveZoom = max(zoom, minZoom)
                let imageSize = CGSize(width: fit.width * effectiveZoom, height: fit.height * effectiveZoom)
                let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)

                ZStack {
                    Color.black.opacity(0.88)

                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .position(center)

                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: size))
                        path.addRoundedRect(
                            in: crop,
                            cornerSize: CGSize(width: 8, height: 8)
                        )
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: crop.width, height: crop.height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let candidate = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                            offset = clampedOffset(candidate, canvas: size, zoom: effectiveZoom)
                        }
                        .onEnded { _ in
                            dragStart = offset
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = max(minZoom, lastZoom * value)
                            offset = clampedOffset(offset, canvas: size, zoom: zoom)
                        }
                        .onEnded { _ in
                            zoom = max(minZoom, zoom)
                            lastZoom = zoom
                            offset = clampedOffset(offset, canvas: size, zoom: zoom)
                            dragStart = offset
                        }
                )
                .onAppear {
                    canvasSize = size
                    let required = max(minZoom, 1)
                    zoom = required
                    lastZoom = required
                    offset = clampedOffset(offset, canvas: size, zoom: required)
                    dragStart = offset
                }
                .onChange(of: size) { _, newSize in
                    canvasSize = newSize
                    let required = max(minZoom, 1)
                    if zoom < required {
                        zoom = required
                        lastZoom = required
                    }
                    offset = clampedOffset(offset, canvas: newSize, zoom: zoom)
                    dragStart = offset
                }
            }
            .frame(minWidth: 320, idealWidth: 720, maxWidth: 860,
                   minHeight: 260, idealHeight: 420, maxHeight: 560)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button("リセット") {
                    let required = max(minZoom, 1)
                    zoom = required
                    lastZoom = required
                    offset = .zero
                    dragStart = .zero
                }
                .buttonStyle(.app)

                Spacer()

                Button("キャンセル") { dismiss() }
                    .buttonStyle(.app)
                Button("この範囲で保存") {
                    guard let cropped = makeCroppedImage() else { return }
                    onConfirm(cropped)
                    dismiss()
                }
                .buttonStyle(.appPrimary)
            }
        }
        .padding(18)
        .frame(minWidth: 360, idealWidth: 780, maxWidth: 900,
               minHeight: 360, idealHeight: 640, maxHeight: 760)
    }

    private func fittedImageSize(in canvas: CGSize) -> CGSize {
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        guard iw > 0, ih > 0, canvas.width > 1, canvas.height > 1 else {
            return .zero
        }
        let scale = min(canvas.width / iw, canvas.height / ih)
        return CGSize(width: iw * scale, height: ih * scale)
    }

    private func cropRect(in canvas: CGSize) -> CGRect {
        let inset: CGFloat = 20
        let maxW = max(40, canvas.width - inset * 2)
        let maxH = max(40, canvas.height - inset * 2)
        var width = maxW
        var height = width / aspectRatio
        if height > maxH {
            height = maxH
            width = height * aspectRatio
        }
        let x = (canvas.width - width) / 2
        let y = (canvas.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func clampedOffset(_ value: CGSize, canvas: CGSize, zoom: CGFloat) -> CGSize {
        let fit = fittedImageSize(in: canvas)
        let crop = cropRect(in: canvas)
        let shownW = fit.width * zoom
        let shownH = fit.height * zoom
        let limitX = max(0, (shownW - crop.width) / 2)
        let limitY = max(0, (shownH - crop.height) / 2)
        return CGSize(
            width: min(max(value.width, -limitX), limitX),
            height: min(max(value.height, -limitY), limitY)
        )
    }

    private func makeCroppedImage() -> CGImage? {
        let fit = fittedImageSize(in: canvasSize)
        guard fit.width > 1, fit.height > 1 else { return nil }
        let crop = cropRect(in: canvasSize)
        let effectiveZoom = max(zoom, minZoom)
        let shownW = fit.width * effectiveZoom
        let shownH = fit.height * effectiveZoom
        let imageOriginX = (canvasSize.width - shownW) / 2 + offset.width
        let imageOriginY = (canvasSize.height - shownH) / 2 + offset.height

        let sx = CGFloat(image.width) / shownW
        let sy = CGFloat(image.height) / shownH
        let cropXTop = (crop.minX - imageOriginX) * sx
        let cropYTop = (crop.minY - imageOriginY) * sy
        let cropW = crop.width * sx
        let cropH = crop.height * sy

        let x = min(max(0, cropXTop), CGFloat(image.width - 1))
        let y = min(max(0, cropYTop), CGFloat(image.height - 1))
        let w = min(cropW, CGFloat(image.width) - x)
        let h = min(cropH, CGFloat(image.height) - y)
        let rect = CGRect(x: floor(x), y: floor(y), width: floor(w), height: floor(h)).integral
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return image.cropping(to: rect)
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
                PhotoCameraPreviewView(session: controller.session)
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

private struct PhotoCameraPreviewView: NSViewRepresentable {
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

private struct PhotoCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
#endif
#endif
