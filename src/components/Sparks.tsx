"use client";

import type { ReactNode } from "react";
import ClickSpark from "@/components/rb/ClickSpark";

// Gold sparks on every click, like flint on a temple step.
export default function Sparks({ children }: { children: ReactNode }) {
  return (
    <ClickSpark
      sparkColor={["#4aa3ff", "#9fd0ff", "#ffffff"]}
      sparkSize={9}
      sparkRadius={22}
      sparkCount={9}
      duration={520}
      shape="streak"
      glow={0.6}
      className="!h-auto"
    >
      {children}
    </ClickSpark>
  );
}
