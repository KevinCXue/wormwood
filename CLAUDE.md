# Wormwood

A hobby open-world fantasy RPG prototype in **Godot 4.7** (GDScript, Forward+
renderer, Jolt physics). "Wormwood" is a codename. Use original names and lore
for anything in-game; nothing borrowed from existing franchises.

**Today:** a 3D terrain with a forest, a two-storey house, and tables of props.
The player can walk around in first or third person, pick up and drop items,
equip a sword or axe, chop down trees and hit straw dummies. A day/night
cycle runs throughout.
**Planned:** a village, NPCs, quests, inventory, save/load and RPG systems.

## Working with the user

- The user is a senior software engineer who is **new to Godot and game dev**.
  This is a learning project. Briefly explain each Godot concept the first time
  it comes up, using analogies to general software engineering.
- Keep scripts well commented, like the existing ones: a `##` doc header saying
  what the node does and how it fits in, plus comments on non-obvious lines.
- The user tunes visuals and game feel in the editor. Claude handles code,
  scene structure and debugging. Expose tunable values as `@export` vars (with
  units in a comment) so they show up in the Inspector.
- **The repo is the source of truth.** The user edits scenes in the editor, so
  read the actual `.tscn`/`.gd` files before acting, not notes or earlier
  descriptions.

## Running and validating

Godot binary: `~/Desktop/Godot.app/Contents/MacOS/Godot`

```sh
GODOT=~/Desktop/Godot.app/Contents/MacOS/Godot
$GODOT --path .                       # run the game (main scene: main.tscn)
$GODOT --headless --path . --quit     # import + parse check; look for script errors
```

Controls: WASD/arrows move, Space jumps, mouse looks, F switches first/third
person, E takes/drops/equips, left click swings, hold T to fast-forward time,
Esc quits. The input actions are registered in code in `player.gd`, not in
the Project Settings input map.

## Layout

| Path | What |
|---|---|
| `main.tscn` / `main.gd` | World root: environment, Sun/Moon + `DayNight`, `Terrain3D`, House, props, TestGrove (trees), TrainingYard (dummies), Player. `main.gd` handles global hotkeys. |
| `player.gd` | `CharacterBody3D`: camera-relative movement, jumping, respawn if you fall off the world. Children: `Model`, `CameraRig`, `HUD`, `Interactor`, `Combat`. |
| `camera_rig.gd` | Orbit camera (yaw node → SpringArm3D pitch → Camera3D) with the first/third-person toggle. `top_level`, so it follows the player in code. |
| `mannequin.gd/.tscn` | Greybox humanoid animated procedurally: a tree of pivot nodes used as joints, eased each frame by `update_pose()`. Has the hand sockets and the swing animation. |
| `interactor.gd` | Raycast from the screen centre to find items in reach. Right hand carries an `Item`, left hand holds an `Equipable`. Grabbing = freeze + clear collision + reparent to a hand socket. |
| `combat.gd` | Left click → swing → sphere overlap query → calls `on_hit(weapon, from_pos, dir)` on the nearest hittable (duck typing). |
| `item.gd` / `equipable.gd` | `class_name Item` (RigidBody3D, `display_name`) and `Equipable extends Item` (`grip`, `hold_rotation_deg`, `kind` = `"blade"`/`"axe"`). |
| `targets/` | `choppable_tree` (axe only: notch decal, falls, leaves a stump) and `straw_dummy` (any weapon: wobble, head pops off, resets). |
| `hit_fx.gd` | `HitFx.burst(...)`: static one-shot particle puff. |
| `day_night.gd` | Moves the sun and moon. The sky (PhysicalSkyMaterial), fog and ambient light follow automatically. |
| `lights/flicker.gd` | Noise-driven candle/lantern flicker. |
| `ui/` | `hud.tscn/.gd` (interaction prompt) and `crosshair.gd` (dot drawn in `_draw`). |
| `props/` | Generated prop scenes: `items/`, `tables/`, `furniture/`, plus the hand-editable layouts `village_props.tscn` and `weapons_table.tscn`. |
| `assets/` | Poly Haven models and textures, generated vegetation, EB Garamond font. |
| `terrain/` | Terrain3D data, materials and vegetation colliders (generated). |
| `addons/terrain_3d/` | Third-party Terrain3D plugin (native binaries included). Don't edit it. |
| `tools/` | Headless generator scripts, see below. |
| `docs/` | README screenshot. `.gdignore` keeps Godot from importing it. |

## Conventions

- **Scale:** 1 unit = 1 metre. The player is 1.8 m tall with its origin at the
  feet. Forward is **-Z** (Godot's convention), for models too.
- **Physics layers** (named in `project.godot`): 1 `world` (everything solid),
  2 `items` (added by `item.gd`), 3 `hittable` (dummies, trees). Queries use
  masks so they only see the layer they care about.
- **Hittable objects** are on layer 3 and implement
  `on_hit(weapon: Equipable, from: Vector3, dir: Vector3)`. Each object decides
  how to react, usually based on `weapon.kind`.
- **Equipable models:** the long axis is +Y, with the business end (blade,
  axe head) towards +Y.
- Gameplay code goes in `_physics_process`, purely visual code in `_process`.
  For frame-rate-independent smoothing, use `1.0 - exp(-k * delta)` as the
  lerp weight.
- Use `@onready var x = $Path` for node lookups. Use `class_name` only for
  types that other scripts check with `is`.
- Commit `.import` and `.uid` files (Godot needs them to keep resource
  references stable). Never commit `.godot/` (an editor cache, gitignored).
  Text files are LF everywhere (`.gitattributes`) because the user also works
  on a Windows PC.

## Generator scripts (`tools/`)

They run headless as standalone programs (`extends SceneTree`, entry point
`_initialize()`):

```sh
$GODOT --headless --path . -s res://tools/build_world.gd   # ~1 min
$GODOT --headless --path . -s res://tools/build_props.gd
$GODOT --headless --path . -s res://tools/build_house.gd   # after build_props
```

- `build_world.gd` **overwrites `terrain/`**, which wipes any sculpting or
  painting done in the editor. Its `KEEP_CLEAR` rects must match where the
  house and tables actually are.
- `build_props.gd` regenerates the prop scenes. It writes the layout scenes
  (`village_props.tscn`, `weapons_table.tscn`) only if they don't exist yet,
  so editor edits to those are safe.
- `build_house.gd` **overwrites `house.tscn`**.

Ask the user before re-running a script that overwrites their editor work.

## Future notes

- When save/load is added, set `application/config/use_custom_user_dir` in
  `project.godot`. Otherwise a project rename moves `user://` and orphans
  existing saves.
- There's no inventory yet. Each hand holds exactly one thing
  (`interactor.gd`).
