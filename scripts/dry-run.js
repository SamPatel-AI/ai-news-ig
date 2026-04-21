#!/usr/bin/env node
/**
 * Local smoke test: validate + render the test fixtures end-to-end.
 *
 * Usage: npm run dry-run
 *
 * Outputs to /tmp/ai-news-dry-run/. Prints ✓ for each step or exits 1 on failure.
 * No network dependencies beyond Google Fonts (which render.js handles gracefully).
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT  = '/tmp/ai-news-dry-run';

const BRAND   = path.join(ROOT, 'config/brand.json');
const SLIDES  = path.join(ROOT, 'test/slides.json');
const STORY   = path.join(ROOT, 'test/story.json');
const VALIDATE = path.join(ROOT, 'scripts/validate.js');
const RENDER   = path.join(ROOT, 'scripts/render.js');

function run(label, fn) {
  try {
    fn();
    console.log(`✓ ${label}`);
  } catch (e) {
    console.error(`✗ ${label}: ${e.message}`);
    process.exit(1);
  }
}

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });

run('validate test/slides.json', () => {
  execFileSync('node', [VALIDATE, SLIDES], { stdio: 'inherit' });
});

run('validate test/story.json', () => {
  execFileSync('node', [VALIDATE, STORY], { stdio: 'inherit' });
});

run('render carousel → /tmp/ai-news-dry-run/carousel/', () => {
  execFileSync('node', [
    RENDER,
    '--slides', SLIDES,
    '--brand', BRAND,
    '--out', path.join(OUT, 'carousel'),
    '--skip-font-check',
  ], { stdio: 'inherit' });
});

run('render story → /tmp/ai-news-dry-run/story/', () => {
  execFileSync('node', [
    RENDER,
    '--slides', STORY,
    '--brand', BRAND,
    '--out', path.join(OUT, 'story'),
    '--skip-font-check',
  ], { stdio: 'inherit' });
});

const carouselPngs = fs.readdirSync(path.join(OUT, 'carousel')).filter(f => f.endsWith('.png'));
const storyPngs    = fs.readdirSync(path.join(OUT, 'story')).filter(f => f.endsWith('.png'));

if (carouselPngs.length < 1) {
  console.error('✗ no carousel PNGs produced');
  process.exit(1);
}
if (storyPngs.length !== 1) {
  console.error(`✗ expected 1 story PNG, got ${storyPngs.length}`);
  process.exit(1);
}

console.log(`\nDry-run OK. ${carouselPngs.length} carousel + ${storyPngs.length} story PNG in ${OUT}`);
console.log(`Open: ${path.join(OUT, 'carousel', carouselPngs[0])}`);
