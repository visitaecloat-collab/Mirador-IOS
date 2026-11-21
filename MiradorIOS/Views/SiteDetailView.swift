import SwiftUI

struct SiteDetailView: View {
    @EnvironmentObject var state: MiradorAppState
    @Environment(\.dismiss) private var dismiss
    let site: HeritageSite

    @State private var showReportSheet = false
    @State private var offlineStatusText: String?

    private var lang: String { state.session.language.rawValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Cabecera editorial de catálogo
                    HStack {
                        Text("CATÁLOGO #\(site.catalogNumber) · \(site.style.uppercased())")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.crimson)
                        Spacer()
                        Button {
                            state.toggleFavorite(siteId: site.id)
                        } label: {
                            Image(systemName: state.session.favoriteSiteIds.contains(site.id) ? "bookmark.fill" : "bookmark")
                                .foregroundColor(MiradorColors.mossGreen)
                        }
                    }

                    Text(site.name(for: lang))
                        .font(MiradorTypography.headlineLarge)
                        .foregroundColor(MiradorColors.ink)

                    Text("\(site.architect) · \(site.address)")
                        .font(MiradorTypography.bodyMedium)
                        .foregroundColor(MiradorColors.greenishGrey)

                    // Imagen aprobada con atribución obligatoria
                    if let cover = site.coverImage,
                       let imgURL = cover.resolvedImageURL(baseImagesURL: SupabaseConfig.publicImagesBaseURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: imgURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 210)
                                        .clipped()
                                default:
                                    Rectangle()
                                        .fill(MiradorColors.creamDarker)
                                        .frame(height: 210)
                                }
                            }
                            Text("Foto: \(cover.author) · Licencia: \(cover.license)")
                                .font(MiradorTypography.bodySmall)
                                .foregroundColor(MiradorColors.greenishGrey)
                        }
                        .padding(8)
                        .museumCard()
                    }

                    Divider().background(MiradorColors.line)

                    // Bloque de Audioguía según nivel de acceso
                    audioSection

                    // Historia según nivel de acceso
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.session.accessLevel == .subscribed ? "HISTORIA COMPLETA" : "RESUMEN HISTORICO")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.mossGreen)

                        Text(state.session.accessLevel == .subscribed ? site.story(for: lang) : site.summary(for: lang))
                            .font(MiradorTypography.bodyLarge)
                            .foregroundColor(MiradorColors.ink)

                        if state.session.accessLevel != .subscribed {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("La narración completa, el audio íntegro y la descarga sin conexión están reservados a suscriptores.")
                                    .font(MiradorTypography.bodySmall)
                                    .foregroundColor(MiradorColors.greenishGrey)
                                Button("Ver planes de suscripción") {
                                    dismiss()
                                    state.selectedTab = 4
                                }
                                .buttonStyle(MuseumOutlinedButtonStyle(borderColor: MiradorColors.gold, foreground: MiradorColors.ink))
                            }
                            .padding(12)
                            .museumCard(background: MiradorColors.creamDarker)
                        }
                    }

                    Text("Fuentes documentales: \(site.sourceRefs)")
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.greenishGrey)

                    // Botón obligatorio de reporte de error o contenido
                    Button("Reportar un error o contenido") {
                        showReportSheet = true
                    }
                    .font(MiradorTypography.bodySmall)
                    .foregroundColor(MiradorColors.crimson)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(MiradorColors.cream)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundColor(MiradorColors.ink)
                }
            }
            .sheet(isPresented: $showReportSheet) {
                ReportContentSheet(site: site)
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.session.accessLevel == .subscribed ? "AUDIOGUÍA COMPLETA" : "AVANCE DE AUDIOGUÍA")
                    .font(MiradorTypography.catalogTag)
                    .foregroundColor(MiradorColors.gold)
                Spacer()
                let secs = state.session.accessLevel == .subscribed ? site.audioDurationSeconds : site.previewDurationSeconds
                Text(String(format: "%d:%02d", secs / 60, secs % 60))
                    .font(MiradorTypography.catalogTag)
                    .foregroundColor(MiradorColors.greenishGrey)
            }

            if state.session.accessLevel == .guest {
                Text("Inicia sesión con tu cuenta gratuita (7 días) o suscríbete para escuchar la audioguía.")
                    .font(MiradorTypography.bodySmall)
                    .foregroundColor(MiradorColors.greenishGrey)
                Button("Acceder") {
                    dismiss()
                    state.showAuthSheet = true
                }
                .buttonStyle(MuseumPrimaryButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button(state.audioGuide.isPlaying && state.audioGuide.activeSiteId == site.id ? "Detener" : "Reproducir") {
                        Task {
                            if state.audioGuide.isPlaying && state.audioGuide.activeSiteId == site.id {
                                state.audioGuide.stop()
                            } else {
                                await state.audioGuide.playTrack(
                                    site: site,
                                    accessToken: state.session.accessToken,
                                    accessLevel: state.session.accessLevel,
                                    language: lang
                                )
                            }
                        }
                    }
                    .buttonStyle(MuseumPrimaryButtonStyle())

                    if state.session.accessLevel == .subscribed {
                        let isSaved = state.audioGuide.hasEncryptedOfflineTrack(siteSlug: site.slug, language: lang)
                        Button(isSaved ? "Descargado (AES)" : "Descargar offline") {
                            Task {
                                guard let token = state.session.accessToken else {
                                    offlineStatusText = "Requiere sesión activa para descargar."
                                    return
                                }
                                do {
                                    try await state.audioGuide.downloadEncryptedTrack(
                                        site: site,
                                        accessToken: token,
                                        language: lang
                                    )
                                    state.session.offlineDownloadedSlugs.insert(site.slug)
                                    state.persistSession()
                                    offlineStatusText = "Guardado y cifrado en el dispositivo."
                                } catch {
                                    offlineStatusText = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(MuseumOutlinedButtonStyle())
                    }
                }

                if let err = state.audioGuide.errorMessage ?? offlineStatusText {
                    Text(err)
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.crimson)
                }
            }
        }
        .padding(14)
        .museumCard(background: MiradorColors.creamDarker)
    }
}

struct ReportContentSheet: View {
    @EnvironmentObject var state: MiradorAppState
    @Environment(\.dismiss) private var dismiss
    let site: HeritageSite

    @State private var reason = "Dato histórico o ubicación incorrecta"
    @State private var details = ""
    @State private var statusMsg: String?

    private let reasons = [
        "Dato histórico o ubicación incorrecta",
        "Problema con la audioguía o traducción",
        "Atribución o licencia de imagen",
        "Otro error"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sitio") {
                    Text("#\(site.catalogNumber) · \(site.name)")
                }
                Section("Motivo") {
                    Picker("Motivo", selection: $reason) {
                        ForEach(reasons, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    TextField("Detalles adicionales", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button("Enviar reporte") {
                        Task {
                            if let token = state.session.accessToken, let uid = state.session.userId {
                                try? await state.supabase.submitContentReport(
                                    accessToken: token,
                                    userId: uid,
                                    siteId: site.id,
                                    language: state.session.language.rawValue,
                                    reason: reason,
                                    details: details
                                )
                            }
                            statusMsg = "Reporte registrado para revisión editorial."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                dismiss()
                            }
                        }
                    }
                    .foregroundColor(MiradorColors.mossGreen)
                }
                if let msg = statusMsg {
                    Text(msg)
                        .foregroundColor(MiradorColors.mossGreen)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MiradorColors.cream)
            .navigationTitle("Reportar contenido")
        }
    }
}
