import SwiftUI

struct RoutePlannerView: View {
    @EnvironmentObject var state: MiradorAppState
    @State private var maxStops: Int = 4

    private var routeSites: [HeritageSite] {
        state.activeRouteSiteIds.compactMap { id in
            state.sites.first(where: { $0.id == id })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.session.accessLevel == .guest {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RUTAS BLOQUEADAS · MODO INVITADO")
                                .font(MiradorTypography.catalogTag)
                                .foregroundColor(MiradorColors.crimson)

                            Text("Crea una cuenta gratuita para generar recorridos automáticos por distancia y guardar itinerarios.")
                                .font(MiradorTypography.bodyLarge)
                                .foregroundColor(MiradorColors.ink)

                            Button("Crear cuenta gratuita (7 días)") {
                                state.showAuthSheet = true
                            }
                            .buttonStyle(MuseumPrimaryButtonStyle())
                        }
                        .padding(16)
                        .museumCard()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PLANIFICADOR POR PROXIMIDAD")
                                .font(MiradorTypography.catalogTag)
                                .foregroundColor(MiradorColors.gold)

                            Stepper("Paradas máximas: \(maxStops)", value: $maxStops, in: 2...6)
                                .font(MiradorTypography.bodyMedium)
                                .foregroundColor(MiradorColors.ink)

                            Button("Generar ruta automática") {
                                state.generateAutoRoute(maxStops: maxStops)
                            }
                            .buttonStyle(MuseumPrimaryButtonStyle())
                        }
                        .padding(16)
                        .museumCard()

                        if !routeSites.isEmpty {
                            HStack {
                                Text("RUTA EN CURSO (\(routeSites.count) PARADAS)")
                                    .font(MiradorTypography.catalogTag)
                                    .foregroundColor(MiradorColors.mossGreen)
                                Spacer()
                                Button("Guardar ruta") {
                                    state.saveCurrentRoute()
                                }
                                .font(MiradorTypography.labelSmall)
                                .foregroundColor(MiradorColors.gold)
                            }

                            ForEach(Array(routeSites.enumerated()), id: \.element.id) { idx, site in
                                Button {
                                    state.currentRouteStepIndex = idx
                                    state.selectedSite = site
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(String(format: "%02d", idx + 1))
                                            .font(MiradorTypography.titleLarge)
                                            .foregroundColor(idx == state.currentRouteStepIndex ? MiradorColors.crimson : MiradorColors.gold)
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(site.name(for: state.session.language.rawValue))
                                                .font(MiradorTypography.titleMedium)
                                                .foregroundColor(MiradorColors.ink)
                                            Text("\(site.address) · \(state.locationService.distanceMeters(to: site)) m (~\(state.locationService.walkingMinutes(to: site)) min)")
                                                .font(MiradorTypography.bodySmall)
                                                .foregroundColor(MiradorColors.greenishGrey)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(MiradorColors.ink)
                                    }
                                    .padding(14)
                                    .museumCard(background: idx == state.currentRouteStepIndex ? MiradorColors.creamDarker : MiradorColors.cream)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(MiradorColors.cream)
            .navigationTitle("Rutas")
        }
    }
}
