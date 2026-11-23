"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { AnimatePresence, motion } from "motion/react";
import BrailleImage from "@/components/BrailleImage";

/* ── shared pieces ─────────────────────────────────────────────── */

function CardText({ title, description, light = false }: { title: string; description: string; light?: boolean }) {
  return (
    <div className="relative z-[1] mt-auto flex flex-col gap-1.5">
      <h3 className={`text-[clamp(18px,1.55vw,22px)] font-medium leading-[1.2] tracking-[-0.025em] ${light ? "text-[#0b1830]" : "text-marble"}`}>
        {title}
      </h3>
      <p className={`max-w-[34rem] text-[15px] leading-[1.5] ${light ? "text-[#4a5d7c]" : "text-marble-2"}`}>{description}</p>
    </div>
  );
}

function ClaudeMark({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} aria-hidden="true">
      <path d="M8 1 9.3 6.7 15 8 9.3 9.3 8 15 6.7 9.3 1 8 6.7 6.7Z" fill="#d97757" />
    </svg>
  );
}

function CodexMark({ className = "h-4 w-4", color = "currentColor" }: { className?: string; color?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" aria-hidden="true">
      <circle cx="8" cy="8" r="6.2" stroke={color} strokeWidth="1.4" />
      <path d="M5.6 6.3 7.4 8 5.6 9.7M8.6 10h2" stroke={color} strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function Sunburst({ className = "h-5 w-5", color = "#4aa3ff" }: { className?: string; color?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={`${className} animate-[spin_1.6s_steps(8)_infinite]`} aria-hidden="true">
      {Array.from({ length: 8 }, (_, i) => (
        <line key={i} x1="12" y1="2.5" x2="12" y2="7" stroke={color} strokeWidth="2.2" strokeLinecap="round" opacity={0.25 + (i / 8) * 0.75} transform={`rotate(${i * 45} 12 12)`} />
      ))}
    </svg>
  );
}

function useInView<T extends Element>() {
  const ref = useRef<T>(null);
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setInView(e.isIntersecting), { threshold: 0.2 });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return [ref, inView] as const;
}

/* ── painting cards ────────────────────────────────────────────── */

export function PaintingCard({ src, focus, title, description }: { src: string; focus: [number, number]; title: string; description: string }) {
  return (
    <>
      <BrailleImage src={src} cell={6} focus={focus} bleed={0.1} gain={0.78} tint={0.9} ramp={["#040f24", "#6f9fdc"]} className="z-0" />
      <div className="pointer-events-none absolute inset-0 z-0 bg-[linear-gradient(to_top,rgba(4,9,20,0.92)_0%,rgba(4,9,20,0.55)_30%,transparent_65%)]" />
      <CardText title={title} description={description} />
    </>
  );
}

/* ── the overseer's task list, tilted ─────────────────────────── */

type TaskState = "done" | "run" | "todo";
const tasks: { text: string; state: TaskState; agent: "claude" | "codex" }[] = [
  { text: "Plan paginated search", state: "done", agent: "claude" },
  { text: "Cursor pagination on /search", state: "done", agent: "codex" },
  { text: "Results list with load more", state: "run", agent: "claude" },
  { text: "Edge-case tests", state: "done", agent: "codex" },
  { text: "Review the API contract", state: "todo", agent: "claude" },
  { text: "Update the OpenAPI spec", state: "todo", agent: "codex" },
  { text: "Rate limit at 60 a minute", state: "run", agent: "codex" },
  { text: "Deploy to build-01", state: "todo", agent: "claude" },
];

function TaskToggle({ state }: { state: TaskState }) {
  if (state === "done")
    return (
      <span className="grid h-5 w-5 shrink-0 place-items-center rounded-full bg-azure shadow-[0_0_14px_rgba(74,163,255,0.55)]">
        <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden="true">
          <path d="m2.5 6.2 2.2 2.2 4.8-4.8" stroke="#fff" strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    );
  if (state === "run") return <Sunburst className="h-5 w-5 shrink-0" />;
  return <span className="h-5 w-5 shrink-0 rounded-full border-[1.5px] border-[rgba(168,185,212,0.35)]" />;
}

export function TaskBoardCard({ title, description }: { title: string; description: string }) {
  const rows = [...tasks, ...tasks];
  return (
    <>
      <div className="pointer-events-none absolute inset-0 overflow-hidden [mask-image:linear-gradient(to_bottom,transparent_0%,#000_12%,#000_42%,transparent_64%)]" style={{ perspective: "1100px" }}>
        <div className="absolute left-[30%] -top-[30%] w-[115%] origin-[0%_50%] [transform:rotateX(38deg)_rotateZ(-20deg)]">
          <ul className="animate-[taskscroll_34s_linear_infinite] space-y-3">
            {rows.map((t, i) => (
              <li
                key={i}
                className={`flex h-[48px] items-center gap-3 rounded-[14px] border px-4 text-[15px] tracking-[-0.01em] ${
                  t.state === "run"
                    ? "border-azure/40 bg-[#10274a] text-marble shadow-[0_0_30px_-8px_rgba(74,163,255,0.45)]"
                    : "border-white/[0.05] bg-[#0d1b33] text-marble-2"
                }`}
              >
                <TaskToggle state={t.state} />
                <span className="truncate">{t.text}</span>
                <span className="ml-auto opacity-70">{t.agent === "claude" ? <ClaudeMark /> : <CodexMark className="h-4 w-4" color="#a8b9d4" />}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
      <CardText title={title} description={description} />
    </>
  );
}

/* ── handoffs: two agents orbiting one workspace ───────────────── */

export function HandoffCard({ title, description }: { title: string; description: string }) {
  return (
    <>
      <div className="pointer-events-none absolute inset-0 bg-[linear-gradient(180deg,#f4f8fd_0%,#e9f0fa_100%)]" />
      <div className="pointer-events-none absolute inset-x-0 top-0 bottom-[88px] flex items-center justify-center overflow-hidden [mask-image:linear-gradient(to_bottom,#000_65%,transparent)]">
        <div className="relative grid h-[260px] w-[260px] place-items-center">
          {[260, 190, 118].map((s) => (
            <span key={s} className="absolute rounded-full border border-[rgba(11,24,48,0.08)]" style={{ width: s, height: s }} />
          ))}
          {/* a message running around the middle ring */}
          <span
            className="absolute h-[190px] w-[190px] animate-[spin_3.2s_linear_infinite] rounded-full"
            style={{
              background: "conic-gradient(from 0deg, transparent 0deg, transparent 280deg, rgba(74,163,255,0.85) 355deg, transparent 360deg)",
              WebkitMask: "radial-gradient(farthest-side, transparent calc(100% - 2px), #000 calc(100% - 2px))",
              mask: "radial-gradient(farthest-side, transparent calc(100% - 2px), #000 calc(100% - 2px))",
            }}
          />
          {/* the two agents on the ring */}
          <span className="absolute h-[190px] w-[190px] animate-[spin_22s_linear_infinite]">
            <span className="absolute -left-[17px] top-1/2 grid h-[34px] w-[34px] -translate-y-1/2 animate-[spin_22s_linear_infinite_reverse] place-items-center rounded-full bg-white shadow-[0_6px_18px_-6px_rgba(11,24,48,0.35)] ring-1 ring-black/5">
              <ClaudeMark className="h-4 w-4" />
            </span>
            <span className="absolute -right-[17px] top-1/2 grid h-[34px] w-[34px] -translate-y-1/2 animate-[spin_22s_linear_infinite_reverse] place-items-center rounded-full bg-white shadow-[0_6px_18px_-6px_rgba(11,24,48,0.35)] ring-1 ring-black/5">
              <CodexMark className="h-4 w-4" color="#0b1830" />
            </span>
          </span>
          <span className="relative grid h-[68px] w-[68px] place-items-center rounded-full bg-white shadow-[0_14px_34px_-10px_rgba(11,24,48,0.35),0_0_0_8px_rgba(255,255,255,0.6)]">
            <Image src="/brand/protea-mark.png" alt="" width={34} height={34} />
          </span>
        </div>
      </div>
      <CardText title={title} description={description} light />
    </>
  );
}

/* ── notifications stacking in ─────────────────────────────────── */

type Toast = { id: number; kind: "done" | "run" | "ask"; text: string };
const feed: Omit<Toast, "id">[] = [
  { kind: "done", text: "api finished · 42 tests passing" },
  { kind: "run", text: "Overseer is reviewing web" },
  { kind: "ask", text: "tests wants to write cursor.ts" },
  { kind: "done", text: "deploy is healthy on build-01" },
  { kind: "done", text: "Overseer approved the web branch" },
  { kind: "run", text: "Codex is adding rate limits" },
];

function ToastIcon({ kind }: { kind: Toast["kind"] }) {
  if (kind === "done")
    return (
      <span className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full bg-[#0b1830]">
        <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden="true">
          <path d="m2.5 6.2 2.2 2.2 4.8-4.8" stroke="#fff" strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    );
  if (kind === "run") return <Sunburst className="h-[22px] w-[22px] shrink-0" />;
  return <span className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full bg-coral text-[12px] font-bold text-white">!</span>;
}

export function InboxCard({ title, description }: { title: string; description: string }) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const [n, setN] = useState(3);

  useEffect(() => {
    if (!inView || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const id = window.setInterval(() => setN((v) => v + 1), 2400);
    return () => window.clearInterval(id);
  }, [inView]);

  const visible: Toast[] = [0, 1, 2].map((k) => {
    const id = n - k;
    return { id, ...feed[((id % feed.length) + feed.length) % feed.length] };
  });

  return (
    <>
      <div className="pointer-events-none absolute inset-0 bg-[#f3f7fc]" />
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(55%_60%_at_85%_10%,rgba(74,163,255,0.32),transparent_70%),radial-gradient(45%_50%_at_10%_60%,rgba(159,208,255,0.35),transparent_70%)]" />
      <div ref={ref} className="pointer-events-none absolute inset-x-0 top-0 bottom-[92px] flex items-center justify-center px-6 pt-4">
        <ul className="relative flex w-full max-w-[400px] flex-col gap-2.5">
          <AnimatePresence initial={false} mode="popLayout">
            {visible.map((t, i) => (
              <motion.li
                key={t.id}
                layout
                initial={{ opacity: 0, y: -18, scale: 0.97 }}
                animate={{ opacity: i === 2 ? 0.55 : 1, y: 0, scale: i === 2 ? 0.96 : 1 }}
                exit={{ opacity: 0, scale: 0.94, transition: { duration: 0.25 } }}
                transition={{ type: "spring", stiffness: 260, damping: 26 }}
                className="flex h-[48px] items-center gap-3 rounded-[14px] border border-black/[0.06] bg-white px-4 shadow-[0_14px_34px_-16px_rgba(11,24,48,0.35)]"
              >
                <ToastIcon kind={t.kind} />
                <span className="truncate text-[15px] tracking-[-0.01em] text-[#0b1830]">{t.text}</span>
                {t.kind === "ask" && (
                  <span className="ml-auto shrink-0 rounded-lg bg-azure px-3 py-1 text-[12.5px] font-medium text-white">Allow</span>
                )}
              </motion.li>
            ))}
          </AnimatePresence>
        </ul>
      </div>
      <CardText title={title} description={description} light />
    </>
  );
}
