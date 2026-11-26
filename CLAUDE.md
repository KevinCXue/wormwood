# Wormwood

A hobby open-world fantasy RPG prototype in **Godot 4.7** (GDScript, Forward+
renderer, Jolt physics). "Wormwood" is a codename. Use original names and lore
for anything in-game; nothing borrowed from existing franchises.

**Today:** a 3D terrain with a forest, the player's two-storey house, and a
town of 30 villagers (families, traders, a mayor, a priest, guards) with a
town square and well, a market, a town hall, a church on the hill and family
houses along streets that climb the slopes. Every villager can be talked to.
The player can walk around in first or third person, collect items into an
inventory (stacking, weight limit, a category-list screen, a quick-select
wheel for favourites), carry things by
hand, equip a sword or axe, chop down trees for logs and hit straw dummies,
save and load, and talk to villagers in branching conversations. One side
quest exists: Tobin's "Suspicious Stew" (fetch 5 mushrooms from a cave in
the woods north-west of town), tracked in a journal. A day/night cycle runs
throughout.
**Next:** Milestone 1 in `ROADMAP.md` (lore sketch, Anselm's quest, title and
pause menus, smoke tests).

## Plans and priorities

- `VISION.md`: why the game exists, the pillars (in priority order) and the
  non-goals. Check a feature against the pillars before starting it.
- `ROADMAP.md`: the only plan. Milestones are playable slices; tick items off
  as they land, and add settled design choices to its **decision log**.
- `TODO.md`: bugs and polish only. Log visual nitpicks there instead of
  fixing them mid-feature, unless they badly break immersion.
- Villager dialogue written so far is an AI placeholder (to be rewritten by
  the user). Keep new placeholder lines short and plainly functional.

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

Controls: WASD/arrows move, hold Shift to run, Space jumps, mouse looks, mouse wheel zooms (all the way in = first person), F switches first/third
person, E takes into the bag (hold E: carry / equip, E again drops what's
carried), I or Tab opens the inventory, hold Q for the favourites wheel,
left click swings, hold T to fast-forward time, F5 saves, F9 lists saves,
J opens the journal, in conversations Up/Down or W/S + Enter/E (or 1-9) pick replies,
H shows all controls, Esc quits (autosaving first). The input actions are registered in code in
`player.gd`, not in the Project Settings input map. **When adding or changing
a key, update the table at the top of `ui/help_menu.gd`** (and the README).

## Layout

| Path | What |
|---|---|
| `main.tscn` / `main.gd` | World root: environment, Sun/Moon + `DayNight`, `Terrain3D`, House, props, TestGrove (trees), TrainingYard (dummies), Player. `main.gd` handles global hotkeys. |
| `player.gd` | `CharacterBody3D`: camera-relative movement, Shift to run (top speed eased between `speed` and `sprint_speed`), jumping, respawn if you fall off the world. Children: `Model` (a `BodySlot`), `CameraRig`, `HUD`, `Interactor`, `Combat`. |
| `debug/console.gd/.tscn` | Autoload `Console` (debug builds only): `` ` `` opens a paused command line: `quest list/start/stage/complete/reset`, `give`/`take ITEM N`, `items`, `gold N`, `tp PLACE/VILLAGER/X Y Z`, `time HH:MM`, `save`, `load`, `newgame`, `help`. History and Tab completion. Documented in `docs/console.md`. |
| `settings.gd` | Autoload `Settings`: `character_detail` (`detailed`/`blocky`) and `quality` (`high`/`low`) from the `wormwood/graphics/*` project settings (quality has a `.macos` override to `low`). CLI override: `-- --detail=blocky --quality=high`. F2 in game toggles detail and reloads the scene (`main.gd`), carrying the game state over via `SaveGame`. |
| `save/save_game.gd` | Autoload `SaveGame`: JSON saves in `user://saves` (user dir pinned to "Wormwood"), each with a JPG thumbnail. F5 = new manual save (50 kept), autosave every 5 min and on quit (3 kept). Startup continues from the newest save (`-- --new-game` to skip; `-s` tool/test runs never do). Loading reloads the scene, then applies the state. Saves nodes in the **`persist` group** (`save_state()`/`load_state()`) by path, plus every world `Item` (scene-placed ones by path, runtime ones re-spawned from their ItemData). `-- --save-dir=user://test_saves` for tests. |
| `characters/body_slot.gd` | `class_name BodySlot`: spawns the body for the current detail setting and forwards the **body contract** (listed in its header) to it. Rotate the slot to turn the character. |
| `characters/humanoid.gd/.tscn` | Detailed body, built lazily (villagers on `apply_look`, the player on its first frame as a hoodless ranger): outfit glTF (peasant/ranger, male/female) is the body and skeleton; the head is cut from the superhero base body by bone weights (`_head_only`), the back of the outfit's own painted-on neck is cut away (`_strip_outfit_neck`, it poked through the nape), and the head is bound to it with eyes, eyebrows and hair. `characters/dye.gdshader` recolours the peasant outfit's linen (`tunic` colour). `AnimationTree` built in code (locomotion blend by speed; legs/hips eased towards the rest pose when standing, because every pack idle has a wide staggered stance; jump; `Idle_Talking` layered on arms/upper spine only for chatting villagers; filtered carry/ready arm poses; upper-body one-shot swing), `BoneAttachment3D` sockets (weapon = right hand, carry = left), `LookAtModifier3D` head turn. First person: the player's arm meshes stay on render layer 1 (rest of body on 2), and a `TwoBoneIK3D` on the right arm brings the hand into view (`fp_hand_offset`), then `characters/fist_grip.gd` (a `SkeletonModifier3D`) turns the hand so the weapon stands upright (`fp_weapon_tilt_deg`) and measures the fist from the finger bones so the weapon is seated in it; both fade out during swings. |
| `camera_rig.gd` | Orbit camera (yaw node → SpringArm3D pitch → Camera3D) with the first/third-person toggle. `top_level`, so it follows the player in code. |
| `mannequin.gd/.tscn` | Blocky body: greybox humanoid animated procedurally (pivot nodes as joints, eased each frame by `update_pose()`). Implements the same body contract (weapon = left hand, carry = right). |
| `interactor.gd` | Raycast from the screen centre to find items or villagers in reach. Tap E = into the bag (a weapon is also put on the wheel if there's room, and equipped if the hand is empty); hold E = carry in the right hand (or, for a weapon, bag + equip). The weapon hand holds a spawned copy of a bag item (`equip`/`unequip`/`drop`, also used by the inventory screen). Grabbing = freeze + clear collision + reparent to a hand socket. E on an `Npc` shows their next line as a subtitle. |
| `inventory/` | `item_data.gd` (`class_name ItemData`, a Resource: name, category, weight, description, `scene_path`) and `inventory.gd` (the Player's `Inventory` node: stacks of [ItemData, count], gold, `carry_limit`, `equipped`, `favourites`, `changed` signal). |
| `quests/` | `quest_data.gd` (`class_name QuestData`, a Resource per quest; **file name = quest id**: title, MAIN/SIDE, giver, summary, `objectives` per stage, `completed_text`, optional `gather_item`/`gather_count` for "(3/5)" progress) and `quest_log.gd` (the Player's `QuestLog` node: start/set_stage/complete, is_active/is_ready/is_done, `objective()`, `changed` signal; persisted). |
| `dialogue/` | Conversation scripts, one plain-text file per villager (`tobin.txt`), and `dialogue_script.gd`, the parser. **The format is documented in its header** (sections `== name`, `Speaker: line`, `- choice -> section [if cond]`, `? cond -> section`, `! effect`). Conditions: quest states, `has ITEM N`; effects: quests, `take`/`give` items, `gold`. Errors are reported with file:line on load. |
| `places/` | Generated wilderness places: `mushroom_cave.tscn` (from `tools/build_cave.gd`: CSG rock dome with a ragged arch entrance, triplanar rock texture, boulders, green glow lights, a random mix of mushroom items: `mushroom`, `_small`, `_large`, `_pair`, all one ItemData, generated by `build_props.gd` with curved stems and spotted caps). Placed in `village.tscn` under **Wilds**. |
| `combat.gd` | Left click → swing → sphere overlap query → calls `on_hit(weapon, from_pos, dir)` on the nearest hittable (duck typing). |
| `item.gd` / `equipable.gd` | `class_name Item` (RigidBody3D, `data: ItemData`, fallback `display_name`, `amount` = how many picking it up gives, e.g. 2 for a mushroom pair) and `Equipable extends Item` (`grip`, `hold_rotation_deg`, `kind` = `"blade"`/`"axe"`). |
| `targets/` | `choppable_tree` (axe only: notch decal, falls, leaves a stump) and `straw_dummy` (any weapon: wobble, head pops off, resets). |
| `hit_fx.gd` | `HitFx.burst(...)`: static one-shot particle puff. |
| `day_night.gd` | Moves the sun and moon. The sky (PhysicalSkyMaterial), fog and ambient light follow automatically. |
| `lights/flicker.gd` | Noise-driven candle/lantern flicker. |
| `ui/` | `hud.tscn/.gd` (interaction prompt with hold hint, short notes, a big fading banner for quest start/complete via `show_banner()` and a Tween, dialogue subtitle), `crosshair.gd` (dot drawn in `_draw`) `inventory_menu.tscn/.gd` (I/Tab: pauses the game, category tabs, a `Tree` list, a `SubViewport` 3D preview; E equip, F favourite, R drop) and `help_menu.tscn/.gd` (H: every control in Player/System columns, built from a table at the top of the script; the HUD shows a book + H hint drawn by `book_icon.gd`), `keycap_style.tres` (shared key-cap look), `dialogue_box.tscn/.gd` (plays a dialogue script at the bottom of the screen; sets `player.in_dialogue`, which stops movement, swings and menus; runs the script's conditions/effects against Inventory and QuestLog), `journal.tscn/.gd` (J: Main/Side/Completed quests and the selected one's objective), `load_menu.tscn/.gd` (F9: `ItemList` of saves with thumbnails, Enter loads, Delete twice deletes) and `quick_wheel.tscn/.gd` (hold Q: `Engine.time_scale` slows the world, a ring drawn in `_draw` shows up to 8 favourites, mouse movement picks a slot, release to equip/put away a weapon or hold anything else; right click removes a slot). |
| `npcs/` | `npc.tscn/.gd` (`class_name Npc`): a villager. Look exports (`body_type`, colours, hair) go to the body via `apply_look()`; watches the player via `set_look_target()`. `dialogue_file` (a `dialogue/*.txt`) gives them a conversation; without one, `talk()` returns their next one-liner from `lines`. `quest_marker.gd`: a billboard `Sprite3D` speech bubble (drawn in code) added automatically when their script starts/completes quests: gold ! = new, grey ▶ = in progress, gold ▶ = ready to hand in. |
| `village/` | `village.tscn`: Roads (including `CaveTrail` to the cave) (`road.gd`, `class_name Road`: a `Path3D` with a `width`; curve point Y = road height), Plazas (`plaza.gd`, `class_name Plaza`: a flat paved area at its Y), Buildings, Villagers and Wilds (places out of town, e.g. the cave; footprints are flattened like buildings). **Hand-editable source of truth for the village layout.** First written from `tools/village_layout.gd`. |
| `buildings/` | Generated by `tools/build_buildings.gd`: cottages, family houses, church, town hall, market stalls, well. Each root has a `footprint` metadata entry (Vector2 metres) that `build_village.gd` reads. A lighting check (`_light_rooms`) adds fixed wall lanterns until every floor spot reaches `MIN_LIGHT`; it prints what each building needed. |
| `props/` | Generated prop scenes: `items/`, `tables/`, `furniture/`, plus the hand-editable layouts `village_props.tscn` and `weapons_table.tscn`. |
| `assets/` | Poly Haven models and textures, generated vegetation, EB Garamond font. `assets/characters/quaternius/` (Universal Base Characters, CC0; only heads, eyes and hair are used), `assets/characters/outfits/` (Modular Character Outfits – Fantasy, CC0; textures downscaled 4K→2K) and `assets/animations/UAL1_Standard.glb` (Universal Animation Library, CC0). All share one 65-bone skeleton (UE-style names: `pelvis`, `spine_01`, `hand_r`...), so clips play on any of them without retargeting. Two glTFs had their normal-map file names fixed by hand. |
| `terrain/` | Terrain3D data, materials and vegetation colliders (generated). |
| `addons/terrain_3d/` | Third-party Terrain3D plugin (native binaries included). Don't edit it. |
| `tools/` | Headless generator scripts, see below. |
| `docs/` | README screenshot and `console.md` (developer console reference). `.gdignore` keeps Godot from importing it. |

## Conventions

- **Saving:** anything with state that should survive a save joins the
  `persist` group and implements `save_state() -> Dictionary` (plain JSON
  data; `SaveGame.vector_to_array()` etc. for vectors) and
  `load_state(state)`. It's keyed by its node path, so renaming a node in the
  editor makes old saves forget it. Bump `SaveGame.VERSION` when a format
  changes in a way old saves can't read.
- **Quests and dialogue are data.** A new quest = a `.tres` in `quests/`; a
  new conversation = a `.txt` in `dialogue/` set as a villager's
  `dialogue_file`. No code. Item names in scripts are file names in
  `props/items/`. (When the game is first exported, add `*.txt` to the export
  filter, or the dialogue files won't be packed.)
- **Console commands:** when a new system lands (shops, routines...), add
  console commands to test it (`debug/console.gd`) and document them in
  `docs/console.md`. Use them when testing instead of playing through.
  `SaveGame.new_game()` starts a fresh world without deleting saves.
- **Menus** check `not get_tree().paused and not get_parent().in_dialogue`
  before opening.
- **Scale:** 1 unit = 1 metre. The player is 1.8 m tall with its origin at the
  feet. Forward is **-Z** (Godot's convention), for models too.
- **Physics layers** (named in `project.godot`): 1 `world` (everything solid),
  2 `items` (added by `item.gd`), 3 `hittable` (dummies, trees). Queries use
  masks so they only see the layer they care about.
- **Bodies:** player/NPC code talks only to the `BodySlot` (body contract in
  `characters/body_slot.gd`), never to mannequin or humanoid internals. A
  new capability = add it to the contract and to both bodies.
- **Villagers** are `npcs/npc.tscn` instances under `village.tscn`/Villagers.
  Appearance and dialogue are exports on the instance; the root's yaw picks
  which way they face.
- **Hittable objects** are on layer 3 and implement
  `on_hit(weapon: Equipable, from: Vector3, dir: Vector3)`. Each object decides
  how to react, usually based on `weapon.kind`.
- **Equipable models:** the long axis is +Y, with the business end (blade,
  axe head) towards +Y.
- **Lights:** a light inside a model (a lantern's cage) needs that model's
  `cast_shadow` off, or the model shadows its own light and it lights nothing.
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
$GODOT --headless --path . -s res://tools/build_buildings.gd  # after build_props
$GODOT --headless --path . -s res://tools/build_cave.gd       # after build_props
$GODOT --headless --path . -s res://tools/build_village.gd    # after build_world + build_buildings + build_cave
```

After adding a new `class_name` script, run `$GODOT --headless --path . --import`
once so headless runs know the new type.

- `build_world.gd` **overwrites `terrain/`**, which wipes any sculpting or
  painting done in the editor. Its `KEEP_CLEAR` rects must match where the
  house and tables actually are.
- `build_props.gd` regenerates the prop scenes. It writes the layout scenes
  (`village_props.tscn`, `weapons_table.tscn`) only if they don't exist yet,
  so editor edits to those are safe.
- `build_house.gd` **overwrites `house.tscn`**. `build_buildings.gd`
  overwrites `buildings/*.tscn`.
- `build_village.gd` **edits the terrain in place**. It reshapes heights near
  village features (flat pads under buildings and plazas, where a building's pad always wins over a nearby road, roads graded to
  their curve heights, eased into the hills over 5 m), computing from the
  natural land in `tools/world_shape.gd` so re-runs are idempotent. It paints
  roads dirt and plazas stone, removes vegetation in the way (moving the rest
  with the ground), and saves villagers' heights onto the new ground into
  `village.tscn`. It never adds vegetation back. It writes `village.tscn` from
  `tools/village_layout.gd` only if missing, or with `-- --rewrite-layout`
  (which discards editor edits). To change the town, edit `village.tscn` and
  re-run. After running `build_world.gd`, always run it again.

Ask the user before re-running a script that overwrites their editor work.

## Future notes

- `user://` is pinned to "Wormwood" (`use_custom_user_dir` in
  `project.godot`), so renaming the project won't orphan saves.
- Town layout: the main street runs south from the spawn point (0, 0) to
  the square (~(2, 37), y 1) and climbs on south. Market west of the square,
  town hall east, church on the south-east hill (~(44, 56), y 9). Natural
  land is flat out to ~28 m and rises to hills south and east.
- Villagers snap to the ground at runtime too (`npc.gd`), in case the terrain
  changed after `build_village.gd` last ran.
- **Items:** each item scene in `props/items/` has its data beside it
  (`apple.tscn` + `apple.tres`). `build_props.gd` writes the `.tres` only if
  missing (tune weights and descriptions in the Inspector); new items need an
  `ITEM_INFO` entry. Identical items stack. Felled trees leave Pine Logs.
