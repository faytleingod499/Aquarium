extends Node

# Aquarium
# Lets the aquarium tank hold up to 5 fish instead of 1. Press the interact key at the tank to open a list where you can
# take any fish back out, add the fish you are holding, or swap it for one in the tank.
#
# How it fits into the game:
#  - Fish #1 is the game's own aquarium slot (PlayerData.saved_aqua_fish, kept in the game's save). That fish is what
#    everyone sees, exactly as without the mod, and it is what is left if the mod is removed.
#  - Fish #2 to #5 are kept in the mod's own file, one per save slot: user://aquarium_slot_<N>.json.
#  - Fish #2 is a real aquarium fish actor like fish #1, so every player's game shows it (the game accepts two
#    aquarium fish per player from other players). Fish #3 to #5 are shown only in your own game: other players' games
#    refuse a third aquarium fish from one player, and sending actors they refuse would only cost them network traffic.
#  - Everything is client side; nothing needs to be installed on the server or on other players' games.

const VERSION = "1.0.1"

const MAX_FISH = 5                    # in the tank in total, including the game's own slot
const NETWORKED_FISH = 2              # the first two fish are real actors that other players' games show
const POLL = 0.5                      # seconds between checks of the tank hook / fish actors
const RESEND_EVERY = 10.0             # seconds between re-sends of the announced fish (the game's own fish does the same)
const POPUP = "AQUARIUM_MOD"          # entry in the HUD's popup list: it freezes the player and frees the mouse
const SAVE_PATH = "user://aquarium_slot_%d.json"
const EMPTY_FISH = {"id": "empty", "size": 1.0, "ref": 0, "quality": 0}
const TANK_SCRIPT = "res://mods/Aquarium/tank.gd"

const COL_PANEL = Color(0.16, 0.115, 0.085, 0.97)
const COL_BORDER = Color(0.662745, 0.498039, 0.286275, 1)
const COL_ROW = Color(0.235, 0.17, 0.125, 1)
const COL_ROW_EMPTY = Color(0.2, 0.145, 0.105, 0.7)
const COL_NORMAL = Color(0.662745, 0.498039, 0.286275, 1)
const COL_HOVER = Color(0.772549, 0.603922, 0.384314, 1)
const COL_PRESSED = Color(0.631373, 0.466667, 0.258824, 1)
const COL_OFF = Color(0.5, 0.42, 0.32, 0.75)
const COL_TEXT = Color(1, 0.933333, 0.835294, 1)
const COL_TEXT_DIM = Color(0.85, 0.78, 0.68, 0.75)
const COL_GOOD = Color(0.62, 0.85, 0.6, 1)

var clock = 0.0
var poll = 0.0
var resend_clock = 0.0
var extras = []              # fish #2 to #5 (dictionaries like the game's inventory items)
var loaded_slot = -999       # the save slot `extras` was read for
var actors = []              # actors[i] shows extras[i]; null until it is needed
var applied = []             # what actors[i] was last told to show (see _sig)
var vanilla_seen = []        # ids of the game's own fish actors whose broken join signal was already taken over

# the open list
var ui = null
var ui_player = null
var ui_hud = null
var ui_list = null
var ui_title = null
var ui_held = null
var ui_add = null
var ui_message = null
var ui_held_ref = -1


func _ready():
	for i in MAX_FISH - 1:
		actors.append(null)
		applied.append("")
	# `_new_player_join` passes the joiner's id, but the game's fish actor connects it to a function without
	# parameters, which Godot refuses to call (the game's 10 s timer covers late joiners anyway, just slower); the
	# `_empty` version of the same signal has no parameter, so the mod answers that one at once.
	Network.connect("_new_player_join_empty", self, "_on_player_join")
	PlayerData.connect("_save_reset", self, "_on_save_reset")


func _process(delta):
	clock += delta
	if ui != null:
		_ui_process()
	resend_clock += delta
	if resend_clock >= RESEND_EVERY:
		resend_clock = 0.0
		_resend()
	poll += delta
	if poll < POLL:
		return
	poll = 0.0
	_tick()


# ---------------------------------------------------------------------------------------------------------------
# The tank, the fish actors
# ---------------------------------------------------------------------------------------------------------------

func _tick():
	_hook_tank()
	var player = _player()
	if player == null:
		_forget_actors()
		return
	_check_slot()
	if player.get("world") == null:
		return
	_sync_actors(player)


func _player():
	for p in get_tree().get_nodes_in_group("controlled_player"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			return p
	return null


# The tank's interact area keeps the game's script until it is seen here; then it gets the mod's own script, which
# opens the list instead of inserting/retrieving one fish.
func _hook_tank():
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n):
			continue
		var s = n.get_script()
		if s == null:
			continue
		if str(s.resource_path).get_file().begins_with("tank_insert"):
			var mine = load(TANK_SCRIPT)
			if mine == null:
				print("[Aquarium] could not load ", TANK_SCRIPT)
				return
			n.set_script(mine)
			n.mod = self
			print("[Aquarium] hooked the aquarium tank")


func _forget_actors():
	for i in actors.size():
		actors[i] = null
		applied[i] = ""
	vanilla_seen.clear()


# Finds the game's own aquarium fish (the one world.gd creates for this player) and adds/updates the mod's fish.
func _sync_actors(player):
	var vanilla = _vanilla_actor()
	if vanilla == null:
		return
	if not vanilla_seen.has(vanilla.actor_id):
		vanilla_seen.append(vanilla.actor_id)
		_take_over_join_signal(vanilla)
	for i in actors.size():
		var want = extras[i] if i < extras.size() else null
		var a = actors[i]
		if a != null and not is_instance_valid(a):
			a = null
			actors[i] = null
			applied[i] = ""
		if want == null and a == null:
			continue
		var networked = i < NETWORKED_FISH - 1
		if a == null:
			a = _spawn(player.world, networked)
			if a == null:
				continue
			actors[i] = a
			applied[i] = ""
		var sig = _sig(want)
		if applied[i] != sig:
			applied[i] = sig
			_show(a, want, networked)


func _vanilla_actor():
	for a in get_tree().get_nodes_in_group("actor"):
		if not is_instance_valid(a) or a.get("actor_type") != "aqua_fish":
			continue
		if a.get("owner_id") != Network.STEAM_ID or actors.has(a):
			continue
		return a
	return null


# The game connects `_new_player_join` (it carries the joiner's id) to a function without parameters, so the call is
# dropped with an error and a player who joins later never gets the fish. Cut that connection (it only produces the
# error) and answer the signal without a parameter instead, see _on_player_join.
func _take_over_join_signal(a):
	if Network.is_connected("_new_player_join", a, "_host_change_id"):
		Network.disconnect("_new_player_join", a, "_host_change_id")


func _on_player_join():
	# somebody joined: tell them the fish again (this runs again for the next tick, and the actors resend)
	var v = _vanilla_actor()
	if v != null and v.has_method("_host_change_id"):
		v._host_change_id()
	_resend()


func _spawn(world, networked):
	var locs = get_tree().get_nodes_in_group("aqua_spawn_loc")
	if locs.empty():
		return null
	var pos = locs[0].global_transform.origin
	if networked:
		# a real actor, announced to the other players like the game's own fish
		var id = Network._sync_create_actor("aqua_fish", pos, "aquarium_zone", -1, Network.STEAM_ID)
		var a = _find_actor(id)
		if a != null:
			_unhook_vanilla(a)
		return a
	return _spawn_local(world, pos)


func _find_actor(id):
	for a in get_tree().get_nodes_in_group("actor"):
		if is_instance_valid(a) and a.get("actor_id") == id:
			return a
	return null


# A fish that exists only in this game: the same scene as the game's fish, but nothing is announced or sent. It is
# created with another owner id so that its _ready does not announce its zone, then made "mine" so that it swims.
func _spawn_local(world, pos):
	var scene = load("res://Scenes/Entities/AquaFish/aqua_fish.tscn")
	if scene == null or world == null:
		return null
	var a = scene.instance()
	a.visible = false
	a.actor_id = randi()
	a.owner_id = -2
	a.current_zone = "aquarium_zone"
	a.current_zone_owner = -1
	a.actor_type = "aqua_fish"
	a.world = world
	world.entities.add_child(a)
	a.global_transform.origin = pos
	a.owner_id = Network.STEAM_ID
	a._setup_controlled()
	_unhook_vanilla(a)
	if Network.is_connected("_network_tick", a, "_network_share"):
		Network.disconnect("_network_tick", a, "_network_share")
	return a


# The game's fish actor shows PlayerData.saved_aqua_fish (fish 1) whenever it changes, when somebody joins AND every 10
# seconds (a Timer in the scene is connected to the same function). The mod's fish show their own fish, so all three
# connections are cut; without the timer's, every extra fish turned into a copy of fish 1 after 10 seconds, and told
# everybody else's game so too.
func _unhook_vanilla(a):
	if PlayerData.is_connected("_aquarium_update", a, "_host_change_id"):
		PlayerData.disconnect("_aquarium_update", a, "_host_change_id")
	if Network.is_connected("_new_player_join", a, "_host_change_id"):
		Network.disconnect("_new_player_join", a, "_host_change_id")
	var t = a.get_node_or_null("Timer")
	if t != null and t.is_connected("timeout", a, "_host_change_id"):
		t.disconnect("timeout", a, "_host_change_id")


func _show(a, fish, networked):
	var d = fish.duplicate(true) if fish != null else EMPTY_FISH.duplicate(true)
	if networked:
		_send(a, d.duplicate(true))
	a._change_id(d)


# (a separate function so that tests can see what would be sent)
func _send(a, fish):
	Network._send_actor_action(a.actor_id, "_change_id", [fish])


# The game's own fish tells everybody what it shows every 10 seconds (a Timer in its scene), which is how players who
# join later get it. The mod's announced fish (fish 2) has that timer cut off (see _unhook_vanilla), so it does the same.
func _resend():
	for i in NETWORKED_FISH - 1:
		var a = actors[i]
		if a == null or not is_instance_valid(a):
			continue
		var want = extras[i] if i < extras.size() else null
		_send(a, want.duplicate(true) if want != null else EMPTY_FISH.duplicate(true))


func _sig(fish):
	if fish == null:
		return "empty"
	return str(fish["id"]) + "|" + str(fish["ref"]) + "|" + str(fish["size"]) + "|" + str(fish["quality"])


# ---------------------------------------------------------------------------------------------------------------
# What is in the tank
# ---------------------------------------------------------------------------------------------------------------

func _vanilla_has():
	var f = PlayerData.saved_aqua_fish
	return typeof(f) == TYPE_DICTIONARY and f.has("id") and f["id"] != "empty"


# Every fish in the tank in order. Index 0 is the game's own slot.
func all_fish():
	var out = []
	if _vanilla_has():
		out.append(PlayerData.saved_aqua_fish.duplicate(true))
	for e in extras:
		out.append(e.duplicate(true))
	return out


# Keeps the game's own slot filled first, so that the fish everyone sees are the first ones and the game's slot is
# only empty when the whole tank is.
func _compact():
	if not _vanilla_has() and extras.size() > 0:
		var f = extras.pop_front()
		PlayerData._aquarium_update(f, false)


func fish_count():
	return all_fish().size()


# The fish the player is holding, or null.
func held_fish(player):
	if player == null or not is_instance_valid(player):
		return null
	var h = player.get("held_item")
	if typeof(h) != TYPE_DICTIONARY or not h.has("id") or not h.has("ref"):
		return null
	if h["ref"] == 0 or not Globals.item_data.has(h["id"]):
		return null
	if Globals.item_data[h["id"]]["file"].category != "fish":
		return null
	return h


# Puts the fish being held into the first free place.
func add_held(player):
	var h = held_fish(player)
	if h == null:
		return "Hold a fish to put it in the aquarium."
	if fish_count() >= MAX_FISH:
		return "The aquarium is full. Swap a fish or take one out."
	var fish = _clean(h)
	if fish == null:
		return "That fish can't go in the aquarium."
	player._equip_item({"ref": 0}, true, true)
	_put(fish)
	_changed()
	return ""


# Gives the fish in place `index` back to the inventory.
func take(index):
	var fish = all_fish()
	if index < 0 or index >= fish.size():
		return "That fish is already gone."
	if index == 0:
		PlayerData._add_raw_item(PlayerData.saved_aqua_fish)
		PlayerData._aquarium_update(EMPTY_FISH.duplicate(true), false)
	else:
		PlayerData._add_raw_item(extras[index - 1])
		extras.remove(index - 1)
	_compact()
	PlayerData._send_notification("fish retrieved from aquarium", 0)
	_changed()
	return ""


# Puts the held fish in place `index` and gives that fish back (used when the tank is full).
func swap(player, index):
	var h = held_fish(player)
	if h == null:
		return "Hold a fish to swap it."
	var fish = all_fish()
	if index < 0 or index >= fish.size():
		return "That fish is already gone."
	var incoming = _clean(h)
	if incoming == null:
		return "That fish can't go in the aquarium."
	player._equip_item({"ref": 0}, true, true)
	if index == 0:
		# the game's own swap: the held fish goes in, the old one comes back to the inventory
		PlayerData._aquarium_update(incoming, true)
	else:
		var old = extras[index - 1]
		extras[index - 1] = incoming
		PlayerData._remove_item(incoming["ref"])
		PlayerData._add_raw_item(old)
		PlayerData._send_notification("fish swapped in the aquarium!")
	_changed()
	return ""


func _put(fish):
	if not _vanilla_has():
		# the game's own path: keeps its slot, takes the fish out of the inventory and says so
		PlayerData._aquarium_update(fish, true)
	else:
		extras.append(fish)
		PlayerData._remove_item(fish["ref"])
		PlayerData._send_notification("fish sent to aquarium!")


func _changed():
	_save_file()
	_save_game()
	if ui != null:
		_rebuild()


func _save_game():
	# write the game's own save now, so that the inventory and the mod's file never disagree after a crash
	if UserSave.current_loaded_slot == -1 or UserSave.saving_in_progress:
		return
	UserSave._save_slot(UserSave.current_loaded_slot)


# A copy of a fish with only the fields that matter, safe to store.
func _clean(e):
	if typeof(e) != TYPE_DICTIONARY:
		return null
	for k in ["id", "size", "quality", "ref"]:
		if not e.has(k):
			return null
	var id = str(e["id"])
	if not Globals.item_data.has(id):
		return null
	if Globals.item_data[id]["file"].category != "fish":
		return null
	# (fish never have tags in the game, and the game's own item check can't handle a filled tag list, so none are kept)
	var c = {"id": id, "ref": int(e["ref"]), "size": float(e["size"]), "quality": int(e["quality"]), "tags": [], "custom_name": ""}
	c["size"] = clamp(c["size"], 0.01, 999999999.0)
	c["quality"] = int(clamp(c["quality"], 0, PlayerData.QUALITY_DATA.size() - 1))
	if e.has("custom_name"):
		c["custom_name"] = str(e["custom_name"]).left(28).replace("[", "").replace("]", "")
	return c


# ---------------------------------------------------------------------------------------------------------------
# The mod's file
# ---------------------------------------------------------------------------------------------------------------

func _path():
	return SAVE_PATH % int(UserSave.current_loaded_slot)


func _check_slot():
	var slot = UserSave.current_loaded_slot
	if slot == loaded_slot:
		return
	loaded_slot = slot
	_forget_actors()
	_load_file()


func _load_file():
	extras = []
	var path = _path()
	var f = File.new()
	if not f.file_exists(path):
		return
	if f.open(path, File.READ) != OK:
		print("[Aquarium] could not read ", path)
		return
	var text = f.get_as_text()
	f.close()
	var res = JSON.parse(text)
	if res.error != OK or typeof(res.result) != TYPE_DICTIONARY or typeof(res.result.get("fish")) != TYPE_ARRAY:
		print("[Aquarium] ", path, " is not readable; it is left as it is and a copy is kept")
		Directory.new().copy(path, path + ".unreadable")
		return
	# a fish that is also in the inventory (the game's save is older than the mod's file after a crash) stays in the
	# inventory: nothing is duplicated and nothing is lost
	var refs = {}
	for it in PlayerData.inventory:
		if typeof(it) == TYPE_DICTIONARY and it.has("ref"):
			refs[int(it["ref"])] = true
	if _vanilla_has():
		refs[int(PlayerData.saved_aqua_fish["ref"])] = true
	for e in res.result["fish"]:
		var c = _clean(e)
		if c == null:
			print("[Aquarium] skipped a fish in the file that the game doesn't know")
			continue
		if refs.has(c["ref"]):
			print("[Aquarium] skipped a fish that is already in the inventory or the tank")
			continue
		if extras.size() >= MAX_FISH - 1:
			print("[Aquarium] the file has more fish than the tank holds; the rest were left out")
			break
		refs[c["ref"]] = true
		extras.append(c)
	_compact()
	print("[Aquarium] loaded ", extras.size(), " extra fish for save slot ", loaded_slot)


func _save_file():
	var path = _path()
	var tmp = path + ".tmp"
	var f = File.new()
	if f.open(tmp, File.WRITE) != OK:
		print("[Aquarium] could not write ", tmp)
		return false
	f.store_string(JSON.print({"version": 1, "fish": extras}, "\t"))
	f.close()
	var d = Directory.new()
	if d.file_exists(path):
		d.copy(path, path + ".bak")
		d.remove(path)
	d.rename(tmp, path)
	return true


# a new game was started in the save slot: the old extra fish belong to the old game
func _on_save_reset():
	extras = []
	_forget_actors()
	var d = Directory.new()
	if d.file_exists(_path()):
		d.remove(_path())


# ---------------------------------------------------------------------------------------------------------------
# The list
# ---------------------------------------------------------------------------------------------------------------

func open(player):
	if ui != null or player == null:
		return
	var hud = player.get("hud")
	if hud == null or not is_instance_valid(hud) or hud.popups.has(POPUP):
		return
	_check_slot()
	ui_player = player
	ui_hud = hud
	hud.popups.append(POPUP)
	_build_ui()
	_rebuild()


func close():
	if ui_hud != null and is_instance_valid(ui_hud):
		ui_hud.popups.erase(POPUP)
	if ui != null and is_instance_valid(ui):
		ui.queue_free()
	ui = null
	ui_player = null
	ui_hud = null
	ui_list = null


func _ui_process():
	if not is_instance_valid(ui_player) or not is_instance_valid(ui_hud) or not is_instance_valid(ui):
		close()
		return
	if Input.is_action_just_pressed("esc_menu"):
		close()
		return
	var h = held_fish(ui_player)
	var r = h["ref"] if h != null else 0
	if r != ui_held_ref:
		_rebuild()


func _build_ui():
	var parent = ui_hud.get_node_or_null("main")
	if parent == null:
		parent = ui_hud
	ui = Control.new()
	ui.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	if parent is Control and parent.theme != null:
		ui.theme = parent.theme
	parent.add_child(ui)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)

	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(720, 0)
	var sb = _box(COL_PANEL, 14, 18)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = COL_BORDER
	panel.add_stylebox_override("panel", sb)
	center.add_child(panel)

	var box = VBoxContainer.new()
	box.add_constant_override("separation", 10)
	panel.add_child(box)

	ui_title = _label("", COL_TEXT)
	ui_title.align = Label.ALIGN_CENTER
	box.add_child(ui_title)

	ui_list = VBoxContainer.new()
	ui_list.add_constant_override("separation", 6)
	box.add_child(ui_list)

	ui_message = _label("", COL_GOOD)
	ui_message.align = Label.ALIGN_CENTER
	ui_message.visible = false
	box.add_child(ui_message)

	var bottom = HBoxContainer.new()
	bottom.add_constant_override("separation", 10)
	box.add_child(bottom)

	ui_held = _label("", COL_TEXT_DIM)
	ui_held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_held.autowrap = true
	bottom.add_child(ui_held)

	ui_add = _button("Add held fish")
	ui_add.connect("pressed", self, "_on_add")
	bottom.add_child(ui_add)

	var closeb = _button("Close")
	closeb.connect("pressed", self, "close")
	bottom.add_child(closeb)


func _rebuild():
	if ui == null or not is_instance_valid(ui) or ui_list == null:
		return
	for c in ui_list.get_children():
		ui_list.remove_child(c)
		c.queue_free()
	var fish = all_fish()
	var h = held_fish(ui_player)
	ui_held_ref = h["ref"] if h != null else 0
	var full = fish.size() >= MAX_FISH
	ui_title.text = "AQUARIUM   %d / %d" % [fish.size(), MAX_FISH]
	for i in MAX_FISH:
		ui_list.add_child(_row(i, fish[i] if i < fish.size() else null, h != null and full))
	if h != null:
		ui_held.text = "Holding: " + fish_name(h) + ("  (full: pick a fish to swap with)" if full else "")
	else:
		ui_held.text = "To add a fish: close this, hold the fish, and use the tank again."
	ui_add.disabled = h == null or full


func _row(i, fish, swap_mode):
	var pc = PanelContainer.new()
	pc.add_stylebox_override("panel", _box(COL_ROW if fish != null else COL_ROW_EMPTY, 8, 8))
	var hb = HBoxContainer.new()
	hb.add_constant_override("separation", 12)
	pc.add_child(hb)

	var icon = TextureRect.new()
	icon.rect_min_size = Vector2(56, 56)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if fish != null:
		icon.texture = Globals.item_data[fish["id"]]["file"].icon
	hb.add_child(icon)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGN_CENTER
	hb.add_child(vb)

	var seen = "everyone can see this fish" if i < NETWORKED_FISH else "only you can see this fish"
	if fish != null:
		var q = PlayerData.QUALITY_DATA.get(fish["quality"], PlayerData.QUALITY_DATA[0])
		var title = _label("%d.  %s" % [i + 1, fish_name(fish)], Color(q["color"]) if fish["quality"] > 0 else COL_TEXT)
		vb.add_child(title)
		vb.add_child(_label("%scm  -  %s" % [str(stepify(fish["size"], 0.1)), seen], COL_TEXT_DIM))
		var b = _button("Swap" if swap_mode else "Take")
		b.rect_min_size = Vector2(110, 40)
		b.connect("pressed", self, "_on_swap" if swap_mode else "_on_take", [i])
		hb.add_child(b)
	else:
		vb.add_child(_label("%d.  (empty)" % (i + 1), COL_TEXT_DIM))
		vb.add_child(_label(seen, COL_TEXT_DIM))
		var spacer = Control.new()
		spacer.rect_min_size = Vector2(110, 40)
		hb.add_child(spacer)
	return pc


func _on_take(i):
	_report(take(i))


func _on_swap(i):
	_report(swap(ui_player, i))


func _on_add():
	_report(add_held(ui_player))


func _report(msg):
	if ui_message == null or not is_instance_valid(ui_message):
		return
	ui_message.text = msg
	ui_message.visible = msg != ""
	ui_message.add_color_override("font_color", Color(0.9, 0.5, 0.42, 1) if msg != "" else COL_GOOD)


# "Large Shining Bluegill" (or the name the player gave it), like the inventory shows it
func fish_name(f):
	var data = Globals.item_data[f["id"]]["file"]
	var n = str(data.item_name)
	var prefix = ""
	if f.has("custom_name") and f["custom_name"] != "":
		n = f["custom_name"]
	else:
		var p = PlayerData._get_size_type(f["id"], f["size"])
		if p != "":
			prefix = p.capitalize() + " "
	var q = PlayerData.QUALITY_DATA.get(f["quality"])
	var quality = str(q["name"]) if q != null else ""
	return quality + prefix + n


func _label(text, color):
	var l = Label.new()
	l.text = text
	l.add_color_override("font_color", color)
	return l


func _button(text):
	var b = Button.new()
	var generic = "res://Scenes/Menus/Main Menu/ui_generic_button.gd"
	if ResourceLoader.exists(generic):
		b.set_script(load(generic))
	b.text = text
	b.rect_min_size = Vector2(150, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.add_color_override("font_color", COL_TEXT)
	b.add_color_override("font_color_hover", COL_TEXT)
	b.add_color_override("font_color_pressed", COL_TEXT)
	b.add_color_override("font_color_disabled", COL_TEXT_DIM)
	b.add_stylebox_override("normal", _box(COL_NORMAL, 8, 6))
	b.add_stylebox_override("hover", _box(COL_HOVER, 8, 6))
	b.add_stylebox_override("pressed", _box(COL_PRESSED, 8, 6))
	b.add_stylebox_override("disabled", _box(COL_OFF, 8, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _box(color, radius, margin):
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s
