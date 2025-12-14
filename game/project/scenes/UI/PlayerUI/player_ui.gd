extends PlayerCameraEffect


const default_weapon_icon_color = Config.player_ui.default_weapon_icon_color
const highlighted_weapon_icon_color = Config.player_ui.highlighted_weapon_icon_color

var previous_highlighted_weapon_texture : TextureRect

@onready var bomb_interaction_progress_bar_container = $GameBombInteractionBar/ProgressContainer
@onready var bomb_interaction_progress_bar = $GameBombInteractionBar/ProgressContainer/Progressbar
@onready var center_triangle = $LobbyBar/CenterTriangle
@onready var center_triangle_timer : Timer = $LobbyBar/CenterTriangle/Timer

const center_triangle_colors = {
	"unplanted": Color("#474747"),
	"planted": Color("#ff0000"),
	"planted_tick": Color("#7d0000")
}

# what interaction the source player could have with the game_bomb
# either "plant" or "diffuse"
var source_bomb_interaction_type : String

# overridden function from parent class
func _on_source_set(new_value : Player):
	source = new_value
	
	source_bomb_interaction_type = "plant" if source.team == 0 else "diffuse"
	$GameBombInteractionBar/Label.text = "Press and hold button E to %s the bomb" % source_bomb_interaction_type

func set_hp(percent : float):
	var m : ShaderMaterial = $Player/Red.material
	m.set_shader_parameter("DisplayPercent", percent)

func set_lobby_bar_portrait(team : int, _color : int):
	var current_player_team = Globals.game_node.get_player(multiplayer.get_unique_id()).team
	var _portrait_prefix = "L" if team == current_player_team else "R"
	
	# TODO, do once ive decided how to do team member id/join order

func set_current_gun(gun : Gun):
	var texture : AtlasTexture = $Weapons/Weapon/ImageContainer/WeaponTexture.texture
	texture.region.position.x = Globals.weapon_texture_regions.get(gun.name)

func set_current_ammo(count : int):
	$Weapons/Weapon/Ammo/CurrentAmmo.text = str(count)

func set_current_stored_ammo(count : int):
	$Weapons/Weapon/Ammo/StoredAmmo.text = str(count)

func set_current_util_count(utils : Array):
	var all_util_names = ["Molotov", "FlashGrenade", "SmokeGrenade", "Tripwire"]
	var current_util = {}
	utils.map(func(util : Throwable): current_util[util.name] = util)
	
	for util_name in all_util_names:
		var label = get_node("Weapons/Utils/%s/Label" % util_name)
		if util_name in current_util:
			label.text = str(current_util[util_name].ammo)
		else:
			label.text = "0"

func set_current_held_item(item):
	# item : Throwable | Gun | null
	
	if previous_highlighted_weapon_texture:
		previous_highlighted_weapon_texture.self_modulate = default_weapon_icon_color
	
	var current_texture : TextureRect
	
	# decide which texture to change
	if item is Gun:
		current_texture = $Weapons/Weapon/ImageContainer/WeaponTexture
	elif item is Throwable:
		current_texture = get_node("Weapons/Utils/%s/ImageContainer/TextureRect" % item.name)
	
	# update the current texture if item isnt null
	if current_texture:
		current_texture.self_modulate = highlighted_weapon_icon_color
		previous_highlighted_weapon_texture = current_texture

func _process(delta):
	super._process(delta)
	
	# NOTE: all of this can be greatly optimized using event signals, eg. on player hp changed: set_hp(...)
	# the thing is i dont have time to do that shit
	if source:
		# update the progress bar based on the progress of the current interaction
		# the current interaction being either planting of diffusing the bomb
		
		var interaction_progress : float
		
		if source_bomb_interaction_type == "plant":
			$GameBombInteractionBar.visible = source.can_plant and not Globals.game_node.game_bomb_planted
			interaction_progress = source.plant_progress if source.is_planting else 0.0
		
		else:
			$GameBombInteractionBar.visible = source.can_diffuse
			interaction_progress = source.diffuse_progress if source.is_diffusing else 0.0
		
		bomb_interaction_progress_bar.size.x = bomb_interaction_progress_bar_container.size.x * interaction_progress
		
		set_hp(float(source.hp)/float(source.max_hp))
		if source.gun:
			set_current_gun(source.gun)
			if source.gun.current_mag_ammo != null:
				set_current_ammo(source.gun.current_mag_ammo)
			set_current_stored_ammo(source.gun.extra_bullets)
		set_current_util_count(source.utils)
		set_current_held_item(source.in_hand)
	
	if Globals.game_node.game_bomb:
		# update the color if the center triangle if its still colored as unplanted
		var current_color = center_triangle.color
		if current_color == center_triangle_colors["unplanted"]:
			center_triangle.color = center_triangle_colors["planted"]
		
		# figure out how often the center triangle should tick
		var game_bomb_progress = Globals.game_node.game_bomb.progress
		var center_triangle_tick_time_delta
		
		# stage is a lower percentage limit for game_bomb_progress
		for stage in Globals.game_bomb_tick_stages.keys():
			if game_bomb_progress <= stage:
				center_triangle_tick_time_delta = Globals.game_bomb_tick_stages[stage]
				break
		
		# update the timer
		if center_triangle_tick_time_delta and center_triangle_timer.wait_time != center_triangle_tick_time_delta:
			center_triangle_timer.start(center_triangle_tick_time_delta)


func _on_center_triangle_tick_timer_timeout():
	var current_color = center_triangle.color
	
	if not Globals.game_node.game_bomb or Globals.game_node.game_bomb_diffused:
		center_triangle_timer.stop()
		center_triangle.color = center_triangle_colors["unplanted"]
		return
	
	# make a list of the pobbile colors and remove that current color
	var colors = [center_triangle_colors["planted"], center_triangle_colors["planted_tick"]]
	colors.erase(current_color)
	
	center_triangle.color = colors[0]
