extends RefCounted
class_name Throwable

var ammo = 1
var is_in_hand = false

var throwable_preview : Node2D

var preview_types = {
	"target": Globals.scenes.throwable_preview,
	"tripwire": Globals.scenes.tripwire_preview
}

func _init(source : Player):
	throwable_preview = preview_types[self.preview_type].instantiate()
	throwable_preview.source = source
	throwable_preview.parent_util = self
	Globals.game_node.add_child(throwable_preview)

func fire(player_name : String, _current_ads_factor : float, rotation : float, position : Vector2):
	if ammo == 0:
		return
	
	ammo -= 1
	
	# the below line calls the function `spawn_projectile(...)` on
	#   the peer with peer id 1, aka the lobby host. this is needed since adding children
	#   from any peer which isnt the lobby host is wonky and likely to fail
	Globals.spawn_projectile.rpc_id(1, self.projectile_type, player_name, rotation, position, null, self.throwable_preview.distance_from_player)


func delete():
	throwable_preview.queue_free()
