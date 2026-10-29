extends "res://mods/Aquarium/main.gd"
# TEST: the mod, except that what it would send to the other players is recorded instead of sent.

var sent = []


func _send(a, fish):
	sent.append([a.actor_id, fish])
