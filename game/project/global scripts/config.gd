extends Node

const credit_name = "Theodor Wallinder" # easily changable for wether i wanna doxx myself depending on the publication platform

class debug:
	const multiplayer_enabled = true
	const network_logs_verbose = false # live webrtc status logs
	const print_network_logs = false

class network:
	const signaling_server_url = "wss://theodor-test-ced3867bc168.herokuapp.com/"
	const lobby_size = 6

class game_bomb:
	const plant_duration = 2
	const windup_duration = 50
	const diffuse_duration = 2
	const dmg = 999

class player:
	const movement_speed = 250         # constant velocity
	const movement_ads_speed = 125     # constant velocity
	const movement_halt_speed = 2000   # -velocity/second
	const rotation_speed = 4
	const rotation_ads_speed = 1.5
	const rotation_halt_speed = 35
	const stun_mobility_factor = 0.5
	const max_hp = 100

class weapons:
	const bullet_movement_speed = 1000        # constant velocity
	const bullet_life_time = 4                # seconds
	const bullet_dmg = 8
	
	const assault_rifle_base_spread = PI/4    # radians bullet spread
	const assault_rifle_ads_spread = PI/32    # radians bullet spread
	const assault_rifle_firing_speed = 6      # shots per second
	const assault_rifle_dmg_factor = 1
	const assault_rifle_mag_size = 24
	const assault_rifle_extra_bullets = 48
	
	const sub_machine_gun_base_spread = PI/3  # radians bullet spread
	const sub_machine_gun_ads_spread = PI/6   # radians bullet spread
	const sub_machine_gun_firing_speed = 18   # shots per second
	const sub_machine_gun_dmg_factor = 0.5
	const sub_machine_gun_mag_size = 24
	const sub_machine_gun_extra_bullets = 48
	
	const shotgun_base_spread = PI/2          # radians bullet spread
	const shotgun_ads_spread = PI/5           # radians bullet spread
	const shotgun_firing_speed = 1.25         # shots per second
	const shotgun_fragment_count = 10
	const shotgun_dmg_factor = 0.3
	const shotgun_mag_size = 50
	const shotgun_extra_bullets = 100

class throwables:
	const throw_distance = 250
	const ads_throw_distance = 400
	const movement_speed = 500
	const firing_speed = 1
	
	const molotov_explosion_radius = 100
	const molotov_dmg = 35
	const flash_grenade_windup_duration = 0.5
	const flash_grenade_max_flash_distance = 2500
	const tripwire_max_length = 650
	const tripwire_max_stun_factor = 0.8
	const tripwire_dmg = 5

class player_camera_effects:
	const flash_start_fade_delay = 0.75
	const flash_fade_duration = 1
	const stun_total_duration = 0.8
	const stun_windup_duration = 0.15
	const stun_winddown_duration = 0.15

class player_ui:
	const default_weapon_icon_color = "#424242"
	const highlighted_weapon_icon_color = "#0fb000"
