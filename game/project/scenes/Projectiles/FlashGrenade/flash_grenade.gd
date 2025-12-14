extends ThrowableProjectile

var is_exploding = false

const flash_grenade_max_flash_distance = Config.throwables.flash_grenade_max_flash_distance

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, throw_distance_ : float):
	super.setup(source_, rotation_, start_position_, throw_distance_)
	self.movement_speed = Config.throwables.movement_speed

	# set the flash windup duration from config
	var anim_lib : AnimationLibrary = $AnimationPlayer.get_animation_library("")
	var anim : Animation = anim_lib.get_animation("explode")
	anim.length = Config.throwables.flash_grenade_windup_duration
	anim.track_set_key_time(0, 1, Config.throwables.flash_grenade_windup_duration)
	anim.track_set_key_time(1, 0, Config.throwables.flash_grenade_windup_duration)

	CollidedWithEnvironment.connect(explode.bind("collision"))
	MaxDistanceReached.connect(explode.bind("distance"))


func explode(reason : String):
	$Area2D.set_deferred("monitoring", false)
	movement_enabled = false
	
	if reason == "distance":
		position = start_position + direction * throw_distance
	
	$AnimationPlayer.play("explode")


func _on_explosion_peak():
	var players = get_tree().get_nodes_in_group("players")
	
	for player : Player in players:
		var raycast = RayCast2D.new()
		raycast.target_position = to_local(player.global_position)
		add_child(raycast)
		
		raycast.force_raycast_update()
		if not raycast.is_colliding() and global_position.distance_to(player.global_position) < flash_grenade_max_flash_distance:
			Globals.flash_peer.rpc_id(player.id)
	
	if is_multiplayer_authority():
		# delete the flash grenade only after the screenflash was triggered
		get_tree().create_timer(0.1).timeout.connect(queue_free)
