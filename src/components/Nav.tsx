"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import PillNav from "@/components/rb/PillNav";
import { Mark } from "@/components/Logo";
import { site } from "@/lib/site";

const items = [
  { label: "Features", href: "#features" },
  { label: "Overview", href: "#overview" },
  { label: "Download", href: site.download.href },
];

// A long, see-through glass bar: brand on the left, React Bits PillNav in the middle, download on the right.
export default function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-3 z-50 px-3 sm:top-4 sm:px-4">
      <div
        className={`mx-auto flex h-[56px] max-w-[760px] items-center gap-3 rounded-full border pl-4 pr-1.5 backdrop-blur-md backdrop-saturate-150 transition-[background-color,border-color,box-shadow] duration-500 sm:pl-5 ${
          scrolled
            ? "border-[rgba(150,190,255,0.12)] bg-[rgba(6,14,30,0.22)] shadow-[0_20px_50px_-30px_rgba(0,0,0,0.8)]"
            : "border-[rgba(150,190,255,0.08)] bg-[rgba(6,14,30,0.08)]"
        }`}
      >
        <Link href="#top" className="flex shrink-0 items-center gap-2.5" aria-label={`${site.name} home`}>
          <Mark size={30} />
          <span className="text-[1.15rem] font-semibold tracking-[-0.04em] text-marble">{site.name}</span>
        </Link>

        <div className="flex min-w-0 flex-1 justify-end md:justify-center">
          <PillNav
            items={items}
            theme="dark"
            layout="joined"
            surface="none"
            size="md"
            itemStyle="plain"
            hoverEffect="fill"
            indicator="none"
            defaultActiveIndex={-1}
            highlightColor="#4aa3ff"
            highlightTextColor="#ffffff"
            textColor="#c9d7ec"
            ariaLabel="Main"
            className="data-[collapsed]:justify-end"
          />
        </div>

        <span className="hidden shrink-0 md:block">
          <Link href={site.download.href} prefetch={false} className="btn btn-primary !min-h-[44px] !px-5 text-[0.9rem]">
            <AppleGlyph />
            Download
          </Link>
        </span>
      </div>
    </header>
  );
}

export function AppleGlyph({ className = "h-[15px] w-[15px]" }: { className?: string }) {
  return (
    <svg viewBox="0 0 384 512" className={className} fill="currentColor" aria-hidden="true">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}
