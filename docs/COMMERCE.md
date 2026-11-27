# The commercial empire (2026-11-27)

The aim is to make businesses the reason to come back: every business grows, every trade plays differently, and shops, stock, vans, warehouses, property and staff all depend on each other.
Numbers are in `config/empire/commerce.json`. The code lives in `src/empire/sim` (Growth, Company, SupplyChain, Trades, Progression) and `src/empire/ui/commerce_pages.gd`.

## Business levels (Growth)

| Level | Name | Needs | Gives |
|---|---|---|---|
| 1 | Independent shop | – | the base shop |
| 2 | Established business | 3 upgrades, 2 staff, 3 days open, rep 50, a profitable week | +1 shelf unit, shelves ×1.25, stockroom ×1.3, +10% footfall, nicer shop; your company lightbox hangs over the floor |
| 3 | Major retailer | 5 upgrades, a manager, rep 62, £3.5k week | +2 units, shelves ×1.6, self-checkout till, re-orders itself (no auto-restock fee), +25% footfall, track lighting, second lightbox + SELF CHECKOUT sign |
| 4 | Corporate flagship | head office, 3 branches of the trade, rep 72, £9k week | shelves ×2, more tills, +40% footfall, gold-trimmed FLAGSHIP sign; every other branch of the trade gets +8% footfall and the chain buys 3% cheaper |

Level costs scale by trade (`cost_k`) and are 1.5× for flagship premises.
A bought-out rival store arrives at level 2.
Phone: Businesses → Empire → Growth, or a shop's manage panel → **Growth**.

## Company (Company)

- Your brand (name, colours, face) plus a logo mark: monogram, circle, diamond, bars, arch or star.
- Divisions are grouped by trade (e.g. "Crown Goods Coffee"), plus Logistics, the club and car hire, each with its 7-day books.
- Brand recognition: every branch beyond the second adds 2% footfall to all of them, up to 10%.
- Fleet delivery vans carry your livery: brand-colour side panels with the company name.

## Supply chain (SupplyChain)

wholesale supplier → company warehouse → delivery fleet → branches → profit

- **Warehouses:** Westbank Depot (£85k, 600 cases), Harbour Distribution Centre (£240k, 1,800 cases), or the Skyport Logistics estate (900 cases). Racking adds 400 cases, up to three times.
- **Contract prices:** the top bulk band, minus 7%, on top of head office and flagship discounts. Stock is the `depot` pallet, so every existing stock count and save includes it.
- **Fleet:** vans, box trucks or pickups from your garage, each with a driver hired from the day's job seekers. Rounds leave at 06:00 and 13:00, and each van loads what its branches are short of. Trip time comes from road distance; km, wear and diesel are booked. Unloading puts stock in the stockroom and plays the existing delivery: a van pulls up and a worker carries the cases in.
- **No supplier needed:** branches the fleet serves pay no delivery fees, and their managers skip supplier orders for lines the warehouse holds.
- **Contracts:** city firms ask for N cases a day for some days at 10–22% over cost. They ship from the warehouse each night; a short day costs half its value.

## Trade loops (Trades)

- **Convenience:** the existing stock, pricing and margins loop.
- **Food (takeaway, café, bakery):**
  - Supplier range: Value (−14% cost, worse food), Market fresh, or Artisan (+22%, better). Reputation drifts towards the range's level.
  - Menu: tight is better but quieter; wide is busier but rougher.
- **Clothing:** collections (basics, streetwear, tailoring, resort, designer).
  - Each has a launch cost and suits an affluence band, so designer labels flop in the estates.
  - A collection fades over 14 days; resort wear sells 1.5× on sunny days.
- **Nightclub:**
  - Venues: The Vault (Midtown, 420 capacity) or Halo Rooftop (Financial District, 300, VIPs spend 1.6×).
  - Open Thursday to Sunday. You choose the event (house, R&B, guest DJ, VIP launch) and the door price.
  - Popularity, VIP tables and staff are covered. It runs statistically; the club is not walk-in yet.
- **Car hire:** a Skyport desk. Cars on hire are booked by class, price, condition and weekend. They wear down and leave your garage and the street while on hire.
- **Hotel:** Skyport Hotel facilities (restaurant, spa, conference suite, rooftop bar) add occupancy and room rate.
- **Already present:** the airport charter, dealership and property company work as before.

## Career stages (Progression)

1. Entrepreneur
2. Business owner
3. Regional investor
4. Corporate executive
5. Tycoon
6. Billionaire

Each stage has three steps measured from the live game. The last stage targets £1 billion net worth with businesses on all three islands. The stage is stored in `flags.stage`.

## Checks

- `tests/test_commerce.gd` has 12 tests.
- `--scenarios=BZ` runs in the live game: the pages, warehouse → van → shop, the Growth tab, the fit-out lightbox, livery, ventures, and cars leaving for hire.
- `--demo=commerce` sets up a company a few weeks in, for captures.

## Not done yet

- The nightclub and car-hire desk have no walk-in interiors; they run from the phone.
- Fleet vans don't drive visibly through traffic; they appear at the kerb when they arrive.
- Staff uniforms don't change with level.
- Competitors still react only through the existing rival chain and promos, not to your prices.
- Balance is first-pass. Car hire pays back slowly (a saloon earns about £32 a day).
