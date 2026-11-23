// Generates logo candidates for Protea with fal.ai nano-banana-pro.
// Usage: node --env-file=.env.local scripts/generate-logo.mjs
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const KEY = process.env.FAL_KEY;
if (!KEY) throw new Error("FAL_KEY missing — add it to .env.local");
const OUT = path.resolve("assets/logo-candidates");

const PROMPTS = {
  flower:
    "A minimal, refined logo mark for a software product called Protea. A single stylised protea flower seen from the front, " +
    "its petals drawn as clean pointed arcs like the flutes of a Greek column, forming a symmetrical crown. " +
    "Bright white and luminous Aegean blue (#4aa3ff) on a solid flat deep navy background (#050a14). " +
    "Flat vector style, geometric, crisp edges, perfectly centred with generous empty space around it, reads clearly at 24 pixels. " +
    "No text, no letters, no frame.",
  trident:
    "A minimal, refined logo mark for a software product called Protea, inspired by Proteus the Greek sea god: " +
    "a protea flower whose central petals rise into the three prongs of a trident, above a single curling wave. " +
    "White and luminous Aegean blue (#4aa3ff) on a solid flat deep navy background (#050a14). Flat vector, geometric, symmetrical, " +
    "crisp edges, centred with generous empty space, legible at 24 pixels. No text, no letters, no frame.",
  coin:
    "A minimal logo mark for a software product called Protea in the style of an ancient Greek silver coin seen flat: " +
    "a small circular emblem with a thin Greek key meander ring around a stylised protea flower. " +
    "Bright white lines and luminous Aegean blue (#4aa3ff) on a solid flat deep navy background (#050a14). Flat vector, geometric, " +
    "crisp, centred with generous empty space, legible at 24 pixels. No text, no letters.",
  wave:
    "A minimal, elegant monoline logo mark for a software product called Protea: a protea flower drawn with a single continuous line " +
    "whose petals turn into a Greek wave scroll (running dog motif) at the base. Bright white and luminous Aegean blue (#4aa3ff) " +
    "on a solid flat deep navy background (#050a14). Flat vector, geometric, crisp, centred with generous empty space, " +
    "legible at 24 pixels. No text, no letters, no frame.",
};

async function api(url, body) {
  const res = await fetch(url, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Key ${KEY}`, ...(body && { "Content-Type": "application/json" }) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
}

async function generate(name) {
  const job = await api("https://queue.fal.run/fal-ai/nano-banana-pro", {
    prompt: PROMPTS[name],
    num_images: 2,
    aspect_ratio: "1:1",
    resolution: "1K",
    output_format: "png",
  });
  for (let i = 0; i < 150; i++) {
    const s = await api(job.status_url);
    if (s.status === "COMPLETED") break;
    if (s.status === "FAILED" || s.status === "ERROR") throw new Error(`${name}: ${JSON.stringify(s)}`);
    await new Promise((r) => setTimeout(r, 3000));
  }
  const result = await api(job.response_url);
  await Promise.all(
    (result.images ?? []).map(async (img, i) => {
      const file = path.join(OUT, `${name}-${i + 1}.png`);
      await writeFile(file, Buffer.from(await (await fetch(img.url)).arrayBuffer()));
      console.log(`done ${file}`);
    })
  );
}

await mkdir(OUT, { recursive: true });
const results = await Promise.allSettled(Object.keys(PROMPTS).map(generate));
results.forEach((r) => r.status === "rejected" && console.error(`FAILED: ${r.reason}`));
