# Wormwood: Vision

## North star

**A story-driven open-world fantasy RPG in the classic mould: a handcrafted
valley, a main questline with a mystery at its heart, towns full of people
with lives of their own, and wilderness worth exploring. Fun comes first.
The sandbox exists to serve the story and the quests, not the other way
round.**

Small enough for one person to finish, and good enough that a friend plays
it to the end because they want to know what happens.

> **Read this before starting a feature.** If a piece of work doesn't serve a
> pillar below, it waits. Where pillars conflict, the higher one wins.
> What to build next, and in what order, is in `ROADMAP.md`.

## Why this exists

Wormwood is a hobby project to learn game development, and to stretch
software skills outside my day job, by building a small open-world fantasy RPG
in Godot. It is not being made to sell. "Done" means a game a friend could
play start to finish and enjoy, not a commercial release.

## The pitch (draft)

*A star fell on the valley, and the rivers turned bitter. You arrive in a
hillside town that is learning to live with what came down from the sky,
and you find out what it really was.*

> The lore here is a placeholder. The premise (a fallen "Wormwood" star, bitter
> waters, a town living in its shadow) is a starting point for the main story,
> not a decision. A one-page lore sketch (`docs/lore.md`) is part of
> Milestone 1 so that quests and gossip point at the same truth from the
> start; the full lore bible comes in Milestone 5. All names and lore are
> original; nothing is borrowed from existing franchises.

## What makes it fun

"Fun" is the goal, so here is what it means for this game. Every milestone
should deliver more of these, and each one has a playtest question to check
it (see `ROADMAP.md`).

- **Curiosity:** the town is hiding something, and you want to know what.
  People say odd things; places don't add up.
- **Agency:** your choices change things. The same quest can end more than
  one way, and the town remembers which.
- **Discovery:** leaving the road finds something worth having: a ruin, a
  note, a view, a better axe.
- **Mastery:** you get better in ways you can feel, at fighting, at chopping,
  at talking your way through.
- **A world that answers back:** you can pick it up, knock it over, chop it
  down, and people notice.

Patterns that kill fun, to design against:
- **Chores:** "bring me 5 X" with nothing else to it. Every quest needs a
  hook, a choice or a reveal, however small.
- **Empty space:** walking a long way past nothing.
- **Systems without purpose:** a mechanic nobody needs to use. If no quest or
  goal uses it, it isn't done.
- **Busywork menus:** managing the inventory should be quick (hence the
  wheel and auto-equip).

## Pillars, in priority order

1. **Story and lore: there's a mystery worth uncovering.**
   The world has a history, and the main quest reveals it. Side quests,
   books, ruins and villager gossip all hint at the same truth.
   *Test:* does this feature tell the player something about the world, or
   give them a reason to care?

2. **A living world: the town goes on without you.**
   Villagers have homes, jobs and daily routines. They remember what you did,
   and the town visibly changes as quests resolve.
   *Test:* would a villager notice or react to this?

3. **Exploration: curiosity pays off.**
   Leave the road and you find something: a ruin, a cave, a note, a view.
   No map markers for undiscovered things.
   *Test:* is there a reason to go and look over there?

4. **Combat and growth: you get better by doing.**
   Weighty, physical melee (the swing and hit system already in place), and
   skills that improve as you use them. Gear matters, but it doesn't
   replace skill.
   *Test:* does this make the player feel stronger in a way they earned?

**Underneath all four: the world is physical.** Items are real objects you
pick up, carry, drop and place, trees fall, and things react when hit. This
is already Wormwood's signature, so keep it. (The inventory respects it: tap
to pocket, hold to carry by hand.)

## Core loop

```
 explore / talk ──► find a hook (quest, rumour, resource, ruin)
       ▲                       │
       │                       ▼
 town changes ◄── return ◄── act (fight, gather, sneak, persuade)
 story advances     reward, skills grow
```

Every system should plug into this loop. A system that doesn't, like
decorative furniture with no use, is polish, not progress.

## What "1.0" looks like: a small RPG

- **One region:** the valley, with **2–3 towns** (the current hillside town
  is the hub) and wilderness between them.
- **2 dungeons** (a cave or ruin each), at least one tied to the main story.
- **Main quest:** about 3–5 hours, in 3 acts, ending in a reveal about the
  fallen star.
- **Side quests:** around 10–15, each using existing systems, most of them
  showing a villager's life or a piece of lore.
- **Total playtime:** about 5–10 hours.

## Visual bar

Ambitious: **screenshots that hold up next to commercial open-world fantasy
RPGs**, reached through lighting, atmosphere and a cohesive look rather than
polygon counts or photorealism.
That means a consistent art direction (one palette, one level of detail
across characters, buildings and props), real lighting (interiors lit by
their lamps, day/night, fog), and replacing the flat-coloured greybox
buildings with textured ones in a polish pass. It is built from CC0 assets
(Quaternius, Poly Haven) plus generated pieces, and it must still hold up on
the MacBook Air's `low` preset.

## Non-goals (things we deliberately won't do)

- Multiplayer or online features
- Voice acting (text dialogue only)
- Consoles or mobile (PC and Mac only)
- Photorealism (see *Visual bar*: stylised and cohesive instead)
- Deep crafting trees, base building, romance, mounts
- AI-generated text, dialogue or art **shipped** in the game. Development
  help is fine, and AI-written lines are fine as **placeholders** while
  systems are being built (the 30 villagers' current lines are placeholders).
  All shipped text is rewritten by me before release; that's scheduled in
  Milestone 5. See the Steam disclosure rules if it's ever released.
- A huge world. Dense and handcrafted beats big and empty

## Working principles

1. **Playable over pretty.** Every milestone ends with something you can
   play from start to finish. Visual polish happens in a dedicated polish
   pass at the end of a milestone, not whenever something looks off.
2. **Log polish, don't fix it.** Visual nitpicks go in `TODO.md` under
   *Polish*, and only get fixed now if they break immersion badly (a sword
   through the hand, yes; a slightly dark corner, no). Otherwise they wait
   for the polish pass.
3. **One loop, end to end, before widening.** Build one quest that uses
   inventory, dialogue and save/load before building a second system.
4. **Content is data.** Quests, dialogue, items and villager routines live
   in resource files (`.tres`) or simple data, not hard-coded scripts, so
   adding content never needs new code. (Items already work this way:
   `props/items/*.tres`.)
5. **Keep it running on the MacBook Air.** The `low` quality setting must stay
   playable there (60 fps target in the town). The Windows PC is for heavier
   work.
6. **Learn on purpose.** When a system is new to me, such as state machines,
   saving or AI, build it the understandable way first and the clever way only
   when it's actually needed.
7. **Every system gets a smoke test.** A headless script in `tests/` that
   plays the system the way a player would (pick up, equip, save, reload...)
   and fails loudly. Run them all before committing, so new work can't
   quietly break old work.
8. **Record decisions.** When a design choice is made (list vs grid
   inventory, tap vs hold E), add a line to the decision log in
   `ROADMAP.md` so it isn't relitigated later.
