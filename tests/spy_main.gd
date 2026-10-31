extends "res://mods/Aquarium/main.gd"
# TEST: the mod, except that what it would send to the other players is recorded instead of sent, and that Steam's lobby
# member data is a dictionary here (steam id -> the text of the key "aquarium").

var sent = []
var lobby_id = 1          # 0 = not in a lobby
var lobby_data = {}
var writes = []


func _send(a, fish):
	sent.append([a.actor_id, fish])


func _lobby():
	return lobby_id


func _write_member(text):
	if lobby_id <= 0:
		return
	writes.append(text)
	lobby_data[int(Network.STEAM_ID)] = text


func _read_member(id):
	if lobby_id <= 0:
		return ""
	return lobby_data.get(int(id), "")
