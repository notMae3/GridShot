extends Node2D

@onready var path_line = $PathLine

var player_raycast : RayCast2D
var distance_from_player : float

var source : Player : 
	set(new_value):
		source = new_value
		_on_source_set()

var parent_util : Throwable

var old_player_position = null
var old_player_rotation = null
var old_position = null

func _on_source_set():
	player_raycast = source.get_node("ThrowablePreviewRaycast")

func _process(_delta):
	if parent_util:
		visible = parent_util.is_in_hand
	
	# prevents fatal errors when the lobby host leaves the lobby after a match
	if not player_raycast:
		return
	
	# move the preview box
	if player_raycast.is_colliding():
		position = player_raycast.get_collision_point()
	else:
		var direction = Vector2.from_angle(player_raycast.global_rotation)
		position = player_raycast.global_position + direction * player_raycast.target_position.length()
	
	# if no values changed since last frame dont update the lines and stuff
	if [
			source.position == old_player_position,
			source.rotation == old_player_rotation,
			position == old_position
			].all(func(val): return val):
		return
	
	
	# move the path line
	var preview_position = to_local(global_position)
	var player_position = to_local(source.global_position)
	var player_point_position = player_position + player_position.direction_to(preview_position) * 76
	var preview_point_position = preview_position + preview_position.direction_to(player_position) * 48
	
	if preview_point_position.distance_to(player_position) < player_point_position.distance_to(player_position):
		path_line.set_point_position(0, Vector2.ZERO)
		path_line.set_point_position(1, Vector2.ZERO)
	
	else:
		path_line.set_point_position(0, player_point_position)
		path_line.set_point_position(1, preview_point_position)
	
	# update distance to player, which is used when firing
	distance_from_player = source.position.distance_to(position)
	
	old_player_position = source.position
	old_player_rotation = source.rotation
	old_position = position
