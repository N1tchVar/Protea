"use client";

import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";

/* A working miniature of the app: real panes, real layouts, live output. */

type Mode = "free" | "tile" | "overview";
type Kind = "claude" | "codex" | "shell" | "browser";
type Line = { t: string; c?: "dim" | "gold" | "ok" | "err" | "aeg" | "mar" };

interface Pane {
  id: string;
  title: string;
  kind: Kind;
  meta: string;
  status: "work" | "done" | "ask" | "idle";
  lines?: Line[];
  page?: "search" | "docs";
}

const panes: Pane[] = [
  {
    id: "overseer",
    title: "overseer",
    kind: "claude",
    meta: "Claude · Overseer",
    status: "work",
    lines: [
      { t: "Objective  ship paginated search", c: "gold" },
      { t: "→ api    add cursor pagination to /search", c: "mar" },
      { t: "→ web    results list + load more", c: "mar" },
      { t: "→ tests  cover empty and last page", c: "mar" },
      { t: "✓ api finished · reviewing the diff", c: "ok" },
      { t: "! web uses 20 per page, api sends 25", c: "err" },
      { t: "→ web    import PAGE_SIZE from shared", c: "mar" },
      { t: "✓ contract agreed · 2 of 3 done", c: "ok" },
    ],
  },
  {
    id: "web",
    title: "web",
    kind: "claude",
    meta: "Claude Code",
    status: "work",
    lines: [
      { t: "> Build the search results list with load more", c: "gold" },
      { t: "⏺ Read src/app/search/page.tsx", c: "mar" },
      { t: "⏺ Write src/components/SearchResults.tsx", c: "mar" },
      { t: "  └ +84 lines", c: "dim" },
      { t: "⏺ Update src/lib/api.ts", c: "mar" },
      { t: "  └ +12 −3", c: "dim" },
      { t: "⏺ Bash npm run test -- search", c: "mar" },
      { t: "  ✓ 18 passed (1.9s)", c: "ok" },
      { t: "⏺ Waiting for overseer review…", c: "aeg" },
    ],
  },
  { id: "preview", title: "localhost:3000/search", kind: "browser", meta: "Browser", status: "idle", page: "search" },
  {
    id: "api",
    title: "api",
    kind: "codex",
    meta: "Codex",
    status: "done",
    lines: [
      { t: "codex› implement cursor pagination for GET /search", c: "gold" },
      { t: "• Editing server/routes/search.ts", c: "mar" },
      { t: "• Adding encodeCursor / decodeCursor", c: "mar" },
      { t: "• Running pnpm vitest run server", c: "mar" },
      { t: "  ✓ search.cursor.test.ts (12)", c: "ok" },
      { t: "  ✓ search.route.test.ts (30)", c: "ok" },
      { t: "  42 passed · 0 failed", c: "ok" },
      { t: "• Summary sent to overseer", c: "aeg" },
    ],
  },
  {
    id: "tests",
    title: "tests",
    kind: "codex",
    meta: "Codex",
    status: "ask",
    lines: [
      { t: "codex› add edge-case tests for search", c: "gold" },
      { t: "• Writing search.empty.test.ts", c: "mar" },
      { t: "• Writing search.lastpage.test.ts", c: "mar" },
      { t: "  ✗ lastpage › returns a null cursor", c: "err" },
      { t: "• Fixing off-by-one in decodeCursor", c: "mar" },
      { t: "  ✓ 6 passed", c: "ok" },
      { t: "? Allow write to server/lib/cursor.ts", c: "err" },
    ],
  },
  {
    id: "deploy",
    title: "deploy · build-01",
    kind: "shell",
    meta: "zsh over SSH",
    status: "idle",
    lines: [
      { t: "dev@build-01 ~/halcyon $ git pull", c: "mar" },
      { t: "Already up to date.", c: "dim" },
      { t: "$ docker compose up -d api", c: "mar" },
      { t: " ✔ Container halcyon-db   Healthy", c: "ok" },
      { t: " ✔ Container halcyon-api  Started", c: "ok" },
      { t: "$ curl -s :8080/health", c: "mar" },
      { t: '{"ok":true,"version":"2.4.1"}', c: "aeg" },
    ],
  },
  { id: "docs", title: "docs · README.md", kind: "browser", meta: "Browser", status: "idle", page: "docs" },
  {
    id: "logs",
    title: "logs",
    kind: "shell",
    meta: "zsh",
    status: "idle",
    lines: [
      { t: "$ tail -f api.log", c: "mar" },
      { t: "GET /search?q=ferry 200 18ms", c: "dim" },
      { t: "GET /search?q=ferry&c=eyJp 200 11ms", c: "dim" },
      { t: "GET /health 200 1ms", c: "dim" },
      { t: "GET /search?q=lantern 200 16ms", c: "dim" },
    ],
  },
];

// Virtual stage: 1240 × 780. Canvas area is 1040 × 740.
type Box = [number, number, number, number];
const FREE: Record<string, Box> = {
  overseer: [24, 24, 300, 300],
  web: [340, 24, 400, 336],
  preview: [756, 24, 260, 236],
  api: [24, 340, 380, 300],
  tests: [420, 376, 320, 264],
  deploy: [756, 276, 260, 364],
  docs: [1060, 24, 300, 300],
  logs: [1060, 340, 300, 300],
};
const TILE: Record<string, Box> = Object.fromEntries(
  panes.map((p, i) => {
    const col = i % 4;
    const row = Math.floor(i / 4);
    const w = (1040 - 48 - 36) / 4;
    const h = (740 - 48 - 12 - 64) / 2;
    return [p.id, [24 + col * (w + 12), 24 + row * (h + 12), w, h] as Box];
  })
);

const color: Record<NonNullable<Line["c"]>, string> = {
  dim: "text-marble-3",
  gold: "text-azure",
  ok: "text-sea",
  err: "text-coral",
  aeg: "text-sky",
  mar: "text-marble-2",
};
const statusColor = { work: "text-azure", done: "text-sea", ask: "text-coral", idle: "text-marble-3" };

function KindIcon({ kind }: { kind: Kind }) {
  if (kind === "claude")
    return (
      <svg viewBox="0 0 16 16" className="h-3 w-3" aria-hidden="true">
        <path d="M8 1.5 9.2 6.8 14.5 8 9.2 9.2 8 14.5 6.8 9.2 1.5 8 6.8 6.8Z" fill="#d97757" />
      </svg>
    );
  if (kind === "codex")
    return (
      <svg viewBox="0 0 16 16" className="h-3 w-3" aria-hidden="true">
        <circle cx="8" cy="8" r="6" fill="none" stroke="#eef4ff" strokeWidth="1.5" />
        <path d="M5.5 6.5 7.5 8l-2 1.5M8.5 10h2.5" stroke="#eef4ff" strokeWidth="1.2" fill="none" strokeLinecap="round" />
      </svg>
    );
  if (kind === "browser")
    return (
      <svg viewBox="0 0 16 16" className="h-3 w-3" aria-hidden="true">
        <circle cx="8" cy="8" r="6" fill="none" stroke="#7fa9c4" strokeWidth="1.4" />
        <path d="M2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12" stroke="#7fa9c4" strokeWidth="1" fill="none" />
      </svg>
    );
  return <span className="mono text-[10px] leading-none text-sea">❯_</span>;
}

function Terminal({ lines, step }: { lines: Line[]; step: number }) {
  const n = step % (lines.length + 4);
  const shown = lines.slice(0, Math.min(n, lines.length));
  return (
    <div className="mono space-y-[3px] p-3 text-[10.5px] leading-[1.45]">
      {shown.map((l, i) => (
        <div key={i} className={`truncate ${color[l.c ?? "mar"]}`}>
          {l.t}
        </div>
      ))}
      {n <= lines.length && <span className="caret !h-[11px] !w-[6px]" />}
    </div>
  );
}

function SearchPage() {
  return (
    <div className="space-y-2 bg-[#f3f6fb] p-3 text-[#0b1830]">
      <div className="flex items-center gap-2 rounded-md border border-black/10 bg-white px-2 py-1.5 text-[10px] text-black/60">
        <span>⌕</span> ferry
      </div>
      {["Charon Ferries · timetable", "Lantern rentals near the dock", "Crossing fees, explained", "Night crossings"].map((t, i) => (
        <div key={t} className="rounded-md bg-white px-2 py-1.5 shadow-[0_1px_0_rgba(0,0,0,0.06)]">
          <div className="text-[10px] font-medium">{t}</div>
          <div className="mt-1 h-1 rounded bg-black/10" style={{ width: `${70 - i * 9}%` }} />
        </div>
      ))}
      <div className="rounded-md bg-[#0b1830] py-1 text-center text-[9.5px] text-[#eef4ff]">Load more</div>
    </div>
  );
}

function DocsPage() {
  return (
    <div className="h-full space-y-2 bg-[#f3f6fb] p-3 text-[#0b1830]">
      <div className="text-[12px] font-semibold">Halcyon</div>
      {[92, 80, 86, 60].map((w, i) => (
        <div key={i} className="h-1.5 rounded bg-black/12" style={{ width: `${w}%`, background: "rgba(0,0,0,0.12)" }} />
      ))}
      <div className="text-[10px] font-semibold">Search API</div>
      <div className="rounded bg-[#0b1830] p-2 font-mono text-[9px] text-[#9fd0ff]">GET /search?q=&amp;cursor=</div>
      {[88, 70].map((w, i) => (
        <div key={i} className="h-1.5 rounded" style={{ width: `${w}%`, background: "rgba(0,0,0,0.12)" }} />
      ))}
    </div>
  );
}

function PaneView({ pane, box, step, focused }: { pane: Pane; box: Box; step: number; focused: boolean }) {
  const [x, y, w, h] = box;
  return (
    <div
      className="absolute left-0 top-0 flex flex-col overflow-hidden rounded-[10px] border bg-[#061022]/95 shadow-[0_18px_50px_-18px_rgba(0,0,0,0.9)] transition-[transform,width,height,border-color] duration-[900ms] ease-[cubic-bezier(0.65,0,0.35,1)]"
      style={{
        transform: `translate(${x}px, ${y}px)`,
        width: w,
        height: h,
        borderColor: focused ? "rgba(74,163,255,0.6)" : "rgba(239,228,208,0.1)",
      }}
    >
      <div className="flex h-7 shrink-0 items-center justify-between border-b border-line bg-[#0a1630] px-2.5">
        <span className="flex min-w-0 items-center gap-1.5 text-[10.5px] text-marble">
          <KindIcon kind={pane.kind} />
          <span className="truncate">{pane.title}</span>
        </span>
        <span className="flex items-center gap-1.5 text-[9.5px] text-marble-3">
          {pane.meta}
          <span className={`live-dot !h-[6px] !w-[6px] ${statusColor[pane.status]}`} />
        </span>
      </div>
      <div className="min-h-0 flex-1 overflow-hidden">
        {pane.lines && <Terminal lines={pane.lines} step={step} />}
        {pane.page === "search" && <SearchPage />}
        {pane.page === "docs" && <DocsPage />}
      </div>
    </div>
  );
}

function Wires({ show }: { show: boolean }) {
  const from = FREE.overseer;
  const sx = from[0] + from[2];
  const sy = from[1] + from[3] / 2;
  const targets = ["web", "api", "tests"].map((id) => {
    const [x, y, , h] = FREE[id];
    return id === "api" ? { x: x + 150, y, id } : { x, y: y + h / 2, id };
  });
  return (
    <svg
      className="pointer-events-none absolute inset-0 h-full w-full transition-opacity duration-500"
      style={{ opacity: show ? 1 : 0, transitionDelay: show ? "700ms" : "0ms" }}
      viewBox="0 0 1040 740"
      aria-hidden="true"
    >
      {targets.map((t) => {
        const d =
          t.id === "api"
            ? `M ${from[0] + 150} ${from[1] + from[3]} C ${from[0] + 150} ${from[1] + from[3] + 10}, ${t.x} ${t.y - 10}, ${t.x} ${t.y}`
            : `M ${sx} ${sy} C ${sx + 40} ${sy}, ${t.x - 40} ${t.y}, ${t.x} ${t.y}`;
        return (
          <g key={t.id}>
            <path d={d} stroke="rgba(74,163,255,0.25)" strokeWidth="1.2" fill="none" />
            <path d={d} stroke="#4aa3ff" strokeWidth="1.6" fill="none" strokeDasharray="6 90" className="wire-pulse" />
          </g>
        );
      })}
    </svg>
  );
}

const MODES: { id: Mode; label: string }[] = [
  { id: "free", label: "Freeform" },
  { id: "tile", label: "Tile" },
  { id: "overview", label: "Overview" },
];

const reducedQuery = "(prefers-reduced-motion: reduce)";
const subscribeReduced = (cb: () => void) => {
  const mq = window.matchMedia(reducedQuery);
  mq.addEventListener("change", cb);
  return () => mq.removeEventListener("change", cb);
};
const getReduced = () => window.matchMedia(reducedQuery).matches;

export default function CanvasDemo() {
  const outer = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [mode, setMode] = useState<Mode>("free");
  const [auto, setAuto] = useState(true);
  const [step, setStep] = useState(0);
  const [inView, setInView] = useState(false);
  const reduced = useSyncExternalStore(subscribeReduced, getReduced, () => false);
  const playing = auto && !reduced;
  const shownStep = reduced ? 99 : step;

  useEffect(() => {
    const el = outer.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setScale(e.contentRect.width / 1240));
    ro.observe(el);
    const io = new IntersectionObserver(([e]) => setInView(e.isIntersecting), { threshold: 0.2 });
    io.observe(el);
    return () => {
      ro.disconnect();
      io.disconnect();
    };
  }, []);

  // typing
  useEffect(() => {
    if (!inView || !playing) return;
    const id = setInterval(() => setStep((s) => s + 1), 650);
    return () => clearInterval(id);
  }, [inView, playing]);

  // layout cycle
  useEffect(() => {
    if (!inView || !playing) return;
    const order: Mode[] = ["free", "overview", "tile"];
    const id = setInterval(() => setMode((m) => order[(order.indexOf(m) + 1) % order.length]), 5200);
    return () => clearInterval(id);
  }, [inView, playing]);

  const layout = mode === "tile" ? TILE : FREE;
  const zoom = mode === "overview" ? 0.72 : 1;

  const controls = (
    <div className="flex items-center gap-1 rounded-full border border-line-strong bg-[#0a1630]/95 p-1 shadow-xl">
      {MODES.map((m) => (
        <ToolbarButton
          key={m.id}
          active={mode === m.id}
          onClick={() => {
            setMode(m.id);
            setAuto(false);
            setStep((s) => Math.max(s, 99));
          }}
        >
          {m.label}
        </ToolbarButton>
      ))}
      <span className="mx-1 h-4 w-px bg-line-strong" />
      <ToolbarButton active={false} onClick={() => setAuto((a) => !a)} label={playing ? "Pause the demo" : "Play the demo"}>
        {playing ? "❚❚" : "▶"}
      </ToolbarButton>
    </div>
  );

  return (
    <div>
    <div ref={outer} className="relative w-full" style={{ height: 780 * scale }}>
      <div
        className="absolute left-0 top-0 origin-top-left overflow-hidden rounded-[18px] border border-line-strong bg-[#050c1c] shadow-[0_60px_140px_-40px_rgba(0,0,0,0.95),0_0_0_1px_rgba(0,0,0,0.6)]"
        style={{ width: 1240, height: 780, transform: `scale(${scale})` }}
        role="group"
        aria-label="The Protea canvas: an overseer, two Codex sessions, a Claude Code session, a browser preview and an SSH shell arranged side by side."
      >
        {/* title bar */}
        <div className="flex h-10 items-center justify-between border-b border-line bg-[#08132a] px-4">
          <div className="flex gap-2">
            <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
            <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
            <span className="h-3 w-3 rounded-full bg-[#28c840]" />
          </div>
          <div className="flex items-center gap-1 text-[12px]">
            {["Halcyon app", "Halcyon site", "infra"].map((w, i) => (
              <span key={w} className={`rounded-md px-3 py-1 ${i === 0 ? "bg-ink-4 text-marble" : "text-marble-3"}`}>
                {w}
              </span>
            ))}
          </div>
          <span className="mono text-[11px] text-marble-3">{Math.round(zoom * 100)}%</span>
        </div>

        <div className="flex h-[740px]">
          {/* sidebar */}
          <aside className="w-[200px] shrink-0 border-r border-line bg-[#071024] p-3">
            <div className="mb-2 px-2 text-[10.5px] uppercase tracking-[0.12em] text-marble-3">Sessions</div>
            <ul className="space-y-0.5">
              {panes.map((p) => (
                <li key={p.id} className="flex items-center justify-between rounded-md px-2 py-1.5 text-[12px] text-marble-2">
                  <span className="flex items-center gap-2">
                    <KindIcon kind={p.kind} />
                    {p.id}
                  </span>
                  <span className={`live-dot !h-[6px] !w-[6px] ${statusColor[p.status]}`} />
                </li>
              ))}
            </ul>
            <div className="mt-5 rounded-lg border border-line bg-ink-3/60 p-2.5">
              <div className="text-[10.5px] uppercase tracking-[0.12em] text-marble-3">Overseer</div>
              <div className="mt-1.5 text-[11.5px] leading-snug text-marble-2">2 of 3 tasks done. Tests needs your approval.</div>
              <div className="mt-2 h-1 overflow-hidden rounded bg-ink-4">
                <div className="h-full w-2/3 rounded bg-azure" />
              </div>
            </div>
          </aside>

          {/* canvas */}
          <div className="relative flex-1 overflow-hidden bg-[radial-gradient(rgba(160,200,255,0.1)_1px,transparent_1px)] [background-size:22px_22px]">
            <div
              className="absolute inset-0 origin-top-left transition-transform duration-[900ms] ease-[cubic-bezier(0.65,0,0.35,1)]"
              style={{ transform: mode === "overview" ? `translate(20px, 46px) scale(${zoom})` : "none" }}
            >
              {panes.map((p) => (
                <PaneView key={p.id} pane={p} box={layout[p.id]} step={shownStep} focused={p.id === "overseer" && mode === "free"} />
              ))}
              <Wires show={mode === "free"} />
            </div>

            {/* toolbar */}
            <div className="absolute bottom-4 left-1/2 hidden -translate-x-1/2 md:block">{controls}</div>
          </div>
        </div>
      </div>
    </div>
    <div className="mt-4 flex justify-center md:hidden">{controls}</div>
    </div>
  );
}

function ToolbarButton({
  active,
  onClick,
  children,
  label,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  label?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      aria-pressed={active}
      className={`min-h-[40px] rounded-full px-4 py-2 text-[12.5px] transition-colors duration-300 ${
        active ? "bg-marble text-ink" : "text-marble-2 hover:bg-ink-4 hover:text-marble"
      }`}
    >
      {children}
    </button>
  );
}
