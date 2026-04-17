import SwiftUI

// MARK: - Typography Tokens

extension AppTheme {
    /// Typography tokens — macOS-native type scale
    ///
    /// Scale: pageTitle(26) > sectionTitle(17) > cardTitle(15) > heading(13 bold) >
    ///        body(13) > bodySecondary(12) > label(12 medium) > caption(12) > detail(11)
    ///
    /// Minimum readable text: detail (11pt). Use detail only for
    /// supplementary monospaced metadata (timestamps, IDs, byte counts).
    enum Typography {
        // --- Display tier ---
        /// 26pt — empty-state hero icons, feature illustrations
        static let pageTitle: Font = .largeTitle
        /// 17pt — page-level headings, section titles
        static let sectionTitle: Font = .title2
        /// 15pt — card/panel titles, dialog headings
        static let cardTitle: Font = .title3

        // --- Content tier ---
        /// 13pt bold — inline headings, panel headers
        static let heading: Font = .headline
        /// 13pt — body copy, form fields, primary content
        static let body: Font = .body
        /// 12pt — secondary descriptions, callout text
        static let bodySecondary: Font = .callout

        // --- Support tier --- (bumped +1pt for macOS readability)
        /// 12pt medium — form labels, filter chips, secondary info
        static let label: Font = .system(size: 12, weight: .medium)
        /// 12pt — tertiary metadata, timestamps, badge text
        static let caption: Font = .system(size: 12)
        /// 11pt — technical detail only: API paths, hashes, stream output
        static let detail: Font = .system(size: 11)

        // --- Icon tier (10pt minimum exempt — non-textual) ---
        /// 9pt — compact badge icons, inline indicators
        static let iconSmall: Font = .system(size: 9)
        /// 10pt — standard inline icons
        static let iconMedium: Font = .system(size: 10)

        // --- Graph tier (compact visualization) ---
        /// 9pt — graph node micro-detail, smallest readable text in graphs
        static let graphDetail: Font = .system(size: 9)
        /// 10pt — graph node captions, badge text in graphs
        static let graphCaption: Font = .system(size: 10)
        /// 11pt — graph node labels, section headers in graphs
        static let graphLabel: Font = .system(size: 11)
    }
}

struct ThemePalette {
    let appBackgroundStart: Color
    let appBackgroundMid: Color
    let appBackgroundEnd: Color

    let surfacePrimary: Color
    let surfaceSecondary: Color
    let surfaceSubtle: Color

    let borderSubtle: Color
    let shadowColor: Color

    let accentPrimary: Color
    let accentPrimaryPressed: Color
    let accentSoft: Color

    let selectionFill: Color
    let neutralSoftFill: Color
    let neutralBadgeFill: Color

    let infoSoftFill: Color
    let warningSoftFill: Color
    let criticalSoftFill: Color

    let positiveAccent: Color
    let warningAccent: Color
    let criticalAccent: Color

    /// Text foreground tokens — 4-tier hierarchy
    ///
    /// 판단 기준: "이 텍스트가 사라지면 사용자가 혼란스러운가?"
    ///
    /// `foregroundPrimary`   — 사용자가 읽고 판단하는 콘텐츠
    ///                         (스펙 내용, 전문가 의견, 오류 메시지, 추론, 비즈니스 규칙)
    /// `foregroundSecondary` — 보조 설명, 요약, briefDescription
    ///                         (부연 설명, 캡션, 수정 노트)
    /// `foregroundTertiary`  — 메타데이터, 레이블, 수치
    ///                         (타임스탬프, 에이전트명, 폼 레이블, 카운트 배지)
    /// `foregroundMuted`     — 장식/비활성 요소
    ///                         (쉐브론, 불릿, 구분선, 플레이스홀더, disabled)
    let foregroundPrimary: Color
    let foregroundSecondary: Color
    let foregroundTertiary: Color
    let foregroundMuted: Color
}

enum AppTheme {
    static let light = ThemePalette(
        appBackgroundStart: Color.blue.opacity(0.06),
        appBackgroundMid: Color.green.opacity(0.04),
        appBackgroundEnd: Color(nsColor: .windowBackgroundColor),
        surfacePrimary: .white,
        surfaceSecondary: Color.white.opacity(0.96),
        surfaceSubtle: Color.black.opacity(0.05),
        borderSubtle: Color.black.opacity(0.12),
        shadowColor: Color.black.opacity(0.08),
        accentPrimary: Color.blue,
        accentPrimaryPressed: Color.blue.opacity(0.7),
        accentSoft: Color.blue.opacity(0.12),
        selectionFill: Color.blue.opacity(0.12),
        neutralSoftFill: Color.primary.opacity(0.06),
        neutralBadgeFill: .white,
        infoSoftFill: Color.blue.opacity(0.10),
        warningSoftFill: Color.orange.opacity(0.12),
        criticalSoftFill: Color.red.opacity(0.12),
        positiveAccent: Color.green,
        warningAccent: Color.orange,
        criticalAccent: Color.red,
        foregroundPrimary: Color(nsColor: .labelColor),
        foregroundSecondary: Color(nsColor: .secondaryLabelColor),
        foregroundTertiary: Color(nsColor: .tertiaryLabelColor),
        foregroundMuted: Color(nsColor: .quaternaryLabelColor)
    )

    static let dark = ThemePalette(
        appBackgroundStart: Color.blue.opacity(0.08),
        appBackgroundMid: Color.green.opacity(0.05),
        appBackgroundEnd: Color(nsColor: .windowBackgroundColor),
        surfacePrimary: Color(white: 0.16),
        surfaceSecondary: Color(white: 0.14),
        surfaceSubtle: Color.white.opacity(0.07),
        borderSubtle: Color.white.opacity(0.16),
        shadowColor: Color.black.opacity(0.25),
        accentPrimary: Color.blue,
        accentPrimaryPressed: Color.blue.opacity(0.7),
        accentSoft: Color.blue.opacity(0.15),
        selectionFill: Color.blue.opacity(0.15),
        neutralSoftFill: Color.white.opacity(0.10),
        neutralBadgeFill: Color(white: 0.22),
        infoSoftFill: Color.blue.opacity(0.15),
        warningSoftFill: Color.orange.opacity(0.18),
        criticalSoftFill: Color.red.opacity(0.18),
        positiveAccent: Color.green,
        warningAccent: Color.orange,
        criticalAccent: Color.red,
        foregroundPrimary: Color(nsColor: .labelColor),
        foregroundSecondary: Color(nsColor: .secondaryLabelColor),
        foregroundTertiary: Color(nsColor: .tertiaryLabelColor),
        foregroundMuted: Color(nsColor: .quaternaryLabelColor)
    )
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemePalette = AppTheme.light
}

extension EnvironmentValues {
    var theme: ThemePalette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Theme Injector

struct ThemeInjector<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.theme, colorScheme == .dark ? AppTheme.dark : AppTheme.light)
    }
}

// MARK: - Gradient

extension ThemePalette {
    var windowBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [appBackgroundStart, appBackgroundMid, appBackgroundEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Window Background

struct WindowBackgroundStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        ZStack {
            theme.windowBackgroundGradient
                .ignoresSafeArea()
            content
        }
    }
}

extension View {
    func laoWindowBackground() -> some View {
        modifier(WindowBackgroundStyle())
    }
}

// MARK: - Design Tokens

extension AppTheme {
    /// Corner radius tokens — 4-tier system for macOS-native density
    enum Radius {
        /// 4pt — micro elements, toolbar toggles, inline code badges
        static let xs: CGFloat = 4
        /// 6pt — buttons, inputs, small controls
        static let small: CGFloat = 6
        /// 10pt — cards, panels, banners
        static let medium: CGFloat = 10
        /// 14pt — modals, sheets, large containers
        static let large: CGFloat = 14
    }

    /// Spacing tokens — 4pt grid
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Sheet width tokens — standardized form sheet sizes
    enum SheetWidth {
        /// 380pt — simple dialogs (1-2 fields)
        static let compact: CGFloat = 380
        /// 430pt — standard CRUD forms
        static let standard: CGFloat = 430
        /// 480pt — text-heavy creation forms
        static let wide: CGFloat = 480
    }
}
