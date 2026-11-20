[![make.fun · roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/alfasurya91/brainrot-heist/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/alfasurya91/brainrot-heist/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Heist

Brainrot Heist is a 3D "Steal a Brainrot" game built as a Rojo project. Players walk around a shared 3D
world, buy brainrot characters off a conveyor, drop them onto their own base plot, and collect the money
those characters produce every second. Money buys rarer brainrots, and the rarest ones are worth stealing
from somebody else.

## How the game plays

- You spawn into a 3D world and move your character around it with the standard Roblox controls.
- A conveyor keeps offering brainrot characters for sale. Walk up, buy one, and it is yours.
- Carry it to your plot and place it on the base. From then on it earns money per second, and that income
  keeps paying while you are elsewhere in the world.
- Brainrots come in five rarities: Common, Rare, Epic, Legendary and Mythic. Each step up costs more and
  produces more per second.
- Bases you have not locked can be robbed. If another player's plot is open, you can take a brainrot off it
  and add it to your own collection — which is why locking your base matters.
- Every 120 seconds a hazard wave hits the world. It is the pressure that keeps everyone moving instead of
  idling on a finished plot.

## Building the place

The Rojo project file is `default.project.json` and it maps `src/` into the Roblox data model. Build the
place from the repository root:

    rojo build default.project.json --output game.rbxl

That writes `game.rbxl`, the file `main.ts` hands to the judge.

## Producing the submission

`main.ts` runs on Node 22 with nothing but the standard library. It copies `game.rbxl`, `PLAY.json`, `src/`
and `screenshots/` (skipping every name that starts with a dot) into the output directory, then writes
`dossier.json` there with the vendored make.fun helper.

Point `MAKEFUN_OUTPUT_DIR` at a folder to stage the output locally:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

Without that variable the output directory is `/output`, which is what the grader uses.

## Source layout

Server, under `src/server/`:

- `init.server.luau` — the server entry point. Wires the rules to remote events, leaderstats and the
  income, conveyor and wave loops.
- `GameService.luau` — the server-side rules: players and their money, the base plots, the conveyor stock,
  locks, robbery cooldowns and the wave hazard. It touches no Roblox instances, so it can be tested on its
  own, and every public function validates its arguments so a malformed remote payload cannot crash it.
- `BrainrotDefs.luau` — the static catalogue: 12 brainrots across the five rarities, each with a name,
  rarity, cost, money per second and colour. No state, safe to require anywhere.

Client, under `src/client/`:

- `Game.client.luau` — the HUD. A single ScreenGui over the 3D view: money at the top left, the conveyor
  shop on the right, the base panel at the bottom left and the wave warning across the top centre, all kept
  clear of the Roblox menu button.
