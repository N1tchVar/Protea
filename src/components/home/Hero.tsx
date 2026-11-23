import Link from "next/link";
import BrailleImage from "@/components/BrailleImage";
import SplitText from "@/components/rb/SplitText";
import Magnet from "@/components/rb/Magnet";
import { AppleGlyph } from "@/components/Nav";
import { site } from "@/lib/site";

export default function Hero() {
  return (
    <section id="top" className="relative isolate flex min-h-[100svh] flex-col items-center justify-center overflow-hidden px-5 pb-20 pt-32 text-center">
      <BrailleImage
        src="/images/tex/hero.jpg"
        cell={9}
        focus={[0.56, 0.5]}
        bleed={0.16}
        gain={1}
        tint={0.82}
        ramp={["#061633", "#d6ebff"]}
        className="-z-10"
      />
      {/* a calm pool of dark behind the copy, and a fade into the page */}
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(60%_55%_at_50%_55%,rgba(4,9,20,0.9)_0%,rgba(4,9,20,0.6)_55%,rgba(4,9,20,0.2)_100%)]" />
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[linear-gradient(180deg,rgba(4,9,20,0.6)_0%,transparent_20%,transparent_70%,var(--ink)_100%)]" />

      <h1 className="display-xl !leading-[0.92]">
        <span className="block">
          <SplitText text="Every agent you run," tag="span" splitType="words" effect="blur" trigger="load" delay={70} duration={1.1} />
        </span>
        <span className="block text-sky">
          <SplitText text="on one canvas." tag="span" splitType="words" effect="blur" trigger="load" delay={70} duration={1.1} />
        </span>
      </h1>

      <p className="enter lede mx-auto mt-8 max-w-[34rem] !text-marble-2" style={{ ["--d" as string]: "0.6s" }}>
        {site.name} lays Claude Code, Codex and your shells out side by side, lets one agent oversee the rest, and
        follows the work to your phone.
      </p>

      <div className="enter mt-10 flex flex-wrap items-center justify-center gap-3" style={{ ["--d" as string]: "0.8s" }}>
        <Magnet padding={50} magnetStrength={5} maxOffset={8}>
          <Link href={site.download.href} className="btn btn-primary !min-h-[54px] !px-7 text-[1rem]" prefetch={false}>
            <AppleGlyph className="h-4 w-4" />
            Download for Mac
          </Link>
        </Magnet>
        <Link href="#overview" className="btn btn-ghost !min-h-[54px] !px-7">
          See it in action
        </Link>
      </div>
      <p className="enter mono mt-6 text-[0.78rem] text-marble-3" style={{ ["--d" as string]: "1s" }}>
        {site.download.requirements}
      </p>
    </section>
  );
}
