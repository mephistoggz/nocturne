import SwiftUI

private func rgb(_ hex: UInt32) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
}

private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
  Color(nsColor: NSColor(name: nil) { appearance in
    rgb(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
  })
}

struct ThemePalette {
  let canvas, panel, card, accent, detail: Color
}

enum PlayerTheme: String, CaseIterable, Identifiable {
  case classic, miku, aero, tokyo, jazz
  var id: String { rawValue }
  static let initial = Self.classic
  static let additionalThemes = allCases.filter { $0 != .classic }
  static let preference = "playerTheme"
  var name: String {
    switch self {
    case .classic: return L("Nocturne (Default)")
    case .miku: return "Hatsune Miku"
    case .aero: return "Frutiger Aero"
    case .tokyo: return "Tokyo Afterglow"
    case .jazz: return "Jazz Kissa"
    }
  }
  var palette: ThemePalette {
    switch self {
    case .classic:
      return .init(canvas: Color(nsColor: .textBackgroundColor), panel: Color(white: 0.15),
                   card: .primary.opacity(0.055), accent: .accentColor, detail: .secondary)
    case .miku:
      return .init(canvas: adaptive(0xE8F7F5, 0x081A20), panel: adaptive(0xCFEBEA, 0x102C35),
                   card: adaptive(0xF5FFFE, 0x15343D), accent: adaptive(0x006C68, 0x56EADB), detail: adaptive(0xAC2865, 0xFF86BC))
    case .aero:
      return .init(canvas: adaptive(0xE5F6FF, 0x0A293C), panel: adaptive(0xBEEAF5, 0x12445D),
                   card: adaptive(0xF3FEFF, 0x23536A), accent: adaptive(0x005988, 0x8FE4FF), detail: adaptive(0x387421, 0xA9E782))
    case .tokyo:
      return .init(canvas: adaptive(0xF6EBFA, 0x181224), panel: adaptive(0xE6D7EF, 0x2E1B3D),
                   card: adaptive(0xFEF7FF, 0x352243), accent: adaptive(0x99265C, 0xFF84B1), detail: adaptive(0x5540AB, 0xB09EFF))
    case .jazz:
      return .init(canvas: adaptive(0xF3EBDD, 0x211A16), panel: adaptive(0xE6D7C0, 0x30241C),
                   card: adaptive(0xFBF5EB, 0x3A2C23), accent: adaptive(0x834718, 0xECC088), detail: adaptive(0x8A3D2D, 0xE79877))
    }
  }
  var symbol: String {
    switch self {
    case .classic, .miku: return "waveform"
    case .aero: return "drop.fill"
    case .tokyo: return "building.2.fill"
    case .jazz: return "record.circle"
    }
  }
  var radius: CGFloat {
    switch self {
    case .classic: return 12
    case .miku: return 7
    case .aero: return 18
    case .tokyo: return 9
    case .jazz: return 10
    }
  }
  var design: Font.Design {
    switch self {
    case .miku, .aero: return .rounded
    case .classic, .tokyo: return .default
    case .jazz: return .serif
    }
  }
  func heading(_ size: CGFloat) -> Font {
    .system(size: size, weight: self == .jazz ? .semibold : .bold, design: design)
  }
  var heroBase: Color {
    let hex: UInt32
    switch self {
    case .classic: return Color(white: 0.095)
    case .miku: hex = 0x06252C
    case .aero: hex = 0xD8F5FA
    case .tokyo: hex = 0x21122E
    case .jazz: hex = 0x291A11
    }
    return Color(nsColor: rgb(hex))
  }
  var heroInk: Color { self == .aero ? Color(white: 0.09) : .white }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = PlayerTheme.initial }
extension EnvironmentValues {
  var playerTheme: PlayerTheme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}

struct ThemeScope: ViewModifier {
  @AppStorage(PlayerTheme.preference) private var theme = PlayerTheme.initial
  @AppStorage("appearance") private var appearance = "Dark"
  func body(content: Content) -> some View {
    content.environment(\.playerTheme, theme)
      .tint(theme == .classic ? nil : theme.palette.accent)
      .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
  }
}

enum ThemeImages {
  static let images: [PlayerTheme: NSImage] = {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle.main
    #endif
    return Dictionary(uniqueKeysWithValues: PlayerTheme.additionalThemes.compactMap { theme in
      guard let url = bundle.url(forResource: theme.rawValue, withExtension: "jpg", subdirectory: "ThemeArt"),
            let image = NSImage(contentsOf: url) else { return nil }
      return (theme, image)
    })
  }()
}

struct ThemeArtwork: View {
  let theme: PlayerTheme
  var body: some View {
    GeometryReader { geo in
      ZStack {
        theme.heroBase
        if let image = ThemeImages.images[theme] {
          Image(nsImage: image).resizable().scaledToFill()
        } else { ThemeMotif(theme: theme).foregroundStyle(theme.heroInk.opacity(0.3)) }
      }.frame(width: geo.size.width, height: geo.size.height).clipped()
    }.accessibilityHidden(true)
  }
}

// The small-scale motifs echo the key art across navigation and playback surfaces.
struct ThemeMotif: View {
  let theme: PlayerTheme
  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      guard w > 0, h > 0 else { return }
      let ink = GraphicsContext.Shading.foreground
      func line(_ a: CGPoint, _ b: CGPoint, _ width: CGFloat = 1) {
        var p = Path(); p.move(to: a); p.addLine(to: b); ctx.stroke(p, with: ink, lineWidth: width)
      }
      switch theme {
      case .classic: break
      case .miku:
        for i in 0..<26 {
          let bar = h * (0.18 + 0.65 * abs(sin(Double(i) * 0.81) * cos(Double(i) * 0.23)))
          ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i)*w/26, y: h-bar, width: max(1,w/42), height: bar),
                        cornerRadius: 1), with: ink)
        }
      case .aero:
        for (x,y,r) in [(0.15,0.70,0.26),(0.52,0.21,0.17),(0.76,0.76,0.39),(0.94,0.20,0.12)] {
          let radius = h*r
          let box = CGRect(x: w*x-radius,y: h*y-radius,width: 2*radius,height: 2*radius)
          ctx.stroke(Path(ellipseIn: box), with: ink, lineWidth: 1.5)
          ctx.fill(Path(ellipseIn: CGRect(x: box.minX+radius*0.35,y: box.minY+radius*0.3,
                                         width: radius*0.42,height: radius*0.23)), with: ink)
        }
      case .tokyo:
        for i in 0..<14 {
          let x = CGFloat(i)*w/14, top = h * (0.2 + 0.52 * abs(cos(Double(i)*1.8)))
          ctx.stroke(Path(CGRect(x:x,y:top,width:w/17,height:h-top+1)), with:ink,lineWidth:1)
          for y in stride(from:top+5,to:h,by:8) { line(.init(x:x+2,y:y),.init(x:x+w/26,y:y)) }
        }
      case .jazz:
        for i in 0..<14 {
          let r = h*(0.18+Double(i)*0.08)
          ctx.stroke(Path(ellipseIn: CGRect(x:w*0.62-r,y:h*0.82-r,width:2*r,height:2*r)),with:ink,lineWidth:i%4==0 ? 1.5 : 0.6)
        }
      }
    }.clipped().accessibilityHidden(true).allowsHitTesting(false)
  }
}

struct ThemePanel: View {
  @Environment(\.playerTheme) private var theme
  var classicBackground: AnyShapeStyle = AnyShapeStyle(Color.clear)
  var body: some View {
    if theme == .classic {
      Rectangle().fill(classicBackground).accessibilityHidden(true).allowsHitTesting(false)
    } else { themedPanel }
  }
  private var themedPanel: some View {
    GeometryReader { geo in
      ZStack(alignment: .bottomTrailing) {
        LinearGradient(colors: [theme.palette.card, theme.palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
        ThemeMotif(theme: theme).foregroundStyle(theme.palette.detail.opacity(theme == .miku ? 0.22 : 0.16))
          .frame(width: min(geo.size.width*0.54, 170), height: min(geo.size.height, 110))
        if theme == .aero {
          LinearGradient(colors: [.white.opacity(0.19), .clear], startPoint: .top, endPoint: .center)
        }
      }
    }.accessibilityHidden(true).allowsHitTesting(false)
  }
}

struct ThemeChooser: View {
  @AppStorage(PlayerTheme.preference) private var selection = PlayerTheme.initial
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Theme").font(.headline)
      Button { selection = .classic } label: {
        HStack {
          Image(systemName: "opticaldisc")
          Text(verbatim: PlayerTheme.classic.name)
          Spacer()
          if selection == .classic { Image(systemName: "checkmark.circle.fill") }
        }.padding(8).contentShape(Rectangle())
          .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
      }.buttonStyle(.plain)
        .accessibilityAddTraits(selection == .classic ? .isSelected : [])
        .accessibilityIdentifier("theme.classic")
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
        ForEach(PlayerTheme.additionalThemes) { theme in
          Button { selection = theme } label: {
            VStack(alignment: .leading, spacing: 4) {
              ThemeArtwork(theme: theme).frame(height: 46)
              HStack(spacing: 3) {
                Text(verbatim: theme.name).font(.system(size: 11, weight: .semibold, design: theme.design)).lineLimit(1)
                Spacer(minLength: 0)
                if selection == theme { Image(systemName:"checkmark.circle.fill").foregroundStyle(theme.palette.accent) }
              }.padding(.horizontal, 5).padding(.bottom, 5)
            }.background(theme.palette.card)
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selection == theme ? theme.palette.accent : .secondary.opacity(0.22),lineWidth: selection == theme ? 2 : 1) }
              .contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel(theme.name)
            .accessibilityAddTraits(selection == theme ? .isSelected : [])
            .accessibilityIdentifier("theme." + theme.rawValue)
        }
      }
    }.padding(.vertical, 4)
  }
}
