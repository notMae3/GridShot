extends ProjectileBase
class_name ThrowableProjectile

var throw_distance : float
var movement_enabled = true

signal MaxDistanceReached

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, throw_distance_ : float):
	self.source = source_
	
	self.rotation = rotation_
	self.direction = Vector2.from_angle(self.rotation)

	self.start_position = start_position_
	self.position = self.start_position + self.direction * 64 # offset spawn position from player center

	self.throw_distance = throw_distance_

func _physics_process(_delta):
	if movement_enabled:
		super._physics_process(_delta)

	var distance_to_start_position = start_position.distance_to(position)
	if throw_distance <= distance_to_start_position:
		MaxDistanceReached.emit()

#! setup signals here
#! move the projectile scenes and stuff to scenes/Projectiles/...
