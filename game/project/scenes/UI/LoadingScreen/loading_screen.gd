extends PlayerCameraEffect

@onready var anim_texture_rect = $AnimTextureRect

func _process(delta):
	super._process(delta)
	
	if visible:
		anim_texture_rect.pivot_offset = anim_texture_rect.size/2
