"use client";

import { useRef, useEffect, useState, useCallback } from "react";
import { toPng } from "html-to-image";

// ─── Canvas dimensions ────────────────────────────────────────────────────────
const W = 1320;
const H = 2868;

// ─── Mockup measurements (pre-measured from mockup.png) ──────────────────────
const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

// ─── Export sizes ─────────────────────────────────────────────────────────────
const SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

// ─── Phone mockup component ───────────────────────────────────────────────────
function Phone({
  src,
  alt,
  style,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
}) {
  return (
    <div style={{ aspectRatio: `${MK_W}/${MK_H}`, position: "relative", ...style }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/mockup.png"
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={src}
          alt={alt}
          style={{
            display: "block",
            width: "100%",
            height: "100%",
            objectFit: "cover",
            objectPosition: "top",
          }}
          draggable={false}
        />
      </div>
    </div>
  );
}

// ─── Caption component ────────────────────────────────────────────────────────
function Caption({
  label,
  lines,
  labelColor = "#007AFF",
  headlineColor = "#1C1C1E",
  canvasW = W,
  align = "left",
}: {
  label: string;
  lines: string[];
  labelColor?: string;
  headlineColor?: string;
  canvasW?: number;
  align?: "left" | "center";
}) {
  const sf = canvasW / W;
  return (
    <div style={{ textAlign: align }}>
      <div
        style={{
          fontSize: canvasW * 0.028,
          fontWeight: 600,
          letterSpacing: "0.12em",
          textTransform: "uppercase" as const,
          color: labelColor,
          marginBottom: canvasW * 0.022,
          fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
          fontWeight: 700,
          lineHeight: 1.0,
          color: headlineColor,
        }}
      >
        {lines.map((line, i) => (
          <div key={i} style={{ fontSize: canvasW * 0.094 * sf, lineHeight: 1.0 }}>
            {line}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Decorative blob ──────────────────────────────────────────────────────────
function Blob({
  color,
  style,
}: {
  color: string;
  style?: React.CSSProperties;
}) {
  return (
    <div
      style={{
        position: "absolute",
        borderRadius: "50%",
        background: `radial-gradient(circle, ${color} 0%, transparent 70%)`,
        pointerEvents: "none",
        ...style,
      }}
    />
  );
}

// ─── Slide 1: Hero ────────────────────────────────────────────────────────────
// "Clean your camera roll." — warm cream, centered phone with app icon badge
function Slide1({ canvasW = W }: { canvasW?: number }) {
  const h = (canvasW / W) * H;
  const sf = canvasW / W;
  return (
    <div
      style={{
        width: canvasW,
        height: h,
        background: "linear-gradient(155deg, #FAF8F5 0%, #EEE7DA 100%)",
        position: "relative",
        overflow: "hidden",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      }}
    >
      <Blob
        color="rgba(0,122,255,0.09)"
        style={{ top: "-12%", left: "-18%", width: "75%", height: "55%" }}
      />
      <Blob
        color="rgba(0,122,255,0.05)"
        style={{ bottom: "8%", right: "-12%", width: "60%", height: "42%" }}
      />

      {/* Caption */}
      <div style={{ position: "absolute", top: canvasW * 0.115, left: canvasW * 0.088 }}>
        <Caption
          label="Photo Cleaner"
          lines={["Clean your", "camera roll."]}
          canvasW={canvasW}
        />
      </div>

      {/* App icon */}
      <div
        style={{
          position: "absolute",
          top: canvasW * 0.088,
          right: canvasW * 0.088,
          width: canvasW * 0.15,
          height: canvasW * 0.15,
          borderRadius: canvasW * 0.030,
          overflow: "hidden",
          boxShadow: `0 ${sf * 8}px ${sf * 28}px rgba(0,0,0,0.18)`,
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/app-icon.png"
          alt="PhotoSoap"
          style={{ width: "100%", height: "100%" }}
          draggable={false}
        />
      </div>

      {/* Centered phone */}
      <Phone
        src="/screenshots/review.png"
        alt="PhotoSoap review screen"
        style={{
          position: "absolute",
          width: canvasW * 0.83,
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(20%)",
        }}
      />
    </div>
  );
}

// ─── Slide 2: Swipe mechanic ──────────────────────────────────────────────────
// "Keep. Delete. Swipe." — cool-white bg, two phones layered
function Slide2({ canvasW = W }: { canvasW?: number }) {
  const h = (canvasW / W) * H;
  return (
    <div
      style={{
        width: canvasW,
        height: h,
        background: "linear-gradient(160deg, #F2F6FF 0%, #EBF1FF 55%, #E6EDF8 100%)",
        position: "relative",
        overflow: "hidden",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      }}
    >
      <Blob
        color="rgba(52,199,89,0.13)"
        style={{ top: "28%", right: "-8%", width: "55%", height: "42%" }}
      />
      <Blob
        color="rgba(255,59,48,0.09)"
        style={{ top: "32%", left: "-12%", width: "52%", height: "38%" }}
      />
      <Blob
        color="rgba(0,122,255,0.07)"
        style={{ top: "-8%", left: "20%", width: "60%", height: "40%" }}
      />

      {/* Caption */}
      <div style={{ position: "absolute", top: canvasW * 0.1, left: canvasW * 0.088 }}>
        <Caption
          label="Instant Decisions"
          lines={["Keep.", "Delete.", "Swipe."]}
          canvasW={canvasW}
        />
      </div>

      {/* Back phone: delete (left, rotated, dimmed) */}
      <Phone
        src="/screenshots/delete.png"
        alt="Delete gesture"
        style={{
          position: "absolute",
          width: canvasW * 0.63,
          bottom: 0,
          left: "-6%",
          transform: "rotate(-5deg) translateY(17%)",
          opacity: 0.5,
        }}
      />

      {/* Front phone: keep (right) */}
      <Phone
        src="/screenshots/keep.png"
        alt="Keep gesture"
        style={{
          position: "absolute",
          width: canvasW * 0.80,
          bottom: 0,
          right: "-5%",
          transform: "translateY(18%)",
        }}
      />
    </div>
  );
}

// ─── Slide 3: Daily Goals (dark contrast) ─────────────────────────────────────
// "Ten a day. Every day." — dark navy, orange fire accent
function Slide3({ canvasW = W }: { canvasW?: number }) {
  const h = (canvasW / W) * H;
  return (
    <div
      style={{
        width: canvasW,
        height: h,
        background: "linear-gradient(160deg, #0A0F1E 0%, #0F1728 60%, #121D35 100%)",
        position: "relative",
        overflow: "hidden",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      }}
    >
      <Blob
        color="rgba(255,149,0,0.18)"
        style={{ top: "-8%", right: "-8%", width: "72%", height: "52%" }}
      />
      <Blob
        color="rgba(0,122,255,0.12)"
        style={{ bottom: "5%", left: "-14%", width: "65%", height: "44%" }}
      />

      {/* Decorative fire dot */}
      <div
        style={{
          position: "absolute",
          top: canvasW * 0.08,
          right: canvasW * 0.09,
          fontSize: canvasW * 0.12,
          opacity: 0.22,
          lineHeight: 1,
        }}
      >
        🔥
      </div>

      {/* Caption */}
      <div style={{ position: "absolute", top: canvasW * 0.115, left: canvasW * 0.088 }}>
        <Caption
          label="Daily Goals"
          lines={["Ten a day.", "Every day."]}
          labelColor="#FF9500"
          headlineColor="#FFFFFF"
          canvasW={canvasW}
        />
      </div>

      {/* Centered phone */}
      <Phone
        src="/screenshots/streak.png"
        alt="Streak and goal screen"
        style={{
          position: "absolute",
          width: canvasW * 0.83,
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(20%)",
        }}
      />
    </div>
  );
}

// ─── Slide 4: Build a Streak ──────────────────────────────────────────────────
// "Build a habit. Keep it going." — warm peach, streak motif
function Slide4({ canvasW = W }: { canvasW?: number }) {
  const h = (canvasW / W) * H;
  const sf = canvasW / W;
  return (
    <div
      style={{
        width: canvasW,
        height: h,
        background: "linear-gradient(150deg, #FFF9F4 0%, #FFF0E2 50%, #FDEBD5 100%)",
        position: "relative",
        overflow: "hidden",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      }}
    >
      <Blob
        color="rgba(255,149,0,0.12)"
        style={{ top: "-10%", left: "-8%", width: "68%", height: "52%" }}
      />
      <Blob
        color="rgba(0,122,255,0.07)"
        style={{ bottom: "18%", right: "-10%", width: "58%", height: "42%" }}
      />

      {/* Subtle streak badge */}
      <div
        style={{
          position: "absolute",
          top: canvasW * 0.088,
          right: canvasW * 0.088,
          background: "rgba(255,149,0,0.12)",
          borderRadius: canvasW * 0.04,
          padding: `${sf * 14}px ${sf * 22}px`,
          display: "flex",
          alignItems: "center",
          gap: sf * 8,
        }}
      >
        <span style={{ fontSize: canvasW * 0.055 }}>🔥</span>
        <span
          style={{
            fontSize: canvasW * 0.048,
            fontWeight: 700,
            color: "#FF6B00",
            fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
          }}
        >
          Streak
        </span>
      </div>

      {/* Caption */}
      <div style={{ position: "absolute", top: canvasW * 0.115, left: canvasW * 0.088 }}>
        <Caption
          label="Build a Streak"
          lines={["Build a habit.", "Keep it going."]}
          labelColor="#FF9500"
          canvasW={canvasW}
        />
      </div>

      {/* Centered phone */}
      <Phone
        src="/screenshots/review.png"
        alt="Review screen with streak counter"
        style={{
          position: "absolute",
          width: canvasW * 0.83,
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(20%)",
        }}
      />
    </div>
  );
}

// ─── Slide 5: Stats / Impact ──────────────────────────────────────────────────
// "See your impact." — cool-warm light bg, stats screen centered
function Slide5({ canvasW = W }: { canvasW?: number }) {
  const h = (canvasW / W) * H;
  return (
    <div
      style={{
        width: canvasW,
        height: h,
        background: "linear-gradient(155deg, #F4F8FF 0%, #EBF2FF 50%, #E6EDF8 100%)",
        position: "relative",
        overflow: "hidden",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      }}
    >
      <Blob
        color="rgba(0,122,255,0.1)"
        style={{ top: "-10%", right: "-10%", width: "68%", height: "50%" }}
      />
      <Blob
        color="rgba(52,199,89,0.08)"
        style={{ bottom: "10%", left: "-8%", width: "55%", height: "40%" }}
      />

      {/* Caption */}
      <div style={{ position: "absolute", top: canvasW * 0.115, left: canvasW * 0.088 }}>
        <Caption
          label="Your Impact"
          lines={["See what", "you've freed."]}
          canvasW={canvasW}
        />
      </div>

      {/* Centered phone */}
      <Phone
        src="/screenshots/stats.jpg"
        alt="Statistics screen"
        style={{
          position: "absolute",
          width: canvasW * 0.83,
          bottom: 0,
          left: "50%",
          transform: "translateX(-50%) translateY(20%)",
        }}
      />
    </div>
  );
}

// ─── Slide registry ───────────────────────────────────────────────────────────
const SLIDES = [
  { id: "slide1", label: "Hero", Component: Slide1 },
  { id: "slide2", label: "Swipe", Component: Slide2 },
  { id: "slide3", label: "Goals", Component: Slide3 },
  { id: "slide4", label: "Streak", Component: Slide4 },
  { id: "slide5", label: "Stats", Component: Slide5 },
] as const;

// ─── Preview card ─────────────────────────────────────────────────────────────
function PreviewCard({
  label,
  index,
  Component,
  onMount,
}: {
  label: string;
  index: number;
  Component: React.ComponentType<{ canvasW?: number }>;
  onMount: (el: HTMLDivElement | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.2);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      setScale(el.clientWidth / W);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div>
      <div
        style={{
          fontSize: 12,
          fontWeight: 500,
          color: "#8E8E93",
          marginBottom: 8,
          fontFamily: "system-ui",
          letterSpacing: "0.04em",
        }}
      >
        {String(index + 1).padStart(2, "0")} — {label}
      </div>

      {/* Scaled preview */}
      <div
        ref={containerRef}
        style={{
          width: "100%",
          aspectRatio: `${W}/${H}`,
          overflow: "hidden",
          borderRadius: 16,
          boxShadow: "0 4px 24px rgba(0,0,0,0.12)",
          position: "relative",
          background: "#eee",
        }}
      >
        <div
          style={{
            width: W,
            height: H,
            transform: `scale(${scale})`,
            transformOrigin: "top left",
            position: "absolute",
            top: 0,
            left: 0,
          }}
        >
          <Component canvasW={W} />
        </div>
      </div>

      {/* Offscreen export target */}
      <div
        ref={onMount}
        style={{
          position: "absolute",
          left: "-9999px",
          top: 0,
          width: W,
          height: H,
          fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
        }}
      >
        <Component canvasW={W} />
      </div>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────
export default function ScreenshotsPage() {
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState(false);
  const exportEls = useRef<(HTMLDivElement | null)[]>([]);

  const selectedSize = SIZES[sizeIdx];

  const exportAll = useCallback(async () => {
    setExporting(true);
    for (let i = 0; i < SLIDES.length; i++) {
      const el = exportEls.current[i];
      if (!el) continue;

      // Move on-screen so html-to-image can render it
      el.style.left = "0px";
      el.style.opacity = "1";
      el.style.zIndex = "-1";

      await new Promise((r) => setTimeout(r, 120));

      // skipFonts avoids cross-origin stylesheet access and the font.trim() crash —
      // we use system fonts so font embedding is not needed anyway.
      const opts = {
        width: W,
        height: H,
        pixelRatio: 1,
        cacheBust: true,
        skipFonts: true,
      };
      // Double-call: first warms up images, second produces clean output
      await toPng(el, opts);
      const dataUrl = await toPng(el, opts);

      // Move back off-screen
      el.style.left = "-9999px";
      el.style.opacity = "";
      el.style.zIndex = "";

      // Resize to target dimensions
      const img = new Image();
      img.src = dataUrl;
      await new Promise((r) => (img.onload = r));

      const canvas = document.createElement("canvas");
      canvas.width = selectedSize.w;
      canvas.height = selectedSize.h;
      const ctx = canvas.getContext("2d")!;
      ctx.drawImage(img, 0, 0, selectedSize.w, selectedSize.h);

      const finalUrl = canvas.toDataURL("image/png");
      const a = document.createElement("a");
      a.href = finalUrl;
      a.download = `${String(i + 1).padStart(2, "0")}-${SLIDES[i].label.toLowerCase()}-${selectedSize.w}x${selectedSize.h}.png`;
      a.click();

      await new Promise((r) => setTimeout(r, 300));
    }
    setExporting(false);
  }, [selectedSize]);

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#F2F2F7",
        padding: "32px 24px",
        fontFamily: "system-ui",
      }}
    >
      {/* Toolbar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          marginBottom: 36,
          flexWrap: "wrap" as const,
        }}
      >
        <div>
          <h1
            style={{
              fontSize: 22,
              fontWeight: 700,
              color: "#1C1C1E",
              margin: 0,
              letterSpacing: "-0.02em",
            }}
          >
            PhotoSoap
          </h1>
          <p style={{ fontSize: 13, color: "#8E8E93", margin: "2px 0 0", fontWeight: 400 }}>
            App Store Screenshots
          </p>
        </div>
        <div
          style={{ marginLeft: "auto", display: "flex", gap: 10, alignItems: "center" }}
        >
          <select
            value={sizeIdx}
            onChange={(e) => setSizeIdx(Number(e.target.value))}
            style={{
              padding: "8px 12px",
              borderRadius: 10,
              border: "1px solid #C7C7CC",
              fontSize: 14,
              background: "white",
              color: "#1C1C1E",
              fontFamily: "system-ui",
            }}
          >
            {SIZES.map((s, i) => (
              <option key={i} value={i}>
                {s.label} — {s.w}×{s.h}
              </option>
            ))}
          </select>
          <button
            onClick={exportAll}
            disabled={exporting}
            style={{
              padding: "8px 20px",
              borderRadius: 10,
              background: exporting ? "#C7C7CC" : "#007AFF",
              color: "white",
              fontWeight: 600,
              fontSize: 14,
              border: "none",
              cursor: exporting ? "not-allowed" : "pointer",
              fontFamily: "system-ui",
              transition: "background 0.15s",
            }}
          >
            {exporting ? "Exporting…" : "Export All"}
          </button>
        </div>
      </div>

      {/* Grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))",
          gap: 36,
        }}
      >
        {SLIDES.map((slide, i) => (
          <PreviewCard
            key={slide.id}
            label={slide.label}
            index={i}
            Component={slide.Component}
            onMount={(el) => {
              exportEls.current[i] = el;
            }}
          />
        ))}
      </div>
    </div>
  );
}
