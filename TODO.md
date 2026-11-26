# TODO

## Next up (in order)

1. ~~**Inventory.**~~ Done: bag with stacking and a weight limit,
   category-list screen, equip/drop, logs from trees, quick-select wheel.
   Gold has a counter but no source yet (traders or loot, later).
2. **Save/load.** Straight after the inventory, while there's little state:
   player position, inventory, felled trees, time of day. Design every later
   system to be saveable. Set `application/config/use_custom_user_dir` in
   `project.godot` first (see CLAUDE.md).
3. **Villager routines.** Walk to work by day, home at night, using a
   navigation mesh and the existing day/night clock. Keep it cheap on the
   MacBook Air: villagers far away or indoors skip physics and animation
   updates.
4. **Dialogue and quests.** Short branching conversations with simple flags
   ("met Tobin", "has the axe") and a quest log. First quest idea: bring Tobin
   3 logs (chopping + inventory + dialogue together).

Later: stats, levelling and combat damage, once there's content to balance
them against. Small game-feel fixes whenever something bugs you.

## Bugs

1. **(Minor) See-through chest in the male peasant tunic's V-neck.** Every
   man in the peasant outfit (e.g. Tobin, by his cottage at (5.6, 23)) has it:
   the outfit has no chest under the V opening, and the head mesh cut from the
   base body (`_head_only` in `characters/humanoid.gd`) only reaches the top
   of it, so you see through to what's behind him. Options: keep the base
   body's upper-chest triangles (front only) in the head mesh, or put a small
   skin- or undershirt-coloured patch behind the opening.
