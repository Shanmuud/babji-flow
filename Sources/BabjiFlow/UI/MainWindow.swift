import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, dictionary, style, notetaker, settings
    var id: String { rawValue }
    var label: String { switch self { case .home: "Insights"; case .dictionary: "Dictionary"; case .style: "Style"; case .notetaker: "Notetaker"; case .settings: "Settings" } }
    var icon: String { switch self { case .home: "waveform"; case .dictionary: "book"; case .style: "textformat"; case .notetaker: "doc.text"; case .settings: "gearshape" } }
}

final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var page: Page = .home
}

struct MainWindow: View {
    @AppStorage("onboardingCompleteV2") private var onboardingComplete = false
    @ObservedObject var nav = Navigation.shared
    var body: some View {
        if !onboardingComplete { OnboardingView() } else { workspace }
    }
    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    BabjiAvatar(mood: .happy, size: 26)
                    Text("Babji Flow").font(.system(size: 15, weight: .semibold, design: .rounded))
                }.padding(.bottom, 14).padding(.horizontal, 6)
                ForEach(Page.allCases) { p in
                    Button { nav.page = p } label: {
                        HStack(spacing: 8) { Image(systemName: p.icon).frame(width: 18); Text(p.label).font(.system(size: 13, weight: nav.page == p ? .semibold : .regular)) }
                            .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(nav.page == p ? Theme.panel : .clear).clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(nav.page == p ? Theme.line : .clear))
                            .shadow(color: .black.opacity(nav.page == p ? 0.04 : 0), radius: 4, y: 1)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(14).frame(width: 190).background(Theme.bg)
            Divider()
            Group {
                switch nav.page {
                case .home: HomeView()
                case .dictionary: DictionaryView()
                case .style: StyleView()
                case .notetaker: NotetakerView()
                case .settings: SettingsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        }.frame(minWidth: 980, minHeight: 640)
    }
}
