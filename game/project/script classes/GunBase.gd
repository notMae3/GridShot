extends RefCounted
class_name Gun

var current_mag_ammo

func _init():
	current_mag_ammo = self.mag_size

func get_current_accuracy(ads_factor) -> float:
	# the current accuracy is dependent on ads_factor, which is
	#   dependent on the to_ads animation progress
	
	var spread_delta = self.base_spread - self.ads_spread
	var current_spread = self.base_spread - spread_delta * ads_factor
	
	return current_spread

func can_fire():
	return current_mag_ammo != 0

func reload():
	if self.extra_bullets != 0:
		# decrease the extra_bullet count by how many bullets current_mag_ammo is off from self.mag_size
		# then set the current mag ammo to the extra_bullets delta, which might be less than self.mag_size
		var mag_ammo_deficit = self.mag_size - current_mag_ammo
		var extra_bullet_delta = self.extra_bullets - max(0, self.extra_bullets - mag_ammo_deficit)
		self.extra_bullets -= extra_bullet_delta
		current_mag_ammo += extra_bullet_delta

func fire(player_name : String, current_ads_factor : float, rotation : float, position : Vector2):
	if not can_fire():
		return
	
	# the bullet always travels in the direction it is facing
	# therefore bullet spread can be done by modifying the bullets rotation
	var current_accuracy = get_current_accuracy(current_ads_factor)
	var bullet_rotation = rotation + randf_range(-current_accuracy/2, current_accuracy/2)
	
	# the below line calls the function `spawn_projectile(...)` on
	#   the peer with peer id 1, aka the lobby host. this is needed since adding children
	#   from any peer which isnt the lobby host is wonky and likely to fail
	Globals.spawn_projectile.rpc_id(1, self.projectile_type, player_name, bullet_rotation, position, self.dmg)
	
	current_mag_ammo -= 1


func delete():
	pass
