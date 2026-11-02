import Foundation

public struct SavedTabState: Codable, Equatable {
    public let workingDirectory: String
    public let title: String

    public init(workingDirectory: String, title: String) {
        self.workingDirectory = workingDirectory
        self.title = title
    }
}

public struct SavedSession: Codable {
    public let tabs: [SavedTabState]
    public let activeIndex: Int
    public let savedAt: Date

    public init(tabs: [SavedTabState], activeIndex: Int, savedAt: Date = Date()) {
        self.tabs = tabs
        self.activeIndex = activeIndex
        self.savedAt = savedAt
    }
}

public final class TabSessionManager {
    public static let shared = TabSessionManager()

    private let sessionKey = "BidiTermSavedSession"
    private let restoreOnStartupKey = "BidiTermRestoreTabsOnStartup"
    private let recentlyClosedKey = "BidiTermRecentlyClosedTabs"

    private var recentlyClosedStack: [SavedTabState] = []

    private init() {
        loadRecentlyClosed()
    }

    /// User preference controlling whether previous session tabs are automatically restored on launch
    public var restoreOnStartup: Bool {
        get {
            if UserDefaults.standard.object(forKey: restoreOnStartupKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: restoreOnStartupKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: restoreOnStartupKey)
        }
    }

    // MARK: - Recently Closed Tabs (Cmd+Shift+T)

    public func pushClosedTab(workingDirectory: String, title: String) {
        let state = SavedTabState(workingDirectory: workingDirectory, title: title)
        recentlyClosedStack.append(state)
        // Keep up to 30 closed tabs in the restoration history
        if recentlyClosedStack.count > 30 {
            recentlyClosedStack.removeFirst()
        }
        saveRecentlyClosed()
    }

    public func popClosedTab() -> SavedTabState? {
        guard !recentlyClosedStack.isEmpty else { return nil }
        let state = recentlyClosedStack.removeLast()
        saveRecentlyClosed()
        return state
    }

    public func peekClosedTab() -> SavedTabState? {
        return recentlyClosedStack.last
    }

    public var hasRecentlyClosedTabs: Bool {
        return !recentlyClosedStack.isEmpty
    }

    private func saveRecentlyClosed() {
        if let data = try? JSONEncoder().encode(recentlyClosedStack) {
            UserDefaults.standard.set(data, forKey: recentlyClosedKey)
        }
    }

    private func loadRecentlyClosed() {
        if let data = UserDefaults.standard.data(forKey: recentlyClosedKey),
           let stack = try? JSONDecoder().decode([SavedTabState].self, from: data) {
            recentlyClosedStack = stack
        }
    }

    // MARK: - Session Persistence

    public func saveSession(tabs: [SavedTabState], activeIndex: Int) {
        guard !tabs.isEmpty else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        let session = SavedSession(tabs: tabs, activeIndex: max(0, min(activeIndex, tabs.count - 1)))
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    public func loadSavedSession() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else {
            return nil
        }
        return session
    }

    public func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
