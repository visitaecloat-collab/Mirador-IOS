import SwiftUI
import AVFoundation

enum CameraScanState {
    case permissionRequired
    case scanning
    case matchFound
    case noMatch
}

/// Equivalente de `CameraRecognitionScreen.kt`:
/// - Explica el uso de la cámara antes de solicitar el permiso
/// - Muestra visor en vivo con retícula de museo
/// - Permite confirmar coincidencia, pulsar "No es este" para rotar candidatos o buscar por nombre si no hay coincidencia/permiso
struct CameraRecognitionView: View {
    @EnvironmentObject var state: MiradorAppState
    @Environment(\.dismiss) private var dismiss

    @State private var scanState: CameraScanState = .permissionRequired
    @State private var candidateIndex: Int = 0

    private var availableCandidates: [HeritageSite] {
        state.session.accessLevel == .guest ? state.sites.filter { $0.isFlagship } : state.sites
    }

    private var matchedSite: HeritageSite? {
        guard !availableCandidates.isEmpty else { return nil }
        return availableCandidates[candidateIndex % availableCandidates.count]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MiradorColors.ink.ignoresSafeArea()

                switch scanState {
                case .permissionRequired:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("RECONOCIMIENTO VISUAL")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.gold)

                        Text("Permiso de cámara")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        Text("Utilizamos la cámara únicamente en tiempo real para identificar la fachada del monumento frente a ti. No grabamos ni subimos vídeo a servidores.")
                            .font(MiradorTypography.bodyLarge)
                            .foregroundColor(MiradorColors.greenishGrey)

                        Button("Activar cámara") {
                            requestCameraAccess()
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())

                        Button("Buscar monumento por nombre") {
                            dismiss()
                            state.selectedTab = 2
                        }
                        .buttonStyle(MuseumOutlinedButtonStyle())
                    }
                    .padding(20)
                    .museumCard()
                    .padding(20)

                case .scanning, .matchFound:
                    ZStack(alignment: .bottom) {
                        CameraPreviewRepresentable()
                            .ignoresSafeArea()

                        // Retícula arquitectónica
                        Rectangle()
                            .stroke(scanState == .matchFound ? MiradorColors.gold : MiradorColors.cream, lineWidth: 2)
                            .frame(width: 260, height: 260)
                            .padding(.bottom, 180)

                        if scanState == .scanning {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .tint(MiradorColors.mossGreen)
                                Text("Analizando fachada...")
                                    .font(MiradorTypography.labelLarge)
                                    .foregroundColor(MiradorColors.ink)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .museumCard()
                            .padding(16)
                        } else if let site = matchedSite {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("COINCIDENCIA IDENTIFICADA · #\(site.catalogNumber)")
                                    .font(MiradorTypography.catalogTag)
                                    .foregroundColor(MiradorColors.crimson)

                                Text(site.name(for: state.session.language.rawValue))
                                    .font(MiradorTypography.titleLarge)
                                    .foregroundColor(MiradorColors.ink)

                                Text("\(site.architect) · \(site.address)")
                                    .font(MiradorTypography.bodySmall)
                                    .foregroundColor(MiradorColors.greenishGrey)

                                HStack(spacing: 10) {
                                    Button("Ver historia y audio") {
                                        dismiss()
                                        state.selectedSite = site
                                    }
                                    .buttonStyle(MuseumPrimaryButtonStyle())

                                    Button("No es este") {
                                        if candidateIndex + 1 < availableCandidates.count {
                                            candidateIndex += 1
                                            triggerScanCycle()
                                        } else {
                                            scanState = .noMatch
                                        }
                                    }
                                    .buttonStyle(MuseumOutlinedButtonStyle())
                                }
                            }
                            .padding(16)
                            .museumCard()
                            .padding(16)
                        }
                    }

                case .noMatch:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SIN COINCIDENCIA")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.crimson)

                        Text("No hemos podido confirmar el edificio con claridad.")
                            .font(MiradorTypography.titleLarge)
                            .foregroundColor(MiradorColors.ink)

                        Button("Intentar de nuevo") {
                            candidateIndex = 0
                            triggerScanCycle()
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())

                        Button("Buscar por nombre en el catálogo") {
                            dismiss()
                            state.selectedTab = 2
                        }
                        .buttonStyle(MuseumOutlinedButtonStyle())
                    }
                    .padding(20)
                    .museumCard()
                    .padding(20)
                }
            }
            .onAppear {
                if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                    triggerScanCycle()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundColor(MiradorColors.cream)
                }
            }
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    triggerScanCycle()
                } else {
                    scanState = .permissionRequired
                }
            }
        }
    }

    private func triggerScanCycle() {
        scanState = .scanning
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if scanState == .scanning {
                scanState = .matchFound
            }
        }
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let session = AVCaptureSession()
        session.sessionPreset = .high

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = UIScreen.main.bounds
            view.layer.addSublayer(previewLayer)
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
