extends ConstantProjectile

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, dmg_ : int):
	super.setup(source_, rotation_, start_position_, dmg_)
	self.movement_speed = Config.weapons.bullet_movement_speed
	$LifeTimeTimer.wait_time = Config.weapons.bullet_life_time

	CollidedWithPlayer.connect(_on_collided_with_player)
	CollidedWithEnvironment.connect(queue_free)

func _on_collided_with_player(player : Player):
	print("bullet collision %s, %s" % [multiplayer.get_unique_id(), source.is_multiplayer_authority()])
	if player.team != source.team:
		Globals.player_take_dmg.rpc_id(player.id, dmg)
		queue_free()

# a timer that removes the projectile if its been alive for long enough
func _on_life_time_timer_timeout():
	if is_multiplayer_authority():
		queue_free()
