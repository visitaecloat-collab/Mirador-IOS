import Foundation
import CoreLocation

@MainActor
final class MiradorAppState: ObservableObject {
    @Published var sites: [HeritageSite] = SeedReusData.sites
    @Published var session = UserSessionState()
    @Published var selectedTab: Int = 0
    @Published var selectedSite: HeritageSite?
    @Published var showAuthSheet: Bool = false
    @Published var showCameraSheet: Bool = false
    @Published var activeRouteSiteIds: [String] = []
    @Published var currentRouteStepIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var bannerMessage: String?

    let supabase = SupabaseService()
    let audioGuide = AudioGuideService()
    let locationService = LocationProximityService()
    let billing = StoreKitSubscriptionService()

    private let sessionStorageKey = "com.mirador.ios.session.v1"

    init() {
        loadSavedSession()
        locationService.configureSites(sites)
        locationService.alertsEnabled = session.proximityAlertsEnabled
    }

    func bootstrap() async {
        await billing.loadProducts()
        await syncRemoteCatalogAndSession()
    }

    func syncRemoteCatalogAndSession() async {
        if let token = session.accessToken, let uid = session.userId, SupabaseConfig.isConfigured {
            if let snapshot = try? await supabase.fetchServerAccessSnapshot(accessToken: token, userId: uid) {
                session.accessLevel = snapshot.accessLevel
                session.activePlanId = snapshot.activePlanId
                session.autoRenew = snapshot.autoRenew
                session.validUntilISO = snapshot.validUntilISO
                session.displayName = snapshot.displayName ?? session.displayName
                session.isAgeConfirmed = snapshot.isAgeConfirmed
                if let langCode = snapshot.language, let lang = AppLanguage(rawValue: langCode) {
                    session.language = lang
                }
            }
        } else if billing.activeProductId != nil {
            session.accessLevel = .subscribed
            session.activePlanId = billing.activeProductId
        }

        if SupabaseConfig.isConfigured {
            if let remoteSites = try? await supabase.fetchApprovedCatalog(bearerToken: session.accessToken),
               !remoteSites.isEmpty {
                self.sites = remoteSites
                self.locationService.configureSites(remoteSites)
            }
        }
        persistSession()
    }

    // MARK: - Acciones de Autenticación y RGPD

    func continueAsGuest() {
        session.isGuest = true
        session.accessToken = nil
        session.userId = nil
        session.accessLevel = .guest
        showAuthSheet = false
        persistSession()
    }

    func signIn(email: String, password: String) async throws {
        let dto = try await supabase.signInWithPassword(email: email, password: password)
        session.accessToken = dto.access_token
        session.refreshToken = dto.refresh_token
        session.userId = dto.user?.id ?? dto.id
        session.email = dto.user?.email ?? dto.email ?? email
        session.isGuest = false
        await syncRemoteCatalogAndSession()
        showAuthSheet = false
        persistSession()
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let dto = try await supabase.signUp(email: email, password: password, displayName: displayName)
        session.email = email
        session.displayName = displayName
        if let token = dto.access_token {
            session.accessToken = token
            session.refreshToken = dto.refresh_token
            session.userId = dto.user?.id ?? dto.id
            session.isGuest = false
            await syncRemoteCatalogAndSession()
            showAuthSheet = false
        }
        persistSession()
    }

    func verifyOtp(email: String, code: String) async throws {
        let dto = try await supabase.verifyEmailOtp(email: email, code: code)
        session.accessToken = dto.access_token
        session.refreshToken = dto.refresh_token
        session.userId = dto.user?.id ?? dto.id
        session.email = dto.user?.email ?? dto.email ?? email
        session.isGuest = false
        await syncRemoteCatalogAndSession()
        showAuthSheet = false
        persistSession()
    }

    func confirmAge(birthDate: Date) async -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let isoDate = formatter.string(from: birthDate)

        if let token = session.accessToken, SupabaseConfig.isConfigured {
            do {
                let serverLevel = try await supabase.confirmAgeOnServer(accessToken: token, birthDateISO: isoDate)
                session.accessLevel = serverLevel
                session.isAgeConfirmed = (serverLevel != .none)
                persistSession()
                return session.isAgeConfirmed
            } catch {
                bannerMessage = error.localizedDescription
                return false
            }
        }

        // Validación local de respaldo (>= 16 años)
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        if years < 16 {
            session.isAgeConfirmed = false
            session.accessLevel = .none
            persistSession()
            return false
        }
        session.isAgeConfirmed = true
        if session.accessLevel == .none {
            session.accessLevel = .free
        }
        persistSession()
        return true
    }

    func signOut() {
        audioGuide.stop()
        session = UserSessionState()
        session.accessLevel = .guest
        activeRouteSiteIds = []
        persistSession()
    }

    func deleteAccountCompletely() async {
        if let token = session.accessToken, SupabaseConfig.isConfigured {
            try? await supabase.deleteAccount(accessToken: token)
        }
        audioGuide.purgeAllEncryptedAudio()
        session = UserSessionState()
        session.accessLevel = .guest
        activeRouteSiteIds = []
        UserDefaults.standard.removeObject(forKey: sessionStorageKey)
    }

    // MARK: - Rutas automáticas y favoritos

    func generateAutoRoute(maxStops: Int = 4, maxRadiusMeters: Int = 2500) {
        guard session.accessLevel != .guest && session.accessLevel != .none else { return }
        let origin = locationService.userLocation ?? CLLocation(latitude: 41.15483, longitude: 1.10843)

        let sorted = sites.sorted { a, b in
            let dA = origin.distance(from: CLLocation(latitude: a.lat, longitude: a.lng))
            let dB = origin.distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
            return dA < dB
        }.filter {
            origin.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng)) <= Double(maxRadiusMeters)
        }

        let chosen = Array((sorted.isEmpty ? sites : sorted).prefix(maxStops))
        activeRouteSiteIds = chosen.map(\.id)
        currentRouteStepIndex = 0
    }

    func saveCurrentRoute() {
        guard !activeRouteSiteIds.isEmpty else { return }
        if !session.savedRoutes.contains(activeRouteSiteIds) {
            session.savedRoutes.append(activeRouteSiteIds)
            persistSession()
        }
    }

    func toggleFavorite(siteId: String) {
        if session.favoriteSiteIds.contains(siteId) {
            session.favoriteSiteIds.remove(siteId)
        } else {
            session.favoriteSiteIds.insert(siteId)
        }
        persistSession()
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "mirador" else { return }
        await syncRemoteCatalogAndSession()
    }

    func persistSession() {
        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: sessionStorageKey)
        }
    }

    private func loadSavedSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionStorageKey),
              let decoded = try? JSONDecoder().decode(UserSessionState.self, from: data) else {
            return
        }
        self.session = decoded
    }
}

enum SeedReusData {
    static let sites: [HeritageSite] = [
        HeritageSite(
            id: "site-casa-navas",
            catalogNumber: "01",
            slug: "casa-navas",
            name: "Casa Navàs",
            architect: "Lluís Domènech i Montaner",
            style: "Modernismo",
            address: "Plaça del Mercadal, 7",
            city: "Reus",
            lat: 41.15483,
            lng: 1.10843,
            isFlagship: true,
            summary: "Obra maestra del modernismo catalán en el centro del Mercadal de Reus, con vidrieras, mosaicos y mobiliario original conservado.",
            fullStory: "Encargada en 1901 por el comerciante textil Joaquim Navàs a Lluís Domènech i Montaner, Casa Navàs representa la síntesis total de las artes aplicadas del modernismo europeo: vitrales emplomados, esgrafiados florales, cerámica vidriada y carpintería diseñada al milímetro.",
            audioDurationSeconds: 275,
            previewDurationSeconds: 65,
            sourceRefs: "Ajuntament de Reus · Patrimoni Generalitat de Catalunya",
            localizedNames: ["es": "Casa Navàs", "en": "Casa Navàs", "fr": "Casa Navàs"],
            localizedSummaries: [
                "en": "Catalan Modernisme masterpiece on Plaça del Mercadal in Reus, preserving stained glass and original decorative arts.",
                "fr": "Chef-d'œuvre du modernisme catalan sur la place du Mercadal à Reus, conservant vitraux et arts décoratifs d'origine."
            ],
            localizedStories: [:],
            images: []
        ),
        HeritageSite(
            id: "site-casa-gasull",
            catalogNumber: "02",
            slug: "casa-gasull",
            name: "Casa Gasull",
            architect: "Lluís Domènech i Montaner",
            style: "Modernismo",
            address: "Carrer de Sant Joan, 29",
            city: "Reus",
            lat: 41.15627,
            lng: 1.10375,
            isFlagship: false,
            summary: "Edificio residencial y almacén de aceite proyectado por Domènech i Montaner con fachada de ladrillo visto y cerámica.",
            fullStory: "Construida entre 1911 y 1912 para la familia exportadora de aceite Gasull, combina funcionalidad industrial en planta baja con una vivienda señorial ornamentada con esgrafiados y cerámica esmaltada.",
            audioDurationSeconds: 230,
            previewDurationSeconds: 60,
            sourceRefs: "Ruta del Modernisme de Reus",
            localizedNames: ["es": "Casa Gasull", "en": "Casa Gasull", "fr": "Casa Gasull"],
            localizedSummaries: [:],
            localizedStories: [:],
            images: []
        ),
        HeritageSite(
            id: "site-casa-rull",
            catalogNumber: "03",
            slug: "casa-rull",
            name: "Casa Rull",
            architect: "Lluís Domènech i Montaner",
            style: "Modernismo",
            address: "Carrer de Sant Joan, 27",
            city: "Reus",
            lat: 41.15611,
            lng: 1.10389,
            isFlagship: false,
            summary: "Residencia modernista contigua a Casa Gasull, destacada por su equilibrio compositivo en piedra y ladrillo.",
            fullStory: "Encargada por el notario Pere Rull en 1900, muestra la vertiente más contenida y medievalista de Lluís Domènech i Montaner antes de su etapa más exuberante.",
            audioDurationSeconds: 195,
            previewDurationSeconds: 55,
            sourceRefs: "Patrimoni Cultural de Catalunya",
            localizedNames: ["es": "Casa Rull", "en": "Casa Rull", "fr": "Casa Rull"],
            localizedSummaries: [:],
            localizedStories: [:],
            images: []
        ),
        HeritageSite(
            id: "site-institut-pere-mata",
            catalogNumber: "04",
            slug: "institut-pere-mata",
            name: "Institut Pere Mata",
            architect: "Lluís Domènech i Montaner",
            style: "Modernismo",
            address: "Carretera de l'Institut Pere Mata, 1",
            city: "Reus",
            lat: 41.16694,
            lng: 1.08472,
            isFlagship: false,
            summary: "Conjunto pavillonario modernista que precedió al Hospital de Sant Pau de Barcelona.",
            fullStory: "Iniciado en 1897, el Institut Pere Mata constituye el gran laboratorio arquitectónico de Domènech i Montaner en Reus, organizando pabellones ajardinados bañados por luz natural y cerámica higiénica.",
            audioDurationSeconds: 310,
            previewDurationSeconds: 70,
            sourceRefs: "Generalitat de Catalunya · Ruta del Modernisme",
            localizedNames: ["es": "Institut Pere Mata", "en": "Institut Pere Mata", "fr": "Institut Pere Mata"],
            localizedSummaries: [:],
            localizedStories: [:],
            images: []
        ),
        HeritageSite(
            id: "site-palau-bofarull",
            catalogNumber: "05",
            slug: "palau-bofarull",
            name: "Palau Bofarull",
            architect: "Pere Blai / Reforma modernista",
            style: "Barroco / Neoclásico",
            address: "Carrer de Llovera, 15",
            city: "Reus",
            lat: 41.15658,
            lng: 1.10684,
            isFlagship: false,
            summary: "Palacio señorial del siglo XVIII con patio clasicista y salón noble decorado con pinturas históricas.",
            fullStory: "Edificado por la familia Bofarull en el siglo XVIII en el eje comercial de Llovera, conserva su fachada neoclásica y un salón principal adornado con frescos alegóricos.",
            audioDurationSeconds: 210,
            previewDurationSeconds: 60,
            sourceRefs: "Diputació de Tarragona",
            localizedNames: ["es": "Palau Bofarull", "en": "Bofarull Palace", "fr": "Palais Bofarull"],
            localizedSummaries: [:],
            localizedStories: [:],
            images: []
        ),
        HeritageSite(
            id: "site-campanar-sant-pere",
            catalogNumber: "06",
            slug: "campanar-sant-pere",
            name: "Campanar de Sant Pere",
            architect: "Benet Otger",
            style: "Gótico tardío",
            address: "Plaça de Sant Pere",
            city: "Reus",
            lat: 41.15422,
            lng: 1.10944,
            isFlagship: false,
            summary: "Torre campanario gótica del siglo XVI que corona la iglesia prioral de Sant Pere y el casco antiguo.",
            fullStory: "Levantado entre 1512 y 1569 por el maestro de obras Benet Otger, su silueta hexagonal de más de 60 metros constituye el hito vertical histórico de Reus.",
            audioDurationSeconds: 205,
            previewDurationSeconds: 55,
            sourceRefs: "Patrimoni Històric de Reus",
            localizedNames: ["es": "Campanar de Sant Pere", "en": "Sant Pere Bell Tower", "fr": "Clocher de Sant Pere"],
            localizedSummaries: [:],
            localizedStories: [:],
            images: []
        )
    ]
}
