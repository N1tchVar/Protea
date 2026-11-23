import { NextResponse } from "next/server";
import { site } from "@/lib/site";

// A short link to the newest build: /download/latest → the latest GitHub release asset.
export function GET() {
  return NextResponse.redirect(process.env.PROTEA_DMG_URL || site.download.href, 302);
}
