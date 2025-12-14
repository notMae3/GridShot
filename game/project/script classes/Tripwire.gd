extends Throwable
class_name Tripwire

const firing_speed = Config.throwables.firing_speed
const preview_type = "tripwire"
const projectile_type = ""
const name = "Tripwire"

func fire(player_name : String, _current_ads_factor : float, _rotation : float, _position : Vector2):
	if self.throwable_preview.tripwire_valid and ammo != 0:
		Globals.spawn_tripwire.rpc_id(
			1,
			player_name,
			self.throwable_preview.tripwire_connector_1.global_position,
			self.throwable_preview.tripwire_connector_1.global_rotation,
			self.throwable_preview.tripwire_connector_2.global_position,
			self.throwable_preview.tripwire_connector_2.global_rotation
		)
		
		ammo -= 1
