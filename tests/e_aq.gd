extends SceneTree
# Headless test of the Aquarium mod against the decompiled game (real PlayerData, Globals, Network, UserSave, the
# real aqua_fish scene and the real tank_insert.gd). Run with tests/run.sh.
# (SceneTree scripts are compiled before the autoloads exist, so the game's singletons are reached with get_node.)

var T = ""
var PD
var NW
var US
var GL
var world
var hud
var player
var tank
var mod
var fails = 0
var checks = 0
var loc

const FISH = ["fish_lake_bluegill", "fish_lake_crab", "fish_lake_rainbowtrout", "fish_lake_sturgeon", "fish_rain_heliocoprion", "fish_alien_dog", "fish_rain_leedsichthys"]


func check(name, cond):
	checks += 1
	if cond:
		print("ok   ", name)
	else:
		fails += 1
		print("FAIL ", name)


func _init():
	call_deferred("_go")


func fish(i, quality = 0, size = 40.0):
	return PD._add_item(FISH[i], - 1, size, quality)


func owned_fish_actors():
	var out = []
	for a in get_nodes_in_group("actor"):
		if is_instance_valid(a) and a.get("actor_type") == "aqua_fish" and a.owner_id == NW.STEAM_ID:
			out.append(a)
	return out


# waits (up to a few seconds) until every one of my fish actors has the given visibility; the actors set it in their
# physics step, which does not run at a fixed number per idle frame
func wait_visible(want):
	for n in 300:
		yield(self, "idle_frame")
		var ok = true
		for a in owned_fish_actors():
			if a.visible != want:
				ok = false
		if ok:
			return true
	return false


func tick():
	mod._tick()
	yield(self, "idle_frame")


func _go():
	T = OS.get_environment("TESTS_DIR")
	if OS.get_environment("AQ_PCK") != "":
		print("note  using the built pck: ", OS.get_environment("AQ_PCK"), " mounted: ", ProjectSettings.load_resource_pack(OS.get_environment("AQ_PCK")))
	PD = root.get_node("PlayerData")
	NW = root.get_node("Network")
	US = root.get_node("UserSave")
	GL = root.get_node("Globals")
	NW.STEAM_ID = 4242
	# no Steam library here, so the game's Network stops initialising its variables partway: set what the mod touches
	NW.STEAM_LOBBY_ID = 0
	NW.PLAYING_OFFLINE = true
	NW.OWNED_ACTORS = []
	US.current_loaded_slot = - 1   # the mod's file for "no slot"; the game's own save is not written
	var d = Directory.new()
	for f in ["user://aquarium_slot_-1.json", "user://aquarium_slot_-1.json.bak", "user://aquarium_slot_-1.json.tmp", "user://aquarium_slot_-1.json.unreadable", "user://aquarium_slot_7.json"]:
		if d.file_exists(f):
			d.remove(f)

	print("--- setup")
	world = load(T + "/stubs/world.gd").new()
	root.add_child(world)
	loc = Position3D.new()
	loc.add_to_group("aqua_spawn_loc")
	root.add_child(loc)
	loc.global_transform.origin = Vector3(5, 1, - 20)
	hud = load(T + "/stub_hud.gd").new()
	root.add_child(hud)
	player = load(T + "/stub_player.gd").new()
	player.world = world
	player.hud = hud
	root.add_child(player)
	tank = Area.new()
	tank.set_script(load("res://Scenes/Map/Zones/tank_insert.gd"))
	root.add_child(tank)
	# the game's own fish, created the way world.gd creates it
	NW._sync_create_actor("aqua_fish", loc.global_transform.origin, "aquarium_zone", - 1, NW.STEAM_ID)
	yield(self, "idle_frame")
	mod = load(T + "/spy_main.gd").new()
	mod.name = "Aquarium"
	mod.resend_clock = - 1000.0   # the automatic 10 s resend is tested on its own, further down
	root.add_child(mod)
	yield(self, "idle_frame")

	var vanilla = owned_fish_actors()[0]
	check("the game's own fish exists and is controlled", owned_fish_actors().size() == 1 and vanilla.controlled)
	check("vanilla fish is connected to the aquarium update", PD.is_connected("_aquarium_update", vanilla, "_host_change_id"))
	check("vanilla fish has the broken join connection (the game's own bug)", NW.is_connected("_new_player_join", vanilla, "_host_change_id"))

	print("--- the tank is hooked")
	yield(tick(), "completed")
	check("tank script replaced by the mod's", str(tank.get_script().resource_path).ends_with("mods/Aquarium/tank.gd"))
	check("tank text", tank.text == "AQUARIUM")
	check("tank still an interactable", tank.is_in_group("interactable"))
	check("vanilla fish: broken join connection taken over", not NW.is_connected("_new_player_join", vanilla, "_host_change_id"))
	check("vanilla fish: still follows the aquarium update", PD.is_connected("_aquarium_update", vanilla, "_host_change_id"))
	check("empty tank: only the game's fish exists", owned_fish_actors().size() == 1)

	print("--- open the list")
	tank._activate(player)
	check("list open", mod.ui != null and hud.popups.has("AQUARIUM_MOD"))
	check("title shows 0 / 5", mod.ui_title.text.ends_with("0 / 5"))
	check("five rows", mod.ui_list.get_child_count() == 5)
	check("add button disabled with nothing held", mod.ui_add.disabled)
	tank._activate(player)
	check("a second activation does not open a second list", hud.popups.size() == 1)
	mod.close()
	check("closing frees the popup", mod.ui == null and hud.popups.empty())

	print("--- fill the tank")
	var refs = []
	for i in 6:
		refs.append(fish(i, i % 3, 30.0 + i * 11))
	var inv_before = PD.inventory.size()
	check("not holding a fish -> refused", mod.add_held(player) != "")
	player.hold(refs[0])
	check("adding the first fish works", mod.add_held(player) == "")
	check("first fish is in the game's own slot", PD.saved_aqua_fish["ref"] == refs[0] and PD.saved_aqua_fish["id"] == FISH[0])
	check("first fish left the inventory", PD.inventory.size() == inv_before - 1)
	check("hands were emptied", player.held_item["ref"] == 0)
	check("no extras yet", mod.extras.size() == 0)
	for i in range(1, 5):
		player.hold(refs[i])
		check("adding fish %d works" % (i + 1), mod.add_held(player) == "")
	check("tank holds 5", mod.fish_count() == 5)
	check("4 extras", mod.extras.size() == 4)
	check("order is the order they were added", mod.all_fish()[3]["ref"] == refs[3] and mod.all_fish()[4]["ref"] == refs[4])
	player.hold(refs[5])
	var msg = mod.add_held(player)
	check("a sixth fish is refused", msg != "" and mod.fish_count() == 5)
	var still = false
	for it in PD.inventory:
		if it["ref"] == refs[5]:
			still = true
	check("the refused fish is still in the inventory", still)
	check("the refused fish is still held", player.held_item["ref"] == refs[5])

	print("--- the mod's file")
	var f = File.new()
	check("file written", f.file_exists("user://aquarium_slot_-1.json"))
	f.open("user://aquarium_slot_-1.json", File.READ)
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	check("file holds the 4 extras, not the game's own fish", parsed.error == OK and parsed.result["fish"].size() == 4 and int(parsed.result["fish"][0]["ref"]) == refs[1])
	mod.extras = []
	mod.loaded_slot = - 999
	mod._check_slot()
	check("the file loads back", mod.extras.size() == 4 and mod.extras[2]["ref"] == refs[3] and mod.extras[2]["id"] == FISH[3])
	check("quality and size survive the file", mod.extras[0]["quality"] == 1 % 3 and abs(mod.extras[0]["size"] - 41.0) < 0.01)

	print("--- the fish in the tank")
	yield(tick(), "completed")
	var mine = owned_fish_actors()
	check("five fish actors in my game", mine.size() == 5)
	check("fish 2 is a real, announced actor (owned actor)", mod.actors[0] != null and NW.OWNED_ACTORS.has(mod.actors[0]))
	for i in range(1, 4):
		check("fish %d is local only (not announced as an owned actor)" % (i + 2), mod.actors[i] != null and not NW.OWNED_ACTORS.has(mod.actors[i]) and not mod.actors[i].is_in_group("owned_actor"))
		check("fish %d is not sending zone/position updates" % (i + 2), mod.actors[i].remembered_zone == "" and not NW.is_connected("_network_tick", mod.actors[i], "_network_share"))
		check("fish %d has no zone sync timer (only the scene's own timer)" % (i + 2), _timers(mod.actors[i]) == 1)
	check("the game's own fish does have the zone sync timer (so the check above means something)", _timers(vanilla) == 2)
	check("fish 2 does not follow the game's aquarium update", not PD.is_connected("_aquarium_update", mod.actors[0], "_host_change_id"))
	check("fish 2 has no broken join connection", not NW.is_connected("_new_player_join", mod.actors[0], "_host_change_id"))
	check("fish 3 does not follow the game's aquarium update", not PD.is_connected("_aquarium_update", mod.actors[1], "_host_change_id"))
	print("--- the scene's own 10 s timer must not copy fish 1 onto the others (reported by the user in game)")
	check("fish 1 keeps the game's timer resend (it is how the game tells late joiners)", _timer_hooked(vanilla))
	for i in 4:
		check("fish %d: the scene's timer is not connected to the game's resend" % (i + 2), not _timer_hooked(mod.actors[i]))
	var before = []
	for i in 4:
		before.append(look(mod.actors[i]))
		check("fish %d looks different from fish 1 (so the check below means something)" % (i + 2), before[i] != look(vanilla))
	for a in owned_fish_actors():
		a.get_node("Timer").emit_signal("timeout")   # what the game does every 10 seconds
	for i in 4:
		check("fish %d still shows its own fish after the timer fired" % (i + 2), look(mod.actors[i]) == before[i])
	check("fish 1 still shows fish 1", look(vanilla).find("<empty>") == - 1)

	check("fish 2 was sent once", mod.sent.size() == 1 and mod.sent[0][0] == mod.actors[0].actor_id and mod.sent[0][1]["ref"] == refs[1])
	check("sent fish data has what the receivers need", mod.sent[0][1].has("id") and mod.sent[0][1].has("size") and mod.sent[0][1].has("quality") and mod.sent[0][1].has("ref"))
	for i in 4:
		var sprite = mod.actors[i].get_node("Sprite3D")
		check("fish %d shows its fish" % (i + 2), sprite.texture != null)
	check("a local fish sits in the tank area", mod.actors[2].global_transform.origin.distance_to(loc.global_transform.origin) < 14)
	yield(tick(), "completed")
	check("ticking again sends nothing new", mod.sent.size() == 1)
	var vis = yield(wait_visible(true), "completed")
	if not vis:
		for a in owned_fish_actors():
			print("note  not visible: ", a.actor_id, " controlled=", a.controlled, " in_zone=", a.in_zone, " zone=", a.current_zone, " hidden=", a.hidden, " visible=", a.visible)
	check("all five are visible when I'm in the aquarium zone", vis)
	world.active_zone = "main_zone"
	var hidden = yield(wait_visible(false), "completed")
	check("all five are hidden outside the aquarium zone", hidden)
	world.active_zone = "aquarium_zone"

	print("--- a player joins later")
	mod._on_player_join()
	yield(tick(), "completed")
	check("fish 2 is sent again to the newcomer", mod.sent.size() == 2)

	print("--- what other players' games accept")
	NW.STEAM_LOBBY_ID = 1
	for i in 5:
		world._instance_actor({"actor_type": "aqua_fish", "at": Vector3.ZERO, "zone": "aquarium_zone", "actor_id": 9000 + i, "creator_id": 777, "rot": Vector3.ZERO, "zone_owner": - 1}, 777)
	NW.STEAM_LOBBY_ID = 0
	var theirs = 0
	for a in get_nodes_in_group("actor"):
		if is_instance_valid(a) and a.get("owner_id") == 777 and a.get("actor_type") == "aqua_fish":
			theirs += 1
	check("the game keeps only 2 aquarium fish per other player (the cap the mod works around)", theirs == 2)
	for a in get_nodes_in_group("actor"):
		if is_instance_valid(a) and a.get("owner_id") == 777:
			a.queue_free()

	print("--- take a fish out")
	var inv0 = PD.inventory.size()
	check("take the middle fish", mod.take(2) == "")
	check("it is back in the inventory", PD.inventory.size() == inv0 + 1 and _in_inventory(refs[2]))
	check("the others closed up", mod.all_fish().size() == 4 and mod.all_fish()[2]["ref"] == refs[3] and mod.all_fish()[3]["ref"] == refs[4])
	check("the game's own slot is unchanged", PD.saved_aqua_fish["ref"] == refs[0])
	check("taking a fish that isn't there is refused", mod.take(9) != "")
	check("take the game's own fish", mod.take(0) == "")
	check("it is back in the inventory too", _in_inventory(refs[0]))
	check("the game's slot is filled again by the next fish", PD.saved_aqua_fish["ref"] == refs[1] and mod.extras.size() == 2)
	check("3 fish left, in order", mod.all_fish().size() == 3 and mod.all_fish()[1]["ref"] == refs[3] and mod.all_fish()[2]["ref"] == refs[4])
	yield(tick(), "completed")
	yield(self, "idle_frame")
	check("fish 2 now shows the next fish", mod.actors[0].get_node("Sprite3D").texture != null and mod.sent[mod.sent.size() - 1][1]["ref"] == refs[3])
	check("the fish that moved away from slot 4 is gone from the tank", mod.actors[2].get_node("Sprite3D").texture == null)
	check("the leftover empty fish 3 only exists locally (nothing sent for it)", mod.sent.size() == 3)

	print("--- swap in a full tank")
	player.hold(refs[0])
	mod.add_held(player)
	player.hold(refs[2])
	mod.add_held(player)
	check("full again", mod.fish_count() == 5)
	player.hold(refs[5])
	var all_before = mod.all_fish()
	check("swap into an extra slot", mod.swap(player, 3) == "")
	check("held fish is in that slot", mod.all_fish()[3]["ref"] == refs[5])
	check("the old fish came back", _in_inventory(all_before[3]["ref"]) and not _in_inventory(refs[5]))
	check("still 5, other slots untouched", mod.fish_count() == 5 and mod.all_fish()[0]["ref"] == all_before[0]["ref"] and mod.all_fish()[4]["ref"] == all_before[4]["ref"])
	var back = all_before[3]["ref"]
	player.hold(back)
	check("swap into the game's own slot", mod.swap(player, 0) == "")
	check("held fish is in the game's slot", PD.saved_aqua_fish["ref"] == back)
	check("the old first fish came back", _in_inventory(all_before[0]["ref"]))
	player.hold(0)
	check("swapping with nothing held is refused", mod.swap(player, 1) != "")

	print("--- the list while the tank is full")
	player.hold(refs[3] if _in_inventory(refs[3]) else all_before[0]["ref"])
	tank._activate(player)
	check("rows say Swap when the tank is full and a fish is held", mod.ui_list.get_child(0).get_child(0).get_child(2).text == "Swap")
	check("add button disabled when full", mod.ui_add.disabled)
	mod.close()
	player.hold(0)
	tank._activate(player)
	check("rows say Take when nothing is held", mod.ui_list.get_child(0).get_child(0).get_child(2).text == "Take")
	mod.close()

	print("--- the announced fish 2 is re-sent now and then (the game's timer resend is cut off for it)")
	var n0 = mod.sent.size()
	mod._resend()
	check("one resend, for fish 2 only", mod.sent.size() == n0 + 1 and mod.sent[n0][0] == mod.actors[0].actor_id)
	check("and it carries fish 2's own data", mod.sent[n0][1]["ref"] == mod.all_fish()[1]["ref"])

	print("--- real time: 11 seconds pass (the game's timers run, nobody calls anything)")
	yield(tick(), "completed")   # (the actors follow the data within half a second; start from a settled tank)
	var looks_before = []
	for a in owned_fish_actors():
		looks_before.append([a, look(a)])
	var n1 = mod.sent.size()
	mod.resend_clock = 0.0
	yield(create_timer(11.0), "timeout")
	var still_ok = true
	for pair in looks_before:
		if is_instance_valid(pair[0]) and look(pair[0]) != pair[1]:
			still_ok = false
	for pair in looks_before:
		if is_instance_valid(pair[0]) and look(pair[0]) != pair[1]:
			print("note  changed: ", pair[0].actor_id, "  before: ", pair[1], "  after: ", look(pair[0]))
	check("after 11 real seconds every fish still shows its own fish", still_ok and looks_before.size() == 5)
	check("the mod re-sent fish 2 once by itself, to the right actor", mod.sent.size() == n1 + 1 and mod.sent[n1][0] == mod.actors[0].actor_id)

	print("--- fish 3 to 5 are published for the other players who have the mod")
	mod.sync_dirty = true
	mod._sync_lobby()
	var mytext = mod.lobby_data.get(4242, "")
	check("my member data holds fish 3 to 5, not fish 1 and 2", mytext.begins_with("1~") and mod._decode(mytext).size() == 3)
	var pub = mod._decode(mytext)
	var all5 = mod.all_fish()
	var same_refs = true
	for i in 3:
		if pub[i]["ref"] != all5[i + 2]["ref"] or pub[i]["id"] != all5[i + 2]["id"] or pub[i]["quality"] != all5[i + 2]["quality"] or abs(pub[i]["size"] - all5[i + 2]["size"]) > 0.01:
			same_refs = false
	check("they are exactly my places 3, 4 and 5", same_refs)
	check("fish 1 and 2 are not in it (everybody sees those anyway)", mytext.find(str(all5[0]["ref"])) == - 1 and mytext.find(str(all5[1]["ref"])) == - 1)
	var w0 = mod.writes.size()
	mod.next_check = 0.0
	mod._sync_lobby()
	check("nothing is written again while the lobby still holds it", mod.writes.size() == w0)
	mod.lobby_data.erase(4242)
	mod.next_check = 0.0
	mod._sync_lobby()
	check("a write that got lost (or a new lobby) is written again", mod.writes.size() == w0 + 1 and mod.lobby_data.get(4242, "") == mytext)
	mod.lobby_id = 2
	mod._sync_lobby()
	check("a different lobby gets it at once", mod.writes.size() == w0 + 2)
	mod.lobby_id = 1
	mod._sync_lobby()
	var saved_extras = mod.extras.duplicate(true)
	mod.extras = [saved_extras[0]]   # (Godot 3's Array.slice includes its end index, so build these by hand)
	check("with fish 1 and 2 only there is nothing to publish", mod._my_text() == "")
	mod.extras = [saved_extras[0], saved_extras[1]]
	check("with 3 fish there is one in it", mod._decode(mod._my_text()).size() == 1)
	mod.extras = saved_extras
	var wc = mod.writes.size()
	mod.lobby_id = 0
	mod.sync_dirty = true
	mod._sync_lobby()
	check("outside a lobby nothing is written", mod.writes.size() == wc)
	mod.lobby_id = 1
	mod.sync_dirty = true
	mod._sync_lobby()

	print("--- hostile text from another player")
	var good = "%s|40.00|0|111" % FISH[0]
	check("a normal fish decodes", mod._decode("1~" + good).size() == 1)
	check("empty text", mod._decode("").empty())
	check("wrong version", mod._decode("2~" + good).empty())
	check("no version", mod._decode(good).empty())
	check("unknown fish", mod._decode("1~no_such_fish|40.00|0|111").empty())
	check("an item that is not a fish", mod._decode("1~treasure_chest|40.00|0|111").empty())
	check("a path as the fish id", mod._decode("1~../../root/Network|40.00|0|111").empty() and mod._decode("1~res://x.gd|40.00|0|111").empty())
	check("capitals in the id", mod._decode("1~Fish_Lake_Bluegill|40.00|0|111").empty())
	check("too few or too many fields", mod._decode("1~%s|40.00|0" % FISH[0]).empty() and mod._decode("1~%s|40.00|0|111|9" % FISH[0]).empty())
	check("text instead of numbers", mod._decode("1~%s|big|0|111" % FISH[0]).empty() and mod._decode("1~%s|40.00|x|111" % FISH[0]).empty() and mod._decode("1~%s|40.00|0|y" % FISH[0]).empty())
	check("only 3 fish are taken from a longer list", mod._decode("1~" + "~".join(PoolStringArray([good, good, good, good, good]))).size() == 3)
	check("text longer than allowed", mod._decode("1~" + good + "~" + "x".repeat(700)).empty())
	var big = mod._decode("1~%s|99999999.00|0|111" % FISH[0])
	var avg = float(GL.item_data[FISH[0]]["file"].average_size)
	check("a huge size is cut to %s times the average" % mod.SIZE_LIMIT, big.size() == 1 and abs(big[0]["size"] - avg * mod.SIZE_LIMIT) < 0.01)
	check("a negative size is cut to the smallest", mod._decode("1~%s|-5.00|0|111" % FISH[0])[0]["size"] == 0.01)
	check("an infinite size is cut too", mod._decode("1~%s|1e999|0|111" % FISH[0]).size() == 0 or mod._decode("1~%s|1e999|0|111" % FISH[0])[0]["size"] <= avg * mod.SIZE_LIMIT)
	check("quality is cut to the game's range", mod._decode("1~%s|40.00|99|111" % FISH[0])[0]["quality"] == 5 and mod._decode("1~%s|40.00|-3|111" % FISH[0])[0]["quality"] == 0)
	check("one bad fish does not spoil the others", mod._decode("1~no_such|1.00|0|1~" + good).size() == 1)

	print("--- other players' fish 3 to 5, shown while I am in the aquarium")
	var mine_local = []
	for i in range(1, 4):
		mine_local.append(look(mod.actors[i]))
	var p555 = make_other(555)
	var p556 = make_other(556)
	var me_again = make_other(4242)    # my own id: never treated as another player
	var dead = make_other(558)
	dead.dead_actor = true
	mod.lobby_data[555] = mytext        # player 555 has the same fish 3 to 5 as I have: they must look identical
	mod.lobby_data[556] = "1~%s|30.00|1|333~%s|20.00|0|444" % [FISH[2], FISH[3]]
	mod.lobby_data[558] = mytext
	yield(tick(), "completed")
	yield(tick(), "completed")
	check("player 555 has 3 fish shown", mod.others.has(555) and mod.others[555]["actors"].size() == 3)
	check("player 556 has 2 fish shown", mod.others.has(556) and mod.others[556]["actors"].size() == 2)
	check("my own id and a dead player's are not shown", not mod.others.has(4242) and not mod.others.has(558))
	var same_look = true
	for i in 3:
		if look(mod.others[555]["actors"][i]) != mine_local[i]:
			same_look = false
	check("player 555's fish look exactly like my own fish 3 to 5 (what I publish is what they show)", same_look)
	check("player 556's two fish are not empty and differ", look(mod.others[556]["actors"][0]) != "<empty>" and look(mod.others[556]["actors"][0]) != look(mod.others[556]["actors"][1]))
	check("the game's own fish is still found as the game's own fish", mod._vanilla_actor() == vanilla)
	vanilla.remove_from_group("actor")
	check("with the game's fish gone, none of the mod's local fish is taken for it", mod._vanilla_actor() == null)
	vanilla.add_to_group("actor")
	var theirs_ok = true
	for id in [555, 556]:
		for a in mod.others[id]["actors"]:
			if NW.OWNED_ACTORS.has(a) or a.is_in_group("owned_actor") or NW.is_connected("_network_tick", a, "_network_share") or _timer_hooked(a) or PD.is_connected("_aquarium_update", a, "_host_change_id"):
				theirs_ok = false
	check("they are local only: nothing announced, no updates, no game timer, no follow of my fish 1", theirs_ok)
	var tb = []
	for a in mod.others[556]["actors"]:
		tb.append(look(a))
	for id in [555, 556]:
		for a in mod.others[id]["actors"]:
			a.get_node("Timer").emit_signal("timeout")
	var tl = []
	for a in mod.others[556]["actors"]:
		tl.append(look(a))
	check("the game's 10 s timer does not turn them into fish 1", tb == tl)
	var n_sent = mod.sent.size()
	yield(tick(), "completed")
	check("showing them sends nothing to anybody", mod.sent.size() == n_sent)

	mod.lobby_data[556] = "1~%s|99.00|2|555" % FISH[4]
	var old_actor = mod.others[556]["actors"][1]
	yield(tick(), "completed")
	check("when the data shrinks the spare fish go away", mod.others[556]["actors"].size() == 1 and not is_instance_valid(old_actor))
	check("and the first one shows the new fish", look(mod.others[556]["actors"][0]).find("<empty>") == - 1 and look(mod.others[556]["actors"][0]) != tb[0])
	mod.lobby_data[556] = ""
	var last_actor = mod.others[556]["actors"][0]
	yield(tick(), "completed")
	check("when a player takes their fish out, theirs are gone", not mod.others.has(556) and not is_instance_valid(last_actor))

	PD.players_hidden.append(555)
	var h_actor = mod.others[555]["actors"][0]
	yield(tick(), "completed")
	check("a player I have hidden (or Griefer Shield has) is not shown", not mod.others.has(555) and not is_instance_valid(h_actor))
	PD.players_hidden.erase(555)
	yield(tick(), "completed")
	check("and is shown again when no longer hidden", mod.others.has(555) and mod.others[555]["actors"].size() == 3)

	mod.lobby_data[555] = "garbage"
	yield(tick(), "completed")
	check("garbage from a player shows nothing and breaks nothing", mod.others.has(555) and mod.others[555]["actors"].empty())
	mod.lobby_data[555] = mytext
	yield(tick(), "completed")
	p555.queue_free()
	var leaving = mod.others[555]["actors"][0]
	yield(self, "idle_frame")
	yield(tick(), "completed")
	check("a player who left takes their fish with them", not mod.others.has(555) and not is_instance_valid(leaving))

	print("--- caps")
	var crowd = []
	for i in 26:
		var c = make_other(9000 + i)
		crowd.append(c)
		mod.lobby_data[9000 + i] = mytext
	yield(tick(), "completed")
	yield(tick(), "completed")
	check("at most %d other players are looked at" % mod.MAX_OTHER_PLAYERS, mod.others.size() <= mod.MAX_OTHER_PLAYERS)
	check("at most %d fish of other players at once" % mod.MAX_OTHER_FISH, mod._other_fish_count() == mod.MAX_OTHER_FISH)
	var contiguous = true
	for id in mod.others.keys():
		for a in mod.others[id]["actors"]:
			if a == null or not is_instance_valid(a):
				contiguous = false
	check("the cap leaves no empty places behind", contiguous)

	print("--- only in the aquarium, only in a lobby")
	world.active_zone = "main_zone"
	var some = mod.others[mod.others.keys()[0]]["actors"][0]
	yield(tick(), "completed")
	check("outside the aquarium nothing of other players exists", mod.others.empty() and not is_instance_valid(some))
	world.active_zone = "aquarium_zone"
	yield(tick(), "completed")
	check("back in the aquarium their fish appear again", mod.others.size() > 0)
	mod.lobby_id = 0
	yield(tick(), "completed")
	check("without a lobby nothing of other players is shown", mod.others.empty())
	mod.lobby_id = 1
	for c in crowd:
		c.queue_free()
	p556.queue_free()
	me_again.queue_free()
	dead.queue_free()
	yield(tick(), "completed")
	yield(tick(), "completed")
	check("everybody gone: nothing left", mod.others.empty() and mod._other_fish_count() == 0)
	var stray = 0
	for a in get_nodes_in_group("actor"):
		if is_instance_valid(a) and a.has_meta("aquarium_mod") and not mod.actors.has(a):
			stray += 1
	check("no fish of other players is left over", stray == 0)

	print("--- things that are not fish")
	var chest = PD._add_item("treasure_chest", - 1, 1.0, 0)
	player.hold(chest)
	check("a non-fish can't be added", mod.held_fish(player) == null)
	check("adding it is refused", mod.add_held(player) != "" or mod.fish_count() == 5)
	check("the tank stays full and the chest stays in the inventory", mod.fish_count() == 5 and _in_inventory(chest))
	player.hold(0)

	print("--- a damaged or odd file")
	mod.take(4)
	mod.take(3)
	mod.take(2)
	mod.take(1)
	check("everything out again", mod.fish_count() == 1)
	var in_inv = refs[4]
	if not _in_inventory(in_inv):
		in_inv = all_before[4]["ref"]
	var odd = {"version": 1, "fish": [
		{"id": FISH[0], "ref": 111, "size": 33.5, "quality": 2},
		{"id": "no_such_fish", "ref": 112, "size": 10.0, "quality": 0},
		{"id": "treasure_chest", "ref": 113, "size": 1.0, "quality": 0},
		{"id": FISH[1], "ref": in_inv, "size": 10.0, "quality": 0},
		{"id": FISH[2], "ref": 114, "size": 12.0, "quality": 99, "custom_name": "Big [b]Bob[/b] with a name that is far too long to fit"},
		{"id": FISH[3], "ref": 115},
		"nonsense",
		{"id": FISH[4], "ref": 116, "size": 5.0, "quality": 0},
		{"id": FISH[5], "ref": 117, "size": 6.0, "quality": 0},
		{"id": FISH[6], "ref": 118, "size": 7.0, "quality": 0},
	]}
	f.open("user://aquarium_slot_-1.json", File.WRITE)
	f.store_string(JSON.print(odd))
	f.close()
	mod.loaded_slot = - 999
	mod._check_slot()
	var refs_loaded = []
	for e in mod.extras:
		refs_loaded.append(e["ref"])
	check("unknown, non-fish, incomplete and non-object entries are skipped", not refs_loaded.has(112) and not refs_loaded.has(113) and not refs_loaded.has(115))
	check("a fish that is also in the inventory is not loaded twice", not refs_loaded.has(in_inv))
	check("no more than 4 extras", mod.extras.size() == 4 and refs_loaded == [111, 114, 116, 117])
	check("quality is limited to the game's range", mod.extras[1]["quality"] == 5)
	check("a custom name loses [ ] and is cut at 28 characters", mod.extras[1]["custom_name"].find("[") == - 1 and mod.extras[1]["custom_name"].length() <= 28)
	f.open("user://aquarium_slot_-1.json", File.WRITE)
	f.store_string("{ this is not json")
	f.close()
	mod.loaded_slot = - 999
	mod._check_slot()
	check("garbage file: nothing loaded, no crash", mod.extras.size() == 0)
	check("garbage file: a copy is kept", f.file_exists("user://aquarium_slot_-1.json.unreadable"))

	print("--- other save slots, new games")
	mod.extras = [mod._clean({"id": FISH[0], "ref": 5551, "size": 10.0, "quality": 0})]
	mod._save_file()
	US.current_loaded_slot = 7
	mod._check_slot()
	check("another save slot has its own (empty) list", mod.extras.size() == 0)
	US.current_loaded_slot = - 1
	mod._check_slot()
	check("going back loads the first slot's fish again", mod.extras.size() == 1 and mod.extras[0]["ref"] == 5551)
	PD.emit_signal("_save_reset")
	check("starting a new game in the slot clears the extra fish and their file", mod.extras.size() == 0 and not f.file_exists("user://aquarium_slot_-1.json"))

	print("--- the list closes by itself")
	tank._activate(player)
	check("the list is open before the player goes", mod.ui != null)
	player.queue_free()
	var closed = false
	for k in 30:
		yield(self, "idle_frame")
		if mod.ui == null:
			closed = true
			break
	check("the list closes by itself when the player is gone", closed and hud.popups.empty())

	print("SUMMARY ", checks, " checks, ", fails, " failed")
	quit()


func _in_inventory(ref):
	for it in PD.inventory:
		if it["ref"] == ref:
			return true
	return false


func _timers(n):
	var c = 0
	for ch in n.get_children():
		if ch is Timer:
			c += 1
	return c


func _timer_hooked(a):
	return a.get_node("Timer").is_connected("timeout", a, "_host_change_id")


# what a fish actor looks like (headless has no pixels to compare, so: the size of the picture, its colour and the
# values the actor derives from the fish it shows)
func look(a):
	var sp = a.get_node("Sprite3D")
	if sp.texture == null:
		return "<empty>"
	return str(sp.scale) + "|" + str(sp.modulate) + "|" + str(a.speed) + "|" + str(sp.texture.get_width()) + "x" + str(sp.texture.get_height())


func make_other(id):
	var n = Node.new()
	n.set_script(load(T + "/stub_other.gd"))
	n.owner_id = id
	root.add_child(n)
	return n
