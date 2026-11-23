// Generates the site's painted backgrounds with fal.ai nano-banana-pro.
// Usage: node --env-file=.env.local scripts/generate-images.mjs [name ...]
import { mkdir, writeFile, access } from "node:fs/promises";
import path from "node:path";

const KEY = process.env.FAL_KEY;
if (!KEY) throw new Error("FAL_KEY missing — add it to .env.local");

const MODEL = "fal-ai/nano-banana-pro";
const OUT = path.resolve("assets/paintings-raw");

const STYLE =
  "A 19th-century romantic classical oil painting in the manner of the Hudson River School and Claude Lorrain. " +
  "Luminous Mediterranean light, atmospheric perspective, rich layered brushwork and visible canvas texture, " +
  "warm sun-bleached marble, deep crimson and ochre robes, olive greens, Aegean blues. Museum-quality masterpiece. " +
  "Full-bleed: the painted scene fills the entire canvas edge to edge. No picture frame, no gilded border, no text, no lettering, no signature, no monogram, no watermark.";

export const SCENES = {
  // Blue-hour versions, to sit inside the Aegean palette
  council_blue:
    "The gods of Olympus seated in council on a curved white marble hemicycle high among silver-blue clouds above snowy peaks, in cool early-morning light. " +
    "Zeus enthroned at the centre: a powerful bare-chested old god with a thick white beard, a white himation, a golden thunderbolt and an eagle beside his throne, " +
    "gesturing toward a marble table with an unrolled map; Athena in a bronze helmet, Hermes in a winged cap, Poseidon with a trident, other gods in white and deep blue robes. " +
    "Pale azure sky, cool blue shadows. Pagan Greek mythology only, no halos.",
  hermes_blue:
    "Hermes with winged sandals and a winged cap flying across a deep valley under a vast clear azure sky, carrying a sealed scroll and his caduceus, " +
    "between two small white hilltop temples on opposite cliffs. Cool bright daylight, deep blue river far below, layered blue mountains, his cloak deep ultramarine. " +
    "Wide composition with plenty of open blue sky.",
  library_blue:
    "Interior of a grand ancient Greek library at night, lit by cool blue moonlight pouring through tall arched windows and one small oil lamp. " +
    "Walls of wooden pigeonholes filled with rolled papyrus scrolls, white marble columns, a scholar in a deep blue robe unrolling a long scroll at a marble table. " +
    "Deep blue night sky and the sea visible through the windows. Cool blue palette with a single warm lamp glow.",
  workshop_blue:
    "The vast workshop of Daedalus in ancient Crete in cool morning light, white marble hall with tall windows open to a bright blue sea and sky. " +
    "Many wooden workbenches, each with its own project — large drawings pinned to easels, models of machines, a pair of feathered wings on a frame, scrolls of plans. " +
    "Apprentices in pale tunics work at different benches while a master in a deep blue robe walks between them. Cool blue and white palette.",
  proteus:
    "Proteus, the bearded Old Man of the Sea, a shape-shifting Greek sea god, rising from deep blue moonlit waves beside a dark rocky shore, " +
    "seals resting on the rocks around him, sea foam swirling into the shapes of a lion, a serpent and a tree around his body. " +
    "Deep ultramarine and silver palette under a full moon, sublime and mysterious, large areas of deep blue shadow.",

  hero:
    "A vast panoramic view from a sunlit marble temple terrace in ancient Greece. Tall fluted Corinthian columns of a temple portico on the far left, " +
    "an ancient olive tree with a broad canopy on the far right. Between them a deep green valley with a winding river, a small white city, " +
    "a turquoise bay and a majestic snow-capped mountain under a clear blue sky with soft cumulus clouds. " +
    "In the middle distance on the terrace a single watchman in a crimson cloak stands at a marble balustrade, gazing out over the valley. " +
    "The lower third of the image is a wide, calm, softly shaded marble terrace floor with few details.",
  council:
    "The gods of Olympus seated in council on a curved marble hemicycle high among golden clouds above the peaks of Mount Olympus. " +
    "Zeus enthroned at the centre presiding: a powerful, muscular, bare-chested old god with a thick curly white beard, a white himation draped over one shoulder, a golden thunderbolt in his hand and a great eagle perched beside his throne. He gestures toward a large marble table with an unrolled map; Athena in a bronze helmet, Hermes in a winged cap, Poseidon with a trident and other gods in crimson, ochre and blue robes lean in to debate. Pagan Greek mythology only, no halos. Shafts of golden light break through the clouds. Wide composition with open sky on the upper half.",
  hermes:
    "Hermes with winged sandals and a winged cap flying across a deep valley at golden hour, carrying a sealed scroll and his caduceus, " +
    "between two small hilltop temples that face each other on opposite cliffs. Warm late sunlight, long shadows, a ribbon of river far below, " +
    "distant blue mountains. Wide composition with plenty of open sky.",
  library:
    "Interior of a grand ancient Greek library at dusk. Tall walls of wooden pigeonholes filled with rolled papyrus scrolls, marble columns, " +
    "a scholar in a crimson robe unrolling a long scroll on a marble table lit by bronze oil lamps, an open doorway showing an evening sky. " +
    "Warm chiaroscuro, deep shadows, glowing amber light.",
  beacons:
    "A chain of signal beacon fires burning on distant mountain peaks at deep blue twilight, receding towards the horizon across the Aegean sea and islands. " +
    "In the foreground, on a rocky summit, a watchman in a crimson cloak raises a blazing torch toward the next peak. First stars in the sky, embers drifting.",
  fleet:
    "A fleet of ancient Greek triremes with crimson and ochre sails crossing a calm turquoise Aegean sea in morning light, oars in rhythm, " +
    "heading toward a white coastal city with a temple on its acropolis. Islands on the horizon, gulls, soft clouds, sparkling water.",
  workshop:
    "The vast sunlit workshop of Daedalus in ancient Crete. Long marble hall with high windows, many wooden workbenches each with its own project — " +
    "large drawings pinned to easels, models of machines, a pair of feathered wings on a frame, scrolls of plans. Apprentices in tunics work at different benches " +
    "while a master in a crimson robe walks between them. Shafts of dusty golden light.",
  delphi:
    "The Oracle at Delphi: the shadowed interior of a Greek temple, the Pythia seated on a tall bronze tripod above a cleft from which pale vapours rise, " +
    "pilgrims in robes kneel and listen, bright shafts of light fall between massive columns onto a marble floor, a laurel tree and mountains visible beyond.",
  styx:
    "Charon's narrow wooden boat gliding across the dark, misty underworld river Acheron beneath towering black cliffs. A single bronze lantern at the bow " +
    "casts a warm golden reflection on the still black water. Faint ghostly figures wait on a distant shore under a deep ember-tinted sky. " +
    "Mostly dark, moody, sublime, large areas of deep shadow. The scene extends to every edge of the image.",
  night:
    "A white marble Doric temple on a high cliff above a calm sea at night under a breathtaking star-filled sky with the Milky Way arching overhead. " +
    "Moonlight silvers the columns and the water, a small fire burns at the temple steps, silhouetted cypress trees. Deep blue and gold palette, mostly dark.",
};

const ASPECT = { hero: "16:9" };

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
  const file = path.join(OUT, `${name}.png`);
  try {
    await access(file);
    console.log(`skip ${name} (exists)`);
    return;
  } catch {}
  const job = await api(`https://queue.fal.run/${MODEL}`, {
    prompt: `${SCENES[name]} ${STYLE}`,
    num_images: 1,
    aspect_ratio: ASPECT[name] ?? "16:9",
    resolution: "2K",
    output_format: "png",
  });
  for (let i = 0; i < 150; i++) {
    const s = await api(job.status_url);
    if (s.status === "COMPLETED") break;
    if (s.status === "FAILED" || s.status === "ERROR") throw new Error(`${name}: ${JSON.stringify(s)}`);
    await new Promise((r) => setTimeout(r, 3000));
  }
  const result = await api(job.response_url);
  const url = result.images?.[0]?.url;
  if (!url) throw new Error(`${name}: no image in ${JSON.stringify(result)}`);
  const img = await fetch(url);
  await writeFile(file, Buffer.from(await img.arrayBuffer()));
  console.log(`done ${name} → ${file}`);
}

await mkdir(OUT, { recursive: true });
const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(SCENES);
const results = await Promise.allSettled(names.map(generate));
results.forEach((r, i) => r.status === "rejected" && console.error(`FAILED ${names[i]}: ${r.reason}`));
