extends ProjectileBase
class_name ConstantProjectile

var dmg : int

func setup(source_ : Player, rotation_ : float, start_position_ : Vector2, dmg_ : int):
	self.source = source_

	self.rotation = rotation_
	self.direction = Vector2.from_angle(self.rotation)

	self.start_position = start_position_
	self.position = self.start_position + self.direction * 64 # offset spawn position from player center
	
	self.dmg = dmg_
