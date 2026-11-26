# Developer console

A command line for testing: reset quests, give yourself items, teleport, set
the time. It exists only in development runs (from the Godot editor, or
`godot --path .`); release exports don't include it.

**Open / close:** `` ` `` (backtick, left of 1). Esc also closes it.
The game is paused while it's open.

**Keys:** Enter runs a command. Up/Down step through earlier commands. Tab
completes command names and their arguments (quest ids, item names, places,
villagers); with several matches it fills in what they share and lists them.

Type `help` in the console for the same list, generated from the code, so
it's always current.

## Commands

| Command | What it does |
|---|---|
| `help [command]` | List the commands, or explain one. |
| `quest` or `quest list` | Every quest, and its state (not started / active, stage N / ready to hand in / done). |
| `quest start ID` | Start a quest. |
| `quest stage ID N` | Jump an active quest to stage N (starts it if needed). |
| `quest complete ID` | Mark a quest done. |
| `quest reset ID` | Forget a quest entirely, as if never started. |
| `give ITEM [COUNT]` | Put items in your bag. Item names are file names in `props/items/` (`mushroom`, `apple`, `axe`, `log`...). |
| `take ITEM [COUNT]` | Remove items from your bag. |
| `items` | List every item name, what's in your bag, and your gold. |
| `gold AMOUNT` | Add gold; a negative amount takes some away. |
| `tp` | List the places you can teleport to. |
| `tp PLACE` | Teleport: `spawn`, `house`, `cave`, `church`, `townhall`, `square`, `market`. |
| `tp VILLAGER` | Teleport in front of a villager, facing them (`tp tobin`, `tp anselm`...). |
| `tp X Y Z` | Teleport to coordinates (you land on the ground below or above). |
| `time HH[:MM]` | Set the time of day, 24-hour clock (`time 21:30`). |
| `save` | Save, like F5. |
| `load` | Load the newest save. |
| `newgame` | Start a new game. Your saves are kept (F9 still lists them). |
| `clear` | Clear the console. |

## Recipes

Replay Tobin's quest from the start:

```
quest reset suspicious_stew
take mushroom 99
tp tobin
```

Skip the walk to the cave and test the hand-in:

```
quest start suspicious_stew
give mushroom 5
tp tobin
```

See the town at night:

```
time 22
tp square
```

## Adding a command

In `debug/console.gd`: add an entry to the table in `_ready()`
(`name: [method, usage, description]`), write the method (it receives the
words after the command as `args: PackedStringArray`), add Tab completion in
`_complete()` if it takes names, and add a row to the table above.
