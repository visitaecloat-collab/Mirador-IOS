import SwiftUI

enum AuthStepMode {
    case login
    case register
    case verifyOtp
    case recoverPassword
    case confirmAge
}

struct AuthFlowView: View {
    @EnvironmentObject var state: MiradorAppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthStepMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var otpCode = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -22, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var feedbackMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("MIRADOR · ACCESO")
                        .font(MiradorTypography.catalogTag)
                        .foregroundColor(MiradorColors.crimson)

                    switch mode {
                    case .login:
                        Text("Inicia sesión en tu cuenta")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Correo electrónico", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .museumCard()

                            SecureField("Contraseña", text: $password)
                                .padding(12)
                                .museumCard()
                        }

                        Button(isSubmitting ? "Entrando..." : "Entrar") {
                            Task { await performLogin() }
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())
                        .disabled(isSubmitting)

                        Button("¿Olvidaste tu contraseña?") {
                            mode = .recoverPassword
                            feedbackMessage = nil
                        }
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.mossGreen)

                        Divider().background(MiradorColors.line)

                        Button("Crear cuenta gratuita (7 días de prueba)") {
                            mode = .register
                            feedbackMessage = nil
                        }
                        .buttonStyle(MuseumOutlinedButtonStyle())

                        Button("Continuar como invitado (solo sitio emblemático)") {
                            state.continueAsGuest()
                            dismiss()
                        }
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.greenishGrey)
                        .frame(maxWidth: .infinity, alignment: .center)

                    case .register:
                        Text("Crear cuenta")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        Text("Incluye 7 días de acceso gratuito al mapa completo, rutas automáticas y avances de audio.")
                            .font(MiradorTypography.bodyMedium)
                            .foregroundColor(MiradorColors.greenishGrey)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Nombre o alias", text: $displayName)
                                .padding(12)
                                .museumCard()

                            TextField("Correo electrónico", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .museumCard()

                            SecureField("Contraseña (mínimo 8 caracteres)", text: $password)
                                .padding(12)
                                .museumCard()
                        }

                        Button(isSubmitting ? "Registrando..." : "Registrarme") {
                            Task { await performRegister() }
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())
                        .disabled(isSubmitting)

                        Button("Ya tengo cuenta · Iniciar sesión") {
                            mode = .login
                            feedbackMessage = nil
                        }
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.mossGreen)

                    case .verifyOtp:
                        Text("Verificar correo")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        Text("Introduce el código enviado a \(email).")
                            .font(MiradorTypography.bodyMedium)
                            .foregroundColor(MiradorColors.greenishGrey)

                        TextField("Código de verificación", text: $otpCode)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .museumCard()

                        Button(isSubmitting ? "Verificando..." : "Confirmar código") {
                            Task { await performVerifyOtp() }
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())

                        Button("Reenviar correo de verificación") {
                            Task {
                                try? await state.supabase.resendSignupOtp(email: email)
                                feedbackMessage = "Código reenviado."
                                isError = false
                            }
                        }
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.mossGreen)

                    case .recoverPassword:
                        Text("Recuperar contraseña")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        TextField("Correo electrónico", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .padding(12)
                            .museumCard()

                        Button("Enviar enlace de recuperación") {
                            Task {
                                isSubmitting = true
                                defer { isSubmitting = false }
                                do {
                                    try await state.supabase.recoverPassword(email: email)
                                    isError = false
                                    feedbackMessage = "Revisa tu bandeja de entrada para restablecer tu contraseña."
                                } catch {
                                    isError = true
                                    feedbackMessage = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())

                        Button("Volver a iniciar sesión") {
                            mode = .login
                        }
                        .font(MiradorTypography.bodySmall)
                        .foregroundColor(MiradorColors.mossGreen)

                    case .confirmAge:
                        Text("Confirmar edad mínima (16+)")
                            .font(MiradorTypography.headlineMedium)
                            .foregroundColor(MiradorColors.ink)

                        Text("Mirador requiere tener al menos 16 años. No almacenamos tu fecha de nacimiento tras la comprobación.")
                            .font(MiradorTypography.bodyMedium)
                            .foregroundColor(MiradorColors.greenishGrey)

                        DatePicker("Fecha de nacimiento", selection: $birthDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(MiradorColors.mossGreen)

                        Button("Confirmar edad") {
                            Task {
                                let ok = await state.confirmAge(birthDate: birthDate)
                                if ok {
                                    dismiss()
                                } else {
                                    isError = true
                                    feedbackMessage = "Debes tener al menos 16 años para utilizar una cuenta en Mirador."
                                }
                            }
                        }
                        .buttonStyle(MuseumPrimaryButtonStyle())
                    }

                    if let msg = feedbackMessage {
                        Text(msg)
                            .font(MiradorTypography.bodySmall)
                            .foregroundColor(isError ? MiradorColors.crimson : MiradorColors.mossGreen)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .museumCard(background: MiradorColors.creamDarker)
                    }
                }
                .padding(20)
            }
            .background(MiradorColors.cream)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundColor(MiradorColors.ink)
                }
            }
        }
    }

    private func performLogin() async {
        isSubmitting = true
        feedbackMessage = nil
        defer { isSubmitting = false }
        do {
            try await state.signIn(email: email, password: password)
            if !state.session.isAgeConfirmed {
                mode = .confirmAge
            } else {
                dismiss()
            }
        } catch SupabaseError.emailNotConfirmed {
            mode = .verifyOtp
            isError = true
            feedbackMessage = "Tu correo aún no está confirmado. Introduce el código recibido."
        } catch {
            isError = true
            feedbackMessage = error.localizedDescription
        }
    }

    private func performRegister() async {
        isSubmitting = true
        feedbackMessage = nil
        defer { isSubmitting = false }
        do {
            try await state.signUp(email: email, password: password, displayName: displayName)
            if state.session.accessToken == nil {
                mode = .verifyOtp
                isError = false
                feedbackMessage = "Te hemos enviado un código de verificación por correo."
            } else {
                mode = .confirmAge
            }
        } catch {
            isError = true
            feedbackMessage = error.localizedDescription
        }
    }

    private func performVerifyOtp() async {
        isSubmitting = true
        feedbackMessage = nil
        defer { isSubmitting = false }
        do {
            try await state.verifyOtp(email: email, code: otpCode)
            mode = .confirmAge
        } catch {
            isError = true
            feedbackMessage = error.localizedDescription
        }
    }
}
