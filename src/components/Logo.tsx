import Image from "next/image";
import { site } from "@/lib/site";

// A protea whose heart rises into Poseidon's trident, over a wave: Proteus, the sea god the flower is named for.
export function Mark({ size = 28, className = "" }: { size?: number; className?: string }) {
  return <Image src="/brand/protea-mark.png" alt="" width={size} height={size} className={className} aria-hidden="true" />;
}

export function Wordmark() {
  return (
    <span className="flex items-center gap-2 text-marble">
      <Mark size={30} />
      <span className="text-[1.22rem] font-semibold leading-none tracking-[-0.04em]">{site.name}</span>
    </span>
  );
}
