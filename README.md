[![make.fun · roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/alfasurya91/brainrot-heist/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/alfasurya91/brainrot-heist/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Heist

A 3D Steal-a-Brainrot game built as a Rojo project. You spawn on a central pad in a 512x512 grass field, with
four base plots 140 studs out to the north, south, west and east, a conveyor shop running along the north
side, and a handful of buildings and trees around the edges for cover. You buy brainrot characters off the
conveyor, carry them to your own plot, and each one pays you money every second — which is what lets you
afford the next, more expensive one.

The catch is that a full plot is not a safe one. Any base that is not locked can be robbed, so a rare
brainrot is only yours while nobody with a free steal cooldown walks past your plot. On top of that, a hazard
wave sweeps the map every 120 seconds and charges anyone standing away from home, so camping somewhere
convenient instead of defending your base costs money.

## How to play

- Move with the standard Roblox controls. You start on the spawn pad in the middle of the map.
- The conveyor north of spawn always lists three brainrots. Press `B` or click the shop row to buy the first
  offer you can afford.
- Stand on your plot to place what you bought. A plot holds four brainrots and pays their combined income
  per second, whether or not you are standing on it.
- Press `L` to lock your base for 20 seconds. Nothing can be taken while the lock holds, but the ability has
  a 60 second cooldown, so it is a window you time rather than a permanent shield.
- Press `S`, or use the Steal button, while you are at another player's plot to take one of their brainrots
  — provided their base is unlocked, their plot is not already full of your loot, and your own 30 second
  steal cooldown has expired.
- Every 120 seconds a wave lands, announced 5 seconds ahead. Anyone more than 24 studs from their own base
  when it hits loses 5% of their money (minimum 5) and is pulled back home. Being at your base costs nothing.

Twelve brainrots span five rarities — Common, Rare, Epic, Legendary and Mythic — from Tung Tung Sahur at 50
money up to Giraffa Celeste at 12000. Each one earns roughly a tenth of its price per second, so the cheap
ones pay for themselves in ten seconds and the expensive ones do the same, only with more zeroes.

## How to build

`default.project.json` holds the whole data model. It maps `src/server` to `ServerScriptService.Server` and
`src/client` to `StarterPlayer.StarterPlayerScripts.Client`, and it declares the static map inside
`Workspace`. From the repository root:

    rojo build default.project.json --output game.rbxl

That produces `game.rbxl` with 57 instances. Forty-six of them are parts: the 512x512 grass baseplate, the
spawn pad, four plot bases, twelve conveyor segments, four buildings each with a roof, eight trees of trunk
plus leaves, and four neon markers. The remainder are the service and container instances Rojo creates plus
the four scripts that drive the game. Open the result in Studio to play it, or leave it as the artifact the
grader reads.

## How to produce the submission

`main.ts` is the entry point. It targets Node 22 and imports only the standard library plus the vendored
helper in `vendor/makefun-roblox.ts`, so there is no `npm install` and no build step beyond the Rojo one
above.

What a run does:

1. Resolves the output directory from `MAKEFUN_OUTPUT_DIR`, falling back to `out/` beside the script.
2. Copies `game.rbxl` and `PLAY.json` into it unchanged.
3. Copies `src/` and `screenshots/` recursively, skipping every entry whose own name starts with a dot.
4. Writes `dossier.json` there with `buildDossier` from the vendored helper.

Stage a local run like this:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

`dossier.json` records the place's instance count and class breakdown, then the full text of every script
with the files matched to `src/` first. The first image in `screenshots/` becomes the cover, so at least one
PNG or JPEG has to be there; if the folder holds none, `main.ts` writes a place-only dossier, says so on
stderr, and that entry is not submittable. The caps it enforces mirror the scorer: at most four images of
256 KiB each, scripts totalling under 8 MiB of source, and a place under 500000 instances.

## Source layout

`src/server/` runs on the server:

- `init.server.luau` — boot script. Creates the remote events, builds a floor part for each plot, sets up
  `leaderstats` money, and drives the three loops: income once a second, conveyor restock every 20 seconds,
  wave every 120 seconds.
- `GameService.luau` — every rule, with no Roblox instances inside it: players and money, the four plots and
  their four slots, conveyor stock, locks, steal cooldowns and the wave hazard. Each public method validates
  its arguments and returns `(false, message)` instead of throwing, so a hostile remote payload cannot take
  the server down. This is the file to read or test first.
- `BrainrotDefs.luau` — the static catalogue: twelve brainrots, five rarities, each with a name, cost, money
  per second and a colour. It holds no state, so it is safe to require anywhere, and it builds its name and
  rarity indexes once at require time.

`src/client/` runs on each player's machine:

- `Game.client.luau` — the HUD. One ScreenGui layered over the 3D view: money top left, the conveyor shop on
  the right, your base panel bottom left, the wave warning across the top centre, all positioned clear of
  the Roblox menu button. It also binds the `B`, `L` and `S` shortcuts.

## Other files

- `PLAY.json` — the published place: place id 111524401926447, universe 10777839575.
- `TOUR.json` — the screenshot tour over `screenshots/`: three steps, two of which press a movement key and
  wait a second so the frame shows motion.
- `vendor/makefun-roblox.ts` — the vendored make.fun helper. Reads the `.rbxl`, matches script sources and
  writes the dossier as canonical JSON. Do not edit it.
- `LICENSE` — see the file for the terms.
