"use client";

import SplitText from "@/components/rb/SplitText";
import CanvasDemo from "@/components/home/CanvasDemo";

export default function Overview() {
  return (
    <section id="overview" className="relative isolate scroll-mt-24 overflow-hidden py-[clamp(88px,10vw,140px)]">
      <div className="pointer-events-none absolute inset-x-0 top-[22%] -z-10 mx-auto h-[50%] max-w-[1100px] rounded-full bg-azure/12 blur-[120px]" />
      <div className="wrap">
        <div className="mx-auto max-w-[40rem] text-center">
          <SplitText
            text="See the whole workspace at once."
            tag="h2"
            className="display-lg"
            splitType="words"
            effect="rise"
            mask
            trigger="view"
            delay={50}
          />
          <p className="lede mx-auto mt-5">
            A live overseer, two Codex sessions, Claude Code, a browser preview and a shell on a remote box. Switch
            between Freeform, Tile and Overview.
          </p>
        </div>
        <div className="mt-14">
          <CanvasDemo />
        </div>
      </div>
    </section>
  );
}
