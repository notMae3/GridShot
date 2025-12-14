extends PlayerCameraEffect

const start_fade_delay = Config.player_camera_effects.flash_start_fade_delay
const fade_duration = Config.player_camera_effects.flash_fade_duration

func _ready():
	self.remove_duplicate_effects("screen flash")
	
	#size = get_viewport_rect().size
	#position = player.position - size/2.0
	
	await RenderingServer.frame_post_draw
	
	# turn the ViewportTexture into an Image then into an ImageTexture
	var img = get_viewport().get_texture().get_image()
	$ScreenTexture.texture = ImageTexture.create_from_image(img)
	
	$EdgeColorEffect.visible = true
	
	var anim_lib : AnimationLibrary = $AnimationPlayer.get_animation_library("")
	var anim : Animation = anim_lib.get_animation("fade")
	
	anim.length = start_fade_delay + fade_duration
	anim.track_set_key_time(0, 2, start_fade_delay + fade_duration)
	anim.track_set_key_time(0, 1, start_fade_delay)
	anim.track_set_key_time(1, 1, start_fade_delay)
	anim.track_set_key_time(2, 0, start_fade_delay)
	anim.track_set_key_time(3, 0, start_fade_delay + fade_duration)
