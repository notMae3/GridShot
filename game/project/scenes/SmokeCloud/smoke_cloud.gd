extends CPUParticles2D

func _on_finished():
	if is_multiplayer_authority():
		queue_free()
