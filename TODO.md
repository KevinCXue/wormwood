# TODO

Bugs and polish only. The order of work lives in `ROADMAP.md`.

## Bugs

Things that are broken. Fix these soon.

- **Women don't visibly flee when attacked.** Reported in play (2026-11-26).
  The combat test sees Rosalind switch to the FLEE state after a punch, so
  the reaction fires; the running itself seems not to happen. Suspects:
  `Npc._flee()` / `_move()` in `npcs/npc.gd` (stuck against a wall or her
  house, the "dodge" veer not getting her out, or not counting as on the
  floor), or the walk animation not playing. Repro: punch Rosalind (by
  Tobin's cottage, `tp rosalind` in the console) and watch.

## Polish

Visual and feel nitpicks. Per `VISION.md`, these wait for the polish pass
(Milestone 5) unless they badly break immersion.

- **See-through chest in the male peasant tunic's V-neck.** Every man in the
  peasant outfit (e.g. Tobin, by his cottage at (5.6, 23)) has it: the outfit
  has no chest under the V opening, and the head mesh cut from the base body
  (`_head_only` in `characters/humanoid.gd`) only reaches the top of it.
  Options: keep the base body's upper-chest triangles (front only) in the
  head mesh, or put a small undershirt-coloured patch behind the opening.
- **Jagged neck seam** visible in close side views, where the head mesh
  meets the outfit.
- **Flat-coloured buildings.** Everything in `buildings/` is CSG with plain
  colours; give them textures (plaster, timber, stone, roof tiles) towards the
  visual bar in `VISION.md`.
- **Trees hide the town from the south hill.** Thin the forest on that slope
  so the view over the town opens up.
- **Log end caps are hard to see** (pale discs on `props/items/log.tscn`);
  a ring texture would read better.
