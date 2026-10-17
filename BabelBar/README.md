# BabelBar

Native macOS menu-bar translator (RU ⇄ EN) built with SwiftUI + AppKit.

> Display name: **BabelBar**. The internal Xcode project / target / scheme / bundle id stay
> `BabelBar` (renaming them would break signing and build paths), so commands below use
> the `BabelBar` scheme.

## Open & run
1. Open `BabelBar.xcodeproj` in Xcode 15+ (macOS 13+ deployment target).
2. Select the `BabelBar` scheme → Run (⌘R).
3. The app launches as a menu-bar agent (no Dock icon). Click the menu-bar icon to open the popover.

For a local test build that immediately replaces and restarts `/Applications/BabelBar.app`,
run `./dev-run.command` from this directory (or double-click it in Finder). It builds
and verifies an Apple Development signed Release before stopping the running app.
If the build fails, the installed app keeps running. No DMG or version bump is needed.

## First-time permissions
The app needs these macOS permissions (System Settings → Privacy & Security):
- **Accessibility** — to send synthetic ⌘C for "translate selection".
- **Screen Recording** — for the screenshot OCR hotkey.

## Shortcuts
- In **Settings → Voice Input**, turn voice input on or off, then choose one dictation mode: **While speaking** streams text to the cursor, while **After phrase** inserts the recognized phrase after recording stops. Both modes use the same configurable shortcut. The microphone starts only when that shortcut is pressed.
- Click the shortcut badge to record modifiers. Hold the full combination and release it to save; use the × button or Delete to clear it. Dictation with translation has a separate optional shortcut in the same section.
- In **Settings → App**, set keyboard shortcuts for opening BabelBar, translating a selection, and translating a screenshot.
- **Fn** is the default dictation shortcut and can be changed or cleared. Press the assigned shortcut again to stop; hold-to-talk also works.
- Manual typing, a click or a focus change ends a live dictation session. Use its assigned shortcut to resume at the current cursor.
- If Fn is assigned, set it to “Do Nothing” in System Settings → Keyboard.
- Live dictation needs Microphone, Speech Recognition and Accessibility permissions. The target editor must expose its text and selection through Accessibility.

## Translation API
Open **Settings (gear icon)** → API Settings. Choose a provider:
- **OpenAI** — `https://api.openai.com/v1`, model `gpt-4o-mini`
- **DeepSeek** — `https://api.deepseek.com/v1`, model `deepseek-chat`
- **Custom** — any OpenAI-compatible `/chat/completions` endpoint

Paste your API key (stored in the macOS **Keychain**). Other settings persist in `UserDefaults`.

## Architecture
- `AppDelegate` — `NSStatusItem` + detachable `NSPopover` (arrow hides when detached); pin = floating window level.
- `HotKeyManager` — Carbon global hotkeys + `NSEvent` global monitor for double ⌘C.
- `TranslationService` — OpenAI-compatible chat-completions client.
- `ScreenCapture` — `screencapture -i` + Vision OCR (`VNRecognizeTextRequest`, ru/en).
- `Transcriber` — Voice-to-text (WhisperKit local or Groq remote), model auto-management, audio ducking.
- `Keychain` / `SettingsStore` — API keys in the Keychain, other preferences in `UserDefaults`.
- `Views/` — `RootView`, `TranslatorView`, `SettingsView`, `Theme` (navy glassmorphism, dark default).

## Notes
The app runs **unsandboxed** (see `BabelBar.entitlements`) because it launches `screencapture`, posts synthetic key events, and registers global hotkeys.
