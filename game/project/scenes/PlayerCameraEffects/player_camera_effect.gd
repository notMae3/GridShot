extends Control
class_name  PlayerCameraEffect

var source : Player:
	set = _on_source_set

# this function should be overriden by class children if necessary
func _on_source_set(new_value : Player):
	source = new_value

func remove_duplicate_effects(effect_type):
	# if the player receives identical camera effect multiple times within a short interval
	#   the graphical effects will get annoying when stacked on top of eachother
	# to prevent graphical issues all pre-existing effects of a certain type are deleted once
	#   a new effect of that type is added
	var present_effects = get_tree().get_nodes_in_group(effect_type)
	for effect in present_effects:
		if effect != self: effect.queue_free()

func _process(_delta):
	self.size = get_viewport_rect().size
	self.position = -self.size/2
