extends Node2D


func _on_plant_area_player_entered(player : Player, _area : int):
	if player.is_multiplayer_authority():
		player.can_plant = true


func _on_plant_area_player_exited(player : Player, _area : int):
	if player.is_multiplayer_authority():
		player.can_plant = false
