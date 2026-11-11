import Foundation
import SwiftUI
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext


struct AppBadge: Identifiable, Hashable {
    let id: UUID = .init()
    let displayName: String
    let assetName: String
}

private func appBadges(_ styles: [(name: String, title: String)]) -> [AppBadge] {
    return styles.filter { !$0.name.hasSuffix("DuckyAppBadge") || SGSimpleSettings.shared.duckyAppIconAvailable }.map { AppBadge(displayName: $0.title, assetName: $0.name) }
}

func getAyuGramAppBadges() -> [AppBadge] {
    return appBadges(ayuGramAppBadgeStyles)
}

func getSwiftgramAppBadges() -> [AppBadge] {
    return appBadges(swiftgramAppBadgeStyles)
}

func getAvailableAppBadges() -> [AppBadge] {
    return getAyuGramAppBadges() + getSwiftgramAppBadges()
}
    
@available(iOS 14.0, *)
struct AppBadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lang) var lang: String
    
    @State var selectedBadge: AppBadge
    let availableAppBadges: [AppBadge] = getAvailableAppBadges()

    private enum Layout {
        static let cardCorner: CGFloat = 12
        static let imageHeight: CGFloat = 56
        static let columnSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 20
    }

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing), count: 2)
    }
    
    init(wrapperController: LegacyController?, context: AccountContext) {
        self.wrapperController = wrapperController
        self.context = context
        
        for badge in self.availableAppBadges {
            if badge.assetName == SGSimpleSettings.shared.customAppBadge {
                self._selectedBadge = State(initialValue: badge)
                return
            }
        }
        
        self._selectedBadge = State(initialValue: self.availableAppBadges.first!)
    }
    
    private func onSelectBadge(_ badge: AppBadge) {
        self.selectedBadge = badge
        if self.context.sharedContext.immediateSGStatus.status > 1 {
            DispatchQueue.main.async {
                SGSimpleSettings.shared.customAppBadge = badge.assetName
                self.context.sharedContext.mainWindow?.badgeView.image = ayuGramAppBadgeImage(style: badge.assetName, scale: 0)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            badgeSection(title: "AyuGram", badges: getAyuGramAppBadges())
            badgeSection(title: "Swiftgram", badges: getSwiftgramAppBadges())
                .padding(.bottom, 24)
        }
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func badgeSection(title: String, badges: [AppBadge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, Layout.horizontalPadding + 4)
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.columnSpacing) {
                ForEach(badges) { badge in
                    Button {
                        onSelectBadge(badge)
                    } label: {
                        VStack(spacing: 8) {
                            Image(uiImage: ayuGramAppBadgeImage(style: badge.assetName, scale: 3))
                                .resizable()
                                .scaledToFit()
                                .frame(height: Layout.imageHeight)
                                .accessibilityHidden(true)

                            Text(badge.displayName)
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
                        .cornerRadius(Layout.cardCorner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCorner)
                                .stroke(selectedBadge.assetName == badge.assetName ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
        }
        .padding(.top, 24)
    }
    
}

@available(iOS 14.0, *)
public func sgAppBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )

    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "AppBadge.Title".i18n(strings.baseLanguageCode)
    
    let swiftUIView = SGSwiftUIView<AppBadgeSettingsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            AppBadgeSettingsView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
