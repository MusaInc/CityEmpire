# Status (2026-11-13)

## Working (verified headless / in renders on the VPS)
- Two islands with economic identities: Westbank (cheap, industrial/residential) and the Commercial Island (avg rent >1.5×); 24 shops to let + a wholesaler each.
- Full first loop: rent → drive → buy at trade counter → collection bay → boot → carry in → stock shelves/stockroom → open → serve at till → takings; hire staff (cashier serves alone, stacker, cleaner, manager re-orders, driver = free delivery); upgrades rebuild the shop; loans, transfers, vehicles (van/box truck), homes (buy, lift, sleep, let), goals, day reports, autosave.
- Tests: 24 City Empire tests pass; `--autoplay` 37/37; inherited CitySwing 156/161 (see SHARED_FOUNDATION.md).
- Perf counters (Xvfb/llvmpipe; only counts are meaningful): in a busy shop 282 draws / 699k prims / 452 objects; on the street 185 / 501k / 334; economy tick ~0.02 ms/frame. Static mem ~419 MB.

## Not verified
- No phone, tablet or web build tested. No device FPS claims.
- Autoplay teleports the car between places; road driving routes aren't scripted.

## Not done yet
- Other industries (types defined, locked), AI delivery vans on the roads, City Empire sound/music, icon + branding, street-level city improvements, onboarding beyond the intro + objective line, web/iOS export presets checked.
