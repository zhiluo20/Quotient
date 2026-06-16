# Quotient

[简体中文](README.md) · **English**

A macOS desktop widget that shows the remaining quota of your local **Codex**, **Claude Code**, and **Gemini** as red / yellow / green LEDs — so you can tell your usage at a glance without opening a terminal. At most two services are shown at once; pick any combination in Settings.

## Screenshots

**Liquid-glass floating panel** — pin on top, drag anywhere; controls appear on hover (pin / settings / refresh / hide / quit):

<img src="screenshot/main-panel.png" width="440" alt="Floating panel">

**Native desktop widget** — sits on the desktop like Calendar or Weather; in full-color mode the LEDs and bars are tinted by remaining quota:

<img src="screenshot/desktop-widget.png" width="600" alt="Desktop widget (full color)">

In the desktop **monochrome (frosted) mode**, bars automatically switch to an opacity-contrast scheme so they stay readable:

<img src="screenshot/widget-monochrome.png" width="420" alt="Desktop widget (monochrome)">

**Widget gallery** — right-click the desktop → "Edit Widgets" → search "Quotient"; small and medium sizes are available:

<img src="screenshot/widget-gallery.png" width="600" alt="Widget gallery">

## Features

- 🟢 **Traffic-light quota** — green when ≥ 10% remains; yellow when 0 < remaining < 10%; red at 0.
- 🪟 **Liquid-glass panel** — native macOS 26 Liquid Glass (`glassEffect`), with the same two-column layout and corner radius as system widgets; draggable, position remembered.
- 📌 **Pin / hide** — the pin button toggles always-on-top; the ➖ button hides the panel, and you can restore it anytime from the menu-bar LED menu (the dot's color is the overall quota state).
- ⚙️ **Standard menu & settings** — the menu-bar menu has "About Quotient" (standard About panel: version, author Zhi Luo, built with the help of Claude Code) and "Settings…". Options:
  - **Show services** (max two): Codex only / Claude only / Gemini only, or Codex+Claude / Codex+Gemini / Claude+Gemini — applies to both the panel and the desktop widget;
  - **Language**: match system (default) / 简体中文 / English.
- 🔄 **Auto refresh** — Codex is read from local files every minute; Claude / Gemini are fetched every 5 minutes. It refreshes again right after each reset time, and windows past their reset show as 100%. When the Claude / Gemini access token expires, it is silently refreshed via the local refresh token (no re-login). When offline, the last result is kept and tagged with its "as of" time.
- 🔐 **Privacy-friendly**:
  - **Codex** quota comes from the `rate_limits` snapshots the CLI itself records in `~/.codex/sessions/**/rollout-*.jsonl` — **fully offline**, never touching `auth.json`.
  - **Claude** quota reuses Claude Code's existing login (keychain `Claude Code-credentials` or `~/.claude/.credentials.json`) and calls Anthropic's official `api.anthropic.com/api/oauth/usage` endpoint.
  - **Gemini** quota reuses Gemini CLI's login (`~/.gemini/oauth_creds.json`) and calls Code Assist's `retrieveUserQuota` endpoint (the same source as Gemini CLI's `/status`), showing the remaining fraction per model family (Pro / Flash / Flash-Lite).
  - All tokens are used in memory only, for the quota requests and token refresh; after refresh they are written back to their original store to stay in sync with each CLI — **never saved elsewhere, never displayed, never sent to any third party**.

## Two display forms

1. **Liquid-glass floating panel** (the host app itself): pinnable, refreshes by the minute, controls appear on hover.
2. **System desktop widget** (WidgetKit extension): right-click the desktop → "Edit Widgets" → search "Quotient"; small and medium sizes, usable on the desktop and in Notification Center. In desktop monochrome rendering mode, bars switch to an opacity-contrast scheme.

The host app fetches all data and writes it to an App Group container (`snapshot.json` — percentages and reset times only, never any credentials), then asks the system to reload the widget. While the host app runs, the widget is near-real-time; after the host quits, the widget refreshes on the system budget (~15 min) and turns green automatically at reset times. Adding the host app as a login item is recommended.

## Build & release

Requires macOS 15+, Xcode, XcodeGen (`brew install xcodegen`), and an Apple Development signing certificate (the widget extension must be genuinely signed; the Team ID goes in `project.yml` and the App Group ID in `Snapshot.swift` — note the Team ID is the certificate's OU field, not the name in parentheses; replace it with your own Team ID when cloning). Liquid Glass requires macOS 26.

```sh
./build.sh                # builds dist/Quotient.app and packages dist/Quotient-1.0.0.zip
./Scripts/make_icon.sh    # (optional) regenerate Resources/AppIcon.icns
open dist/Quotient.app
```

The app runs without a Dock icon (a menu-bar LED menu is provided); quit from the menu or the panel's ✕. The widget is registered in the gallery only after the first launch.

> Distribution note: it is currently signed with an Apple Development certificate, so it runs only on the developer's own/registered devices. Public distribution requires a paid developer account's Developer ID certificate plus notarization — change `CODE_SIGN_IDENTITY` in `project.yml` to `Developer ID Application` and run `xcrun notarytool`.

## Acknowledgements

Inspired by [xicunwus2025-sys/codex-led-widget](https://github.com/xicunwus2025-sys/codex-led-widget) — the traffic-light quota idea comes from that project.

## License

[MIT](LICENSE) © 2026 Zhi Luo

## Project layout

```
Sources/
  Shared/   models, bilingual strings, Codex/Claude/Gemini readers, shared views, snapshot
  App/      floating-panel host (NSPanel + menu-bar menu + settings window + refresh scheduler)
  Widget/   WidgetKit extension (TimelineProvider + small/medium views)
Scripts/    icon generation script
Resources/  AppIcon.icns
project.yml XcodeGen project definition (two targets, entitlements, App Group)
```
