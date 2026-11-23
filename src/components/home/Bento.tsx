"use client";

import { useSyncExternalStore, type CSSProperties } from "react";
import MagicBento, { type MagicBentoItem } from "@/components/rb/MagicBento";
import SplitText from "@/components/rb/SplitText";
import { HandoffCard, InboxCard, PaintingCard, TaskBoardCard } from "@/components/home/BentoCards";

// Same layout as before, new card contents:
// [canvas      ][lead   ][handoffs]
// [     "      ][archive          ]
// [inbox       ][machines         ]
const buildItems = (): MagicBentoItem[] => [
  {
    colSpan: 2,
    rowSpan: 2,
    content: (
      <PaintingCard
        src="/images/tex/workshop_blue.jpg"
        focus={[0.55, 0.5]}
        title="Every session on one surface"
        description="Freeform, tiled or zoomed all the way out. Text never reflows, and every pane stays live."
      />
    ),
  },
  {
    content: <TaskBoardCard title="One agent leads" description="Claude Code or Codex hands out the tasks and checks every result." />,
  },
  {
    content: <HandoffCard title="Handoffs you can read" description="A finished reply becomes the next agent's prompt." />,
  },
  {
    colSpan: 2,
    content: (
      <PaintingCard
        src="/images/tex/library_blue.jpg"
        focus={[0.6, 0.5]}
        title="Quit the app, keep the work"
        description="Sessions live in tmux. Archive a thread and resume the exact conversation later."
      />
    ),
  },
  {
    colSpan: 2,
    content: (
      <InboxCard
        title="Answer from your phone"
        description="Approvals, errors and finished work from every project, in one inbox."
      />
    ),
  },
  {
    colSpan: 2,
    content: (
      <PaintingCard
        src="/images/tex/fleet.jpg"
        focus={[0.5, 0.55]}
        title="Steer your other machines"
        description="Open another Mac or Linux box on this canvas. Its agents keep running there."
      />
    ),
  },
];

const query = (q: string) => ({
  subscribe: (cb: () => void) => {
    const mq = window.matchMedia(q);
    mq.addEventListener("change", cb);
    return () => mq.removeEventListener("change", cb);
  },
  get: () => window.matchMedia(q).matches,
});
const wide = query("(min-width: 1024px)");
const medium = query("(min-width: 640px)");

// Navy versions of MagicBento's dark surface.
const navy = {
  "--mb-surface": "linear-gradient(180deg, #0c1a33 0%, #071226 100%)",
  "--mb-edge": "rgba(150, 190, 255, 0.12)",
  "--mb-highlight": "rgba(255, 255, 255, 0.06)",
  "--mb-ink": "#eef4ff",
  "--mb-muted": "rgba(200, 216, 240, 0.72)",
} as CSSProperties;

export default function Bento() {
  const isWide = useSyncExternalStore(wide.subscribe, wide.get, () => true);
  const isMedium = useSyncExternalStore(medium.subscribe, medium.get, () => true);
  const columns = isWide ? 4 : isMedium ? 2 : 1;

  return (
    <section id="features" className="relative scroll-mt-24 py-[clamp(88px,10vw,140px)]">
      <div className="wrap">
        <div className="mx-auto max-w-[40rem] text-center">
          <SplitText
            text="Built for a day with many agents."
            tag="h2"
            className="display-lg"
            splitType="words"
            effect="rise"
            mask
            trigger="view"
            delay={50}
          />
          <p className="lede mx-auto mt-5">Six things a row of terminal tabs was never going to do.</p>
        </div>

        <div className="mt-14">
          <MagicBento
            items={buildItems()}
            columns={columns}
            rowHeight={columns === 1 ? 330 : 290}
            gap={14}
            radius={22}
            theme="dark"
            glowColor="#4aa3ff"
            textAutoHide={false}
            enableBorderGlow
            enableSpotlight={false}
            enableStars={false}
            enableTilt={false}
            enableMagnetism={false}
            clickEffect={false}
            style={navy}
          />
        </div>
      </div>
    </section>
  );
}
