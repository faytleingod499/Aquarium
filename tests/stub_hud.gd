extends Node
# TEST STUB: the HUD's popup list (the mod adds its name to freeze the player) and a "main" control to put the list on.

var popups = []


func _ready():
	var m = Control.new()
	m.name = "main"
	m.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(m)
