extends Area

# Replaces the script of the aquarium's interact area (tank_insert.gd in the game): the interact key opens the
# mod's list instead of inserting/retrieving a single fish. main.gd sets `mod` right after swapping the script.

var text = "AQUARIUM"
var mod = null


func _activate(actor):
	if mod != null and is_instance_valid(mod):
		mod.open(actor)
