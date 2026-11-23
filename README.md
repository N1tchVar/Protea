# Protea

A canvas for your terminals. Run Claude Code, Codex, Gemini, GPT and plain shells side by side on one zoomable
canvas, see which one needs you, dictate prompts with your voice, and keep an eye on usage.

- **Website** — Next.js 16 + Tailwind 4, in this folder (`src/`). `npm install && npm run dev`.
- **Mac app** — native Swift (AppKit + SwiftUI + SwiftTerm), in [`macos/`](macos/README.md). `cd macos && ./build-app.sh --open`.

## Download

[**Download Protea for Mac**](https://github.com/n1tchvar/protea/releases/latest/download/Protea.dmg) — Apple silicon, macOS 14 or later.

The build is not notarized yet, so the first time you open it macOS will refuse. Open **System Settings → Privacy &
Security**, scroll down, and click **Open Anyway** next to the Protea message (or right-click the app → **Open**).

## Releasing a new build

```sh
cd macos && ./build-app.sh --dmg     # → macos/build/Protea.dmg
gh release create v0.1.1 build/Protea.dmg --title "Protea 0.1.1"
```

The website's download button always points at `releases/latest/download/Protea.dmg`, so a new release is live
the moment it is published.
