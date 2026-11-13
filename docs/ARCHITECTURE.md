# Architecture

## Layers
1. **Economy (src/empire/sim, no nodes)** — data in config/empire/*.json.
   - `EmpireData` loads/caches the JSON (products, districts, business types + upgrades, staff, vehicles, career).
   - `Stock` is every container of goods (pallet, boot, hands, stockroom). Goods move only via `Stock.transfer`, so units are conserved (tested).
   - `Business` = premises, fixtures → product slots, prices, upgrades, staff, reputation, day counters.
   - `DemandModel` = footfall (district × hour × reputation × upgrades × competition), baskets by district mix, willingness to pay. Same code for walking shoppers and the offscreen model.
   - `Staff` = candidates, wages, speed, skill growth.
   - `Empire` = the whole game state: clock, accounts (personal / company), minute tick (arrivals, staff work), wholesale, deliveries + manager re-orders, rent/buy, vehicles (fuel, wear), loans, homes, day close + reports, milestones, versioned save + migrate.
2. **World (src/empire/world)** — `Premises` cuts shop units and wholesalers into real ground floors (b["apt"] with "ground": true, the CitySwing apartment mechanism). `ShopInterior` builds a unit's room (shell, shopfront, fixtures from the Business, goods per slot, price tags, stockroom, walk grid + A*, interaction spots).
3. **People (src/empire/npc)** — `ShopFloor` runs the shop the player is in with `ShopPerson` agents (npc.gdshader on the street pedestrian model). Every other shop runs in the model.
4. **Game (src/empire/empire_game.gd)** — wires CityWorld, the hero (Player with swing_enabled=false, everyday=true, config/empire_params.tres), cars (Car/CarVisual/ChaseCamera/DriveInput), interior streaming, spots + prompts, carrying, homes, clock → Atmosphere, saves (user://cityempire_save.json, tmp→bak→rename).
5. **UI (src/empire/ui)** — EmpireUI (HUD, toasts, panels), EmpireTouch, EmpireMap, EmpireStyle.

## Adding an industry
Add a type to config/empire/business_types.json (categories, hours, roles, fixtures, slot sizes, upgrades), products with a matching `fixture`, then fixture drawing in ShopInterior._fixture and any special interaction in EmpireGame.act. Only `convenience` is playable now.
