# Wormwood: Roadmap

> Milestones are **playable slices**, not lists of systems. Each one ends with
> something you can play from a new game to a finish line, and each system gets
> built because that slice needs it. See `VISION.md` for the why.
>
> This is the only plan. `TODO.md` holds bugs and polish, not the order of
> work. Update the status marks here as work lands.
>
> **Status key:** ✅ done · 🔨 in progress · ⬜ not started

## Time reality check

The plan assumes about **5–10 hours a week, ~30 hours a month**. Hour estimates
are rough, AI-assisted guesses, so expect them to be wrong. Milestones 1–5
add up to roughly **300–400 hours, about a year**, to reach a vertical slice
worth showing a friend. A full 1.0 (the small RPG in `VISION.md`) is realistically
another year or two of content work after that. That's normal for a solo RPG,
and the reason each milestone has to stand on its own.

Recalibrate after Milestone 1: compare its actual hours to the estimate and
scale the rest. (So far the work has gone faster than these numbers: the
whole inventory, including the wheel, took about two sessions.)

---

## ✅ Milestone 0: Sandbox foundations

What's already built:
- Terrain, forest, day/night cycle, Terrain3D world generation
- A hillside town of 30 talkable villagers, with buildings, roads, a plaza,
  a market and a church; interiors lit by lamps (with a lighting check in the
  building generator)
- First- and third-person player, camera, running and jumping
- Physical items: take, carry, drop. Equip a sword or axe and swing it
- Chopping trees, training dummies, hit effects
- Detailed and blocky characters, high and low quality settings

What's missing: **a reason to do any of it.** That's Milestone 1.

---

## 🔨 Milestone 1: "The first job"

**The game exists.** *Pillars: Story (a first taste), Living world*
**Estimate: ~50–70 h**

The slice: Anselm, the priest, needs firewood for the church, and he is
oddly insistent that it arrives **before nightfall**. Talk to him and accept
the job, chop the wood, collect the logs and bring them back. Along the way
there's a choice: simply hand the wood over and get paid, or ask why the
church needs a fire burning all night. If you ask, he lets slip the first
hint about the star (see the lore sketch) and remembers that you were
curious. Bring it after dark, and he's rattled rather than grateful. Save in
the middle of the quest, quit, reload, and everything is where you left it.

(Draft plot, written as a placeholder; rewrite it to fit the lore sketch.)

Systems this forces into existence, roughly in build order:
- [x] **Inventory:** items are stored, not only carried. A category-list
      screen (not a grid, see the decision log), stacking, a data resource
      per item type, a weight limit, and a quick-select wheel.
- [x] **Resources from the world:** a felled tree leaves Pine Log items.
- [ ] **Smoke tests:** a `tests/` folder of headless scripts plus a one-line
      runner, starting with the inventory (pick up, stack, equip, drop) and
      tree felling. Every system below adds its own.
- [ ] **Lore sketch:** one page in `docs/lore.md`: the town's name, what
      the town believes the star is (versus what it really is), Anselm's
      place in that, and three rumours villagers can mention. Enough that
      the first quest's lines point the right way.
- [x] **Stable IDs for world objects:** objects are identified by their node
      path from the world root (see the decision log). Ownership for
      Milestone 2's crime system will hang off the same IDs.
- [x] **Save/load:** player position, camera and view, time of day, the bag,
      gold, favourites, equipped and carried items, felled trees, and moved,
      taken and dropped items. JSON in a pinned user folder, versioned. F5
      saves (50 kept), autosave every 5 minutes and on quit (3 kept), F9 lists
      saves with thumbnails, and starting the game continues from the newest.
      Quest states join when quests exist (they just need the `persist`
      group).
- [x] **Dialogue with choices:** conversations are plain-text scripts in
      `dialogue/` (format in `dialogue/dialogue_script.gd`), with conditions
      (quest states, "has 5 mushroom") and effects (start/complete quest,
      take/give items, gold). Up/Down + Enter, W/S, 1-9 or the mouse.
- [x] **Quests:** `QuestData` resources (stages, gathering goals), a saved
      `QuestLog`, a journal (J) with Main/Side/Completed, and speech-bubble
      markers over quest givers. First quest: Tobin's "Suspicious Stew"
      (5 mushrooms from a new cave north-west of town, 15 gold).
- [ ] **Currency:** 🔨 quests can pay gold now (Tobin gives 15); still
      nothing to spend it on (shops are Milestone 2) and no world source.
- [x] **Title screen and pause menu:** the title shows over the live
      world (Continue, New game, Load, Controls, Quit) and never saves; Esc
      opens a pause menu (Resume, Save, Load, Controls, New game with a
      confirmation, Quit to title, Quit game).
- [ ] **The quest itself:** Anselm's job, built entirely from the data
      formats above (no quest-specific code), including the choice and the
      time-of-day reaction.

**Risks:** save format churn as systems are added (version it, and keep the
smoke test that saves and reloads); dialogue resources being painful to
write in the Inspector (if so, switch to a plain-text format early).

**Done when:** a friend can start a new game, finish the quest without being
told how, and save and reload in the middle of it without anything breaking.

**Fun check:** did they ask Anselm why? Did they want to know more about
the star when it was over?

---

## ⬜ Milestone 2: "The town wakes up"

**Living world.** *Pillar: Living world*
**Estimate: ~60–80 h**

The slice: follow any villager for a full day. They wake at home, go to work
at a market stall or Brannoc's forge, eat, chat, and go home at night. Buy and sell at the
market. The town notices what you've done.

- [ ] **Daily routines:** a schedule per villager (data), navigation between
      places (NavigationRegion3D), and simple activities (work, sit, chat, sleep).
- [ ] **Performance budget:** villagers far away or indoors skip physics and
      animation updates; 30 walking villagers stay at 60 fps on the Air.
- [ ] **Shops and trading:** buy and sell prices, and a shopkeeper's stock.
- [ ] **NPC memory:** villagers react to quest outcomes and remember whether
      you helped them, with dialogue that changes accordingly.
- [ ] **Crime, light version:** taking items that belong to someone is
      theft, and it has consequences (uses the ownership from Milestone 1's
      object IDs).
- [ ] **3 side quests** using only existing systems, to prove the systems
      really are reusable.

**Risks:** navigation on steep streets and through 1.4 m doorways; villagers
crowding doorways; routines that look robotic (stagger start times, add
idle variation).

**Done when:** you can watch the town go through a day, and a side quest's
outcome visibly changes something in it.

**Fun check:** did the tester follow a villager around just to see what they
do? Did anyone react to something the tester did without being scripted to?

---

## ⬜ Milestone 3: "Beyond the walls"

**Exploration and the first danger.** *Pillars: Exploration, Combat*
**Estimate: ~80–100 h**

The slice: a villager mentions a ruin in the hills. Find it without a marker,
go inside (it's an interior scene), fight what lives there, find something
that hints at the fallen star, and bring it back.

- [ ] **Wilderness beyond the town:** paths, landmarks, points of interest,
      and things worth finding off the road.
- [ ] **Interiors and dungeons:** scene transitions (doors and load zones),
      and one hand-built ruin or cave with a layout, lighting and a reward.
- [ ] **Enemies v1:** health, damage both ways, death, and an AI state machine
      (idle, patrol, chase, attack, flee), with 2 enemy types (an animal and a
      humanoid).
- [ ] **Player health and dying:** a health bar, death, and reloading.
- [ ] **Loot:** containers and things that enemies drop.
- [ ] **A map and compass** that only show places you've discovered.

**Risks:** saving across scenes (what persists when you leave the ruin);
the terrain is generated, so wilderness edits must survive
`tools/build_world.gd` re-runs.

**Done when:** the ruin is fun to find, tense to clear, and worth the trip.

**Fun check:** did the tester wander off the road unprompted? Did the fight
make them nervous at least once?

---

## ⬜ Milestone 4: "Getting stronger"

**Combat depth and growth.** *Pillar: Combat and growth*
**Estimate: ~60–80 h**

- [ ] **Stats:** health, stamina (spent by running, swinging and blocking),
      and maybe magicka later.
- [ ] **Learn-by-doing skills:** One-Handed, Woodcutting and Speech improve
      with use, unlocking small perks.
- [ ] **Combat feel:** blocking, a heavy attack, hit stagger, and directional
      reactions. The existing `on_hit` contract extends to enemies.
- [ ] **Gear with stats:** weapon damage and speed, armour, and equipment
      slots on the body.
- [ ] **A balance pass:** enemy toughness matched to early-game gear.

**Done when:** the ruin from Milestone 3 feels noticeably easier after an
hour of play, because *you* got better.

**Fun check:** did the tester notice a skill going up and feel good about
it? Did they change weapons or tactics because of something they learned?

---

## ⬜ Milestone 5: "The Wormwood Star, Act I"

**The vertical slice.** *All pillars*
**Estimate: ~60–80 h**

The first real checkpoint: about 1–2 hours of game you'd be proud to show.

- [ ] **The lore bible:** grow `docs/lore.md` into the full history of the
      valley, the star and the main characters.
- [ ] **Main quest, Act I:** 3–4 story quests that end on a hook.
- [ ] **A story dungeon:** a second dungeon tied to the main quest.
- [ ] **Rewrite all dialogue by hand:** every villager line, quest text and
      book written so far as AI placeholders (see `VISION.md` non-goals).
- [ ] **Polish pass:** work through the `TODO.md` *Polish* list, textured
      buildings (towards the visual bar in `VISION.md`), plus audio
      (ambience, footsteps, hits, and a music bed).
- [ ] **Settings menu:** graphics, mouse sensitivity, key bindings.
- [ ] **A friend playtest:** watch someone play without helping, and fix what
      confuses them.

**Done when:** a friend plays Act I unassisted and asks what happens next.

**Fun check:** that question, unprompted, is the whole test.

---

## Beyond: toward 1.0 (a small RPG)

Mostly content production, reusing the systems built above:
- Acts II–III of the main quest
- Towns 2 and 3, with their own villagers and routines
- The second story dungeon and the finale
- Side quests up to ~10–15 in total
- More enemy types, gear and perks
- Cross-platform builds (Mac and Windows) and a final polish pass

## Parking lot (ideas that aren't scheduled)

Ideas go here so they don't derail the current milestone:
- Fishing, cooking, alchemy with bitter herbs (fits the wormwood theme)
- Weather (rain, fog rolling down from the hills)
- Eating food from the inventory (apples are in the Food tab but do nothing)
- Mod support

---

## Decision log

Settled choices, newest last. Change one only on purpose, and say why here.

| Date | Decision | Why |
|---|---|---|
| 2026-11 | CC0 characters (Quaternius base bodies + outfits, Universal Animation Library); detailed everywhere, blocky on F2 | Licence-safe for a public repo; one shared skeleton |
| 2026-11 | Graphics preset per OS: Mac `low`, PC `high` | Keep the Air playable |
| 2026-11 | Inventory is a **category list** with a 3D preview, not an icon grid | No icon art needed; reads well with text |
| 2026-11 | **Every identical item stacks** (two swords = "Iron Sword x2"); weight limit (60 kg) instead of slots | Simple, fits a list UI |
| 2026-11 | **Tap E** = into the bag, **hold E** = carry by hand (weapons: bag + equip) | Keeps the physical world (carry a goblet to another table) |
| 2026-11 | An equipped weapon stays counted in the bag; the hand holds a spawned copy | Switching weapons never drops one on the floor |
| 2026-11 | Gold is a weightless counter, not an item | Like most RPGs |
| 2026-11 | Quick-select is a **wheel** (hold Q, time slows to 25%, 8 favourites); slots stay put when you run out | Muscle memory |
| 2026-11 | Picked-up weapons auto-favourite (if room) and auto-equip (if the hand is empty) | Fewer menu trips |
| 2026-11 | Existing villager dialogue is an AI-written placeholder, rewritten by hand in Milestone 5 | Vision non-goal: no shipped AI text |
| 2026-11 | Visual bar stays ambitious (holds up next to commercial open-world RPGs), through cohesion and lighting, not photorealism | Personal goal; must still run on the Air |
| 2026-11 | Fun over sandbox: every milestone has a playtest "fun check", and every quest needs a hook, a choice or a reveal | The goal is a game people want to finish (`VISION.md`) |
| 2026-11 | No references to other studios' games or worlds anywhere in the repo (code, docs, names, lore) | Original work; describe the genre instead |
| 2026-11 | Saves are **JSON** (not Godot resources), one file per save plus a thumbnail; 50 manual + 3 rotating autosaves; starting the game continues from the newest | Readable when debugging; resource files can run code on load; ~50 KB per save |
| 2026-11 | World objects are identified by **node path**; anything saveable joins the `persist` group with `save_state()`/`load_state()` | Simplest thing that works; renaming a node in the editor only resets that object in old saves |
| 2026-11 | Loading **reloads the scene**, then applies the save (F2 uses the same path) | Nothing from before the load can linger |
| 2026-11 | Dialogue is a **small plain-text script format** (one file per villager), not JSON or Inspector resources | Easy to write and diff; the user will rewrite all dialogue by hand |
| 2026-11 | Quests are `QuestData` resources keyed by file name; started only by talking to someone | Content as data; no quest-specific code |
| 2026-11 | Quest markers are speech bubbles: gold ! new, grey ▶ in progress, gold ▶ ready to hand in | Readable at a glance |
| 2026-11 | Conversations don't pause the game; they lock the player (no moving, swinging or menus) | Villagers keep breathing; the clock keeps going |
| 2026-11 | The title screen is an overlay on the real world (orbiting camera), not a separate scene; nothing saves while it's up | "New game" is instant; an untouched world can't overwrite saves |
| 2026-11 | Esc opens a pause menu instead of quitting; quitting (and quitting to title) autosaves | No surprise saves or exits |
| 2026-11 | A developer console (backtick) in debug builds, documented in docs/console.md rather than in game | Fast testing; players never see it |
