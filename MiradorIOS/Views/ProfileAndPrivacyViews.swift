import SwiftUI
import StoreKit

struct ProfileAndPrivacyView: View {
    @EnvironmentObject var state: MiradorAppState
    @State private var showWithdrawStep1 = false
    @State private var showWithdrawStep2 = false
    @State private var showDeleteConfirm = false
    @State private var exportedJSONText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta y estado") {
                    LabeledContent("Nivel de acceso", value: state.session.accessLevel.rawValue.uppercased())
                    if let email = state.session.email {
                        LabeledContent("Correo", value: email)
                    }
                    if state.session.isGuest {
                        Button("Iniciar sesión o crear cuenta") {
                            state.showAuthSheet = true
                        }
                        .foregroundColor(MiradorColors.mossGreen)
                    } else {
                        Button("Cerrar sesión") {
                            state.signOut()
                        }
                        .foregroundColor(MiradorColors.crimson)
                    }
                }

                Section("Idioma y país") {
                    Picker("Idioma activo", selection: $state.session.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .onChange(of: state.session.language) { _, _ in
                        state.persistSession()
                    }
                    LabeledContent("País o región", value: "España (ES)")
                    Text("Catalán, italiano y árabe (RTL) preparados para próximas fases.")
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.greenishGrey)
                }

                Section("Suscripción (App Store / StoreKit 2)") {
                    Toggle("Renovar automáticamente", isOn: $state.session.autoRenew)
                        .tint(MiradorColors.mossGreen)

                    if state.billing.products.isEmpty {
                        ForEach(SubscriptionPlanType.allCases) { plan in
                            HStack {
                                Text(plan.title)
                                Spacer()
                                Text(plan.fallbackPriceLabel)
                                    .foregroundColor(MiradorColors.mossGreen)
                            }
                        }
                    } else {
                        ForEach(state.billing.products, id: \.id) { product in
                            Button {
                                Task {
                                    let ok = await state.billing.purchase(product: product, accessToken: state.session.accessToken)
                                    if ok {
                                        state.session.accessLevel = .subscribed
                                        state.session.activePlanId = product.id
                                        state.persistSession()
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName)
                                            .foregroundColor(MiradorColors.ink)
                                        Text("Impuestos incluidos")
                                            .font(MiradorTypography.bodySmall)
                                            .foregroundColor(MiradorColors.greenishGrey)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .bold()
                                        .foregroundColor(MiradorColors.mossGreen)
                                }
                            }
                        }
                    }

                    Button("Restaurar compras") {
                        Task { await state.billing.restorePurchases() }
                    }
                    .foregroundColor(MiradorColors.mossGreen)

                    if state.session.accessLevel == .subscribed {
                        Button("Retirarme del contrato (desistimiento)") {
                            showWithdrawStep1 = true
                        }
                        .foregroundColor(MiradorColors.crimson)
                    }
                }

                Section("Tu privacidad y consentimientos (RGPD)") {
                    Toggle("Estadísticas anónimas de uso", isOn: $state.session.consents.analyticsEnabled)
                        .tint(MiradorColors.mossGreen)
                    Toggle("Mensajes y novedades culturales", isOn: $state.session.consents.marketingEnabled)
                        .tint(MiradorColors.mossGreen)
                    Toggle("Avisos de proximidad en mapa", isOn: $state.session.proximityAlertsEnabled)
                        .tint(MiradorColors.mossGreen)
                        .onChange(of: state.session.proximityAlertsEnabled) { _, val in
                            state.locationService.alertsEnabled = val
                            state.persistSession()
                        }

                    Button("Descargar mis datos (portabilidad RGPD)") {
                        if let data = try? JSONEncoder().encode(state.session),
                           let str = String(data: data, encoding: .utf8) {
                            exportedJSONText = str
                        }
                    }
                    .foregroundColor(MiradorColors.mossGreen)

                    if !state.session.isGuest {
                        Button("Eliminar cuenta permanentemente", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MiradorColors.cream)
            .navigationTitle("Perfil y ajustes")
            .alert("Retirada del contrato (Paso 1 de 2)", isPresented: $showWithdrawStep1) {
                Button("Continuar", role: .destructive) { showWithdrawStep2 = true }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Puedes ejercer tu derecho de desistimiento o gestionar la cancelación de tu suscripción de App Store.")
            }
            .alert("Confirmar retirada (Paso 2 de 2)", isPresented: $showWithdrawStep2) {
                Button("Abrir gestión de suscripciones Apple") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Volver", role: .cancel) {}
            } message: {
                Text("Apple procesará el reembolso o cancelación inmediata conforme a las condiciones de App Store.")
            }
            .alert("Eliminar cuenta y datos", isPresented: $showDeleteConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar definitivamente", role: .destructive) {
                    Task { await state.deleteAccountCompletely() }
                }
            } message: {
                Text("Se borrarán tu perfil, suscripciones asociadas en servidor y todos los archivos cifrados locales de forma irreversible.")
            }
            .sheet(item: Binding(
                get: { exportedJSONText.map { ExportedPayload(text: $0) } },
                set: { exportedJSONText = $0?.text }
            )) { payload in
                NavigationStack {
                    ScrollView {
                        Text(payload.text)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("Exportación RGPD")
                }
            }
        }
    }
}

private struct ExportedPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// Pantalla exclusiva cuando el periodo gratuito venció o la edad no está confirmada (`accessLevel == .none`)
struct ExpiredOrRestrictedAccountView: View {
    @EnvironmentObject var state: MiradorAppState
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("PERIODO GRATUITO VENCIDO O EDAD SIN CONFIRMAR")
                        .font(MiradorTypography.catalogTag)
                        .foregroundColor(MiradorColors.crimson)

                    Text("Activa una suscripción o gestiona tus derechos de cuenta")
                        .font(MiradorTypography.headlineMedium)
                        .foregroundColor(MiradorColors.ink)

                    if !state.session.isAgeConfirmed {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Confirmación de edad mínima (16 años)")
                                .font(MiradorTypography.titleMedium)
                            DatePicker("Fecha de nacimiento", selection: $birthDate, displayedComponents: .date)
                            Button("Confirmar edad") {
                                Task { _ = await state.confirmAge(birthDate: birthDate) }
                            }
                            .buttonStyle(MuseumPrimaryButtonStyle())
                        }
                        .padding(14)
                        .museumCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Planes disponibles")
                            .font(MiradorTypography.titleMedium)
                        ForEach(SubscriptionPlanType.allCases) { plan in
                            HStack {
                                Text(plan.title)
                                Spacer()
                                Text(plan.fallbackPriceLabel)
                                    .bold()
                            }
                            .padding(10)
                            .museumCard(background: MiradorColors.creamDarker)
                        }
                    }

                    Divider().background(MiradorColors.line)

                    Button("Cerrar sesión") {
                        state.signOut()
                    }
                    .buttonStyle(MuseumOutlinedButtonStyle())

                    Button("Eliminar cuenta permanentemente") {
                        showDeleteConfirm = true
                    }
                    .font(MiradorTypography.labelLarge)
                    .foregroundColor(MiradorColors.crimson)
                }
                .padding(20)
            }
            .background(MiradorColors.cream)
            .navigationTitle("Mirador")
            .alert("Eliminar cuenta", isPresented: $showDeleteConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    Task { await state.deleteAccountCompletely() }
                }
            }
        }
    }
}
