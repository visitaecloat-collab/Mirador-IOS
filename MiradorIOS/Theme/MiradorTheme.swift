import SwiftUI

/// Paleta oficial Mirador (estilo museo contemporáneo: esquinas rectas, líneas finas, numeración de catálogo)
enum MiradorColors {
    static let mossGreen = Color(hex: "#4F5D2F")       // Verde musgo - Acciones principales, estados activos
    static let mossGreenDark = Color(hex: "#384321")   // Verde musgo oscuro - Estado presionado
    static let gold = Color(hex: "#B8901F")            // Dorado - Destacados, progreso de audio, etiquetas suscriptor
    static let goldLight = Color(hex: "#E5C05B")       // Dorado claro
    static let crimson = Color(hex: "#C8102E")         // Rojo - Alertas importantes, etiquetas de catálogo, acciones críticas
    static let ink = Color(hex: "#1F2A12")             // Tinta - Títulos principales, texto, bordes de alto contraste
    static let cream = Color(hex: "#FAF8F0")           // Crema - Fondo principal de pantallas y tarjetas
    static let creamDarker = Color(hex: "#F1EEDF")     // Crema secundario - Superficies elevadas y rejillas
    static let greenishGrey = Color(hex: "#555C47")    // Gris verdoso - Subtítulos y metadatos
    static let line = Color(hex: "#D5D9C6")            // Línea - Divisores finos y bordes de tarjeta
    static let lineLight = Color(hex: "#E4E7DA")       // Línea suave
    static let white = Color.white
}

enum MiradorTypography {
    static let catalogTag = Font.system(size: 11, weight: .bold, design: .monospaced)
    static let headlineLarge = Font.system(size: 30, weight: .heavy, design: .default)
    static let headlineMedium = Font.system(size: 24, weight: .bold, design: .default)
    static let headlineSmall = Font.system(size: 20, weight: .bold, design: .default)
    static let titleLarge = Font.system(size: 19, weight: .bold, design: .default)
    static let titleMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
    static let labelLarge = Font.system(size: 14, weight: .bold, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .bold, design: .default)
}

/// Contenedor editorial con esquinas estrictamente rectas (0 pt) y borde fino de 1 pt
struct MuseumCardModifier: ViewModifier {
    var background: Color = MiradorColors.cream
    var borderColor: Color = MiradorColors.line
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: lineWidth)
            )
    }
}

struct MuseumPrimaryButtonStyle: ButtonStyle {
    var background: Color = MiradorColors.mossGreen
    var foreground: Color = MiradorColors.cream

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MiradorTypography.labelLarge)
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? MiradorColors.mossGreenDark : background)
    }
}

struct MuseumOutlinedButtonStyle: ButtonStyle {
    var borderColor: Color = MiradorColors.ink
    var foreground: Color = MiradorColors.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MiradorTypography.labelLarge)
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? MiradorColors.creamDarker : MiradorColors.cream)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func museumCard(
        background: Color = MiradorColors.cream,
        borderColor: Color = MiradorColors.line,
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(MuseumCardModifier(background: background, borderColor: borderColor, lineWidth: lineWidth))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
