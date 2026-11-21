import Foundation
import CoreLocation

/// Niveles de acceso decididos siempre por el servidor (`access_level_for(uid)` en Supabase)
enum AccessLevel: String, Codable, CaseIterable {
    case guest = "guest"           // Invitado: solo sitio emblemático (Casa Navàs), sin audios ni rutas
    case free = "free"             // Prueba gratuita (7 días): mapa completo, rutas, resumen y avance de audio
    case subscribed = "subscribed" // Suscriptor: historia completa, audio completo multilingüe, descarga sin conexión
    case none = "none"             // Periodo vencido o edad sin confirmar: solo planes y derechos RGPD
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case es = "es"
    case en = "en"
    case fr = "fr"
    // Idiomas preparados en BD para futuras fases (desactivados por defecto en selector activo): ca, it, ar (RTL)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        case .fr: return "Français"
        }
    }
}

enum SubscriptionPlanType: String, CaseIterable, Identifiable, Codable {
    case weekly = "mirador_weekly"
    case monthly = "mirador_monthly"
    case quarterly = "mirador_quarterly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Pase 1 semana"
        case .monthly: return "Suscripción 1 mes"
        case .quarterly: return "Suscripción 3 meses"
        }
    }

    var fallbackPriceLabel: String {
        switch self {
        case .weekly: return "3,99 € (IVA incl.)"
        case .monthly: return "7,99 € / mes (IVA incl.)"
        case .quarterly: return "17,99 € / trimestre (IVA incl.)"
        }
    }
}

struct SiteImageItem: Identifiable, Codable, Hashable {
    let id: String
    let siteId: String
    let path: String
    let sortOrder: Int
    let isCover: Bool
    let altTexts: [String: String]
    let author: String
    let license: String
    let reviewStatus: String

    var hasValidAttribution: Bool {
        !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isApprovedAndDisplayable: Bool {
        reviewStatus.lowercased() == "approved" && hasValidAttribution
    }

    func resolvedImageURL(baseImagesURL: String) -> URL? {
        guard isApprovedAndDisplayable else { return nil }
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return URL(string: path)
        }
        let trimmedBase = baseImagesURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, !trimmedPath.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/\(trimmedPath)")
    }

    func altText(for language: String, fallback: String) -> String {
        altTexts[language]?.nonEmpty ?? altTexts["es"]?.nonEmpty ?? fallback
    }
}

struct HeritageSite: Identifiable, Codable, Hashable {
    let id: String
    let catalogNumber: String
    let slug: String
    let name: String
    let architect: String
    let style: String
    let address: String
    let city: String
    let lat: Double
    let lng: Double
    let isFlagship: Bool
    let summary: String
    let fullStory: String
    let audioDurationSeconds: Int
    let previewDurationSeconds: Int
    let sourceRefs: String
    let localizedNames: [String: String]
    let localizedSummaries: [String: String]
    let localizedStories: [String: String]
    let images: [SiteImageItem]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func name(for language: String) -> String {
        localizedNames[language]?.nonEmpty ?? localizedNames["es"]?.nonEmpty ?? name
    }

    func summary(for language: String) -> String {
        localizedSummaries[language]?.nonEmpty ?? localizedSummaries["es"]?.nonEmpty ?? summary
    }

    func story(for language: String) -> String {
        localizedStories[language]?.nonEmpty ??
        localizedSummaries[language]?.nonEmpty ??
        localizedStories["es"]?.nonEmpty ??
        fullStory
    }

    var coverImage: SiteImageItem? {
        let approved = images.filter { $0.isApprovedAndDisplayable }.sorted { $0.sortOrder < $1.sortOrder }
        return approved.first(where: { $0.isCover }) ?? approved.first
    }
}

struct ConsentSettings: Codable, Equatable {
    var analyticsEnabled: Bool = false // RGPD: desactivado por defecto
    var marketingEnabled: Bool = false // RGPD: desactivado por defecto
}

struct UserSessionState: Codable {
    var accessToken: String?
    var refreshToken: String?
    var userId: String?
    var email: String?
    var displayName: String?
    var isGuest: Bool = true
    var isAgeConfirmed: Bool = false
    var language: AppLanguage = .es
    var countryCode: String = "ES"
    var accessLevel: AccessLevel = .guest
    var activePlanId: String?
    var autoRenew: Bool = true
    var validUntilISO: String?
    var consents: ConsentSettings = ConsentSettings()
    var favoriteSiteIds: Set<String> = []
    var savedRoutes: [[String]] = []
    var offlineDownloadedSlugs: Set<String> = []
    var proximityAlertsEnabled: Bool = true
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
