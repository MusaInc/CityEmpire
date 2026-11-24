# WorldState 0.11.0 overhaul

The Codex baseline is tagged `checkpoint-codex-baseline` at `70d1c1f`. It preserves the rebuilt road fleet and cabins, the Ade and Jules character assets, the street and storefront lighting, wet pavement, and the existing iOS build pipeline. Gemini recorded 112 passing baseline tests and eight gameplay images. Its four implementation specialists worked in the same checkout, so their edits were recovered directly from the worktree. The earlier TestFlight branch at `f14eddf` was checked against the checkpoint to identify the newer local additions and avoid replacing them.

## Integrated work

| Track | Integrated behavior |
| --- | --- |
| Environment | District-specific roof forms, balconies, awnings, rainwater pipes, damp street furniture, tree species selection, harbor reflections, and streetlight pools on Skyport. The cinematic grade preserves MSAA on Mobile. |
| Living city | Pedestrian density responds to the time of day and weather. Nearby walkers browse shopfronts, cross with traffic, and pause around parks and plazas. Traffic brakes at queues, emergency vehicles carry beacons, and Skyport air traffic has navigation lights and proximity-based sound. |
| Vehicles and characters | The 56-mesh Blender fleet and the fixed heroes carry forward from the checkpoint. Model-specific steering, braking, suspension, engine audio, wet-road sound, and cabin anchors now apply through the normal purchase and driving paths. The seated pose follows vehicle pitch and roll. Boarding and exit keep their obstruction checks. |
| Interiors and lifestyle | Shop types have distinct fixtures, graphics and lighting. The gym grants a workout perk, meals speed up player checkout, drinks affect movement, homes expose wardrobe and City500 interactions, and exploration rewards distinct destinations. Owned boats and aircraft can earn charter income with wear. |
| Business | Rival promotions change shopper price tolerance both in-store and off-screen. Staff traits affect service, theft and progression. City500 holdings support dividends, controlling stakes and buyouts. The portfolio can be reopened from the rankings, and dividends are excluded from the operating earnings multiple. |
| Interface | The landscape phone retains list positions across navigation. Search, purchase confirmations, safe-area layout, vehicle imagery, and the wardrobe preview use the recovered interface. Touch contacts reset on app suspension. |
| Performance and reliability | Bounded room streaming, interior light culling, cached streetlamp lookups, shadow proxies, reused traffic buffers, and distant vehicle and foliage LODs. The integration repairs script startup failures, roof collision, drive-mode save placement, and the scripted boarding and restocking journey. |

## Review material

Gemini's original matched camera records and PNGs are in `screenshots/worldstate-overhaul/before/`. The recaptures use Godot 4.5.1's Mobile renderer with llvmpipe and are saved in `screenshots/worldstate-overhaul/after/`. Draw calls and primitive counts describe the sampled frame. They vary with traffic, pedestrians, streaming and shadow casters. The software renderer cannot establish iPhone or iPad frame pacing.

City500 acquisitions hold equity and pay dividends. Player-operated premises continue to use the physical business system. Pedestrian trips and aircraft traffic use authored routes with local behavior. Retail, home and venue interiors have differing interaction depth.
