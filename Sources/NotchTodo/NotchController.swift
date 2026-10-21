import AppKit
import SwiftUI

/// 无边框、不抢焦点、可接收键盘输入的浮层窗口
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// 界面状态。全部用 @Published，不依赖 SwiftUI 的 @State 宏。
@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var showSettings = false
    @Published var notchSize = CGSize(width: 200, height: 32)

    @Published var newTaskName = ""
    @Published var editingId: String?
    @Published var pendingDeleteId: String?
    @Published var draft = ""
    @Published var hoveredId: String?
    @Published var tokenInput = ""
    @Published var saving = false

    /// 折叠起来的分组（List ID），会记住
    @Published var collapsedGroups: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "collapsedGroups") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedGroups), forKey: "collapsedGroups") }
    }

    let expandedSize = CGSize(width: 480, height: 460)
    var collapsedSize: CGSize { CGSize(width: notchSize.width + 84, height: notchSize.height) }
}

@MainActor
final class NotchController {
    let panel = NotchPanel()
    let state = NotchState()
    let store: TaskStore
    private var timer: Timer?
    private var outsideSince: Date?

    init(store: TaskStore) {
        self.store = store
        let host = NSHostingView(rootView: NotchRootView(state: state, store: store))
        panel.contentView = host
        layout()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.layout() } }

        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        if !store.hasToken {
            state.showSettings = true
            state.pinned = true
            expand()
        }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func notchSize(for s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0,
           let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        return CGSize(width: 180, height: NSStatusBar.system.thickness)
    }

    func layout() {
        let s = screen
        state.notchSize = notchSize(for: s)
        let size = state.expandedSize
        let f = s.frame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private var isEditing: Bool {
        guard panel.isKeyWindow, let tv = panel.firstResponder as? NSTextView else { return false }
        return tv.isFieldEditor
    }

    /// 弹出菜单（如分组选择、状态选择）期间不要收起
    private var menuOpen: Bool {
        RunLoop.current.currentMode == .eventTracking
    }

    private func tick() {
        let p = NSEvent.mouseLocation
        let f = screen.frame

        if !state.expanded {
            let c = state.collapsedSize
            let hot = NSRect(x: f.midX - c.width / 2, y: f.maxY - c.height - 4,
                             width: c.width, height: c.height + 6)
            if hot.contains(p) { expand() }
            return
        }

        let e = state.expandedSize
        let area = NSRect(x: f.midX - e.width / 2, y: f.maxY - e.height,
                          width: e.width, height: e.height + 2).insetBy(dx: -12, dy: -12)
        if state.pinned || isEditing || menuOpen || area.contains(p) {
            outsideSince = nil
            return
        }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.35 { collapse() }
        } else {
            outsideSince = Date()
        }
    }

    func expand() {
        panel.ignoresMouseEvents = false
        state.expanded = true
        Task { @MainActor in await store.refresh() }
    }

    func collapse() {
        outsideSince = nil
        state.expanded = false
        state.hoveredId = nil
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}
