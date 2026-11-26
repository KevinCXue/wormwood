# Wormwood

A hobby open-world fantasy RPG prototype, built in [Godot 4.7](https://godotengine.org/)
as a way to learn game development. "Wormwood" is a working codename.

![A timber-framed house, a picnic table with items on it, and straw training dummies in a forest clearing](docs/screenshot.jpg)

## What works so far

- A town of 30 villagers you can talk to: families, traders and a mayor
  around a town square, a market, a town hall, and a church on the hill.
- Forested hills, a two-storey house you can walk through, and a day/night
  cycle.
- First- and third-person camera.
- Pick up and drop items: plates, goblets, apples, lanterns and more.
- Equip a sword or an axe and swing it. Chop down trees with the axe; knock
  the stuffing out of straw training dummies with either.

Planned: a village, NPCs, quests, an inventory and other RPG systems.

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard
   version, not .NET).
2. Clone this repo, open Godot, choose **Import**, and select `project.godot`.
   The first open takes a minute while Godot imports the assets.
3. Press **F5** to play.

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Shift (hold) | Run |
| Mouse | Look |
| Space | Jump |
| E | Take, drop or equip what's under the crosshair |
| Left click | Swing the equipped weapon or tool |
| F | Toggle first / third person |
| Mouse wheel | Zoom (scroll all the way in for first person) |
| Hold T | Fast-forward time |
| F2 | Switch between detailed and blocky characters |
| Esc | Quit |

## Project layout

- `main.tscn`: the game world.
- `player.gd`, `camera_rig.gd`, `mannequin.gd`: player movement, camera and
  procedurally animated body.
- `interactor.gd`, `combat.gd`, `item.gd`, `equipable.gd`: picking things up,
  equipping them and hitting things.
- `targets/`: things you can hit (trees, dummies).
- `props/`, `assets/`, `terrain/`: scenes, models and world data.
- `village/`: the town layout (roads, plazas, buildings, villagers);
  `npcs/`: villagers; `buildings/`: generated building scenes.
- `tools/`: scripts that generate the terrain, props, buildings and the
  town. See the header comment in each for how to run it.

## Graphics settings

Characters can be **detailed** (rigged, animated models) or **blocky**
(greybox, handy for testing mechanics), and graphics quality can be **high** or
**low**. Defaults are in `project.godot` under `wormwood/graphics`. Macs default
to low quality. Override for one run with
`godot --path . -- --detail=blocky --quality=high`.

## Credits

- Characters from Quaternius's [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html)
  and [Modular Character Outfits – Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html),
  and animations from the [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (CC0).
- 3D models and textures from [Poly Haven](https://polyhaven.com/) (CC0).
- [EB Garamond](https://github.com/georgd/EB-Garamond) font, SIL Open Font
  License (see `assets/fonts/OFL.txt`).
- [Terrain3D](https://github.com/TokisanGames/Terrain3D) by Tokisan Games,
  MIT License (see `addons/terrain_3d/LICENSE.txt`).
