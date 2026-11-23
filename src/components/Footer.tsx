import Link from "next/link";
import BrailleImage from "@/components/BrailleImage";
import { Mark } from "@/components/Logo";
import { AppleGlyph } from "@/components/Nav";
import { site } from "@/lib/site";

const links = [
  { label: "Features", href: "#features" },
  { label: "Overview", href: "#overview" },
  { label: "Download", href: site.download.href },
];

// Proteus rising from the sea, printed in braille, under a short call to action and the footer.
export default function Footer() {
  return (
    <footer className="relative isolate overflow-hidden">
      <BrailleImage
        src="/images/tex/proteus.jpg"
        cell={9}
        focus={[0.32, 0.45]}
        bleed={0.12}
        gain={1}
        tint={0.75}
        ramp={["#05122a", "#cfe6ff"]}
        className="-z-10 [mask-image:linear-gradient(to_bottom,transparent_0%,rgba(0,0,0,0.35)_14%,#000_40%,#000_80%,transparent_100%)] [-webkit-mask-image:linear-gradient(to_bottom,transparent_0%,rgba(0,0,0,0.35)_14%,#000_40%,#000_80%,transparent_100%)]"
      />
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[linear-gradient(180deg,transparent_0%,rgba(4,9,20,0.4)_35%,rgba(4,9,20,0.5)_65%,transparent_100%)]" />

      <div className="wrap flex min-h-[92svh] flex-col items-center justify-center py-28 text-center">
        <Mark size={56} />
        <h2 className="display-lg mx-auto mt-6 max-w-[16ch] text-center [text-shadow:0_2px_24px_rgba(4,9,20,0.9)]">
          Your agents, <span className="text-sky">in one place.</span>
        </h2>
        <Link href={site.download.href} className="btn btn-primary mt-9 !min-h-[54px] !px-7 text-[1rem]" prefetch={false}>
          <AppleGlyph className="h-4 w-4" />
          Download for Mac
        </Link>
        <p className="mono mt-5 text-[0.78rem] text-marble-2">{site.download.requirements}</p>
      </div>

      <div className="wrap">
        <div className="flex flex-col items-center justify-between gap-5 border-t border-line py-8 sm:flex-row">
          <Link href="#top" className="flex items-center gap-2.5" aria-label={`${site.name} home`}>
            <Mark size={26} />
            <span className="text-[1.05rem] font-semibold tracking-[-0.03em] text-marble">{site.name}</span>
          </Link>
          <nav aria-label="Footer">
            <ul className="flex items-center gap-1">
              {links.map((l) => (
                <li key={l.label}>
                  <Link href={l.href} prefetch={false} className="inline-flex min-h-[44px] items-center px-3 text-[0.9rem] text-marble-2 transition-colors hover:text-marble">
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
          <span className="mono text-[0.75rem] text-marble-3">© 2026 {site.name}</span>
        </div>
      </div>
    </footer>
  );
}
