extends RefCounted
## The town as first laid out: roads, plazas, buildings and its thirty
## villagers. tools/build_village.gd turns this into res://village/village.tscn
## when that file is missing (or with --rewrite-layout). After that the scene
## is the source of truth: edit it in the editor, not this file.
##
## Coordinates are world metres (x east, z south, y up). The player spawns at
## (0, 0, 0); their house is to the north at (-11, -9.5). The land is a flat
## bowl around the spawn rising to hills south and east, so:
##   - the town square sits on the main street just south of the cottages,
##     with the market off its west side and the town hall facing it from
##     the east;
##   - the church stands on the south-east hill (~9 m up), reached by a road
##     that climbs from the square;
##   - family houses line the west street (climbing west), the main street
##     as it climbs south, and a lane to the north-east.
## Heights (y) are chosen near the natural ground; build_village.gd then
## levels pads under buildings and grades roads to these heights.

const VillagerScene := preload("res://npcs/npc.tscn")

# Colours used for skin and hair.
const SKIN_LIGHT := Color(0.86, 0.69, 0.57)
const SKIN_MEDIUM := Color(0.74, 0.56, 0.43)
const SKIN_DARK := Color(0.5, 0.36, 0.27)
const GREY := Color(0.62, 0.62, 0.62)
const BLONDE := Color(0.78, 0.62, 0.38)
const BROWN := Color(0.35, 0.22, 0.13)
const DARK := Color(0.12, 0.09, 0.07)
const AUBURN := Color(0.55, 0.3, 0.14)
const RED := Color(0.62, 0.25, 0.12)

var village: Node3D
var _roads: Node3D
var _plazas: Node3D
var _buildings: Node3D
var _people: Node3D


func build() -> Node3D:
	village = Node3D.new()
	village.name = "Village"
	village.editor_description = "Roads, plazas, buildings and villagers. Edit freely, then re-run tools/build_village.gd so the terrain (heights, dirt and paving, cleared grass and trees) matches."
	_roads = _group("Roads")
	_plazas = _group("Plazas")
	_buildings = _group("Buildings")
	_people = _group("Villagers")
	_streets()
	_town_centre()
	_homes()
	_villagers()
	return village


# --- Streets and open spaces --------------------------------------------------------

func _streets() -> void:
	# Main street: from the spawn point south through the square, then up the
	# slope past the south houses and out into the forest.
	_road("MainStreet", 3.2, [V(0.5, 0, -1), V(0.8, 0, 8), V(-0.6, 0.1, 18), V(-0.3, 0.8, 27),
		V(1.5, 1.0, 37), V(2.8, 1.0, 46), V(3.6, 2.4, 52), V(4.2, 3.8, 58), V(5.2, 5.6, 66),
		V(6.0, 7.2, 74), V(7.0, 8.0, 82)])
	_road("HousePath", 2.2, [V(0.5, 0, -1), V(-5, 0, -2.6), V(-9.2, 0, -3.7), V(-11, 0, -5.4)])
	# West street: through the market and up the slope to the west houses.
	_road("WestStreet", 2.8, [V(-9, 1.0, 37), V(-23, 1.0, 37), V(-32, 1.9, 36), V(-42, 4.0, 34.5), V(-54, 6.6, 32)])
	# Church road: climbs east from the square's south-east corner, then turns
	# up to the church door on the hill.
	_road("ChurchRoad", 2.4, [V(12.5, 1.0, 44.5), V(20, 1.9, 45), V(27, 3.4, 44.2), V(33, 5.2, 43.4),
		V(38.5, 7.0, 43.2), V(42.5, 8.6, 44), V(44, 9.2, 45.4)])
	# North-east lane, off the main street.
	_road("NorthEastLane", 2.4, [V(0.7, 0, 10), V(12, 0, 11.5), V(24, 0.2, 12.5), V(33, 0.9, 13.2), V(38, 1.6, 13.4)])


func _town_centre() -> void:
	_plaza("TownSquare", V(2, 1.0, 37), Vector2(22, 18))
	_plaza("Market", V(-16, 1.0, 37), Vector2(14, 16))
	_building("well", "Well", V(7, 1.0, 40), 0.0)
	# Stalls along the market's north and south edges, facing in.
	var colours := ["stall_red", "stall_blue", "stall_green"]
	for i in 3:
		var x: float = [-20.5, -16.0, -11.5][i]
		_building(colours[i], "StallNorth%d" % (i + 1), V(x, 1.0, 30.8), 0.0)
		_building(colours[(i + 1) % 3], "StallSouth%d" % (i + 1), V(x, 1.0, 43.2), 180.0)
	# Town hall on the square's east side, door facing west.
	_building("town_hall", "TownHall", V(21.5, 1.3, 36), -90.0)
	# Church on the hill, door (in the tower) facing north towards the town.
	_building("church", "Church", V(44, 9.2, 56), 180.0)


# --- Homes ------------------------------------------------------------------------------

## Each home gets a short path from its door to the street.
func _homes() -> void:
	# The first two cottages (from the original village).
	_home("cottage_a", "MiraCottage", V(-9, 0, 16), 90.0, V(-0.6, 0, 16))
	_home("cottage_b", "TobinCottage", V(10, 0, 22), -90.0, V(-0.5, 0, 22))
	# West street.
	_home("house_a", "BakerHouse", V(-31, 1.6, 27.5), 0.0, V(-32.2, 1.9, 35.8))
	_home("house_b", "PenhallowHouse", V(-45, 4.4, 25.5), 0.0, V(-46.2, 4.9, 33.7))
	_home("house_b", "OttilieHouse", V(-34, 2.8, 44.5), 180.0, V(-32.8, 1.9, 36.2))
	_home("house_a", "GuardHouse", V(-48, 5.8, 41.5), 180.0, V(-46.8, 5.0, 33.6))
	# Main street, climbing south.
	_home("house_a", "SmithHouse", V(-7.5, 4.0, 55), 90.0, V(3.9, 3.3, 56.2))
	_home("house_b", "FarmHouse", V(12.5, 5.0, 60), -90.0, V(4.4, 4.2, 58.8))
	_home("cottage_b", "HerbalistCottage", V(-6.5, 6.4, 68), 90.0, V(5.4, 6.0, 68))
	# North-east lane.
	_home("house_a", "HunterHouse", V(21, 0.3, 19.5), 180.0, V(22.2, 0.2, 12.6))
	_home("house_b", "CarpenterHouse", V(33.5, 1.2, 19.5), 180.0, V(34.7, 1.0, 13.3))


func _home(scene: String, node_name: String, pos: Vector3, yaw_deg: float, street: Vector3) -> void:
	var house := _building(scene, node_name, pos, yaw_deg)
	# Doors are in the front (+Z) wall: centred on cottages, 1.2 m left on houses.
	var footprint: Vector2 = house.get_meta("footprint")
	var door_x := -1.2 if scene.begins_with("house") else 0.0
	var door: Vector3 = house.transform * Vector3(door_x, 0, footprint.y / 2 + 0.4)
	_road(node_name + "Path", 1.6, [door, (door + street) / 2, street])


# --- People -----------------------------------------------------------------------------

## Thirty villagers. Each entry: where they stand (x, z) and what they face,
## then their look and what they say. y is found at runtime (they snap to the
## ground). "talk" pairs stand face to face using the talking idle.
func _villagers() -> void:
	# -- The square and the town hall --
	_villager({"name": "Aldric", "at": P(13.2, 36), "face": P(2, 37), "body": "male", "tunic": Color(0.5, 0.16, 0.15),
		"hair_style": "short", "hair": GREY, "beard": true, "skin": SKIN_LIGHT, "height": 1.0,
		"lines": ["Aldric Penhallow, mayor of this town, for my sins. Welcome.",
			"Thirty souls, a market and a church on the hill. Not bad for a clearing in the woods.",
			"If you're staying, the town could use a strong arm. Come and see me once you've settled in."]})
	_villager({"name": "Corwin", "at": P(14.0, 39.8), "face": P(2, 40), "body": "male", "outfit": "ranger",
		"hair_style": "short", "hair": BROWN, "skin": SKIN_LIGHT, "height": 1.04,
		"lines": ["Move along. Or don't. Honestly, it's very quiet here.",
			"Father says guarding the hall builds character. It mostly builds boredom."]})
	_pair({"name": "Isolde", "body": "female", "tunic": Color(0.42, 0.27, 0.48), "hair_style": "long", "hair": BLONDE,
		"skin": SKIN_LIGHT, "height": 0.97,
		"lines": ["Aldric works too hard. Someone has to make him eat.",
			"Elsbeth and I have been friends since before either of us could lift a bucket."]},
		{"name": "Elsbeth", "body": "female", "tunic": Color(0.6, 0.36, 0.2), "hair_style": "short", "hair": DARK,
		"skin": SKIN_DARK, "height": 0.98,
		"lines": ["Brannoc's forge is cold today. He says the iron's not right. He says that a lot.",
			"Isolde's telling me about the mayor's back again. Don't ask."]},
		P(-3, 33), P(-1.8, 33.6))
	_villager({"name": "Marguerite", "at": P(3.2, 46.8), "face": P(4.2, 58), "body": "female", "outfit": "ranger",
		"hair_style": "buzzed", "hair": RED, "skin": SKIN_MEDIUM, "height": 1.02,
		"lines": ["Captain Marguerite. If there's trouble on the south road, I see it first.",
			"Wolves in the hills this season. Keep that blade sharp."]})
	_villager({"name": "Jory", "at": P(8.6, 41.4), "face": P(7, 40), "body": "male", "tunic": Color(0.5, 0.42, 0.32),
		"hair_style": "buzzed", "hair": GREY, "beard": true, "skin": SKIN_MEDIUM, "height": 0.95,
		"lines": ["Sit a while. Did I ever tell you about the winter the river froze solid?",
			"This well's older than the town. Older than me, even. Just.",
			"They say something under the old pines hums at night. I say there's ale under my bed."]})
	_villager({"name": "Tamsin", "at": P(-5, 40.5), "face": P(2, 37), "body": "female", "outfit": "ranger",
		"hair_style": "long", "hair": BLONDE, "skin": SKIN_LIGHT, "height": 0.99,
		"lines": ["A traveller, like you! I'm here for the market and the gossip. Mostly the gossip.",
			"I'm writing a song about this town. So far it rhymes 'well' with 'well'. Needs work."]})

	# -- The market: traders behind their stalls --
	_villager({"name": "Agnes", "at": P(-20.5, 29.6), "face": P(-20.5, 36), "body": "female", "tunic": Color(0.74, 0.6, 0.26),
		"hair_style": "short", "hair": BROWN, "skin": SKIN_LIGHT, "height": 0.97,
		"lines": ["Fresh bread! Well. Bread. It was fresh this morning.",
			"Hamond bakes, I sell, and Lysa eats the profits."]})
	_villager({"name": "Ottilie", "at": P(-16.6, 29.6), "face": P(-16.6, 36), "body": "female", "tunic": Color(0.2, 0.45, 0.45),
		"hair_style": "long", "hair": GREY, "skin": SKIN_LIGHT, "height": 0.95,
		"lines": ["Finest cloth this side of the mountains. Only cloth this side of the mountains, but still.",
			"Piers! Stop daydreaming and fold those."]})
	_villager({"name": "Piers", "at": P(-15.0, 29.8), "face": P(-14.6, 36), "body": "male", "tunic": Color(0.45, 0.55, 0.7),
		"hair_style": "short", "hair": BLONDE, "skin": SKIN_LIGHT, "height": 1.01,
		"lines": ["Mother says I'll run the stall one day. I'd rather run away to sea. Is there a sea?",
			"Everyone wants blue. Nobody wants the green. Except Tobin."]})
	_villager({"name": "Sabine", "at": P(-11.5, 29.6), "face": P(-11.5, 36), "body": "female", "tunic": Color(0.42, 0.5, 0.34),
		"hair_style": "long", "hair": DARK, "skin": SKIN_DARK, "height": 1.0,
		"lines": ["Herbs for what ails you. Mint for the belly, willow bark for the head, nothing for the heart.",
			"If you find blue-capped mushrooms in the forest, bring them to me. Don't eat them."]})
	_villager({"name": "Maud", "at": P(-20.5, 44.4), "face": P(-20.5, 38), "body": "female", "tunic": Color(0.62, 0.42, 0.2),
		"hair_style": "short", "hair": AUBURN, "skin": SKIN_MEDIUM, "height": 0.98,
		"lines": ["Turnips, onions, cabbages. Garrick grows them, I shout about them.",
			"Rain's coming. My knees never lie."]})
	_villager({"name": "Hester", "at": P(-16, 44.4), "face": P(-16, 38), "body": "female", "tunic": Color(0.5, 0.45, 0.62),
		"hair_style": "short", "hair": GREY, "skin": SKIN_LIGHT, "height": 0.93,
		"lines": ["Mira's apples, my prices. Don't haggle, I'm old and I've heard it all.",
			"That girl does all the work and I take all the credit. As grandmothers should."]})
	_villager({"name": "Osric", "at": P(-11.5, 44.4), "face": P(-11.5, 38), "body": "male", "tunic": Color(0.25, 0.35, 0.26),
		"hair_style": "short", "hair": DARK, "beard": true, "skin": SKIN_DARK, "height": 0.99,
		"lines": ["Boots mended, soles replaced. Yours look like they've walked to the moon and back.",
			"My wife's the guard captain. Yes, really. No, I'm not scared of her. Much."]})
	_pair({"name": "Lysa", "body": "female", "tunic": Color(0.7, 0.4, 0.45), "hair_style": "long", "hair": AUBURN,
		"skin": SKIN_LIGHT, "height": 0.96,
		"lines": ["Nell says the new traveller is handsome. I said I hadn't noticed. I'd noticed.",
			"Don't tell my mother I'm not at the stall."]},
		{"name": "Nell", "body": "female", "tunic": Color(0.32, 0.32, 0.35), "hair_style": "buzzed", "hair": DARK,
		"skin": SKIN_DARK, "height": 0.98,
		"lines": ["I'm going to be a smith like my father. Only better. Don't tell him the second part.",
			"Lysa never stops talking. I love her, but she never stops."]},
		P(-18.2, 35.6), P(-17.0, 36.4))

	# -- The church --
	_villager({"name": "Anselm", "at": P(44, 44.6), "face": P(44, 38), "body": "male", "tunic": Color(0.22, 0.22, 0.26),
		"hair_style": "short", "hair": GREY, "skin": SKIN_LIGHT, "height": 0.98,
		"lines": ["Peace be with you, traveller. The doors are always open; the benches are always hard.",
			"We built this church stone by stone, hauled up that hill on our backs. Mostly Tobin's back.",
			"If something troubles you, come and sit. I'm a good listener."]})
	_villager({"name": "Wendel", "at": P(27.5, 42.8), "face": P(12, 44), "body": "male", "tunic": Color(0.7, 0.66, 0.56),
		"hair_style": "buzzed", "hair": BLONDE, "skin": SKIN_LIGHT, "height": 1.0,
		"lines": ["Father Anselm sent me to sweep the road. The whole road. Down the whole hill.",
			"Have you seen the view from the bell tower? You can see the whole valley."]})

	# -- At home --
	_villager({"name": "Hamond", "at": P(-33.8, 32.6), "face": P(-33.8, 37), "body": "male", "tunic": Color(0.8, 0.76, 0.66),
		"hair_style": "short", "hair": BROWN, "beard": true, "skin": SKIN_LIGHT, "height": 1.02,
		"lines": ["Bread's done for the day. Agnes is selling it, Lysa is 'helping'.",
			"Up at four every morning. The ovens don't light themselves. I've asked."]})
	_villager({"name": "Brannoc", "at": P(-2.4, 54.0), "face": P(4, 54), "body": "male", "tunic": Color(0.3, 0.22, 0.15),
		"hair_style": "buzzed", "hair": DARK, "beard": true, "skin": SKIN_DARK, "height": 1.06,
		"lines": ["Brannoc. Smith. The iron's wrong this week. Too soft. Like the people.",
			"That axe of yours. Who sharpened it, a goat? Bring it by sometime."]})
	_pair({"name": "Garrick", "body": "male", "tunic": Color(0.45, 0.45, 0.25), "hair_style": "short", "hair": BROWN,
		"skin": SKIN_MEDIUM, "height": 1.03,
		"lines": ["The fields are up on the south slope. Best soil in the valley, worst hill to plough.",
			"Edda wants to go to the city. What's in the city that isn't here? Besides everything."]},
		{"name": "Edda", "body": "female", "tunic": Color(0.5, 0.6, 0.4), "hair_style": "long", "hair": BLONDE,
		"skin": SKIN_MEDIUM, "height": 0.97,
		"lines": ["Father thinks the world ends at the treeline. It doesn't. I've seen maps.",
			"One day I'll leave. Probably. Maybe after the harvest."]},
		P(7.4, 61.6), P(6.8, 62.8))
	_pair({"name": "Rook", "body": "male", "outfit": "ranger", "hood": true, "hair_style": "short", "hair": DARK,
		"skin": SKIN_MEDIUM, "height": 1.03,
		"lines": ["Rook. I hunt. Deer, boar, and the occasional idiot who wanders off the path.",
			"Wren tracks better than me. Don't tell her I said so."]},
		{"name": "Wren", "body": "female", "outfit": "ranger", "hair_style": "short", "hair": BROWN,
		"skin": SKIN_LIGHT, "height": 0.97,
		"lines": ["Something's been stripping bark off the pines to the east. Not deer. Too high up.",
			"Rook says I track better than him. He thinks I can't hear him."]},
		P(19.4, 14.6), P(20.6, 15.0))
	_pair({"name": "Dunstan", "body": "male", "tunic": Color(0.65, 0.5, 0.26), "hair_style": "short", "hair": GREY,
		"beard": true, "skin": SKIN_LIGHT, "height": 1.0,
		"lines": ["Built half the houses in this town. The straight half.",
			"Need a door fixed? A roof? A coffin? I do all three. The third's the quietest work."]},
		{"name": "Beatrix", "body": "female", "tunic": Color(0.6, 0.4, 0.4), "hair_style": "long", "hair": BROWN,
		"skin": SKIN_LIGHT, "height": 0.96,
		"lines": ["Dunstan talks about wood the way other men talk about ale.",
			"Alys has his hands. Clever with tools, terrible with tidying."]},
		P(31.8, 15.0), P(32.9, 15.6))
	_villager({"name": "Alys", "at": P(37.4, 16.4), "face": P(37.4, 12), "body": "female", "tunic": Color(0.4, 0.45, 0.56),
		"hair_style": "buzzed", "hair": BROWN, "skin": SKIN_LIGHT, "height": 0.95,
		"lines": ["I made the benches in the church. Sit on one. It won't break. Probably.",
			"Father says I'm too young for the big saw. I'm not."]})
	_villager({"name": "Rosalind", "at": P(5.9, 21.4), "face": P(5.6, 23), "body": "female", "tunic": Color(0.33, 0.48, 0.3),
		"hair_style": "long", "hair": RED, "skin": SKIN_LIGHT, "height": 0.97, "idle": "Idle_Talking",
		"lines": ["Tobin brings home wood, sawdust and splinters. Mostly splinters.",
			"Mira's a sweet girl. She thinks I don't know she takes apples from our tree. I know."]})

	# -- The first two villagers, outside their cottages --
	_villager({"name": "Mira", "at": P(-4.6, 14.7), "face": P(0, 14.7), "body": "female", "tunic": Color(0.27, 0.38, 0.6),
		"trousers": Color(0.2, 0.2, 0.26), "hair_style": "long", "hair": AUBURN, "skin": SKIN_LIGHT, "height": 0.95, "skirt": true,
		"lines": ["Oh! You're the one from the big house up the road, aren't you? I'm Mira.",
			"Most mornings I'm at the market, if you're after apples. Don't tell Tobin where they came from.",
			"The forest gets dark early this time of year. Keep a lantern close."]})
	_villager({"name": "Tobin", "at": P(5.6, 23.0), "face": P(0, 23), "body": "male", "tunic": Color(0.3, 0.43, 0.25),
		"trousers": Color(0.32, 0.25, 0.17), "hair_style": "short", "hair": DARK, "skin": SKIN_MEDIUM, "height": 1.03,
		"lines": ["Name's Tobin. I cut wood for the village. Saw you hacking at the pines past the yard.",
			"Swing from the side, not straight down. Let the axe do the work.",
			"More folk are moving in, they say. We'll need a lot more timber."]})


## Two villagers chatting face to face at a and b.
func _pair(first: Dictionary, second: Dictionary, a: Vector2, b: Vector2) -> void:
	first.merge({"at": a, "face": b, "idle": "Idle_Talking"})
	second.merge({"at": b, "face": a, "idle": "Idle_Talking"})
	_villager(first)
	_villager(second)


func _villager(v: Dictionary) -> void:
	var npc: Npc = VillagerScene.instantiate()
	npc.name = v["name"]
	npc.display_name = v["name"]
	var at: Vector2 = v["at"]
	var face: Vector2 = v["face"]
	npc.position = Vector3(at.x, 0.0, at.y)  # y is found at runtime
	# Villagers face their local -Z: this yaw points that at `face`.
	npc.rotation.y = atan2(-(face.x - at.x), -(face.y - at.y))
	npc.body_type = v.get("body", "male")
	npc.outfit = v.get("outfit", "peasant")
	npc.hood = v.get("hood", false)
	npc.tunic_color = v.get("tunic", Color(0.45, 0.4, 0.32))
	if v.has("trousers"):
		npc.trousers_color = v["trousers"]
	npc.skin_color = v.get("skin", SKIN_LIGHT)
	npc.hair_color = v.get("hair", BROWN)
	npc.hair_style = v.get("hair_style", "short")
	npc.beard = v.get("beard", false)
	npc.skirt = v.get("skirt", false)
	npc.height_scale = v.get("height", 1.0)
	npc.idle_animation = v.get("idle", "Idle")
	npc.lines = PackedStringArray(v["lines"])
	_people.add_child(npc)


# --- Helpers ---------------------------------------------------------------------------

static func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


static func P(x: float, z: float) -> Vector2:
	return Vector2(x, z)


func _group(group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	village.add_child(n)
	return n


func _road(road_name: String, width: float, points: Array) -> void:
	var road := Road.new()
	road.name = road_name
	road.width = width
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	for p in points:
		curve.add_point(p)
	# Smooth corners: give each inner point handles along the line from its
	# previous to its next neighbour (a Catmull-Rom style curve).
	for i in range(1, curve.point_count - 1):
		var tangent := (curve.get_point_position(i + 1) - curve.get_point_position(i - 1)) * 0.2
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)
	road.curve = curve
	_roads.add_child(road)


func _plaza(plaza_name: String, centre: Vector3, size: Vector2) -> void:
	var plaza := Plaza.new()
	plaza.name = plaza_name
	plaza.position = centre
	plaza.size = size
	_plazas.add_child(plaza)


func _building(scene: String, node_name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var node: Node3D = load("res://buildings/%s.tscn" % scene).instantiate()
	node.name = node_name
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	_buildings.add_child(node)
	return node
