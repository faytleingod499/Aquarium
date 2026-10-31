extends Node
# TEST STUB: another player as the mod sees them (a node in group "player" with the Steam id as owner_id).

var owner_id = 0
var dead_actor = false
var NPC_body = false


func _ready():
	add_to_group("player")
