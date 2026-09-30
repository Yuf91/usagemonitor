# AI Usage Bar

**English** · [繁體中文](README.zh-TW.md)

A tiny macOS menu-bar app that shows how much of your **Claude** and **Codex** (ChatGPT) subscription quota is left — without opening a browser. It reuses the logins your local Claude Code and Codex CLI already have, so there is no API key and no extra sign-in.

<p align="center">
  <img src="previews/light.png" width="320" alt="Light mode">
  <img src="previews/dark.png" width="320" alt="Dark mode">
</p>

> Unofficial. Not affiliated with or endorsed by Anthropic or OpenAI.

## Features

- **Claude** — session (5 h) and weekly remaining %, reset times, cloud credits (balance / expiry) and usage credits (status, spent this month, limit).
- **Codex** — every rate-limit bucket with remaining % and reset time.
- Six animated menu-bar icons to pick from — running cat, rocket, coffee, heartbeat, ghost, pinwheel. They speed up as your quota fills (and stand still with *Reduce Motion*).
- Auto refresh every 1 / 5 / 15 minutes; keeps the last good data and marks it stale on errors, with back-off.
- Optional notifications at 20 % and 10 % remaining; launch at login.
- Appearance: follow system, or force light / dark for this app only.
- Click the Claude / Codex icon to open the provider's usage page.
- Never sends prompts or spends quota to test anything.

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- For Claude: [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and logged in with a Claude subscription (`claude`)
- For Codex: [Codex CLI](https://github.com/openai/codex) installed and logged in with a ChatGPT subscription (`codex login`)

You only need the one(s) you use.

## Install

1. Download `AIUsageBar-x.y.z.zip` from [Releases](https://github.com/Yuf91/usagemonitor/releases/latest) and unzip it.
2. Move **AI Usage Bar.app** to `/Applications`.
3. The app is ad-hoc signed, not notarized, so macOS blocks it the first time. Either right-click the app → **Open** → **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/AI Usage Bar.app"
   ```
4. Launch it — a running cat appears in the menu bar. Click it to see your usage; ⚙︎ opens settings.

## Build from source

Requires Xcode or the Command Line Tools (Swift 5.9+).

```sh
git clone https://github.com/Yuf91/usagemonitor.git
cd usagemonitor
bash scripts/build.sh          # → dist/AI Usage Bar.app and dist/AIUsageBar-<version>.zip
```

Environment overrides: `BUNDLE_ID`, `VERSION`, `BUILD_NUMBER`, `ARCHS` (default `"arm64 x86_64"`).

Command-line flags of the built binary (`dist/AI Usage Bar.app/Contents/MacOS/AIUsageBar`):

| Flag | Purpose |
| --- | --- |
| `--probe` | Read-only live check of Claude and Codex; prints percentages and reset times, never tokens or account IDs |
| `--self-test` | Parser and snapshot tests |
| `--preview` | Launch with clearly labelled demo data, no network |
| `--window` | Also show the panel in a normal window |
| `--render-preview <file.png> [--dark] [--settings]` | Render the panel (or the settings window) with demo data to a PNG |
| `--render-icons <file.png>` | Render every frame of every menu-bar icon to a PNG |

## How it works & privacy

**Claude.** Reads the Claude Code login from the Keychain item `Claude Code-credentials` using `/usr/bin/security` (the same tool Claude Code uses, so no new permission prompt), then calls `GET https://api.anthropic.com/api/oauth/usage` — the endpoint behind Claude Code's `/usage`. The token lives in memory for a single request and is never stored, logged or refreshed by this app. When it is expired, the app runs `claude auth status` so Claude Code refreshes its own login.

**Codex.** Starts `codex app-server` and calls `account/read` and `account/rateLimits/read`, then shuts the process down (25 s timeout). Existing Codex sessions are untouched.

**Stored locally.** Only the latest usage snapshot and your preferences, in the app's UserDefaults. Nothing is sent anywhere except the two providers above.

## Limitations

- Both data sources are **undocumented** and may change without notice; unknown fields are hidden rather than guessed.
- Reset times do not auto-restore quota to 100 %; the app waits for the next successful read.
- No updates while the Mac sleeps or the app is closed; it refreshes on wake.
- Notifications depend on macOS notification permission and Focus.

See [VALIDATION.md](VALIDATION.md) for what has and hasn't been tested.

## Contributing

Issues and pull requests are welcome. Please run `bash scripts/build.sh` (which runs the self-tests) before submitting.

## License

[MIT](LICENSE)
