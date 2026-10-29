extends SceneTree
# Renders the list at the game's base size (1920x1080) with the game's own HUD theme and saves PNGs:
#   xvfb-run -a -s "-screen 0 1920x1080x24" <windowed godot> --path <decomp> --video-driver GLES2 --resolution 1920x1080 -s tests/v_aq.gd
# (needs the decompiled game as the project; the HUD is a stand-in, so it shows only the list on a dark backdrop)

var T = ""


func _init():
	call_deferred("_go")


func _go():
	T = OS.get_environment("TESTS_DIR")
	var NW = root.get_node("Network")
	var PD = root.get_node("PlayerData")
	NW.STEAM_ID = 4242
	NW.STEAM_LOBBY_ID = 0
	NW.PLAYING_OFFLINE = true
	NW.OWNED_ACTORS = []
	root.get_node("UserSave").current_loaded_slot = - 1
	for c in root.get_children():   # the game's autoload overlays (the scene transition's circle wipe) would cover the shot
		if c is CanvasLayer:
			c.visible = false
	var bg = ColorRect.new()
	bg.color = Color(0.11, 0.2, 0.3)
	bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(bg)
	var hud = load(T + "/stub_hud.gd").new()
	root.add_child(hud)
	hud.get_node("main").theme = load("res://Assets/Themes/main.tres")
	var player = load(T + "/stub_player.gd").new()
	player.hud = hud
	root.add_child(player)
	var mod = load(T + "/spy_main.gd").new()
	root.add_child(mod)
	var ids = ["fish_lake_bluegill", "fish_lake_sturgeon", "fish_rain_heliocoprion", "fish_alien_dog", "fish_lake_crab", "fish_lake_rainbowtrout"]
	var q = [0, 1, 3, 5, 0, 2]
	var sz = [28.0, 210.0, 640.0, 95.0, 9.0, 61.0]
	var refs = []
	for i in 6:
		refs.append(PD._add_item(ids[i], - 1, sz[i], q[i]))
	# 3 fish in the tank, one in hand
	for i in 3:
		player.hold(refs[i])
		mod.add_held(player)
	player.hold(refs[3])
	mod.open(player)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	_shot("not_full_holding_fish")
	# full tank, holding a fish
	mod.add_held(player)
	player.hold(refs[4])
	mod.add_held(player)
	player.hold(refs[5])
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	_shot("full_swap")
	mod.close()
	player.hold(0)
	mod.take(1)
	mod.take(1)
	mod.open(player)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	_shot("three_fish_empty_hand")
	quit()


func _shot(name):
	var img = root.get_texture().get_data()
	img.flip_y()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	print("saved ", name, " ", img.get_size())
