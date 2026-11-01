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
// - 自動: システム推奨カメラ、またはシステム既定カメラ。
// - 手動: ピッカーで列挙された任意のカメラを選択。
// - macOS では iPhone の Continuity Camera も列挙する。
// ════════════════════════════════════════════════════════════

/// ピッカー表示用のカメラ情報。
struct CameraOption: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
}

final class QRScannerController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let autoID = "auto"

    let session = AVCaptureSession()

    @Published var lastCode = ""
    @Published var status = "カメラを起動しています…"
    @Published var mirrorImage = false {
        didSet {
            flagLock.lock()
            mirrorFlag = mirrorImage
            flagLock.unlock()
        }
    }
    @Published var cameras: [CameraOption] = []
    @Published var selectedCameraID = QRScannerController.autoID

    var onCode: ((String) -> Void)?

    /// shouldRun と @Published の値はメインスレッドで管理する。
    private var shouldRun = false

    /// 以下のセッション状態はすべて sessionQueue 上だけでアクセスする。
    private var configured = false
    private var currentInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?

    private let sessionQueue = DispatchQueue(label: "dev.craftill.camera-session")
    private let videoQueue = DispatchQueue(label: "dev.craftill.camera-video")

    private let flagLock = NSLock()
    private var mirrorFlag = false

    private var lastAccepted = ""
    private var lastAcceptedAt = Date.distantPast

    override init() {
        super.init()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(devicesChanged(_:)),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(devicesChanged(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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

    /// 接続・切断時は一覧を更新し、必要なら設定と起動をやり直す。
    @objc private func devicesChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshCameras()

            guard self.shouldRun else { return }
            self.configureOrUpdateAndStart()
        }
    }

    private func restartSoon() {
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
            configureOrUpdateAndStart()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.shouldRun else { return }

                    if granted {
                        self.configureOrUpdateAndStart()
                    } else {
                        self.status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
                    }
                }
            }

        default:
            status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
        }
    }

    func stop() {
        shouldRun = false
        stopSessionOnly()
    }

    /// stopRunning() も必ず sessionQueue 上で実行する。
    private func stopSessionOnly() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - カメラ選択

    func selectCamera(id: String) {
        selectedCameraID = id
        guard shouldRun else { return }
        configureOrUpdateAndStart()
    }

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

    private func preferredDevice() -> AVCaptureDevice? {
        if #available(iOS 17.0, macOS 13.0, *) {
            if let device = AVCaptureDevice.systemPreferredCamera {
                return device
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func resolveDevice() -> AVCaptureDevice? {
        if selectedCameraID != Self.autoID {
            if let selected = discoverDevices().first(where: {
                $0.uniqueID == selectedCameraID
            }) {
                return selected
            }

            selectedCameraID = Self.autoID
        }

        return preferredDevice()
    }

    private func kindLabel(_ type: AVCaptureDevice.DeviceType) -> String {
        type.rawValue.replacingOccurrences(
            of: "AVCaptureDeviceType",
            with: ""
        )
    }

    /// 一覧更新はメインスレッドで行う。
    private func refreshCameras() {
        dispatchPrecondition(condition: .onQueue(.main))

        var seen = Set<String>()
        cameras = discoverDevices().compactMap { device in
            guard seen.insert(device.uniqueID).inserted else { return nil }

            return CameraOption(
                id: device.uniqueID,
                name: device.localizedName,
                kind: kindLabel(device.deviceType)
            )
        }
    }

    /// デバイス解決はメインスレッド、セッション操作は sessionQueue で行う。
    /// 初回設定・カメラ再接続・カメラ切り替えを同じ経路に集約する。
    private func configureOrUpdateAndStart() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard shouldRun else { return }

        refreshCameras()

        guard let device = resolveDevice() else {
            status = "利用できるカメラが見つかりません"
            return
        }

        let deviceName = device.localizedName

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            var configurationSucceeded = false
            defer {
                self.session.commitConfiguration()
            }

            if self.configured {
                configurationSucceeded = self.replaceInputOnSessionQueue(with: device)
            } else {
                guard self.replaceInputOnSessionQueue(with: device) else {
                    return
                }

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true

                guard self.session.canAddOutput(output) else {
                    self.removeCurrentInputOnSessionQueue()
                    DispatchQueue.main.async {
                        self.status = "QR読み取りを開始できません"
                    }
                    return
                }

                self.session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                self.videoOutput = output
                self.configured = true
                configurationSucceeded = true
            }

            guard configurationSucceeded else { return }

            // 設定完了後に開始する。開始・停止・入力変更は同じ直列キュー上。
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                guard self.shouldRun else { return }
                self.status = "使用中のカメラ: \(deviceName)"
            }
        }
    }

    /// session.beginConfiguration()〜commitConfiguration() の内側で呼び出す。
    /// 失敗時は以前の入力を復元する。
    private func replaceInputOnSessionQueue(with device: AVCaptureDevice) -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))

        if let currentInput,
           currentInput.device.uniqueID == device.uniqueID {
            return true
        }

        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async {
                self.status = "カメラを開けません（\(device.localizedName)）"
            }
            return false
        }

        let previousInput = currentInput

        if let previousInput {
            session.removeInput(previousInput)
            currentInput = nil
        }

        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                currentInput = previousInput
            }

            DispatchQueue.main.async {
                self.status = "このカメラは使用できません（\(device.localizedName)）"
            }
            return false
        }

        session.addInput(newInput)
        currentInput = newInput
        return true
    }

    /// 初回設定に失敗した場合の後始末。設定トランザクション内で呼び出す。
    private func removeCurrentInputOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
    }

    // MARK: - QR 読み取り

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

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
            .first(where: { !$0.isEmpty }) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.accept(value)
        }
    }

    private func accept(_ value: String) {
        let now = Date()

        // 同じQRの連続読み取りによる二重追加を防ぐ。
        if value == lastAccepted,
           now.timeIntervalSince(lastAcceptedAt) < 1.2 {
            return
        }

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
// 1. layerClass をオーバーライドした専用UIViewを定義する
class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// 2. UIViewRepresentable では上記のカスタムViewを使用する
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // セッションが更新された場合に備えて再割り当てする
        uiView.videoPreviewLayer.session = session
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