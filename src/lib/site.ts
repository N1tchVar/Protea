// One place for the product's name and facts. Change the name here and it changes everywhere.
export const site = {
  name: "Protea",
  tagline: "A canvas for your terminals.",
  description:
    "Protea is a spatial terminal canvas for macOS. Run Claude Code, Codex and your shells side by side, appoint one agent to oversee the rest, and follow the work from any machine or your phone.",
  version: "0.1.0",
  released: "November 2026",
  repo: "https://github.com/n1tchvar/protea",
  download: {
    // Always the newest release on GitHub; the asset keeps the same name across releases.
    href: "https://github.com/n1tchvar/protea/releases/latest/download/Protea.dmg",
    file: "Protea.dmg",
    requirements: "Free · Apple silicon · macOS 14 or later",
  },
  pricing: { monthly: 6, yearly: 50, devices: 10 },
  runtimes: ["Claude Code", "Codex", "Gemini CLI", "Cursor Agent", "SSH", "zsh", "fish", "bash"],
} as const;

