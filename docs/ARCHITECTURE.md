# Architecture

## Layers
1. **Economy (src/empire/sim, no nodes)** — data in config/empire/*.json.
   - `EmpireData` loads/caches the JSON (products, districts, business types + upgrades, staff, vehicles, career).
   - `Stock` is every container of goods (pallet, boot, hands, stockroom). Goods move only via `Stock.transfer`, so units are conserved (tested).
   - `Business` = premises, fixtures → product slots, prices, upgrades, staff, reputation, day counters.
   - `DemandModel` = footfall (district × hour × reputation × upgrades × competition), baskets by district mix, willingness to pay. Same code for walking shoppers and the offscreen model.
   - `Staff` = candidates, wages, speed, skill growth.
   - `Empire` = the whole game state: clock, accounts (personal / company), minute tick (arrivals, staff work), wholesale, deliveries + manager re-orders, rent/buy, vehicles (fuel, wear), loans, homes, day close + reports, milestones, versioned save + migrate.
   - `CityLife` = the city around your shops (config/empire/events.json): daily weather + forecast (footfall and category mix; the sky follows it), one random event a day (festival, wholesale deal/shortage, hygiene inspection, viral review, sick employee, break-in, payday) and the QuikSave rival chain (opens stores in free units, often near yours; competes like another shop; buy-outs turn them into your freehold shops; after 3 buy-outs it stops expanding and once every store is bought it leaves). State lives on Empire (weather, forecast, events, rivals, news; save v3). `Empire.market` (the city's shop units) is set by the game, not saved.
   - Career: config/empire/career.json, five chapters ending in City Tycoon; when every goal is done Empire emits `won` (victory screen, play on).
2. **World (src/empire/world)** — `Premises` cuts shop units and wholesalers into real ground floors (b["apt"] with "ground": true, the CitySwing apartment mechanism). `ShopInterior` builds a unit's room (shell, brand colour per unit, decor, shopfront, fixtures from the Business; a QuikSave store is drawn from a stocked stand-in Business with no interaction spots, goods per slot, price tags, stockroom, walk grid + A*, interaction spots).
3. **People (src/empire/npc)** — `ShopFloor` runs the shop the player is in with `ShopPerson` agents (npc.gdshader on the street pedestrian model). Every other shop runs in the model.
4. **Game (src/empire/empire_game.gd)** — wires CityWorld, the hero (Player with swing_enabled=false, everyday=true, config/empire_params.tres), cars (Car/CarVisual/ChaseCamera/DriveInput), interior streaming, spots + prompts, carrying, homes, clock → Atmosphere, saves (user://cityempire_save.json, tmp→bak→rename).
5. **UI (src/empire/ui)** — EmpireUI (HUD, toasts, panels), EmpireTouch, EmpireMap, EmpireStyle.

## Adding an industry
Add a type to config/empire/business_types.json (categories, hours, roles, fixtures, slot sizes, upgrades), products with a matching `fixture`, then fixture drawing in ShopInterior._fixture and any special interaction in EmpireGame.act. Only `convenience` is playable now.
