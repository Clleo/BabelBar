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

## Hotkeys
- `⌥ + Space` — open BabelBar
- `⌘ + C + C` (double Cmd-C) — translate the current selection
- `⇧ + ⌘ + 2` — capture a screen region, OCR it, translate
- `⌘ + Return` — translate the input field
- `Fn` — dictate, insert at cursor
- `Shift + Fn` — dictate, then translate the recognized text

## Translation API
Open **Settings (gear icon)** → API Settings. Choose a provider:
- **OpenAI** — `https://api.openai.com/v1`, model `gpt-4o-mini`
- **DeepSeek** — `https://api.deepseek.com/v1`, model `deepseek-chat`
- **Custom** — any OpenAI-compatible `/chat/completions` endpoint

Paste your API key. All settings (API key, providers, preferences) persist in `UserDefaults` — no password dialog.

## Architecture
- `AppDelegate` — `NSStatusItem` + detachable `NSPopover` (arrow hides when detached); pin = floating window level.
- `HotKeyManager` — Carbon global hotkeys + `NSEvent` global monitor for double ⌘C.
- `TranslationService` — OpenAI-compatible chat-completions client.
- `ScreenCapture` — `screencapture -i` + Vision OCR (`VNRecognizeTextRequest`, ru/en).
- `Transcriber` — Voice-to-text (WhisperKit local or Groq remote), model auto-management, audio ducking.
- `SettingsStore` — persisted preferences + API key (UserDefaults, no Keychain).
- `Views/` — `RootView`, `TranslatorView`, `SettingsView`, `Theme` (navy glassmorphism, dark default).

## Notes
The app runs **unsandboxed** (see `BabelBar.entitlements`) because it launches `screencapture`, posts synthetic key events, and registers global hotkeys.
