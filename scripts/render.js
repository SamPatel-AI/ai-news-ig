#!/usr/bin/env node
/**
 * Render slides.json → PNG files via puppeteer. (v2 design)
 *
 * Usage:
 *   node scripts/render.js \
 *     --slides path/to/slides.json \
 *     --brand  path/to/brand.json \
 *     --out    path/to/output_dir/ \
 *     [--skip-font-check]
 *
 * Design goals (v2):
 *   - Editorial, high-contrast look inspired by @evolving.ai-style AI carousels.
 *   - Per-slide layout variety: no two slide types share a layout.
 *   - Accent color used as bold shapes/fills, not just text color, for scroll-stop.
 *   - Optional visual hints in slide JSON (tag, eyebrow, stat) that Claude fills
 *     at content-generation time — renders gracefully if omitted.
 *
 * Hardening carried over from v1:
 *   - 4s Google Fonts timeout → logs font_fallback
 *   - Per-slide try/catch → one bad slide doesn't kill the carousel
 *   - TODO_ sentinel fail-fast in brand.json
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

// ─── CLI args ────────────────────────────────────────────────────────────────

function parseArgs() {
  const args = { _flags: new Set() };
  for (let i = 2; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.replace(/^--/, '');
    const next = process.argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      args._flags.add(key);
    } else {
      args[key] = next;
      i++;
    }
  }
  return args;
}

const argv = parseArgs();
const { slides: slidesPath, brand: brandPath, out: outDir } = argv;
const SKIP_FONT_CHECK = argv._flags.has('skip-font-check');

if (!slidesPath || !brandPath || !outDir) {
  console.error('Usage: render.js --slides <path> --brand <path> --out <dir> [--skip-font-check]');
  process.exit(1);
}

const slides = JSON.parse(fs.readFileSync(slidesPath, 'utf8'));
const brand  = JSON.parse(fs.readFileSync(brandPath,  'utf8'));

// ─── Fail-fast: refuse TODO_ sentinels ───────────────────────────────────────

const sentinelFields = ['handle', 'brand_name', 'niche', 'voice'];
const badSentinels = sentinelFields
  .filter(f => typeof brand[f] === 'string' && brand[f].startsWith('TODO_'));
if (badSentinels.length) {
  console.error(`render.js: brand.json still has TODO_ placeholder(s) in: ${badSentinels.join(', ')}`);
  console.error('Fill in brand.json before rendering. Refusing to produce off-brand output.');
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });

// ─── Viewport per aspect ratio ──────────────────────────────────────────────

const VIEWPORTS = {
  '4:5':  { width: 1080, height: 1350 },
  '9:16': { width: 1080, height: 1920 },
  '1:1':  { width: 1080, height: 1080 },
};
const viewport = VIEWPORTS[slides.aspect] || VIEWPORTS['4:5'];

// ─── Shared styles ──────────────────────────────────────────────────────────

function baseStyles() {
  const { colors, fonts } = brand;
  const fontImport = SKIP_FONT_CHECK
    ? ''
    : `@import url('https://fonts.googleapis.com/css2?family=${encodeURIComponent(fonts.heading)}:wght@${fonts.heading_weight}&family=${encodeURIComponent(fonts.body)}:wght@${fonts.body_weight}&display=swap');`;
  return `
    ${fontImport}
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: ${viewport.width}px;
      height: ${viewport.height}px;
      background: ${colors.background};
      color: ${colors.text};
      font-family: '${fonts.body}', -apple-system, BlinkMacSystemFont, sans-serif;
      font-weight: ${fonts.body_weight};
      overflow: hidden;
      -webkit-font-smoothing: antialiased;
    }
    .slide {
      width: 100%;
      height: 100%;
      padding: 80px 72px;
      display: flex;
      flex-direction: column;
      position: relative;
      overflow: hidden;
    }
    .heading {
      font-family: '${fonts.heading}', -apple-system, BlinkMacSystemFont, sans-serif;
      font-weight: ${fonts.heading_weight};
      line-height: 1.02;
      letter-spacing: -0.03em;
      color: ${colors.text};
    }
    .body-text {
      font-size: 32px;
      line-height: 1.4;
      color: ${colors.muted_text};
      letter-spacing: -0.005em;
    }
    .accent { color: ${colors.accent}; }
    .eyebrow {
      font-family: '${fonts.heading}', -apple-system, sans-serif;
      font-weight: 800;
      font-size: 22px;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      color: ${colors.accent};
    }
    .tag-pill {
      display: inline-block;
      padding: 10px 22px;
      background: ${colors.primary};
      color: ${colors.background};
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 800;
      font-size: 22px;
      border-radius: 999px;
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }
    .handle {
      position: absolute;
      bottom: 48px;
      left: 72px;
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 800;
      font-size: 22px;
      color: ${colors.muted_text};
      letter-spacing: 0.05em;
    }
    .page-num {
      position: absolute;
      bottom: 48px;
      right: 72px;
      font-size: 22px;
      color: ${colors.muted_text};
      font-variant-numeric: tabular-nums;
      letter-spacing: 0.05em;
    }
    .corner-shape {
      position: absolute;
      top: -200px;
      right: -200px;
      width: 600px;
      height: 600px;
      background: ${colors.accent};
      border-radius: 50%;
      opacity: 1;
      z-index: 0;
    }
    .corner-shape-sm {
      position: absolute;
      top: -80px;
      right: -80px;
      width: 320px;
      height: 320px;
      background: ${colors.primary};
      border-radius: 50%;
      opacity: 0.95;
      z-index: 0;
    }
    .stat-card {
      display: inline-block;
      padding: 24px 32px;
      background: ${colors.accent};
      color: ${colors.background};
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 900;
      font-size: 72px;
      line-height: 1;
      letter-spacing: -0.02em;
      border-radius: 24px;
      box-shadow: 0 8px 0 ${colors.primary};
    }
    .big-number-watermark {
      position: absolute;
      top: 60px;
      right: 50px;
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 900;
      font-size: 520px;
      line-height: 1;
      color: ${colors.accent};
      opacity: 0.08;
      z-index: 0;
      letter-spacing: -0.05em;
    }
    .divider {
      width: 88px;
      height: 6px;
      background: ${colors.accent};
      border-radius: 3px;
    }
    .source-line {
      font-size: 20px;
      color: ${colors.muted_text};
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }
    .source-badge {
      display: inline-block;
      padding: 10px 20px;
      background: ${colors.primary};
      color: ${colors.background};
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 800;
      font-size: 20px;
      border-radius: 999px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .icymi-pill {
      display: inline-block;
      padding: 10px 22px;
      background: ${colors.accent};
      color: ${colors.background};
      font-family: '${fonts.heading}', sans-serif;
      font-weight: 800;
      font-size: 22px;
      border-radius: 999px;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }
    .relative { position: relative; z-index: 1; }
  `;
}

function wrapHTML(innerBody) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${baseStyles()}</style></head><body><div class="slide">${innerBody}</div></body></html>`;
}

// ─── Slide renderers (v2 layouts) ────────────────────────────────────────────

function renderHook(slide, pageNum, total) {
  const { colors } = brand;
  return wrapHTML(`
    <div class="corner-shape"></div>
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: space-between;">
      <div>
        ${slide.tag ? `<span class="tag-pill">${escapeHTML(slide.tag)}</span>` : ''}
      </div>
      <div>
        <div class="heading" style="font-size: 120px; margin-bottom: 36px; max-width: 90%;">
          ${escapeHTML(slide.headline)}
        </div>
        <div class="divider" style="margin-bottom: 32px;"></div>
        ${slide.subtext ? `<div class="body-text" style="font-size: 38px; color: ${colors.text}; max-width: 90%;">${escapeHTML(slide.subtext)}</div>` : ''}
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
    <div class="page-num">${pageNum} / ${total}</div>
  `);
}

function renderContext(slide, pageNum, total) {
  const eyebrow = slide.eyebrow || 'THE CONTEXT';
  return wrapHTML(`
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: center;">
      <div class="eyebrow" style="margin-bottom: 32px;">${escapeHTML(eyebrow)}</div>
      <div class="heading" style="font-size: 64px; margin-bottom: 40px;">
        ${escapeHTML(slide.headline)}
      </div>
      <div class="divider" style="margin-bottom: 32px;"></div>
      <div class="body-text" style="font-size: 36px; color: ${brand.colors.text}; max-width: 95%;">
        ${escapeHTML(slide.body)}
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
    <div class="page-num">${pageNum} / ${total}</div>
  `);
}

function renderPoint(slide, pageNum, total) {
  const numStr = `0${slide.number}`;
  return wrapHTML(`
    <div class="big-number-watermark">${numStr}</div>
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: center;">
      <div style="display: flex; align-items: baseline; gap: 24px; margin-bottom: 36px;">
        <div class="heading accent" style="font-size: 80px; line-height: 1;">${numStr}</div>
        <div class="divider" style="flex: 1; max-width: 160px;"></div>
      </div>
      <div class="heading" style="font-size: 76px; margin-bottom: 36px; max-width: 95%;">
        ${escapeHTML(slide.headline)}
      </div>
      ${slide.stat ? `<div class="stat-card" style="margin-bottom: 36px;">${escapeHTML(slide.stat)}</div>` : ''}
      <div class="body-text" style="font-size: 36px; color: ${brand.colors.text}; max-width: 95%;">
        ${escapeHTML(slide.body)}
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
    <div class="page-num">${pageNum} / ${total}</div>
  `);
}

function renderTakeaway(slide, pageNum, total) {
  const { colors, fonts } = brand;
  return `<!doctype html><html><head><meta charset="utf-8"><style>${baseStyles()}
    body { background: ${colors.accent}; }
    .takeaway-headline { color: ${colors.background}; }
    .takeaway-eyebrow { color: ${colors.background}; opacity: 0.75; }
    .takeaway-body { color: ${colors.background}; opacity: 0.9; }
    .handle { color: ${colors.background}; opacity: 0.6; }
    .page-num { color: ${colors.background}; opacity: 0.6; }
    .takeaway-divider { background: ${colors.background}; }
  </style></head><body><div class="slide">
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: center;">
      <div class="eyebrow takeaway-eyebrow" style="margin-bottom: 32px;">${escapeHTML(slide.eyebrow || 'THE TAKEAWAY')}</div>
      <div class="heading takeaway-headline" style="font-size: 88px; margin-bottom: 36px; max-width: 95%;">
        ${escapeHTML(slide.headline)}
      </div>
      <div class="divider takeaway-divider" style="margin-bottom: 36px;"></div>
      <div class="body-text takeaway-body" style="font-size: 38px; max-width: 95%;">
        ${escapeHTML(slide.body)}
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
    <div class="page-num">${pageNum} / ${total}</div>
  </div></body></html>`;
}

function renderCTA(slide, pageNum, total) {
  const { colors } = brand;
  return wrapHTML(`
    <div class="corner-shape-sm"></div>
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: flex-start;">
      <div class="eyebrow" style="margin-bottom: 40px;">YOUR MOVE</div>
      <div class="heading" style="font-size: 96px; margin-bottom: 48px; max-width: 90%;">
        ${escapeHTML(slide.headline)}
      </div>
      <div style="display: inline-flex; align-items: center; gap: 20px; padding: 20px 36px; background: ${colors.accent}; border-radius: 999px;">
        <span style="font-family: inherit; font-weight: 900; font-size: 40px; color: ${colors.background}; letter-spacing: -0.02em;">
          ${escapeHTML(slide.handle || brand.handle)}
        </span>
        <span style="font-size: 36px; color: ${colors.background};">→</span>
      </div>
    </div>
    <div class="page-num">${pageNum} / ${total}</div>
  `);
}

function renderStorySummary(slide) {
  return wrapHTML(`
    <div class="corner-shape"></div>
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: space-between;">
      <div>
        ${slide.source_badge ? `<div class="source-badge">${escapeHTML(slide.source_badge)}</div>` : ''}
      </div>
      <div>
        <div class="heading" style="font-size: 128px; margin-bottom: 48px; max-width: 95%;">
          ${escapeHTML(slide.headline)}
        </div>
        <div class="divider" style="margin-bottom: 36px;"></div>
        ${slide.subtext ? `<div class="body-text" style="font-size: 40px; color: ${brand.colors.text}; max-width: 95%;">${escapeHTML(slide.subtext)}</div>` : ''}
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
  `);
}

function formatBannerDate(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    weekday: 'long',
    month: 'short',
    day: 'numeric',
  });
  return fmt.format(date);
}

function renderIcymiBanner(slide, pageNum, total) {
  const dateText = formatBannerDate(slide.original_date);
  const headline = slide.headline || `From ${dateText}`;
  return wrapHTML(`
    <div class="relative" style="flex: 1; display: flex; flex-direction: column; justify-content: center;">
      <div class="icymi-pill" style="margin-bottom: 40px; align-self: flex-start;">ICYMI</div>
      <div class="heading" style="font-size: 88px; margin-bottom: 28px;">
        ${escapeHTML(headline)}
      </div>
      <div class="divider" style="margin-bottom: 28px;"></div>
      <div class="body-text" style="font-size: 32px;">
        Today's newsletters were thin — here's yesterday's top pick.
      </div>
    </div>
    <div class="handle">${escapeHTML(brand.handle)}</div>
    <div class="page-num">${pageNum} / ${total}</div>
  `);
}

function renderSlide(slide, pageNum, total) {
  switch (slide.type) {
    case 'hook':          return renderHook(slide, pageNum, total);
    case 'context':       return renderContext(slide, pageNum, total);
    case 'point':         return renderPoint(slide, pageNum, total);
    case 'takeaway':      return renderTakeaway(slide, pageNum, total);
    case 'cta':           return renderCTA(slide, pageNum, total);
    case 'story_summary': return renderStorySummary(slide);
    case 'icymi_banner':  return renderIcymiBanner(slide, pageNum, total);
    default:
      throw new Error(`Unknown slide type: ${slide.type}`);
  }
}

function escapeHTML(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ─── Main ───────────────────────────────────────────────────────────────────

const FONT_TIMEOUT_MS = 4000;

async function waitForFontsOrTimeout(page) {
  if (SKIP_FONT_CHECK) return { fontFallback: false, reason: 'skipped' };
  try {
    await Promise.race([
      page.evaluate(() => document.fonts.ready),
      new Promise((_, rej) => setTimeout(() => rej(new Error('font_timeout')), FONT_TIMEOUT_MS)),
    ]);
    return { fontFallback: false };
  } catch (e) {
    return { fontFallback: true, reason: e.message };
  }
}

(async () => {
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  const page = await browser.newPage();
  await page.setViewport({ ...viewport, deviceScaleFactor: 2 });

  const total = slides.slides.length;
  const prefix = slides.aspect === '9:16' ? 'story' : 'slide';

  let okCount = 0;
  let failCount = 0;
  let fontFallbackSeen = false;

  for (let i = 0; i < total; i++) {
    const slide = slides.slides[i];
    const outPath = path.join(outDir, `${prefix}_${String(i + 1).padStart(2, '0')}.png`);

    try {
      const html = renderSlide(slide, i + 1, total);
      await page.setContent(html, { waitUntil: SKIP_FONT_CHECK ? 'load' : 'networkidle0' });
      const fontResult = await waitForFontsOrTimeout(page);
      if (fontResult.fontFallback) fontFallbackSeen = true;
      await page.screenshot({ path: outPath, type: 'png' });
      console.log(`✓ ${outPath}${fontResult.fontFallback ? ' (font_fallback)' : ''}`);
      okCount++;
    } catch (err) {
      console.error(`✗ slide ${i + 1} (${slide.type}) failed: ${err.message}`);
      failCount++;
    }
  }

  await browser.close();
  console.log(`\nRendered ${okCount}/${total} slide(s) to ${outDir}${failCount ? ` — ${failCount} failed` : ''}${fontFallbackSeen ? ' — font_fallback observed' : ''}`);
  if (okCount === 0) process.exit(1);
})().catch((err) => {
  console.error('Render failed:', err);
  process.exit(1);
});
