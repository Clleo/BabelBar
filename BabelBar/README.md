# BabelBar

Native macOS menu-bar translator (RU ⇄ EN) built with SwiftUI + AppKit.

> Display name: **BabelBar**. The internal Xcode project / target / scheme / bundle id stay
> `BabelBar` (renaming them would break signing and build paths), so commands below use
> the `BabelBar` scheme.

## Open & run
1. Open `BabelBar.xcodeproj` in Xcode 15+ (macOS 13+ deployment target).
2. Select the `BabelBar` scheme → Run (⌘R).
3. The app launches as a menu-bar agent (no Dock icon). Click the menu-bar icon to open the popover.

## First-time permissions
The app needs these macOS permissions (System Settings → Privacy & Security):
- **Accessibility** — to send synthetic ⌘C for "translate selection".
- **Screen Recording** — for the screenshot OCR hotkey.

## Hotkey (3.0.1)
- **Fn** — start live dictation; press again to stop. Hold-to-talk also works.
- All other shortcut assignments are cleared, including saved assignments from older versions.
- Manual typing, a click or a focus change ends the session. Press Fn to resume at the current cursor.
- In System Settings → Keyboard, set Fn to “Do Nothing”.
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
