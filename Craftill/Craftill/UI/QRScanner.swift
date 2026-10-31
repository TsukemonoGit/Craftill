import SwiftUI
import Combine
import AVFoundation
import Vision
import CoreImage
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// ════════════════════════════════════════════════════════════
// 内蔵カメラでQRを読む（P1-4）。QRの中身は商品ID。
// macOS / iPadOS の両方でビルドできるようプレビューを分岐。
// 読み取りは Vision。カメラによって鏡像になる場合に備え、
// 検出用フレームを左右反転できる（mirrorImage）。
// ════════════════════════════════════════════════════════════

final class QRScannerController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var lastCode = ""
    @Published var status = "カメラを起動しています…"
    /// 検出用フレームを左右反転するか。カメラによって鏡像になる場合のみ ON にする。
    @Published var mirrorImage = false {
        didSet {
            flagLock.lock()
            mirrorFlag = mirrorImage
            flagLock.unlock()
        }
    }
    var onCode: ((String) -> Void)?

    private var configured = false
    private var lastAccepted = ""
    private var lastAcceptedAt = Date.distantPast
    /// 画面がカメラを必要としているか。遅延再開がシート終了後に走るのを防ぐ。
    private var shouldRun = false
    private let sessionQueue = DispatchQueue(label: "dev.craftill.camera-session")
    private let videoQueue = DispatchQueue(label: "dev.craftill.camera-video")

    // videoQueue から読むためロックで保護する。
    private let flagLock = NSLock()
    private var mirrorFlag = false

    override init() {
        super.init()
        let c = NotificationCenter.default
        c.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                      name: AVCaptureSession.runtimeErrorNotification, object: session)
        c.addObserver(self, selector: #selector(sessionInterrupted(_:)),
                      name: AVCaptureSession.wasInterruptedNotification, object: session)
        c.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)),
                      name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// アプリ切替・スリープ・カメラ割り込みから復帰したら、セッションを再開する（A-3）。
    @objc private func sessionRuntimeError(_ note: Notification) {
        restartSoon()
    }

    @objc private func sessionInterrupted(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.status = "カメラが一時停止しました（復帰を待っています）"
        }
    }

    @objc private func sessionInterruptionEnded(_ note: Notification) {
        restartSoon()
    }

    private func restartSoon() {
        // 通知はメインスレッド以外から来ることもある。`shouldRun` と
        // `@Published` の更新をメインに揃える。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldRun else { return }
            self.stopSessionOnly()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.shouldRun else { return }
                self.start()
            }
        }
    }

    func start() {
        shouldRun = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.shouldRun else { return }
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
        guard shouldRun, !session.isRunning else { return }
        if !configured { configure() }
        guard configured else { return }
        sessionQueue.async { [session] in
            session.startRunning()
        }
        status = "QRをカメラに向けてください"
    }

    func stop() {
        shouldRun = false
        stopSessionOnly()
    }

    private func stopSessionOnly() {
        guard session.isRunning else { return }
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            status = "利用できるカメラが見つかりません"
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else {
            status = "QR読み取りを開始できません"
            return
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: videoQueue)
        configured = true
    }

    /// videoQueue 上で呼ばれる。フレームごとに Vision で QR を検出する。
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        flagLock.lock()
        let mirror = mirrorFlag
        flagLock.unlock()
        if mirror {
            image = image.oriented(.upMirrored)
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let value = request.results?
            .compactMap({ $0.payloadStringValue })
            .first(where: { !$0.isEmpty }) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.accept(value)
        }
    }

    private func accept(_ value: String) {
        // 同じQRを連続で読んだときに二重追加しない（1.2秒あければ再追加できる。A-2）
        let now = Date()
        if value == lastAccepted && now.timeIntervalSince(lastAcceptedAt) < 1.2 { return }
        lastAccepted = value
        lastAcceptedAt = now
        lastCode = value
        onCode?(value)
    }
}

#if canImport(AppKit)
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let preview = nsView.layer as? AVCaptureVideoPreviewLayer {
            preview.frame = nsView.bounds
        }
    }
}
#elseif canImport(UIKit)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let preview = uiView.layer.sublayers?
            .compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first {
            preview.frame = uiView.bounds
        }
    }
}
#endif

struct QRScannerSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = QRScannerController()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("カメラでQRを読み取り").font(.headline)
                Spacer()
                Button("閉じる") {
                    scanner.stop()
                    dismiss()
                }
                .buttonStyle(.app)
                .frame(maxWidth: 120)
            }

            CameraPreview(session: scanner.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )

            HStack(spacing: 12) {
                Text(scanner.status).font(.callout).foregroundColor(.secondary)
                Spacer(minLength: 8)
                if !scanner.lastCode.isEmpty {
                    Text("読取: \(scanner.lastCode)").font(.callout).bold()
                }
                Button(scanner.mirrorImage ? "反転: ON" : "反転: OFF") {
                    scanner.mirrorImage.toggle()
                }
                .buttonStyle(.app)
                .frame(maxWidth: 120)
            }
        }
        .padding(16)
        .frame(minWidth: 300, idealWidth: 640, maxWidth: .infinity,
               minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        .onAppear {
            scanner.onCode = { code in
                if vm.addByID(code) {
                    scanner.onCode = nil
                    scanner.stop()
                    dismiss()
                } else {
                    scanner.status = vm.message
                }
            }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                scanner.start()
            case .inactive, .background:
                scanner.stop()
            @unknown default:
                break
            }
        }
    }
}