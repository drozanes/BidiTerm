import Foundation

public enum PromptStyle: String, CaseIterable, Codable {
    case styledUserHost = "styled_user_host"
    case warpTwoLine = "warp_two_line"
    case warpSingleLine = "warp_single_line"
    case minimalist = "minimalist"
    case defaultMacOS = "default_macos"

    public var displayName: String {
        switch self {
        case .styledUserHost:
            return "Styled User & Host with Colors (drozanes@Mac ~/Dev ❯)"
        case .warpTwoLine:
            return "Warp Two-Line Block (~/Dev git:(main)\n❯ )"
        case .warpSingleLine:
            return "Warp Single-Line (~/Dev git:(main) ❯ )"
        case .minimalist:
            return "Minimalist Arrow (~/Dev ❯ )"
        case .defaultMacOS:
            return "Default macOS (%n@%m %1~ %)"
        }
    }

    public var zshPromptDefinition: String {
        switch self {
        case .styledUserHost:
            // drozanes in purple, @ dimmed, Mac in cyan, path in bright blue, git in warm orange, ❯ in exit-code green/red
            return "PROMPT='%F{141}%n%f%F{242}@%f%F{69}%m%f %F{75}%~%f${vcs_info_msg_0_} %(?.%F{78}❯%f.%F{196}❯%f) '"
        case .warpTwoLine:
            return "PROMPT='%F{75}%~%f${vcs_info_msg_0_}\n%(?.%F{78}❯%f.%F{196}❯%f) '"
        case .warpSingleLine:
            return "PROMPT='%F{75}%~%f${vcs_info_msg_0_} %(?.%F{78}❯%f.%F{196}❯%f) '"
        case .minimalist:
            return "PROMPT='%F{75}%~%f %(?.%F{78}❯%f.%F{196}❯%f) '"
        case .defaultMacOS:
            return "PROMPT='%n@%m %1~ %# '"
        }
    }
}

public final class ShellIntegrationManager {
    public static let shared = ShellIntegrationManager()

    private let promptStyleKey = "BidiTermPromptStyle"

    private init() {}

    public var currentStyle: PromptStyle {
        get {
            if let saved = UserDefaults.standard.string(forKey: promptStyleKey),
               let style = PromptStyle(rawValue: saved) {
                return style
            }
            return .styledUserHost
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: promptStyleKey)
            _ = setupShellIntegration()
        }
    }

    /// Sets up the shell integration directory with proxy startup files and returns its path
    @discardableResult
    public func setupShellIntegration() -> String {
        let fileManager = FileManager.default

        // Standard Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let integrationDir = appSupport.appendingPathComponent("BidiTerm/shell/zsh", isDirectory: true)

        try? fileManager.createDirectory(at: integrationDir, withIntermediateDirectories: true, attributes: nil)

        // 1. .zshenv
        let zshenvContent = """
        # BidiTerm Shell Integration
        if [[ -f "$HOME/.zshenv" ]]; then
            source "$HOME/.zshenv"
        fi
        """
        try? zshenvContent.write(to: integrationDir.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)

        // 2. .zprofile
        let zprofileContent = """
        # BidiTerm Shell Integration
        if [[ -f "$HOME/.zprofile" ]]; then
            source "$HOME/.zprofile"
        fi
        """
        try? zprofileContent.write(to: integrationDir.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)

        // 3. .zlogin
        let zloginContent = """
        # BidiTerm Shell Integration
        if [[ -f "$HOME/.zlogin" ]]; then
            source "$HOME/.zlogin"
        fi
        """
        try? zloginContent.write(to: integrationDir.appendingPathComponent(".zlogin"), atomically: true, encoding: .utf8)

        // 4. .zshrc
        let style = self.currentStyle
        let zshrcContent = """
        # BidiTerm Shell Integration
        # Source user's personal ~/.zshrc first (preserves PATH, aliases, completions)
        if [[ -f "$HOME/.zshrc" ]]; then
            source "$HOME/.zshrc"
        fi

        # Restore ZDOTDIR to standard home directory for child subshells
        export ZDOTDIR="$HOME"

        # Apply BidiTerm Prompt Styling
        setopt PROMPT_SUBST
        autoload -Uz vcs_info
        zstyle ':vcs_info:*' enable git
        zstyle ':vcs_info:git:*' formats ' %F{214}git:(%b)%f'
        precmd() {
            vcs_info
        }

        \(style.zshPromptDefinition)
        """
        try? zshrcContent.write(to: integrationDir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        return integrationDir.path
    }
}
