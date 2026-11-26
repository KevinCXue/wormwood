extends RefCounted
## Reads conversation scripts: the plain-text files in res://dialogue/ (one
## per villager, e.g. tobin.txt). ui/dialogue_box.gd plays them.
##
## A RefCounted is a plain object that frees itself when nothing uses it
## (like a reference-counted object in most languages); nothing here needs to
## be in the scene tree.
##
## ---------------------------------------------------------------------------
## THE FORMAT
##
##   # A comment (whole lines only).
##
##   == start                     A section. Conversations begin at "start".
##   ? quest_done stew -> thanks  If the condition holds, jump to "thanks"
##                                (checked when reached, top to bottom).
##   Tobin: Hello there.          A line: speaker, colon, text. The player
##                                presses Enter/E to continue.
##       More of the same line.   Indented lines continue the line above.
##   ! start_quest stew           An effect (see below), done when reached.
##   - Sure. -> accept            Choices: consecutive "-" lines are offered
##   - No thanks. -> END          together. "-> END" ends the conversation.
##   - Here. -> give if has mushroom 5
##                                A choice shown only if the condition holds.
##   -> somewhere                 Jump to a section. A section that runs out
##                                without a jump ends the conversation.
##
## Conditions (put "not" in front of any to flip it):
##   quest_not_started ID   quest_active ID   quest_ready ID   quest_done ID
##   has ITEM [COUNT]       (ITEM = an item file name: mushroom, apple, axe...)
## Effects:
##   start_quest ID   set_stage ID N   complete_quest ID
##   take ITEM [COUNT]   give ITEM [COUNT]   gold N
## ---------------------------------------------------------------------------
##
## Parsing turns each section into a list of steps (Dictionaries):
##   {"type": "if",     "cond": [...], "goto": "thanks"}
##   {"type": "line",   "speaker": "Tobin", "text": "Hello there."}
##   {"type": "do",     "effect": ["start_quest", "stew"]}
##   {"type": "choose", "options": [{"text", "goto", "cond"}, ...]}
##   {"type": "goto",   "goto": "somewhere"}
## Mistakes (unknown keywords, jumps to missing sections) are reported with
## the file and line number when the script is loaded.

const CONDITIONS := {"quest_not_started": 1, "quest_active": 1, "quest_ready": 1, "quest_done": 1, "has": 1}
const EFFECTS := {"start_quest": 1, "set_stage": 2, "complete_quest": 1, "take": 1, "give": 1, "gold": 1}

static var _cache := {}  # path -> parsed sections, so each file is read once

var path := ""
var sections := {}  # section name -> Array of steps
var errors: PackedStringArray = []


## The parsed script at `path` (cached).
static func load_script(script_path: String):  # -> DialogueScript (this file)
	if not _cache.has(script_path):
		var script = load("res://dialogue/dialogue_script.gd").new()
		script._parse(script_path)
		_cache[script_path] = script
	return _cache[script_path]


## Quest ids this script starts or completes: the villager's quests, for the
## marker over their head.
func quest_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for steps in sections.values():
		for step in steps:
			if step.type == "do" and step.effect[0] in ["start_quest", "complete_quest"] \
					and not step.effect[1] in ids:
				ids.append(step.effect[1])
	return ids


func _parse(script_path: String) -> void:
	path = script_path
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_error(0, "missing or empty file")
		return
	var current: Array = []
	var number := 0
	for raw in text.split("\n"):
		number += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		# An indented line continues the previous dialogue line.
		if raw.begins_with(" ") or raw.begins_with("\t"):
			if not current.is_empty() and current.back().type == "line":
				current.back().text += " " + line
				continue
		if line.begins_with("=="):
			var name := line.trim_prefix("==").strip_edges()
			current = []
			sections[name] = current
		elif sections.is_empty():
			_error(number, "everything must be inside a section (== name)")
		elif line.begins_with("->"):
			current.append({"type": "goto", "goto": line.trim_prefix("->").strip_edges(), "line": number})
		elif line.begins_with("?"):
			var parts := line.trim_prefix("?").split("->")
			if parts.size() != 2:
				_error(number, "a condition needs a jump: ? condition -> section")
				continue
			current.append({"type": "if", "cond": _condition(parts[0], number),
				"goto": parts[1].strip_edges(), "line": number})
		elif line.begins_with("!"):
			current.append({"type": "do", "effect": _effect(line.trim_prefix("!"), number), "line": number})
		elif line.begins_with("-"):
			var option := _option(line.trim_prefix("-"), number)
			if current.is_empty() or current.back().type != "choose":
				current.append({"type": "choose", "options": [], "line": number})
			current.back().options.append(option)
		elif ":" in line:
			var colon := line.find(":")
			current.append({"type": "line", "speaker": line.left(colon).strip_edges(),
				"text": line.substr(colon + 1).strip_edges(), "line": number})
		else:
			_error(number, "not sure what this is: \"%s\"" % line)
	_check_jumps()
	for e in errors:
		push_error(e)


## "- text -> target [if condition]"
func _option(body: String, number: int) -> Dictionary:
	var parts := body.split("->")
	if parts.size() != 2:
		_error(number, "a choice needs a jump: - text -> section")
		return {"text": body.strip_edges(), "goto": "END", "cond": []}
	var target := parts[1].strip_edges()
	var cond := []
	var at := target.find(" if ")
	if at >= 0:
		cond = _condition(target.substr(at + 4), number)
		target = target.left(at).strip_edges()
	return {"text": parts[0].strip_edges(), "goto": target, "cond": cond}


## "not has mushroom 5" -> ["not", "has", "mushroom", "5"], checked.
func _condition(body: String, number: int) -> Array:
	var words := Array(body.strip_edges().split(" ", false))
	var keyword: String = words[1] if words.size() > 1 and words[0] == "not" else (words[0] if words.size() > 0 else "")
	if not CONDITIONS.has(keyword):
		_error(number, "unknown condition \"%s\"" % keyword)
	return words


func _effect(body: String, number: int) -> Array:
	var words := Array(body.strip_edges().split(" ", false))
	if words.is_empty() or not EFFECTS.has(words[0]):
		_error(number, "unknown effect \"%s\"" % (words[0] if words.size() > 0 else ""))
	elif words.size() - 1 < EFFECTS[words[0]]:
		_error(number, "\"%s\" needs %d value(s)" % [words[0], EFFECTS[words[0]]])
	return words


func _check_jumps() -> void:
	if not sections.has("start"):
		_error(0, "no \"== start\" section")
	for steps in sections.values():
		for step in steps:
			var targets: Array = [step.get("goto", "END")]
			if step.type == "choose":
				targets = step.options.map(func(o): return o.goto)
			for target in targets:
				if target != "END" and not sections.has(target):
					_error(step.line, "jump to a section that doesn't exist: \"%s\"" % target)


func _error(number: int, message: String) -> void:
	errors.append("%s:%d: %s" % [path, number, message])
