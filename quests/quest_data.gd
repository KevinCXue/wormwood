class_name QuestData
extends Resource
## One quest, as data (like ItemData for items). Each quest is a .tres file in
## res://quests/, and its file name is its id: quests/suspicious_stew.tres is
## "suspicious_stew", the name dialogue scripts use (`! start_quest
## suspicious_stew`). Edit them in the Inspector.
##
## A quest moves through numbered stages (0, 1, 2...), and the journal shows
## the objective for the current one. Simple gathering quests can set
## gather_item / gather_count instead of extra stages: the journal then shows
## "(3/5)" from what's in the bag, and the giver's marker turns gold once you
## have enough.

enum Category { MAIN, SIDE }

@export var title := "Quest"
@export var category := Category.SIDE
@export var giver := ""                  # who gives it, shown in the journal
@export_multiline var summary := ""      # what it's about, in a sentence or two
## The journal's objective for each stage, in order (stage 0 first).
@export_multiline var objectives: PackedStringArray = []
@export_multiline var completed_text := ""  # shown once it's done
@export_group("Gathering")
@export var gather_item: ItemData        # optional: what to collect...
@export var gather_count := 0            # ...and how many


## The quest's id: its file name without the extension.
func id() -> String:
	return resource_path.get_file().get_basename()
