# WorldState brand & UI system (2026-11-27)

One identity from the app icon to managing a business.

## Mark
- A single high-contrast gold **W** (thick down-strokes, hairline up-strokes,
  pointed base vertices) on dark navy. Nothing else on the icon.
- Geometry lives in one place: `tools/brand/w_mark.py`. It writes
  `assets/brand/w_mark.json` (unit-box polygons), `assets/brand/w_mask.png`
  (alpha mask, mipmapped), `assets/icon_1024.png` (App Store / app icon),
  `assets/splash/launch.png` (OS launch screen) and `assets/brand/wordmark.png`
  (older menus). Re-run after any change:
  `~/.cache/ws-ui/venv/bin/python tools/brand/w_mark.py <dir> --preview`
  (needs Pillow) and copy the outputs in.
- In game: `Brand.Mark` (mask + `brand_mark.gdshader`: brushed-gold gradient
  and a metallic light sweep, `shine()`), `Brand.Wordmark` (mark + tracked
  WORLDSTATE in Inter/SF). Colours: `Brand.NAVY_DEEP` (= boot splash colour),
  `NAVY`, `GOLD`, `GOLD_TEXT`, `IVORY`.

## Launch → menu (src/ui/boot.gd)
1. OS launch screen: `launch.png` (flat `NAVY_DEEP`, W at 22 % of the short
   side). `boot_splash/bg_color` and the iOS storyboard colour are the same.
2. `boot.gd` draws the same W at the same size and place – no cut. A light
   sweep crosses it every ~2.8 s; a gold hairline tracks real progress
   (threaded scene load → instantiate → `EmpireGame.title_ready`: the menu's
   view built and rendered). Master bus is muted meanwhile.
3. Reveal: navy fades off the live city, the W glides into the title
   wordmark (`EmpireUI.title_logo_rect`), menu items fade in staggered, the
   city's sound rises (Master −60 dB → previous over 2.4 s), then the title's
   own W takes over and shines once (`title_handoff`).

## Title menu (src/empire/ui/title_menu.gd, src/empire/title_views.gd)
- The backdrop is the star: wordmark top-left, text-only actions bottom-left
  (gold rule on the primary), the view's name + mood bottom-right; only the
  corners that carry text are shaded.
- Views: `config/empire/title_views.json` – id, name, mood, hour, weather,
  fov, eye/look → eye2/look2 slow dolly (ease there and back over `dur`),
  optional `ground` [x, z] for ground-relative heights. A random view each
  launch, never last launch's (`user://title.cfg`). `"art": true` views are
  never shown; they photograph tiles for the phone.
- Review every view: `--title-tour=<dir> [--title-ui] [--title-wait=7]
  [--title-only=a,b] [--title-at=s]`; force one: `--title-view=<id>`.
- Entering the world dips to navy for a moment (no visible camera cut) while
  the hero's street streams back in.

## Phone (src/empire/ui/phone.gd, phone_pages.gd)
- **Home** (the W in the status bar, and the HUD's W button): money strip
  (tap → Banking), the one thing that needs you, and nine photographed app
  tiles – Businesses, Banking, Vehicles, Properties, Map, Wardrobe, Jobs,
  Marketplace, Settings – then Goals / City today. Everything is two taps.
- No tab strips or dock: each app opens on the page used most; deeper
  management is detail pages (`Phone.DETAILS`, `ph.detail(key)`), e.g.
  Businesses → Company & growth, Supply chain, Ventures, Operations, Reports,
  Corporate, City500; Banking → Statements; Map → Nearby.
- Corporate (`CommercePages.corporate`) and City today
  (`PhonePages.city_today`) are native phone pages (stacked cards/rows); the
  old fixed-width desk layouts overflowed the phone. Goals and Nearby still
  come through `EmpireUI.legacy_tab` and fit.
- Every old section key still works (`Phone.resolve_section` maps it to
  [app, detail]), so `open_phone("supply")` etc. land on the right page.
- Tile art: `assets/ui/apps/<app>.jpg` from `tools/brand/app_art.py` (game
  renders: catalogue/home studio shots, a shopfront and the logistics depot
  photo, the wardrobe lookbook lineup, and title-camera views
  `financial_night` + `art_map`). Settings is a plain tile on purpose.
  New JPGs need `godot --headless --import` before a run will load them.
- Captures: `--phone-shots=<dir> --phone-sections=a,b --phone-delay=25`
  (the first shot after boot can catch the splash reveal: start with a
  throwaway section).
