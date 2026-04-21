#!/usr/bin/env node
/**
 * Build today's folder from yesterday's successful output ("ICYMI" fallback).
 *
 * Usage:
 *   node scripts/fallback.js \
 *     --from output/2026-04-19 \
 *     --to   output/2026-04-20 \
 *     --brand config/brand.json
 *
 * For each story folder under --from:
 *   1. Copy the whole story directory into --to with suffix "_icymi".
 *   2. Prepend an {"type":"icymi_banner", "original_date": "YYYY-MM-DD"} slide
 *      to the copied slides.json.
 *   3. Shell out to render.js to regenerate only the carousel PNGs
 *      (story PNG kept as-is — ICYMI signaling on carousel is enough).
 *
 * Exit 0 on success, non-zero on any fatal copy error.
 * Per-story render failures are logged but do not abort the batch.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function parseArgs() {
  const args = {};
  for (let i = 2; i < process.argv.length; i += 2) {
    args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
  }
  return args;
}

function copyDirSync(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory()) copyDirSync(s, d);
    else fs.copyFileSync(s, d);
  }
}

function extractDateFromPath(p) {
  const m = path.basename(p).match(/(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : null;
}

function main() {
  const { from, to, brand } = parseArgs();
  if (!from || !to || !brand) {
    console.error('Usage: fallback.js --from <past-day-dir> --to <today-dir> --brand <brand.json>');
    process.exit(2);
  }
  if (!fs.existsSync(from)) {
    console.error(`--from not found: ${from}`);
    process.exit(1);
  }
  if (!fs.existsSync(brand)) {
    console.error(`--brand not found: ${brand}`);
    process.exit(1);
  }

  const originalDate = extractDateFromPath(from);
  if (!originalDate) {
    console.error(`Cannot extract YYYY-MM-DD from --from path "${from}"`);
    process.exit(1);
  }

  fs.mkdirSync(to, { recursive: true });

  const storyDirs = fs.readdirSync(from, { withFileTypes: true })
    .filter(e => e.isDirectory() && /^\d+_/.test(e.name))
    .map(e => e.name)
    .sort();

  if (storyDirs.length === 0) {
    console.error(`No story folders (NN_slug/) under ${from}`);
    process.exit(1);
  }

  const renderScript = path.join(path.dirname(process.argv[1]), 'render.js');
  let successCount = 0;
  let failCount = 0;

  for (const storyDir of storyDirs) {
    const srcStory = path.join(from, storyDir);
    const dstStory = path.join(to, `${storyDir}_icymi`);
    const slidesPath = path.join(dstStory, 'slides.json');

    try {
      copyDirSync(srcStory, dstStory);

      if (!fs.existsSync(slidesPath)) {
        console.error(`skip ${storyDir}: no slides.json in source`);
        failCount++;
        continue;
      }

      const slides = JSON.parse(fs.readFileSync(slidesPath, 'utf8'));
      slides.slides = [
        { type: 'icymi_banner', original_date: originalDate },
        ...slides.slides,
      ];
      fs.writeFileSync(slidesPath, JSON.stringify(slides, null, 2));

      // Re-render the carousel (includes the new banner slide at position 1)
      const carouselDir = path.join(dstStory, 'carousel');
      fs.rmSync(carouselDir, { recursive: true, force: true });
      execFileSync('node', [
        renderScript,
        '--slides', slidesPath,
        '--brand', brand,
        '--out', carouselDir,
      ], { stdio: 'inherit' });

      console.log(`✓ fallback built: ${dstStory}`);
      successCount++;
    } catch (e) {
      console.error(`✗ fallback failed for ${storyDir}: ${e.message}`);
      failCount++;
    }
  }

  console.log(`\nFallback: ${successCount} ok, ${failCount} failed (from ${originalDate} → ${path.basename(to)})`);
  process.exit(successCount > 0 ? 0 : 1);
}

main();
