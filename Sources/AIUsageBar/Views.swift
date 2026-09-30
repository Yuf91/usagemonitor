import SwiftUI
import AppKit

enum Theme {
    static let secondary = Color(nsColor: NSColor(name: NSColor.Name("AIUsageSecondary")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.74, alpha: 1) : NSColor(white: 0.32, alpha: 1)
    })
}

/// Window-level frosted backdrop (behind-window blur) so the desktop shows through.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Soft orange/blue glows behind the glass so the blur has color to refract.
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                VisualEffectBackground()
                glow(.orange, scheme == .dark ? 0.35 : 0.28, at: UnitPoint(x: 0.1, y: 0.08), radius: 300)
                glow(.blue, scheme == .dark ? 0.35 : 0.24, at: UnitPoint(x: 0.95, y: 0.62), radius: 320)
                glow(.purple, scheme == .dark ? 0.20 : 0.14, at: UnitPoint(x: 0.3, y: 1.0), radius: 260)
            }
        }
    }
    private func glow(_ color: Color, _ opacity: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}

/// System Liquid Glass (NSGlassEffectView, macOS 26+). Looked up at runtime because the
/// installed SDK predates it; on older systems `isAvailable` is false and callers fall back.
struct LiquidGlassView: NSViewRepresentable {
    static let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type
    static var isAvailable: Bool { glassClass != nil }
    var cornerRadius: CGFloat
    /// NSGlassEffectView.Style: 0 = regular, 1 = clear (more see-through).
    var clear = false
    func makeNSView(context: Context) -> NSView {
        let view = Self.glassClass!.init(frame: .zero)
        apply(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { apply(view) }
    private func apply(_ view: NSView) {
        view.setValue(cornerRadius, forKey: "cornerRadius")
        view.setValue(clear ? 1 : 0, forKey: "style")
    }
}

/// Glass surface. `liquid` surfaces use system Liquid Glass when available; everything else
/// (and older macOS) uses the frosted fallback: translucent material, light-catching rim, soft shadow.
struct Glass: ViewModifier {
    var cornerRadius: CGFloat = 16
    /// nil = clear glass: no blur, only a faint tint over what's already frosted behind it.
    var material: Material? = .ultraThinMaterial
    var elevated = true
    var liquid = false
    var clear = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if liquid && LiquidGlassView.isAvailable {
            content.background(LiquidGlassView(cornerRadius: cornerRadius, clear: clear && !reduceTransparency))
        } else {
            frosted(content, shape)
        }
    }
    private func frosted(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background {
                if reduceTransparency { shape.fill(Color(nsColor: .controlBackgroundColor)) }
                else {
                    if let material { shape.fill(material).opacity(0.85) }
                    else { shape.fill(.white.opacity(scheme == .dark ? 0.05 : 0.22)) }
                    shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.04 : 0.15), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(scheme == .dark ? 0.25 : 0.65), .white.opacity(scheme == .dark ? 0.04 : 0.15), .black.opacity(scheme == .dark ? 0.2 : 0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(elevated ? (scheme == .dark ? 0.22 : 0.06) : 0), radius: 12, y: 5)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 16, material: Material? = .ultraThinMaterial, elevated: Bool = true, liquid: Bool = false, clear: Bool = false) -> some View {
        modifier(Glass(cornerRadius: cornerRadius, material: material, elevated: elevated, liquid: liquid, clear: clear))
    }
}

/// Circular glass icon button, keeps a 32pt hit area.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .glass(cornerRadius: 16, material: nil, elevated: false, liquid: true, clear: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    var openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("CLAUDE · CODEX · 額度監控").font(.system(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { store.refresh(force: true) } label: {
                    if store.loading { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                }.buttonStyle(GlassButtonStyle()).disabled(store.loading || store.preview)
                    .help("立即更新").accessibilityLabel("立即更新 Claude 與 Codex 額度")
            }.padding(20)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Provider.allCases) { ProviderCard(store: store, provider: $0) }
                }.padding(.horizontal, 16).padding(.vertical, 6)
            }.frame(maxHeight: 530)
            VStack(alignment: .leading, spacing: 8) {
                if let date = store.latestCapture {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                        Text("更新於 \(date.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        Text("每 \(Int(store.interval / 60)) 分鐘更新")
                    }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    Text("僅讀取額度，不會啟動 AI 對話").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Divider()
                HStack {
                    Button(action: openSettings) { Label("設定", systemImage: "gearshape") }
                    Spacer()
                    Button("結束") { NSApp.terminate(nil) }.keyboardShortcut("q")
                }.buttonStyle(.borderless).font(.system(size: 12))
            }.padding(14).glass(cornerRadius: 14, material: nil, elevated: false, liquid: true, clear: true).padding(12)
        }
        .frame(width: 390)
        .background(GlassBackdrop().ignoresSafeArea())
    }
}

struct ProviderCard: View {
    @ObservedObject var store: UsageStore
    let provider: Provider
    var state: ProviderState { store[provider] }
    var tint: Color { provider == .claude ? .orange : .blue }
    var body: some View {
        let stale = state.stale(maxAge: max(120, store.interval * 2 + 60))
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(provider.usageURL) } label: {
                    Image(systemName: provider == .claude ? "sparkle" : "terminal.fill").font(.system(size: 20)).foregroundStyle(tint).frame(width: 22, height: 22).padding(10).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25)))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain)
                    .onHover { inside in (inside ? NSCursor.pointingHand : NSCursor.arrow).set() }
                    .help("在瀏覽器開啟 \(provider.name) 用量頁面")
                    .accessibilityLabel("開啟 \(provider.name) 用量網頁")
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name).font(.system(size: 17, weight: .semibold))
                    Text(store.preview ? "示範模式" : state.snapshot?.plan ?? "訂閱額度").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(store.preview ? "示範" : state.loading ? "更新中" : state.failed ? "待連線" : state.snapshot == nil ? "未連接" : "已連接")
                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                    .glass(cornerRadius: 11, material: nil, elevated: false)
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.quotas) { quota in
                    QuotaView(quota: quota, stale: stale, tint: tint)
                }
                if !snapshot.credits.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.credits.enumerated()), id: \.element.id) { index, credit in
                            if index > 0 { Divider() }
                            CreditView(credit: credit)
                        }
                    }.padding(.horizontal, 12).glass(cornerRadius: 12, material: nil, elevated: false)
                }
                if stale {
                    Label("上次成功資料 · 目前可能已變動", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: state.loading ? "network" : "link.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.secondary)
                    Text(state.loading ? "正在讀取額度" : "連接你的 \(provider.name)").font(.system(size: 16, weight: .medium))
                    Text("使用本機 \(provider == .claude ? "Claude Code" : "Codex") 的登入狀態\n不需要 API key 或瀏覽器")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 25)
            }
            if state.failed || store.preview {
                Text(state.message).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glass(cornerRadius: 20, material: .ultraThinMaterial, liquid: true)
    }
}

struct CreditView: View {
    let credit: Credit
    func money(_ value: Double) -> String { value.formatted(.currency(code: credit.currency ?? "USD")) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(credit.title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let balance = credit.balance, let limit = credit.limit {
                    Text("剩餘 \(money(balance)) / \(money(limit))").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                } else if credit.balance == nil, credit.resetsAt == nil {
                    Text(credit.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            if let reset = credit.resetsAt {
                Text("\(reset.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())) \(credit.detail)")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else if credit.balance == nil {
                Text([credit.used.map { "本月已用 \(money($0))" }, credit.limit.map { "上限 \(money($0))" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct QuotaView: View {
    let quota: Quota
    let stale: Bool
    let tint: Color
    var accent: Color { (quota.remaining ?? 100) <= 10 ? .red : (quota.remaining ?? 100) <= 20 ? .orange : tint }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.title).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let remaining = quota.remaining {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("剩餘").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(remaining.formatted(.number.precision(.fractionLength(0...1)))).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("%").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    }
                } else { Text("未知").foregroundStyle(Theme.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    Capsule().fill(LinearGradient(colors: stale ? [.gray, .gray] : [accent.opacity(0.75), accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (quota.remaining ?? 0) / 100)
                        .shadow(color: (stale ? Color.gray : accent).opacity(0.45), radius: 4)
                }
            }.frame(height: 7)
                .accessibilityLabel("\(quota.title)剩餘額度")
                .accessibilityValue(quota.remaining.map { "\(Int($0))%" } ?? "未知")
            if let reset = quota.resetsAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(reset <= context.date ? "重置時間已到 · 等待查詢" : "\(reset.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())) 重置")
                    }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            } else { Text("重置時間尚未提供").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            if let remaining = quota.remaining, remaining <= 20 {
                Label("額度偏低", systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.primary)
            }
        }.padding(.vertical, 8)
    }
}

struct SettingsPanel: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { content.padding(24) }
            // Pinned outside the scroll view so the action stays reachable at any window height
            HStack { Spacer(); Button("立即更新") { store.refresh(force: true) }.disabled(store.loading) }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(.ultraThinMaterial)
        }
        .frame(width: 470).frame(minHeight: 320, maxHeight: .infinity)
        .background(GlassBackdrop().ignoresSafeArea())
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("讓用量一目了然").font(.system(size: 23, weight: .semibold))
                Text("AI Usage Bar · Claude 與 Codex").foregroundStyle(Theme.secondary)
            }
            GlassSection("外觀") {
                Picker("小工具外觀", selection: $store.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).padding(10)
            }
            GlassSection("選單列圖示") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(IconStyle.allCases) { style in
                        IconChoice(style: style, selected: store.iconStyle == style) { store.iconStyle = style }
                    }
                }.padding(6)
            }
            GlassSection("更新與提醒") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("自動更新", selection: $store.interval) {
                        Text("每 1 分鐘").tag(60.0); Text("每 5 分鐘").tag(300.0); Text("每 15 分鐘").tag(900.0)
                    }
                    Toggle("剩餘低於或等於 20%／10% 時通知", isOn: Binding(get: { store.notifications }, set: { store.enableNotifications($0) }))
                    Toggle("登入 Mac 時啟動", isOn: Binding(get: { store.launchAtLogin }, set: { store.toggleLaunchAtLogin($0) }))
                }.padding(10)
            }
            GlassSection("Codex 連線") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(CodexClient.executable(custom: store.customPath) ?? "尚未找到 Codex CLI").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                    HStack {
                        Button("選擇執行檔…") { store.chooseExecutable() }
                        Button("使用自動偵測") { store.customPath = ""; store.refresh(force: true) }
                    }
                    Text("使用 CLI 現有的 ChatGPT 訂閱登入。如果尚未登入，請在終端機執行：")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text("codex login").font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    if let account = store[.codex].snapshot?.account {
                        Text("目前帳號：\(account)").font(.system(size: 12)).textSelection(.enabled)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            GlassSection("Claude 連線") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ClaudeClient.executable() ?? "尚未找到 Claude Code").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                    Text("使用 Claude Code 現有的 Claude 訂閱登入（存於鑰匙圈），只讀取用量，不另外保存登入資料。如果尚未登入，請在終端機執行：")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("claude").font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    if let plan = store[.claude].snapshot?.plan {
                        Text("目前方案：\(plan)").font(.system(size: 12))
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !store.settingsMessage.isEmpty { Text(store.settingsMessage).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            Text("只儲存用量快照及偏好於本機。不讀取對話、不發送提示詞，也不自動購買、啟用 Usage credits 或重置額度。登入由 Claude Code 與 Codex 自行管理。")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Live animated preview of a menu-bar icon style; still when Reduce Motion is on.
struct IconChoice: View {
    let style: IconStyle
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 0.14)) { context in
                    let frames = style.frames
                    let index = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.14) % frames.count
                    Image(nsImage: frames[index]).renderingMode(.template).resizable().interpolation(.high)
                        .frame(width: 36, height: 24)
                }
                Text(style.label).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.18) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
            content.padding(6).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: 16, material: .ultraThinMaterial, elevated: false, liquid: true)
        }
    }
}
