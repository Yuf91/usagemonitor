# Validation

Version 1.2.2 · 2026-10-02

Verified:
- Universal (arm64 + x86_64) release build, ad-hoc signature verified.
- 21 self-tests pass (`--self-test`): Codex multi-bucket and legacy formats, null / invalid / boundary values, reset-time units, snapshot serialization, stale and failed states; Claude session/weekly parsing, null windows, fractional-second timestamps, cloud credits vs. usage credits, currency decimal places, unknown values stay unknown.
- `--probe` against live Claude and Codex accounts returns quotas, credits and reset times; no token or account ID is printed or stored.
- Reading the Claude Code Keychain item did not trigger a new authorization prompt.
- `claude auth status` does not renew an expired token; `claude mcp list` does, without sending a prompt.
- Light / dark previews rendered from demo data (`previews/`).
- All six menu-bar icon animations inspected frame by frame (`--render-icons`); settings window rendered at a short height to confirm it scrolls with the update button pinned (`--render-preview --settings`).
- Clean checkout of the tracked files builds, signs and passes self-tests.

Not yet verified:
- The app renewing an expired Claude token on its own, end to end (the `claude mcp list` step was verified by hand).
- Hands-on checks of menu-bar clicks, settings window, VoiceOver, notifications and launch at login.
- Developer ID notarization; macOS versions other than the development machine; Intel hardware (built, not run).
