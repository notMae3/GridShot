extends ThrowableProjectile

const dmg = Config.throwables.molotov_dmg

var is_exploding = false

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, throw_distance_ : float):
	super.setup(source_, rotation_, start_position_, throw_distance_)
	self.movement_speed = Config.throwables.movement_speed
	
	# set the explosion radius from config
	var anim_lib : AnimationLibrary = $AnimationPlayer.get_animation_library("")
	var anim = anim_lib.get_animation("explode")
	anim.track_set_key_value(0, 1, Config.throwables.molotov_explosion_radius*2)
	anim.track_set_key_value(2, 1, Config.throwables.molotov_explosion_radius)

	CollidedWithPlayer.connect(_on_collided_with_player)
	CollidedWithEnvironment.connect(explode.bind("collision"))
	MaxDistanceReached.connect(explode.bind("distance"))


func _on_collided_with_player(player : Player):
	if is_exploding:
		player.take_dmg(dmg)

	elif player != source:
		explode("collision")


func explode(reason : String):
	is_exploding = true
	movement_enabled = false
	
	if reason == "distance":
		position = start_position + direction * throw_distance
	
	$AnimationPlayer.play("explode")
	
	# the animation player has a area2D:monitoring track that toggles hitbox
	#   off then on again over the span of 0.001 sec
	# this ensures that the collider re-collides with the player which caused the explosion
