import Foundation

enum SupabaseError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case emailNotConfirmed
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configura SUPABASE_URL y SUPABASE_ANON_KEY en Info.plist."
        case .unauthorized:
            return "Sesión caducada o no autorizada. Inicia sesión de nuevo."
        case .emailNotConfirmed:
            return "Debes verificar tu correo electrónico antes de continuar."
        case .serverError(let msg):
            return msg
        }
    }
}

struct SupabaseConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty, !cleaned.contains("your-project-ref") else { return nil }
        return URL(string: cleaned)
    }

    static var anonKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains("your_supabase") else { return nil }
        return cleaned
    }

    static var publicImagesBaseURL: String {
        guard let base = baseURL else { return "" }
        return "\(base.absoluteString)/storage/v1/object/public/images"
    }

    static var isConfigured: Bool {
        baseURL != nil && anonKey != nil
    }
}

struct AuthSessionDTO: Codable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let user: AuthUserDTO?
    let id: String?
    let email: String?
}

struct AuthUserDTO: Codable {
    let id: String
    let email: String?
}

struct RemoteAccessSnapshot {
    let accessLevel: AccessLevel
    let activePlanId: String?
    let autoRenew: Bool
    let validUntilISO: String?
    let displayName: String?
    let language: String?
    let country: String?
    let isAgeConfirmed: Bool
}

final class SupabaseService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        bearerToken: String? = nil,
        queryItems: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) throws -> URLRequest {
        guard let base = SupabaseConfig.baseURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseError.notConfigured
        }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        }
        if let body = jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    // MARK: - Autenticación (GoTrue)

    func signInWithPassword(email: String, password: String) async throws -> AuthSessionDTO {
        let req = try makeRequest(
            path: "auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            jsonBody: ["email": email.trimmingCharacters(in: .whitespaces), "password": password]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.serverError("Respuesta inválida del servidor")
        }
        if !(200...299).contains(http.statusCode) {
            let rawErr = String(data: data, encoding: .utf8) ?? ""
            if rawErr.localizedCaseInsensitiveContains("email_not_confirmed") {
                throw SupabaseError.emailNotConfirmed
            }
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "Credenciales incorrectas")
        }
        return try JSONDecoder().decode(AuthSessionDTO.self, from: data)
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthSessionDTO {
        let req = try makeRequest(
            path: "auth/v1/signup",
            method: "POST",
            jsonBody: [
                "email": email.trimmingCharacters(in: .whitespaces),
                "password": password,
                "data": ["display_name": displayName]
            ]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "Error al registrar cuenta")
        }
        return try JSONDecoder().decode(AuthSessionDTO.self, from: data)
    }

    func verifyEmailOtp(email: String, code: String) async throws -> AuthSessionDTO {
        let req = try makeRequest(
            path: "auth/v1/verify",
            method: "POST",
            jsonBody: [
                "email": email.trimmingCharacters(in: .whitespaces),
                "token": code.trimmingCharacters(in: .whitespaces),
                "type": "signup"
            ]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "Código de verificación inválido")
        }
        return try JSONDecoder().decode(AuthSessionDTO.self, from: data)
    }

    func resendSignupOtp(email: String) async throws {
        let req = try makeRequest(
            path: "auth/v1/resend",
            method: "POST",
            jsonBody: ["type": "signup", "email": email.trimmingCharacters(in: .whitespaces)]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "No se pudo reenviar el código")
        }
    }

    func recoverPassword(email: String) async throws {
        let req = try makeRequest(
            path: "auth/v1/recover",
            method: "POST",
            queryItems: [URLQueryItem(name: "redirect_to", value: "mirador://auth-callback")],
            jsonBody: ["email": email.trimmingCharacters(in: .whitespaces)]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "No se pudo iniciar la recuperación")
        }
    }

    // MARK: - Nivel de acceso en servidor y confirmación de edad (RPC)

    func fetchServerAccessSnapshot(accessToken: String, userId: String) async throws -> RemoteAccessSnapshot {
        // 1. Llamar a rpc/current_access (evalúa en servidor access_level_for(uid))
        let accessReq = try makeRequest(path: "rest/v1/rpc/current_access", method: "POST", bearerToken: accessToken, jsonBody: [:])
        let (accessData, accessResp) = try await session.data(for: accessReq)
        guard let http = accessResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.unauthorized
        }
        let rawLevel = (String(data: accessData, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedLevel = AccessLevel(rawValue: rawLevel) ?? .none

        // 2. Consultar perfil propio
        let profReq = try makeRequest(
            path: "rest/v1/profiles",
            bearerToken: accessToken,
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "id,display_name,language,country,age_confirmed_at")
            ]
        )
        let (profData, _) = try await session.data(for: profReq)
        let profArr = (try? JSONSerialization.jsonObject(with: profData) as? [[String: Any]]) ?? []
        let prof = profArr.first

        // 3. Consultar suscripción propia
        let subReq = try makeRequest(
            path: "rest/v1/subscriptions",
            bearerToken: accessToken,
            queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "plan_id,auto_renew,status,current_period_end")
            ]
        )
        let (subData, _) = try await session.data(for: subReq)
        let subArr = (try? JSONSerialization.jsonObject(with: subData) as? [[String: Any]]) ?? []
        let sub = subArr.first

        return RemoteAccessSnapshot(
            accessLevel: resolvedLevel,
            activePlanId: sub?["plan_id"] as? String,
            autoRenew: (sub?["auto_renew"] as? Bool) ?? true,
            validUntilISO: sub?["current_period_end"] as? String,
            displayName: prof?["display_name"] as? String,
            language: prof?["language"] as? String,
            country: prof?["country"] as? String,
            isAgeConfirmed: (prof?["age_confirmed_at"] as? String)?.nonEmpty != nil
        )
    }

    /// Envía la fecha de nacimiento a `rpc/confirm_age`. El servidor NO almacena la fecha;
    /// confirma si >= 16 años o elimina la cuenta si es menor.
    func confirmAgeOnServer(accessToken: String, birthDateISO: String) async throws -> AccessLevel {
        let req = try makeRequest(
            path: "rest/v1/rpc/confirm_age",
            method: "POST",
            bearerToken: accessToken,
            jsonBody: ["p_birthdate": birthDateISO]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "No se pudo verificar la edad")
        }
        let raw = (String(data: data, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return AccessLevel(rawValue: raw) ?? .none
    }

    // MARK: - Catálogo aprobado (`review_status = 'approved'`)

    func fetchApprovedCatalog(bearerToken: String?) async throws -> [HeritageSite] {
        let sitesReq = try makeRequest(
            path: "rest/v1/sites",
            bearerToken: bearerToken,
            queryItems: [
                URLQueryItem(name: "published", value: "eq.true"),
                URLQueryItem(name: "review_status", value: "eq.approved"),
                URLQueryItem(name: "select", value: "id,slug,name,city,address,architect,lat,lng,is_flagship,style,source_refs")
            ]
        )
        let (sitesData, sitesResp) = try await session.data(for: sitesReq)
        guard let http = sitesResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError("No se pudo descargar el catálogo remoto")
        }

        let textsReq = try makeRequest(
            path: "rest/v1/site_texts",
            bearerToken: bearerToken,
            queryItems: [
                URLQueryItem(name: "review_status", value: "eq.approved"),
                URLQueryItem(name: "select", value: "site_id,language,summary")
            ]
        )
        let storiesReq = try makeRequest(
            path: "rest/v1/site_stories",
            bearerToken: bearerToken,
            queryItems: [
                URLQueryItem(name: "review_status", value: "eq.approved"),
                URLQueryItem(name: "select", value: "site_id,language,story")
            ]
        )
        let imagesReq = try makeRequest(
            path: "rest/v1/site_images",
            bearerToken: bearerToken,
            queryItems: [
                URLQueryItem(name: "review_status", value: "eq.approved"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )

        async let textsPair = session.data(for: textsReq)
        async let storiesPair = session.data(for: storiesReq)
        async let imagesPair = session.data(for: imagesReq)

        let (textsData, _) = try await textsPair
        let (storiesData, _) = try await storiesPair
        let (imagesData, _) = try await imagesPair

        let rawSites = (try? JSONSerialization.jsonObject(with: sitesData) as? [[String: Any]]) ?? []
        let rawTexts = (try? JSONSerialization.jsonObject(with: textsData) as? [[String: Any]]) ?? []
        let rawStories = (try? JSONSerialization.jsonObject(with: storiesData) as? [[String: Any]]) ?? []
        let rawImages = (try? JSONSerialization.jsonObject(with: imagesData) as? [[String: Any]]) ?? []

        var summariesBySite: [String: [String: String]] = [:]
        for row in rawTexts {
            if let sid = row["site_id"] as? String,
               let lang = row["language"] as? String,
               let sum = row["summary"] as? String {
                summariesBySite[sid, default: [:]][lang] = sum
            }
        }

        var storiesBySite: [String: [String: String]] = [:]
        for row in rawStories {
            if let sid = row["site_id"] as? String,
               let lang = row["language"] as? String,
               let st = row["story"] as? String {
                storiesBySite[sid, default: [:]][lang] = st
            }
        }

        var imagesBySite: [String: [SiteImageItem]] = [:]
        for row in rawImages {
            guard let id = row["id"] as? String,
                  let sid = row["site_id"] as? String,
                  let path = row["path"] as? String else { continue }
            let item = SiteImageItem(
                id: id,
                siteId: sid,
                path: path,
                sortOrder: row["sort_order"] as? Int ?? 0,
                isCover: row["is_cover"] as? Bool ?? false,
                altTexts: row["alt_text"] as? [String: String] ?? [:],
                author: row["author"] as? String ?? "",
                license: row["license"] as? String ?? "",
                reviewStatus: row["review_status"] as? String ?? "approved"
            )
            if item.isApprovedAndDisplayable {
                imagesBySite[sid, default: []].append(item)
            }
        }

        return rawSites.enumerated().compactMap { idx, row in
            guard let id = row["id"] as? String,
                  let slug = row["slug"] as? String,
                  let lat = row["lat"] as? Double,
                  let lng = row["lng"] as? Double else { return nil }

            let nameMap = row["name"] as? [String: String] ?? [:]
            let defaultName = nameMap["es"] ?? slug
            let sums = summariesBySite[id] ?? [:]
            let stors = storiesBySite[id] ?? [:]

            return HeritageSite(
                id: id,
                catalogNumber: String(format: "%02d", idx + 1),
                slug: slug,
                name: defaultName,
                architect: row["architect"] as? String ?? "Autor documentado",
                style: row["style"] as? String ?? "Patrimonio histórico",
                address: row["address"] as? String ?? (row["city"] as? String ?? "Reus"),
                city: row["city"] as? String ?? "Reus",
                lat: lat,
                lng: lng,
                isFlagship: row["is_flagship"] as? Bool ?? false,
                summary: sums["es"] ?? "",
                fullStory: stors["es"] ?? sums["es"] ?? "",
                audioDurationSeconds: 260,
                previewDurationSeconds: 60,
                sourceRefs: "Patrimonio catalogado · Mirador",
                localizedNames: nameMap,
                localizedSummaries: sums,
                localizedStories: stors,
                images: imagesBySite[id] ?? []
            )
        }
    }

    // MARK: - Edge Functions: Audio firmado, Reporte contenido, Borrado RGPD y Verificación StoreKit

    func requestSignedAudioURL(
        accessToken: String,
        siteId: String,
        siteSlug: String,
        language: String,
        kind: String
    ) async throws -> URL {
        let req = try makeRequest(
            path: "functions/v1/get-audio-url",
            method: "POST",
            bearerToken: accessToken,
            jsonBody: [
                "site_id": siteId,
                "site_slug": siteSlug,
                "language": language,
                "kind": kind
            ]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.serverError("Error de red al solicitar audioguía")
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200...299).contains(http.statusCode),
              let urlStr = (json["signed_url"] as? String) ?? (json["url"] as? String),
              let url = URL(string: urlStr) else {
            throw SupabaseError.serverError(json["error"] as? String ?? "No autorizado para este audio")
        }
        return url
    }

    func submitContentReport(
        accessToken: String,
        userId: String,
        siteId: String,
        language: String,
        reason: String,
        details: String
    ) async throws {
        let req = try makeRequest(
            path: "rest/v1/content_reports",
            method: "POST",
            bearerToken: accessToken,
            jsonBody: [
                "user_id": userId,
                "site_id": siteId,
                "language": language,
                "reason": reason,
                "details": details
            ]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "No se pudo enviar el reporte")
        }
    }

    func verifyStoreKitTransaction(
        accessToken: String,
        productId: String,
        transactionId: UInt64,
        originalTransactionId: UInt64,
        signedJWS: String
    ) async throws {
        let req = try makeRequest(
            path: "functions/v1/verify-ios-subscription",
            method: "POST",
            bearerToken: accessToken,
            jsonBody: [
                "product_id": productId,
                "transaction_id": String(transactionId),
                "original_transaction_id": String(originalTransactionId),
                "jws_representation": signedJWS
            ]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "No se pudo verificar la suscripción")
        }
    }

    func deleteAccount(accessToken: String) async throws {
        let req = try makeRequest(
            path: "functions/v1/delete-account",
            method: "POST",
            bearerToken: accessToken,
            jsonBody: [:]
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseError.serverError(extractErrorMessage(from: data) ?? "Error al eliminar cuenta")
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["msg"] as? String) ?? (obj["message"] as? String) ?? (obj["error_description"] as? String) ?? (obj["error"] as? String)
    }
}
