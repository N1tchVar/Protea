"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";

/**
 * Renders a painting as a living field of braille cells (2×4 dots each).
 * - On load the field "prints" top-to-bottom like a terminal.
 * - Dots shimmer: a few cells re-roll their pattern every beat.
 * - Optional: a cursor lens that shows the real painting underneath (off by default).
 * Falls back to the plain image when WebGL2 is unavailable.
 */
export interface BrailleImageProps {
  src: string;
  /** Braille cell width in CSS px; the cell is twice as tall. */
  cell?: number;
  /** object-position focal point, 0..1 */
  focus?: [number, number];
  /** Background ink as hex. */
  ink?: string;
  /** How much of the painting tints the gaps between dots (0..1). */
  bleed?: number;
  /** Dot brightness multiplier. */
  gain?: number;
  /** Lens radius in CSS px. 0 disables the lens. */
  lens?: number;
  /** Amount the painting shows through everywhere, outside the lens (0..1). */
  reveal?: number;
  /** Play the print-in intro. */
  intro?: boolean;
  /** Let the lens drift when idle. */
  wander?: boolean;
  /** 0 keeps the painting's colours, 1 recolours the dots on a two-tone ramp. */
  tint?: number;
  /** Ramp from shadow to highlight, as hex. */
  ramp?: [string, string];
  className?: string;
  style?: CSSProperties;
  alt?: string;
}

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
uniform sampler2D uImage;
uniform vec2 uRes;
uniform vec2 uImg;
uniform vec2 uFocus;
uniform float uCell;
uniform float uTime;
uniform vec2 uMouse;
uniform float uLens;
uniform float uLensOn;
uniform float uIntro;
uniform float uReveal;
uniform vec3 uInk;
uniform float uBleed;
uniform float uGain;
uniform float uZoom;
uniform float uTint;
uniform vec3 uDeep;
uniform vec3 uBright;
out vec4 outColor;

float hash(vec2 p) {
  p = fract(p * vec2(234.34, 435.345));
  p += dot(p, p + 34.23);
  return fract(p.x * p.y);
}

vec2 coverUV(vec2 px) {
  float rs = uRes.x / uRes.y;
  float ri = uImg.x / uImg.y;
  vec2 scale = rs > ri ? vec2(1.0, ri / rs) : vec2(rs / ri, 1.0);
  scale /= uZoom;
  vec2 uv = px / uRes;
  return uv * scale + (1.0 - scale) * uFocus;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
  // top-left origin, device px
  vec2 px = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);

  vec2 cellSize = vec2(uCell, uCell * 2.0);
  vec2 cellId = floor(px / cellSize);
  vec2 local = fract(px / cellSize);

  // Which of the 8 dots of this cell we are in
  vec2 dotIdx = floor(local * vec2(2.0, 4.0));
  vec2 dotCenter = (cellId + (dotIdx + 0.5) / vec2(2.0, 4.0)) * cellSize;

  // Average the painting under this dot via mip level
  float texPerPx = (uImg.x / uRes.x) * (uRes.x / uRes.y > uImg.x / uImg.y ? 1.0 : (uRes.x / uRes.y) / (uImg.x / uImg.y)) / uZoom;
  float lod = log2(max(1.0, texPerPx * uCell * 0.5));
  vec3 dotCol = textureLod(uImage, coverUV(dotCenter), lod).rgb;
  float lumRaw = luma(dotCol);
  dotCol = mix(dotCol, mix(uDeep, uBright, smoothstep(0.02, 0.95, lumRaw)), uTint);
  vec3 realCol = textureLod(uImage, coverUV(px), log2(max(1.0, texPerPx))).rgb;

  // Ordered thresholds per dot so mid-tones give partial cells
  float order = dotIdx.y * 2.0 + dotIdx.x;
  float bayer[8] = float[8](0.08, 0.58, 0.83, 0.33, 0.46, 0.96, 0.21, 0.71);
  float thr = 0.0;
  for (int i = 0; i < 8; i++) { if (float(i) == order) thr = bayer[i]; }

  // Shimmer: a few cells re-roll every beat
  float beat = floor(uTime * 2.4);
  float jitter = (hash(cellId + beat * 0.37) - 0.5) * 0.22 * step(0.86, hash(cellId * 1.7 + beat));
  float l = pow(lumRaw, 0.85);
  float on = step(thr * 0.92 + 0.04 + jitter, l);

  // Intro: print rows from top to bottom with a hot leading edge
  float rowY = (cellId.y * cellSize.y) / uRes.y;
  float front = uIntro * 1.25 - 0.1 - hash(vec2(cellId.y, cellId.x * 0.13)) * 0.08;
  float printed = step(rowY, front);
  float edge = smoothstep(0.08, 0.0, abs(rowY - front)) * (1.0 - step(0.999, uIntro));
  on *= printed;
  if (edge > 0.0 && hash(cellId + floor(uTime * 24.0)) > 0.5) on = max(on, edge);

  // Lens
  float lens = 0.0;
  float rim = 0.0;
  if (uLensOn > 0.001 && uLens > 0.0) {
    float d = distance(px, uMouse);
    lens = (1.0 - smoothstep(uLens * 0.55, uLens, d)) * uLensOn;
    rim = smoothstep(uLens * 0.45, uLens * 0.85, d) * (1.0 - smoothstep(uLens * 0.85, uLens * 1.35, d)) * uLensOn;
  }

  // Dot shape
  float r = min(cellSize.x / 2.0, cellSize.y / 4.0) * (0.34 + rim * 0.16);
  float dist = length(px - dotCenter);
  float aa = 1.0;
  float dotMask = 1.0 - smoothstep(r - aa, r + aa, dist);
  float glow = exp(-dist * dist / (r * r * 3.0)) * 0.35;

  vec3 lit = dotCol * uGain * (1.0 + edge * 0.6) + uBright * edge * 0.35;
  vec3 ground = mix(uInk, dotCol * 0.55, uBleed * printed);
  vec3 ghost = mix(ground, dotCol, 0.13 * printed); // unraised dots stay faintly visible
  vec3 braille = mix(ground, ghost, dotMask * (1.0 - on));
  braille = mix(braille, lit, dotMask * on);
  braille += lit * glow * on * 0.5;

  vec3 col = mix(braille, realCol, clamp(max(lens, uReveal * printed), 0.0, 1.0));
  outColor = vec4(col, 1.0);
}`;

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  const n = parseInt(h.length === 3 ? h.split("").map((c) => c + c).join("") : h, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

export default function BrailleImage({
  src,
  cell = 8,
  focus = [0.5, 0.5],
  ink = "#040914",
  bleed = 0.18,
  gain = 1.15,
  lens = 0,
  reveal = 0,
  intro = true,
  wander = true,
  tint = 0,
  ramp = ["#06152e", "#cfe6ff"],
  className = "",
  style,
  alt = "",
}: BrailleImageProps) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const live = useRef({ reveal, gain, bleed });
  useEffect(() => {
    live.current = { reveal, gain, bleed };
  }, [reveal, gain, bleed]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (!canvas || !wrap) return;
    const gl = canvas.getContext("webgl2", { antialias: false, premultipliedAlpha: false, alpha: false });
    if (!gl) {
      setFailed(true);
      return;
    }
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const compile = (type: number, source: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s) ?? "shader");
      return s;
    };
    let program: WebGLProgram;
    try {
      program = gl.createProgram()!;
      gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? "link");
    } catch (e) {
      console.error("[BrailleImage]", e);
      setFailed(true);
      return;
    }
    gl.useProgram(program);

    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program, "aPos");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    const u = (n: string) => gl.getUniformLocation(program, n);
    const U = {
      res: u("uRes"), img: u("uImg"), focus: u("uFocus"), cell: u("uCell"), time: u("uTime"),
      mouse: u("uMouse"), lens: u("uLens"), lensOn: u("uLensOn"), intro: u("uIntro"),
      reveal: u("uReveal"), ink: u("uInk"), bleed: u("uBleed"), gain: u("uGain"), zoom: u("uZoom"),
      tint: u("uTint"), deep: u("uDeep"), bright: u("uBright"),
    };

    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    let imgW = 1, imgH = 1;
    let loaded = false;
    const img = new Image();
    img.decoding = "async";
    img.onload = () => {
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img);
      gl.generateMipmap(gl.TEXTURE_2D);
      imgW = img.naturalWidth;
      imgH = img.naturalHeight;
      loaded = true;
      setReady(true);
    };
    img.onerror = () => setFailed(true);
    img.src = src;

    const dpr = () => Math.min(window.devicePixelRatio || 1, 2);
    let W = 1, H = 1;
    const resize = () => {
      const r = wrap.getBoundingClientRect();
      const d = dpr();
      W = Math.max(1, Math.round(r.width * d));
      H = Math.max(1, Math.round(r.height * d));
      canvas.width = W;
      canvas.height = H;
      gl.viewport(0, 0, W, H);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(wrap);

    // Pointer → lens, smoothed
    const target = { x: -9999, y: -9999 };
    const pos = { x: -9999, y: -9999 };
    let lensOn = 0;
    let lastMove = -1e9;
    const onMove = (e: PointerEvent) => {
      if (e.pointerType === "touch") return;
      const r = wrap.getBoundingClientRect();
      const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
      if (!inside) return;
      target.x = (e.clientX - r.left) * dpr();
      target.y = (e.clientY - r.top) * dpr();
      if (pos.x < -1000) { pos.x = target.x; pos.y = target.y; }
      lastMove = performance.now();
    };
    window.addEventListener("pointermove", onMove, { passive: true });

    // The print-in starts the first time the image is actually on screen.
    let visible = false;
    let start = -1;
    const io = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }, { rootMargin: "0px 0px -10% 0px" });
    io.observe(wrap);

    let raf = 0;
    const ink3 = hexToRgb(ink);
    const deep3 = hexToRgb(ramp[0]);
    const bright3 = hexToRgb(ramp[1]);

    const frame = (now: number) => {
      raf = requestAnimationFrame(frame);
      if (!loaded || !visible || document.hidden) return;
      if (start < 0) start = now;
      const t = (now - start) / 1000;
      const d = dpr();

      const idle = now - lastMove > 2600;
      if (idle && wander && lens > 0) {
        // slow lissajous drift across the upper two thirds
        target.x = W * (0.5 + 0.32 * Math.sin(t * 0.21));
        target.y = H * (0.42 + 0.18 * Math.sin(t * 0.33 + 1.2));
        if (pos.x < -1000) { pos.x = target.x; pos.y = target.y; }
      }
      const k = idle ? 0.02 : 0.14;
      pos.x += (target.x - pos.x) * k;
      pos.y += (target.y - pos.y) * k;
      const wantLens = lens > 0 && (wander || !idle) && t > (intro ? 1.6 : 0) ? 1 : 0;
      lensOn += (wantLens - lensOn) * 0.05;

      const introP = intro && !reduced ? Math.min(1, t / 2.1) : 1;
      const eased = 1 - Math.pow(1 - introP, 3);
      const zoom = reduced ? 1.02 : 1.04 + Math.sin(t * 0.05) * 0.02;

      gl.uniform2f(U.res, W, H);
      gl.uniform2f(U.img, imgW, imgH);
      gl.uniform2f(U.focus, focus[0], focus[1]);
      gl.uniform1f(U.cell, cell * d);
      gl.uniform1f(U.time, reduced ? 0 : t);
      gl.uniform2f(U.mouse, pos.x, pos.y);
      gl.uniform1f(U.lens, lens * d * (idle ? 0.8 : 1));
      gl.uniform1f(U.lensOn, lensOn);
      gl.uniform1f(U.intro, eased);
      gl.uniform1f(U.reveal, live.current.reveal);
      gl.uniform3f(U.ink, ink3[0], ink3[1], ink3[2]);
      gl.uniform1f(U.bleed, live.current.bleed);
      gl.uniform1f(U.gain, live.current.gain);
      gl.uniform1f(U.zoom, zoom);
      gl.uniform1f(U.tint, tint);
      gl.uniform3f(U.deep, deep3[0], deep3[1], deep3[2]);
      gl.uniform3f(U.bright, bright3[0], bright3[1], bright3[2]);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
      window.removeEventListener("pointermove", onMove);
      gl.deleteTexture(tex);
      gl.deleteBuffer(buf);
      gl.deleteProgram(program);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [src, cell, focus[0], focus[1], ink, lens, intro, wander, tint, ramp[0], ramp[1]]);

  return (
    <div ref={wrapRef} className={`absolute inset-0 overflow-hidden ${className}`} style={style}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt={alt}
        aria-hidden={alt ? undefined : true}
        className="absolute inset-0 h-full w-full object-cover transition-opacity duration-700"
        style={{ objectPosition: `${focus[0] * 100}% ${focus[1] * 100}%`, opacity: ready && !failed ? 0 : 0.35 }}
      />
      {!failed && (
        <canvas
          ref={canvasRef}
          aria-hidden="true"
          className="absolute inset-0 h-full w-full transition-opacity duration-500"
          style={{ opacity: ready ? 1 : 0 }}
        />
      )}
    </div>
  );
}
