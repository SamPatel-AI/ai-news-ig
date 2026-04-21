#!/usr/bin/env python3
"""Test harness: mirrors the Node render.js logic in Python/Playwright
so we can visually verify slides in this sandbox before shipping the kit."""

import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

SLIDES_PATH = Path(sys.argv[1])
BRAND_PATH = Path(sys.argv[2])
OUT_DIR = Path(sys.argv[3])
OUT_DIR.mkdir(parents=True, exist_ok=True)

slides = json.loads(SLIDES_PATH.read_text())
brand = json.loads(BRAND_PATH.read_text())

VIEWPORTS = {
    "4:5":  {"width": 1080, "height": 1350},
    "9:16": {"width": 1080, "height": 1920},
    "1:1":  {"width": 1080, "height": 1080},
}
viewport = VIEWPORTS.get(slides.get("aspect", "4:5"), VIEWPORTS["4:5"])


def esc(s):
    return (str(s or "")
            .replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def base_styles():
    c = brand["colors"]
    f = brand["fonts"]
    heading_family = f["heading"].replace(" ", "+")
    body_family = f["body"].replace(" ", "+")
    return f"""
    @import url('https://fonts.googleapis.com/css2?family={heading_family}:wght@{f['heading_weight']}&family={body_family}:wght@{f['body_weight']}&display=swap');
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    html, body {{
      width: {viewport['width']}px; height: {viewport['height']}px;
      background: {c['background']}; color: {c['text']};
      font-family: '{f['body']}', -apple-system, sans-serif;
      font-weight: {f['body_weight']}; overflow: hidden;
    }}
    .slide {{ width: 100%; height: 100%; padding: 80px 72px;
             display: flex; flex-direction: column; position: relative; }}
    .heading {{ font-family: '{f['heading']}', -apple-system, sans-serif;
                font-weight: {f['heading_weight']}; line-height: 1.05;
                letter-spacing: -0.02em; color: {c['text']}; }}
    .body {{ font-size: 32px; line-height: 1.4; color: {c['muted_text']}; }}
    .accent {{ color: {c['accent']}; }}
    .handle {{ position: absolute; bottom: 48px; left: 72px;
               font-size: 22px; color: {c['muted_text']}; letter-spacing: 0.05em; }}
    .page-num {{ position: absolute; bottom: 48px; right: 72px;
                 font-size: 22px; color: {c['muted_text']}; font-variant-numeric: tabular-nums; }}
    .source-badge {{ display: inline-block; padding: 8px 16px;
                     background: {c['primary']}; color: {c['background']};
                     font-size: 20px; font-weight: 700; border-radius: 999px;
                     letter-spacing: 0.03em; text-transform: uppercase; }}
    """


def wrap(inner):
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{base_styles()}</style></head><body><div class='slide'>{inner}</div></body></html>"


def r_hook(s, n, t):
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
        <div class="heading" style="font-size:104px;">{esc(s['headline'])}</div>
        {f'<div class="body" style="margin-top:32px;font-size:36px;">{esc(s["subtext"])}</div>' if s.get('subtext') else ''}
      </div>
      <div class="handle">{esc(brand['handle'])}</div>
      <div class="page-num">{n} / {t}</div>
    """)


def r_context(s, n, t):
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
        <div class="heading accent" style="font-size:48px;margin-bottom:32px;">{esc(s['headline'])}</div>
        <div class="heading" style="font-size:56px;">{esc(s['body'])}</div>
      </div>
      <div class="handle">{esc(brand['handle'])}</div>
      <div class="page-num">{n} / {t}</div>
    """)


def r_point(s, n, t):
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
        <div class="accent heading" style="font-size:160px;line-height:1;margin-bottom:24px;">0{s['number']}</div>
        <div class="heading" style="font-size:72px;margin-bottom:32px;">{esc(s['headline'])}</div>
        <div class="body" style="font-size:36px;">{esc(s['body'])}</div>
      </div>
      <div class="handle">{esc(brand['handle'])}</div>
      <div class="page-num">{n} / {t}</div>
    """)


def r_takeaway(s, n, t):
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
        <div class="accent heading" style="font-size:40px;margin-bottom:24px;text-transform:uppercase;letter-spacing:0.1em;">{esc(s['headline'])}</div>
        <div class="heading" style="font-size:76px;">{esc(s['body'])}</div>
      </div>
      <div class="handle">{esc(brand['handle'])}</div>
      <div class="page-num">{n} / {t}</div>
    """)


def r_cta(s, n, t):
    handle = s.get('handle') or brand['handle']
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;align-items:center;text-align:center;">
        <div class="heading" style="font-size:88px;margin-bottom:40px;">{esc(s['headline'])}</div>
        <div class="accent heading" style="font-size:60px;">{esc(handle)}</div>
      </div>
      <div class="page-num">{n} / {t}</div>
    """)


def r_story_summary(s):
    badge = f'<div class="source-badge" style="margin-bottom:56px;">{esc(s["source_badge"])}</div>' if s.get('source_badge') else ''
    subtext = f'<div class="body" style="font-size:40px;">{esc(s["subtext"])}</div>' if s.get('subtext') else ''
    return wrap(f"""
      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
        {badge}
        <div class="heading" style="font-size:128px;margin-bottom:48px;">{esc(s['headline'])}</div>
        {subtext}
      </div>
      <div class="handle">{esc(brand['handle'])}</div>
    """)


RENDERERS = {
    'hook': r_hook, 'context': r_context, 'point': r_point,
    'takeaway': r_takeaway, 'cta': r_cta,
    'story_summary': lambda s, n, t: r_story_summary(s),
}


def main():
    total = len(slides['slides'])
    prefix = 'story' if slides.get('aspect') == '9:16' else 'slide'

    with sync_playwright() as p:
        browser = p.chromium.launch(args=['--no-sandbox'])
        page = browser.new_page(viewport=viewport, device_scale_factor=2)

        for i, slide in enumerate(slides['slides'], start=1):
            html = RENDERERS[slide['type']](slide, i, total)
            page.set_content(html, wait_until='networkidle')
            page.evaluate("document.fonts.ready")
            out = OUT_DIR / f"{prefix}_{i:02d}.png"
            page.screenshot(path=str(out))
            print(f"✓ {out}")

        browser.close()


if __name__ == "__main__":
    main()
