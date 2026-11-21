import SwiftUI
import MapKit

struct MapExploreView: View {
    @EnvironmentObject var state: MiradorAppState
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.1558, longitude: 1.1065),
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    )
    @State private var showLocationRationale = false

    private var visibleSites: [HeritageSite] {
        if state.session.accessLevel == .guest {
            return state.sites.filter { $0.isFlagship }
        }
        return state.sites
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        state.activeRouteSiteIds.compactMap { id in
            state.sites.first(where: { $0.id == id })?.coordinate
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    ForEach(visibleSites) { site in
                        Annotation(site.name(for: state.session.language.rawValue), coordinate: site.coordinate) {
                            Button {
                                state.selectedSite = site
                            } label: {
                                HStack(spacing: 4) {
                                    Text(site.catalogNumber)
                                        .font(MiradorTypography.catalogTag)
                                    if site.isFlagship {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 9))
                                    }
                                }
                                .foregroundColor(MiradorColors.cream)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(site.isFlagship ? MiradorColors.crimson : MiradorColors.mossGreen)
                                .overlay(Rectangle().stroke(MiradorColors.ink, lineWidth: 1))
                            }
                        }
                    }

                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(MiradorColors.gold, lineWidth: 4)
                    }
                }
                .mapStyle(.standard)

                VStack(spacing: 10) {
                    // Botonera flotante derecha (ubicación y cámara)
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Button {
                                if state.locationService.authorizationStatus == .notDetermined {
                                    showLocationRationale = true
                                } else {
                                    state.locationService.startUpdating()
                                    if let loc = state.locationService.userLocation {
                                        cameraPosition = .region(
                                            MKCoordinateRegion(
                                                center: loc.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                            )
                                        )
                                    }
                                }
                            } label: {
                                Image(systemName: "location")
                                    .foregroundColor(MiradorColors.ink)
                                    .frame(width: 44, height: 44)
                                    .museumCard()
                            }

                            Button {
                                state.showCameraSheet = true
                            } label: {
                                Image(systemName: "camera")
                                    .foregroundColor(MiradorColors.cream)
                                    .frame(width: 44, height: 44)
                                    .background(MiradorColors.mossGreen)
                                    .overlay(Rectangle().stroke(MiradorColors.ink, lineWidth: 1))
                            }
                        }
                    }

                    // Tarjeta inferior editorial
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CATÁLOGO · REUS (ES)")
                                .font(MiradorTypography.catalogTag)
                                .foregroundColor(MiradorColors.crimson)
                            Spacer()
                            Text(state.session.accessLevel.rawValue.uppercased())
                                .font(MiradorTypography.catalogTag)
                                .foregroundColor(MiradorColors.mossGreen)
                        }

                        Text("Guía de patrimonio y modernismo")
                            .font(MiradorTypography.titleLarge)
                            .foregroundColor(MiradorColors.ink)

                        if state.session.accessLevel == .guest {
                            Text("Modo invitado: solo ubicación del sitio emblemático (Casa Navàs). Activa tu cuenta gratuita de 7 días para desbloquear todo el mapa, rutas y audioguías.")
                                .font(MiradorTypography.bodySmall)
                                .foregroundColor(MiradorColors.greenishGrey)

                            Button("Iniciar sesión o registrarse") {
                                state.showAuthSheet = true
                            }
                            .buttonStyle(MuseumPrimaryButtonStyle())
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(visibleSites) { site in
                                        Button {
                                            state.selectedSite = site
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("#\(site.catalogNumber) · \(state.locationService.walkingMinutes(to: site)) min")
                                                    .font(MiradorTypography.catalogTag)
                                                    .foregroundColor(MiradorColors.gold)
                                                Text(site.name(for: state.session.language.rawValue))
                                                    .font(MiradorTypography.titleMedium)
                                                    .foregroundColor(MiradorColors.ink)
                                                    .lineLimit(1)
                                            }
                                            .padding(10)
                                            .frame(width: 175, alignment: .leading)
                                            .museumCard(background: MiradorColors.creamDarker)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .museumCard()
                }
                .padding(16)
            }
            .navigationTitle("Mirador")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Permiso de ubicación", isPresented: $showLocationRationale) {
                Button("Continuar") {
                    state.locationService.requestWhenInUsePermission()
                }
                Button("Ahora no", role: .cancel) {}
            } message: {
                Text("Usamos tu ubicación solo mientras utilizas la app para calcular distancias a pie, ordenar rutas y avisarte al acercarte a un monumento. Si la rechazas, puedes seguir usando la búsqueda por nombre.")
            }
        }
    }
}
