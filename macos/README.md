# Protea for macOS

A canvas for your terminals: run Claude Code, Codex, Gemini, GPT (through Codex) and plain shells side by side,
as many as you like, on one zoomable surface. Native AppKit + SwiftUI with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm); about 7 MB.

## Build and run

```sh
./build-app.sh --open      # builds macos/build/Protea.app and opens it
```

Requires macOS 14+, Apple silicon and Xcode 16+ (Swift 6 toolchain). Drag `build/Protea.app` into `/Applications` to keep it.

## Using it

| | |
|---|---|
| New session | **New session** button, ⌘T (last agent) or ⌥⌘1–5 (Claude Code, Codex, Gemini, GPT, Shell) |
| Move / resize | drag a pane's header; drag its right edge, bottom edge or corner |
| Zoom | pinch, ⌘-scroll, ⌘= / ⌘− / ⌘0 |
| Overview / Tile | ⇧⌘0 / ⇧⌘G (Tile again to put your layout back) |
| Pan | two-finger scroll, or drag empty canvas |
| Focus | double-click a header, click a session in the sidebar, ⌘] / ⌘[ |
| Rename | double-click a pane's title |
| Restart / close | header buttons, ⇧⌘R / ⇧⌘W |
| Dictate a prompt | ⌘D or the mic button, speak, Return to send, Esc to cancel |
| Usage | **Usage** in the top bar; the ring on each pane header shows how full its context is |

Each pane runs your login shell, so your `PATH` and config apply. Agents that aren't installed show the install
command instead. When an agent stops on a prompt ("Do you want to…", "Allow…", "Enter to confirm") the pane turns
coral, the sidebar counts it, and the Dock icon shows a badge. Change the command behind each agent in Settings (⌘,).

**Voice.** Speech is turned into text by macOS (on this Mac when your language supports it) and typed into the
focused session, then Return is pressed. Turn the Return off in Settings. The first time, macOS asks for microphone
and speech-recognition access.

**Usage.** Read from the transcripts the agents already write: `~/.claude/projects` for Claude Code (each Claude pane
is started with its own `--session-id` so Protea knows which file is its own) and `~/.codex/sessions` for Codex.
Each pane shows context used against the model's window; the Usage panel adds Claude's current 5-hour window
(tokens, ≈ cost at API list prices, when it resets) and Codex's plan limits. Gemini doesn't write usage yet.

Layout and workspaces are saved to `~/Library/Application Support/Protea/state.json`. Sessions themselves stop when
you quit (no tmux yet) and start fresh next launch, in the same places.

`--demo` opens a sample workspace without touching your saved layout; `--snapshot <file.png>` renders it to an image and
quits (add `--empty`, `--hud` or `--usage` to capture those states).
