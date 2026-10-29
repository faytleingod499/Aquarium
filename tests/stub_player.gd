extends Spatial
# TEST STUB: just enough of the player for the mod (group, world, hud, held item, putting the item away).

var world = null
var hud = null
var held_item = {"id": "empty_hand", "ref": 0, "size": 1.0, "quality": 0, "tags": []}


func _ready():
	add_to_group("controlled_player")


func hold(ref):
	for it in PlayerData.inventory:
		if it["ref"] == ref:
			held_item = it
			return
	held_item = PlayerData.FALLBACK_ITEM.duplicate()


func _equip_item(item_data, skip_anim = false, forced = false, set_prev = true):
	if item_data.get("ref", 0) == 0:
		held_item = PlayerData.FALLBACK_ITEM.duplicate()
