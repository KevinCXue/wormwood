extends Sprite3D
## The speech bubble over a villager's head when they have something for
## you, quest-wise. Added by npc.gd to villagers whose dialogue script starts
## or completes a quest; it works out what to show by itself:
##   gold !   they have a quest you haven't started
##   grey ▶   one of their quests is under way
##   gold ▶   ...and you have what they need: go back to them
##   nothing  all their quests are done
##
## A Sprite3D is a flat picture placed in the 3D world. With billboard on, it
## always turns to face the camera. The bubble pictures are drawn in code
## once (no image files) and shared by every villager.

@export var height := 2.35       # metres above the villager's feet
@export var bob := 0.05          # metres of gentle up-and-down
@export var size_m := 0.42       # bubble width in metres

const GOLD := Color(0.95, 0.76, 0.3)
const GREY := Color(0.62, 0.6, 0.56)
const PX := 128                  # texture size

static var _textures := {}       # kind -> ImageTexture

var quest_ids: PackedStringArray = []
var _log: Node = null
var _t := 0.0
var _recheck := 0.0


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pixel_size = size_m / PX
	visibility_range_end = 40.0  # no bubbles across the whole town
	render_priority = 1
	position.y = height
	_t = randf() * TAU  # bubbles don't bob in step
	visible = false  # until _update() knows what to show


func _process(delta: float) -> void:
	_t += delta * 2.0
	position.y = height + sin(_t) * bob
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.3  # a few times a second is plenty
		_update()


func _update() -> void:
	if _log == null:
		# Villagers start up before the player does (they come first in the
		# scene), so the player may not have joined its group yet.
		var player := get_tree().get_first_node_in_group("player")
		if player:
			_log = player.get_node_or_null("QuestLog")
	var kind := ""
	if _log:
		for id in quest_ids:
			if not _log.is_started(id):
				kind = "new"
				break
			if _log.is_ready(id):
				kind = "ready"
			elif _log.is_active(id) and kind == "":
				kind = "active"
	visible = kind != ""
	if visible:
		texture = _texture(kind)


static func _texture(kind: String) -> ImageTexture:
	if not _textures.has(kind):
		_textures[kind] = ImageTexture.create_from_image(_draw_bubble(kind))
	return _textures[kind]


## Draw the bubble at 4x size and shrink it, which smooths the edges
## (supersampling: a cheap way to antialias shapes drawn pixel by pixel).
static func _draw_bubble(kind: String) -> Image:
	var s := PX * 4
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var paper := Color(0.97, 0.94, 0.87)
	var ink := Color(0.16, 0.12, 0.09)
	var symbol := GREY if kind == "active" else GOLD
	# The bubble: a rounded box over a little tail pointing down at the head.
	var box := Rect2(s * 0.08, s * 0.06, s * 0.84, s * 0.68)
	var radius := s * 0.2
	var tail := PackedVector2Array([Vector2(s * 0.40, s * 0.7), Vector2(s * 0.60, s * 0.7), Vector2(s * 0.5, s * 0.92)])
	var border := s * 0.035
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _rounded_box_distance(p, box, radius)
			var in_tail := Geometry2D.is_point_in_polygon(p, tail)
			if in_tail:
				# Only the tail's slanted sides get an outline, so it opens
				# into the bubble instead of being shut off by the box's edge.
				img.set_pixel(x, y, ink if _tail_edge(p, tail, border) else paper)
			elif d <= 0.0:
				img.set_pixel(x, y, ink if d > -border else paper)
	# The symbol.
	var c := box.get_center()
	if kind == "new":
		# "!": a tall bar and a dot.
		img.fill_rect(Rect2i(int(c.x - s * 0.05), int(box.position.y + s * 0.12), int(s * 0.1), int(s * 0.3)), symbol)
		_disc(img, Vector2(c.x, box.end.y - s * 0.14), s * 0.06, symbol)
	else:
		# "▶": a play triangle.
		var tri := PackedVector2Array([Vector2(c.x - s * 0.13, c.y - s * 0.17),
			Vector2(c.x - s * 0.13, c.y + s * 0.17), Vector2(c.x + s * 0.17, c.y)])
		for y in range(int(c.y - s * 0.2), int(c.y + s * 0.2)):
			for x in range(int(c.x - s * 0.2), int(c.x + s * 0.2)):
				if Geometry2D.is_point_in_polygon(Vector2(x, y), tri):
					img.set_pixel(x, y, symbol)
	img.resize(PX, PX, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## Signed distance from p to a rounded rectangle: negative inside.
static func _rounded_box_distance(p: Vector2, box: Rect2, r: float) -> float:
	var half := box.size / 2.0 - Vector2(r, r)
	var q := (p - box.get_center()).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## Is p within `width` of the tail's two slanted sides (its outline)?
static func _tail_edge(p: Vector2, tail: PackedVector2Array, width: float) -> bool:
	for i in [[0, 2], [1, 2]]:
		var closest := Geometry2D.get_closest_point_to_segment(p, tail[i[0]], tail[i[1]])
		if p.distance_to(closest) < width:
			return true
	return false


static func _disc(img: Image, centre: Vector2, r: float, color: Color) -> void:
	for y in range(int(centre.y - r), int(centre.y + r) + 1):
		for x in range(int(centre.x - r), int(centre.x + r) + 1):
			if Vector2(x, y).distance_to(centre) <= r:
				img.set_pixel(x, y, color)
