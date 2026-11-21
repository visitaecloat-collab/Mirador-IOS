import SwiftUI

struct SearchCatalogView: View {
    @EnvironmentObject var state: MiradorAppState
    @State private var searchText = ""

    private var visibleSites: [HeritageSite] {
        let base = state.session.accessLevel == .guest ? state.sites.filter { $0.isFlagship } : state.sites
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name(for: state.session.language.rawValue).localizedCaseInsensitiveContains(q) ||
            $0.architect.localizedCaseInsensitiveContains(q) ||
            $0.style.localizedCaseInsensitiveContains(q) ||
            $0.address.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleSites) { site in
                Button {
                    state.selectedSite = site
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CATÁLOGO #\(site.catalogNumber) · \(site.style.uppercased())")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.gold)
                        Text(site.name(for: state.session.language.rawValue))
                            .font(MiradorTypography.titleMedium)
                            .foregroundColor(MiradorColors.ink)
                        Text("\(site.architect) · \(site.address)")
                            .font(MiradorTypography.bodySmall)
                            .foregroundColor(MiradorColors.greenishGrey)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(MiradorColors.cream)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Buscar por nombre, arquitecto o estilo")
            .background(MiradorColors.cream)
            .navigationTitle("Búsqueda")
        }
    }
}

struct OfflineManagerView: View {
    @EnvironmentObject var state: MiradorAppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if state.session.accessLevel != .subscribed {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MODO SIN CONEXIÓN · SUSCRIPTORES")
                                .font(MiradorTypography.catalogTag)
                                .foregroundColor(MiradorColors.crimson)
                            Text("Descarga audioguías cifradas (AES-256-GCM) para escucharlas sin cobertura móvil durante tu visita.")
                                .font(MiradorTypography.bodyLarge)
                                .foregroundColor(MiradorColors.ink)
                            Button("Ver suscripciones") {
                                state.selectedTab = 4
                            }
                            .buttonStyle(MuseumPrimaryButtonStyle())
                        }
                        .padding(16)
                        .museumCard()
                    } else {
                        Text("AUDIOS CIFRADOS EN DISPOSITIVO (AES-256-GCM)")
                            .font(MiradorTypography.catalogTag)
                            .foregroundColor(MiradorColors.mossGreen)

                        ForEach(state.sites) { site in
                            let lang = state.session.language.rawValue
                            let isDownloaded = state.audioGuide.hasEncryptedOfflineTrack(siteSlug: site.slug, language: lang)
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("#\(site.catalogNumber) · \(site.name(for: lang))")
                                        .font(MiradorTypography.titleMedium)
                                        .foregroundColor(MiradorColors.ink)
                                    Text(isDownloaded ? "Disponible sin conexión" : "No descargado")
                                        .font(MiradorTypography.bodySmall)
                                        .foregroundColor(isDownloaded ? MiradorColors.mossGreen : MiradorColors.greenishGrey)
                                }
                                Spacer()
                                if isDownloaded {
                                    Button("Eliminar") {
                                        state.audioGuide.deleteEncryptedTrack(siteSlug: site.slug, language: lang)
                                        state.session.offlineDownloadedSlugs.remove(site.slug)
                                        state.persistSession()
                                    }
                                    .font(MiradorTypography.labelSmall)
                                    .foregroundColor(MiradorColors.crimson)
                                } else {
                                    Button("Descargar") {
                                        Task {
                                            if let token = state.session.accessToken {
                                                try? await state.audioGuide.downloadEncryptedTrack(
                                                    site: site,
                                                    accessToken: token,
                                                    language: lang
                                                )
                                                state.session.offlineDownloadedSlugs.insert(site.slug)
                                                state.persistSession()
                                            }
                                        }
                                    }
                                    .font(MiradorTypography.labelSmall)
                                    .foregroundColor(MiradorColors.mossGreen)
                                }
                            }
                            .padding(14)
                            .museumCard()
                        }
                    }
                }
                .padding(16)
            }
            .background(MiradorColors.cream)
            .navigationTitle("Sin conexión")
        }
    }
}
