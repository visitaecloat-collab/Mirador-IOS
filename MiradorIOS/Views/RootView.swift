import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: MiradorAppState

    var body: some View {
        ZStack(alignment: .top) {
            if state.session.accessLevel == .none && !state.session.isGuest {
                ExpiredOrRestrictedAccountView()
            } else {
                TabView(selection: $state.selectedTab) {
                    MapExploreView()
                        .tabItem {
                            Label("Mapa", systemImage: "map")
                        }
                        .tag(0)

                    RoutePlannerView()
                        .tabItem {
                            Label("Rutas", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        .tag(1)

                    SearchCatalogView()
                        .tabItem {
                            Label("Buscar", systemImage: "magnifyingglass")
                        }
                        .tag(2)

                    OfflineManagerView()
                        .tabItem {
                            Label("Sin conexión", systemImage: "arrow.down.circle")
                        }
                        .tag(3)

                    ProfileAndPrivacyView()
                        .tabItem {
                            Label("Perfil", systemImage: "person")
                        }
                        .tag(4)
                }
                .tint(MiradorColors.mossGreen)
            }

            // Aviso de proximidad cuando el usuario se encuentra a <= 60 m de un sitio
            if let alertSite = state.locationService.nearbyAlertSite {
                ProximityAlertBanner(
                    site: alertSite,
                    language: state.session.language.rawValue,
                    onOpenSite: {
                        state.locationService.nearbyAlertSite = nil
                        state.selectedSite = alertSite
                    },
                    onDismiss: {
                        state.locationService.nearbyAlertSite = nil
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $state.selectedSite) { site in
            SiteDetailView(site: site)
        }
        .sheet(isPresented: $state.showAuthSheet) {
            AuthFlowView()
        }
        .fullScreenCover(isPresented: $state.showCameraSheet) {
            CameraRecognitionView()
        }
    }
}

struct ProximityAlertBanner: View {
    let site: HeritageSite
    let language: String
    let onOpenSite: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AVISO DE PROXIMIDAD · #\(site.catalogNumber)")
                    .font(MiradorTypography.catalogTag)
                    .foregroundColor(MiradorColors.gold)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundColor(MiradorColors.ink)
                }
            }
            Text("Estás frente a \(site.name(for: language))")
                .font(MiradorTypography.titleMedium)
                .foregroundColor(MiradorColors.ink)
            Button("Abrir ficha y audioguía", action: onOpenSite)
                .buttonStyle(MuseumPrimaryButtonStyle())
        }
        .padding(14)
        .museumCard(background: MiradorColors.cream, borderColor: MiradorColors.ink, lineWidth: 1.5)
    }
}
