import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import T2PCore

/// Scan the room's QR code (on a TV, a computer or another phone) with the camera.
struct ScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let p = problem {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                        Text(p).multilineTextAlignment(.center).foregroundStyle(.white)
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied, let u = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: u).foregroundStyle(T2P.gold)
                        }
                    }
                    .padding(32)
                } else {
                    QRCamera(onCode: { text in
                        if let c = RoomCode.fromScan(text) { Haptics.yourTurn(); onCode(c) }
                    }, onProblem: { problem = $0 })
                    .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24).stroke(T2P.gold, lineWidth: 3).frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                    VStack { Spacer(); Text("Point at the room’s QR code").font(.headline).foregroundStyle(.white).padding(.bottom, 40) }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white) } }
        }
    }
}

private struct QRCamera: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onProblem: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController(); c.onCode = onCode; c.onProblem = onProblem; return c
    }
    func updateUIViewController(_ vc: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onProblem: ((String) -> Void)?
    private let capture = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.setUp() : self.onProblem?("Time2Play needs the camera to scan a room’s code. You can type the code instead.") }
        }
    }

    private func setUp() {
        guard let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), capture.canAddInput(input) else {
            onProblem?("There’s no camera here. Type the room’s code instead."); return
        }
        capture.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard capture.canAddOutput(out) else { onProblem?("The camera can’t scan right now. Type the code instead."); return }
        capture.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: capture)
        p.videoGravity = .resizeAspectFill
        p.frame = view.bounds
        view.layer.addSublayer(p)
        preview = p
        DispatchQueue.global(qos: .userInitiated).async { self.capture.startRunning() }
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.capture.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, RoomCode.fromScan(s) != nil else { return }
        done = true
        onCode?(s)
    }
}

/// A room's QR code (what the Share sheet and a TV show): time2play.live/CODE.
enum QR {
    static func image(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
