# Status (2026-11-13, finishing pass)

## Working (verified headless / in renders on the VPS)
- Two islands with economic identities: Westbank (cheap, industrial/residential) and the Commercial Island (avg rent >1.5×); 24 shops to let + a wholesaler each.
- Full loop: rent → drive → buy at trade counter → collection bay → boot → carry in → stock shelves/stockroom → open → serve at till → takings; hire staff (cashier serves alone, stacker, cleaner, manager re-orders, driver = free delivery); upgrades rebuild the shop; loans, transfers, vehicles (van/box truck), homes (buy, lift, sleep, let), goals, day reports, autosave.
- City life: daily weather + forecast (drives footfall, what sells and the sky), daily events (festival, wholesale deal/shortage, hygiene inspection, viral review, sick staff, break-in vs CCTV, payday), news feed.
- Rival chain QuikSave: starts with 2 stores, opens more every 4 days (often next to yours), drawn in its red livery with a BUY OUT prompt at the door; buy-outs become your freehold shops; retreats after 3 buy-outs, leaves when the last store is yours.
- Endgame: 5 career chapters (Early Career → City Tycoon), victory screen, play on.
- Phone: Businesses, City (weather, rivals, news), Map (rivals marked), Bank (net-worth chart + profit bars), Vehicles, Property, Goals, Game; Settings has music/sound volume.
- Balance (tools/balance_sim.gd, fully staffed shop per district, 20 days): +£50..£400/day in good districts, a loss in Westbank Quay without coffee/hot food. Wages were cut ~30% and footfall ×1.4 (footfall_scale) in the finishing pass: before it, a staffed shop lost money in 7 of 8 districts.
- Tests: 34 City Empire tests pass (10 new for city life); `--autoplay` 43/43; inherited CitySwing 154–156/161 (4 course tests + 1 test_city as before; test_motion_quality ledge_dive checks are flaky run to run, 2 of 3 isolated runs pass).
- Capture helpers: `--days=N` (run the economy N days), `--panel=city|bank|goals|victory|rival|…`, `--goto=rival`.

## Not verified
- No phone, tablet or web build tested. No device FPS claims.
- Autoplay teleports the car between places; road driving routes aren't scripted.
- Long-run pacing (how many real hours to City Tycoon) is estimated from the sim, not playtested.

## Not done
- Other industries (types defined, hidden), AI delivery vans on the roads, walking customers inside rival stores, City Empire-specific music.
