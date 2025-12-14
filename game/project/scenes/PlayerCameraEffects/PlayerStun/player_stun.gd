extends PlayerCameraEffect

var peak_stun_factor : float
const total_duration = Config.player_camera_effects.stun_total_duration
const windup_duration = Config.player_camera_effects.stun_windup_duration
const winddown_duration = Config.player_camera_effects.stun_winddown_duration

@export_range(0, 1, 0.05) var stun_factor : float = 0:
	set = _on_stun_factor_set

func _on_stun_factor_set(new_value : float):
	stun_factor = new_value
	self.source.stun_factor = new_value

func _ready():
	self.remove_duplicate_effects("player stun")
	
	var anim_lib : AnimationLibrary = $AnimationPlayer.get_animation_library("")
	var anim : Animation = anim_lib.get_animation("effect")
	
	anim.length = total_duration
	anim.track_set_key_time(0, 0, total_duration)
	anim.track_set_key_time(1, 3, total_duration)
	anim.track_set_key_time(1, 2, total_duration-winddown_duration)
	anim.track_set_key_time(1, 1, windup_duration)
	
	anim.track_set_key_value(1, 1, peak_stun_factor)
	anim.track_set_key_value(1, 2, peak_stun_factor)
