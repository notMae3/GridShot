extends ThrowableProjectile

var is_exploding = false

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, throw_distance_ : float):
	super.setup(source_, rotation_, start_position_, throw_distance_)
	self.movement_speed = Config.throwables.movement_speed

	CollidedWithEnvironment.connect(explode.bind("collision"))
	MaxDistanceReached.connect(explode.bind("distance"))

func explode(reason : String):
	$Area2D.set_deferred("monitoring", false)
	movement_enabled = false
	
	if reason == "distance":
		position = start_position + direction * throw_distance
	
	Globals.spawn_smoke_cloud.rpc_id(1, position)
	
	queue_free()
