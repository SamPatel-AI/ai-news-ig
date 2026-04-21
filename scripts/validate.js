#!/usr/bin/env node
/**
 * Validate a slides.json / story.json against the pinned schema.
 *
 * Usage:  node scripts/validate.js <path-to-json>
 * Exit:   0 = valid, 1 = invalid (with error list to stderr)
 *
 * Catches malformed LLM output before it reaches the renderer.
 */

const fs = require('fs');

const REQUIRED_TOP = ['story_id', 'source', 'aspect', 'slides'];
const VALID_ASPECTS = ['4:5', '9:16', '1:1'];

const SLIDE_SCHEMAS = {
  hook:          { required: ['headline'],                           optional: ['subtext', 'tag'] },
  context:       { required: ['headline', 'body'],                   optional: ['eyebrow'] },
  point:         { required: ['number', 'headline', 'body'],         optional: ['stat'] },
  takeaway:      { required: ['headline', 'body'],                   optional: ['eyebrow'] },
  cta:           { required: ['headline'],                           optional: ['handle'] },
  story_summary: { required: ['headline'],                           optional: ['subtext', 'source_badge'] },
  icymi_banner:  { required: ['original_date'],                      optional: ['headline'] },
};

const errors = [];
const warnings = [];

function err(msg) { errors.push(msg); }
function warn(msg) { warnings.push(msg); }

function isURL(s) {
  try { new URL(s); return true; } catch { return false; }
}

function isISO8601(s) {
  if (typeof s !== 'string') return false;
  const d = new Date(s);
  return !isNaN(d.getTime());
}

function wordCount(s) {
  return String(s || '').trim().split(/\s+/).filter(Boolean).length;
}

function validateSlide(slide, idx) {
  const prefix = `slides[${idx}]`;
  if (!slide || typeof slide !== 'object') {
    err(`${prefix}: must be an object`); return;
  }
  if (!slide.type) { err(`${prefix}.type: required`); return; }
  const schema = SLIDE_SCHEMAS[slide.type];
  if (!schema) { err(`${prefix}.type: unknown type "${slide.type}"`); return; }

  for (const field of schema.required) {
    if (slide[field] === undefined || slide[field] === null || slide[field] === '') {
      err(`${prefix}.${field}: required for type "${slide.type}"`);
    }
  }

  // em-dash hard ban in headlines
  if (typeof slide.headline === 'string' && slide.headline.includes('—')) {
    err(`${prefix}.headline: em-dash (—) not allowed`);
  }

  // soft word-count warnings
  if (slide.type === 'point' && typeof slide.number === 'number') {
    if (slide.number < 1 || slide.number > 5) {
      err(`${prefix}.number: must be between 1 and 5, got ${slide.number}`);
    }
  }
  if (slide.headline && wordCount(slide.headline) > 9) {
    warn(`${prefix}.headline: ${wordCount(slide.headline)} words (>9 soft limit)`);
  }
  if (slide.body) {
    const max = slide.type === 'context' ? 35 : 25;
    if (wordCount(slide.body) > max) {
      warn(`${prefix}.body: ${wordCount(slide.body)} words (>${max} soft limit)`);
    }
  }

  // icymi_banner date format
  if (slide.type === 'icymi_banner' && slide.original_date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(slide.original_date)) {
      err(`${prefix}.original_date: must match YYYY-MM-DD, got "${slide.original_date}"`);
    }
  }
}

function validate(obj) {
  if (!obj || typeof obj !== 'object') { err('root: must be an object'); return; }

  for (const f of REQUIRED_TOP) {
    if (!(f in obj)) err(`${f}: required`);
  }

  if (obj.aspect && !VALID_ASPECTS.includes(obj.aspect)) {
    err(`aspect: must be one of ${VALID_ASPECTS.join(', ')}, got "${obj.aspect}"`);
  }

  if (obj.source) {
    if (!obj.source.name)   err('source.name: required');
    if (!obj.source.url)    err('source.url: required');
    else if (!isURL(obj.source.url)) err(`source.url: invalid URL "${obj.source.url}"`);
    if (!obj.source.published_at)    err('source.published_at: required');
    else if (!isISO8601(obj.source.published_at)) err(`source.published_at: invalid ISO-8601 "${obj.source.published_at}"`);
  }

  if (!Array.isArray(obj.slides)) {
    err('slides: must be an array');
  } else if (obj.slides.length < 1 || obj.slides.length > 10) {
    err(`slides: length must be 1..10, got ${obj.slides.length}`);
  } else {
    obj.slides.forEach(validateSlide);
  }
}

// ─── main ──────────────────────────────────────────────────────────────────

const [,, filePath] = process.argv;
if (!filePath) {
  console.error('Usage: validate.js <path-to-slides-or-story-json>');
  process.exit(2);
}

let raw;
try {
  raw = fs.readFileSync(filePath, 'utf8');
} catch (e) {
  console.error(`Cannot read ${filePath}: ${e.message}`);
  process.exit(1);
}

let parsed;
try {
  parsed = JSON.parse(raw);
} catch (e) {
  console.error(`JSON parse error in ${filePath}: ${e.message}`);
  process.exit(1);
}

validate(parsed);

if (warnings.length) {
  for (const w of warnings) console.error(`warn: ${w}`);
}

if (errors.length) {
  console.error(`\n${filePath} — INVALID (${errors.length} error${errors.length === 1 ? '' : 's'}):`);
  for (const e of errors) console.error(`  ✗ ${e}`);
  process.exit(1);
}

console.log(`${filePath} — OK${warnings.length ? ` (${warnings.length} warning${warnings.length === 1 ? '' : 's'})` : ''}`);
process.exit(0);
