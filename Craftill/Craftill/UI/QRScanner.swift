import SwiftUI
import Combine
import AVFoundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// ════════════════════════════════════════════════════════════
// 内蔵カメラでQRを読む（P1-4）。QRの中身は商品ID。
// macOS / iPadOS の両方でビルドできるようプレビューを分岐。
// ════════════════════════════════════════════════════════════

final class QRScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    @Published var lastCode = ""
    @Published var status = "カメラを起動しています…"
    var onCode: ((String) -> Void)?

    private var configured = false
    private var lastAccepted = ""
    private var lastAcceptedAt = Date.distantPast

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startSession()
                    } else {
                        self?.status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
                    }
                }
            }
        default:
            status = "カメラへのアクセスが許可されていません（システム設定 > プライバシーとセキュリティ > カメラ）"
        }
    }

    private func startSession() {
        guard !session.isRunning else { return }
        if !configured { configure() }
        guard configured else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
        status = "QRをカメラに向けてください"
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
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

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            status = "QR読み取りを開始できません"
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr)
            ? [.qr] : output.availableMetadataObjectTypes
        configured = true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty else { return }

        // 同じQRを連続で読んだときに二重追加しない（0.8秒あければ再追加できる）
        let now = Date()
        if value == lastAccepted && now.timeIntervalSince(lastAcceptedAt) < 0.8 { return }
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
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 640, maxWidth: .infinity,
               minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        .onAppear {
            scanner.onCode = { code in
                vm.addByID(code)
            }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }
}
