import SwiftUI
import RimesCore

// MARK: Gallery pieces, shared by the plugin and scheme screens

/// Where a gallery item stands. Downloading, adding (enabling) and disabling are separate, explicit steps.
enum GalleryStatus: Equatable {
    case notInstalled, installed, enabled
    var title: String {
        switch self {
        case .notInstalled: return L("未下载", "Not downloaded")
        case .installed: return L("已下载 · 未启用", "Downloaded · off")
        case .enabled: return L("已启用", "On")
        }
    }
    var tint: Color { self == .enabled ? .green : self == .installed ? .orange : .secondary }
}

struct GalleryMenuItem: Identifiable {
    var id: String { title }
    var title: String
    var destructive = false
    var action: () -> Void
}

/// One card of a gallery: an icon, a name and a line about it, its status and the one thing to do next.
struct GalleryCard: View {
    let symbol: String
    let title: String
    let tagline: String
    let status: GalleryStatus
    var detail: String? = nil
    let primaryTitle: String
    var primaryIsProminent = true
    var busy = false
    let primary: () -> Void
    /// Less common actions, such as removing the item.
    var menu: [GalleryMenuItem] = []
    /// A line of extra content under the status, such as a link to test the item.
    var accessory: AnyView? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.tint)
                    .frame(width: 40, height: 40).background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                if !menu.isEmpty {
                    Menu { ForEach(menu) { item in Button(item.title, role: item.destructive ? .destructive : nil, action: item.action) } } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                    }.accessibilityLabel(L("更多", "More"))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(1)
                Text(tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 5) {
                Circle().fill(status.tint).frame(width: 7, height: 7)
                Text(detail ?? status.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let accessory { accessory }
            Button(action: primary) {
                ZStack {
                    Text(primaryTitle).opacity(busy ? 0 : 1)
                    if busy { ProgressView() }
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(primaryIsProminent ? .accentColor : .secondary)
            .controlSize(.regular).disabled(busy)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
    }
}

struct GalleryGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12, alignment: .top)], spacing: 12, content: content)
    }
}

// MARK: Buffer plugins

/// What a plugin card says about it. The catalog carries names and versions only.
struct PluginGalleryInfo {
    let symbol: String
    let tagline: String
    static func info(for id: String) -> PluginGalleryInfo {
        switch id {
        case "builtin.apple-translation": return .init(symbol: "translate", tagline: L("边打边译，在设备上完成", "Translate as you type, on device"))
        case "builtin.ask": return .init(symbol: "questionmark.bubble", tagline: L("写下问题，得到简短的回答", "Write a question, get a short answer"))
        case "builtin.polisher": return .init(symbol: "wand.and.stars", tagline: L("润色文字，保持原意", "Polish writing, keep the meaning"))
        case "builtin.poem": return .init(symbol: "text.book.closed", tagline: L("藏头、律绝与现代诗", "Acrostics, classical and modern verse"))
        case "builtin.art": return .init(symbol: "square.grid.3x3.fill", tagline: L("用方块或字符画出图案", "Draw pictures with blocks or characters"))
        case "builtin.fly-chord-learning": return .init(symbol: "hand.draw", tagline: L("并击键盘与键位学习", "Chord keyboard and key learning"))
        default: return .init(symbol: "puzzlepiece.extension", tagline: L("官方插件", "Official plugin"))
        }
    }
}

struct PluginGalleryItem: Identifiable, Equatable {
    var id: String
    var title: String
    var version: String
    var status: GalleryStatus
    var bundled: Bool
}

/// The gallery itself, free of the store so it can be drawn and tested on its own.
struct PluginGalleryContent: View {
    let items: [PluginGalleryItem]
    var busy: String?
    let onPrimary: (PluginGalleryItem) -> Void
    let onUninstall: (PluginGalleryItem) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let on = items.filter { $0.status == .enabled }, rest = items.filter { $0.status != .enabled }
                if !on.isEmpty { section(L("已启用", "On"), on) }
                if !rest.isEmpty { section(on.isEmpty ? L("全部插件", "All plugins") : L("更多插件", "More plugins"), rest) }
                Text(L("下载后默认停用。点“添加”启用后，它才会出现在键盘上；停用或卸载都会保留你的配置、词库和文档。", "A download starts off. Tap Add to turn it on and it appears on the keyboard. Turning it off or removing it keeps your settings, dictionaries and documents."))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
    private func section(_ title: String, _ list: [PluginGalleryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            GalleryGrid {
                ForEach(list) { item in
                    let info = PluginGalleryInfo.info(for: item.id)
                    GalleryCard(symbol: info.symbol, title: item.title, tagline: info.tagline, status: item.status,
                                detail: item.status == .notInstalled ? item.version : "\(item.status.title) · \(item.version)",
                                primaryTitle: primaryTitle(item), primaryIsProminent: item.status != .enabled,
                                busy: busy == item.id, primary: { onPrimary(item) },
                                menu: item.status == .notInstalled ? [] : [GalleryMenuItem(title: L("卸载", "Remove"), destructive: true, action: { onUninstall(item) })])
                    .accessibilityIdentifier("gallery.plugin.\(item.id)")
                }
            }
        }
    }
    private func primaryTitle(_ item: PluginGalleryItem) -> String {
        switch item.status {
        case .notInstalled: return item.bundled ? L("恢复", "Restore") : L("下载", "Download")
        case .installed: return L("添加", "Add")
        case .enabled: return L("停用", "Turn off")
        }
    }
}

struct OfficialPluginsView: View {
    @State private var store: OfficialPluginStore?
    @State private var revision = 0
    @State private var installing: String?
    @State private var error: String?
    var body: some View {
        let _ = revision
        Group {
            if let store {
                PluginGalleryContent(items: items(in: store), busy: installing, onPrimary: { primary($0, in: store) }, onUninstall: { item in
                    change { try store.uninstall(item.id) }
                })
            } else { ProgressView() }
        }
        .navigationTitle(L("官方插件", "Official plugins"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { let store = try MobileOfficialPlugins.makeStore(); try store.bootstrap(); self.store = store }
            catch { self.error = error.localizedDescription }
        }
        .alert(L("插件操作未完成", "Plugin operation failed"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func items(in store: OfficialPluginStore) -> [PluginGalleryItem] {
        store.entries.map { entry in
            let state = store.state(entry.id)
            return PluginGalleryItem(id: entry.id, title: L(entry.nameZH, entry.nameEN), version: entry.version,
                                     status: state?.installed == true ? (state?.enabled == true ? .enabled : .installed) : .notInstalled,
                                     bundled: entry.platforms["ios"]?.distribution == "bundled")
        }
    }
    private func primary(_ item: PluginGalleryItem, in store: OfficialPluginStore) {
        switch item.status {
        case .notInstalled:
            installing = item.id
            Task { @MainActor in
                defer { installing = nil; revision += 1 }
                do { try await MobileOfficialPlugins.install(item.id, in: store) } catch { self.error = error.localizedDescription }
            }
        case .installed: change { try store.setEnabled(true, id: item.id) }
        case .enabled: change { try store.setEnabled(false, id: item.id) }
        }
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); revision += 1 } catch { self.error = error.localizedDescription }
    }
}
