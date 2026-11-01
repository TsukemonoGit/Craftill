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
//
// カメラ選択:
// - 自動: システム推奨カメラ（AVCaptureDevice.systemPreferredCamera。
//   iOS/iPadOS 17+、macOS 13+）。iPhone の Continuity Camera が使える場合は
//   システムが選ぶ。
// - 手動: ピッカーで列挙された任意のカメラを選べる。
//   ピッカーは検出台数に関わらず常に表示する（何が検出されたかを確認できるように）。
// - iPad のカメラを Mac の Web カメラとして使う標準機能は存在しない
//   （Continuity Camera の Web カメラ機能は iPhone のみ）。
// ════════════════════════════════════════════════════════════

/// ピッカー表示用のカメラ情報。
struct CameraOption: Identifiable, Hashable {
    let id: String      // AVCaptureDevice.uniqueID
    let name: String    // AVCaptureDevice.localizedName
    let kind: String    // AVCaptureDevice.deviceType（診断表示用）
}

final class QRScannerController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// 「自動」を表す選択ID。
    static let autoID = "auto"

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
    /// 利用可能なカメラ一覧（メインスレッドで更新）。
    @Published var cameras: [CameraOption] = []
    /// 選択中のカメラID。autoID の場合は自動選択。
    @Published var selectedCameraID = QRScannerController.autoID
    var onCode: ((String) -> Void)?

    private var configured = false
    private var lastAccepted = ""
    private var lastAcceptedAt = Date.distantPast
    /// 画面がカメラを必要としているか。遅延再開がシート終了後に走るのを防ぐ。
    private var shouldRun = false
    /// 現在セッションに接続している入力。メインスレッドからのみ触る。
    private var currentInput: AVCaptureDeviceInput?
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
        // カメラの接続／切断に追従する。
        c.addObserver(self, selector: #selector(devicesChanged(_:)),
                      name: AVCaptureDevice.wasConnectedNotification, object: nil)
        c.addObserver(self, selector: #selector(devicesChanged(_:)),
                      name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
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

    /// カメラの接続・切断時。一覧を更新し、設定済みなら入力を再評価する。
    @objc private func devicesChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshCameras()
            if self.configured {
                self.applySelection()
            }
        }
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

    // MARK: - カメラ選択

    /// ピッカーからの選択。autoID を渡すと自動選択に戻る。
    func selectCamera(id: String) {
        selectedCameraID = id
        guard configured else { return }
        applySelection()
    }

    /// 利用可能なビデオデバイスを列挙する。
    /// - .builtInWideAngleCamera: 内蔵カメラ。
    /// - .external: 外部・仮想カメラ（iOS 17 / macOS 14 以降）。列挙される内容は環境依存。
    /// - .continuityCamera: iPhone の Continuity Camera（macOS 専用）。
    private func discoverDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(iOS 17.0, macOS 14.0, *) {
            types.append(.external)
        }
        #if os(macOS)
        if #available(macOS 14.0, *) {
            types.append(.continuityCamera)
        }
        #endif
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }

    /// 自動選択時のデバイス。
    /// 1. システム推奨カメラ（iOS/iPadOS 17+、macOS 13+）。Apple が自動選択に推奨する方式。
    /// 2. システム既定。
    private func preferredDevice() -> AVCaptureDevice? {
        if #available(iOS 17.0, macOS 13.0, *) {
            if let system = AVCaptureDevice.systemPreferredCamera {
                return system
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// 現在の選択からデバイスを決める。選択中のデバイスが消えていたら自動に戻す。
    private func resolveDevice() -> AVCaptureDevice? {
        if selectedCameraID != QRScannerController.autoID {
            if let chosen = discoverDevices().first(where: { $0.uniqueID == selectedCameraID }) {
                return chosen
            }
            selectedCameraID = QRScannerController.autoID
        }
        return preferredDevice()
    }

    /// 種別名を表示用に短くする（例: "AVCaptureDeviceTypeExternal" → "External"）。
    private func kindLabel(_ type: AVCaptureDevice.DeviceType) -> String {
        type.rawValue.replacingOccurrences(of: "AVCaptureDeviceType", with: "")
    }

    /// 一覧を更新する。メインスレッドで呼ぶ。
    private func refreshCameras() {
        var seen = Set<String>()
        cameras = discoverDevices().compactMap { device in
            guard seen.insert(device.uniqueID).inserted else { return nil }
            return CameraOption(id: device.uniqueID,
                                name: device.localizedName,
                                kind: kindLabel(device.deviceType))
        }
    }

    /// 選択を評価して入力を差し替える。メインスレッドで呼ぶ。
    private func applySelection() {
        refreshCameras()
        guard let device = resolveDevice() else {
            status = "利用できるカメラが見つかりません"
            return
        }
        let changed = currentInput?.device.uniqueID != device.uniqueID
        if setInput(device), changed {
            status = "使用中のカメラ: \(device.localizedName)"
        }
    }

    /// セッションの入力を差し替える。失敗時は元の入力に戻す。
    @discardableResult
    private func setInput(_ device: AVCaptureDevice) -> Bool {
        if let current = currentInput, current.device.uniqueID == device.uniqueID {
            return true
        }
        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            status = "カメラを開けません（\(device.localizedName)）"
            return false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previous = currentInput
        if let previous {
            session.removeInput(previous)
            currentInput = nil
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentInput = newInput
            return true
        }
        // 追加できなかった場合は元の入力に戻す。
        if let previous, session.canAddInput(previous) {
            session.addInput(previous)
            currentInput = previous
        }
        status = "このカメラは使用できません（\(device.localizedName)）"
        return false
    }

    private func configure() {
        refreshCameras()
        guard let device = resolveDevice() else {
            status = "利用できるカメラが見つかりません"
            return
        }
        // 失敗時の理由は setInput がステータスに設定済み。上書きしない。
        guard setInput(device) else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

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

            // 検出台数に関わらず常に表示する。
            HStack(spacing: 8) {
                Text("カメラ（検出: \(scanner.cameras.count)台）")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Picker("カメラ", selection: Binding(
                    get: { scanner.selectedCameraID },
                    set: { scanner.selectCamera(id: $0) }
                )) {
                    Text("自動").tag(QRScannerController.autoID)
                    ForEach(scanner.cameras) { camera in
                        Text("\(camera.name)（\(camera.kind)）").tag(camera.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }

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