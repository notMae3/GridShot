extends Node

var scenes = _scenes.new()
class _scenes extends RefCounted:
	const main_menu            : PackedScene = preload("res://scenes/UI/MainMenu/main_menu.tscn")
	const game                 : PackedScene = preload("res://scenes/Game/game.tscn")
	const game_bomb            : PackedScene = preload("res://scenes/GameBomb/game_bomb.tscn")
	
	const player               : PackedScene = preload("res://scenes/Player/player.tscn")
	const player_camera        : PackedScene = preload("res://scenes/PlayerCamera/player_camera.tscn")
	const player_ui            : PackedScene = preload("res://scenes/UI/PlayerUI/player_ui.tscn")
	const team_menu_player_bar : PackedScene = preload("res://scenes/UI/GameTeamMenu/player_bar_template.tscn")
	
	const throwable_preview    : PackedScene = preload("res://scenes/ThrowablePreview/throwable_preview.tscn")
	const tripwire_preview     : PackedScene = preload("res://scenes/TripwirePreview/tripwire_preview.tscn")
	
	const screen_flash         : PackedScene = preload("res://scenes/PlayerCameraEffects/ScreenFlash/screen_flash.tscn")
	const player_stun          : PackedScene = preload("res://scenes/PlayerCameraEffects/PlayerStun/player_stun.tscn")
	const smoke_cloud          : PackedScene = preload("res://scenes/SmokeCloud/smoke_cloud.tscn")
	const tripwire             : PackedScene = preload("res://scenes/Tripwire/tripwire.tscn")
	
	const bullet               : PackedScene = preload("res://scenes/Projectiles/Bullet/bullet.tscn")
	const molotov              : PackedScene = preload("res://scenes/Projectiles/Molotov/molotov.tscn")
	const flash_grenade        : PackedScene = preload("res://scenes/Projectiles/FlashGrenade/flash_grenade.tscn")
	const smoke_grenade        : PackedScene = preload("res://scenes/Projectiles/SmokeGrenade/smoke_grenade.tscn")

# these x values are used in the player_ui's weapon-texture texture-atlas
const weapon_texture_regions = {
	"AssaultRifle": 0,
	"SubMachineGun": 128,
	"Shotgun": 256
}

const team_member_colors = {
	"team0": [
		Color("#258069"),
		Color("#2ea680"),
		Color("#5fcf9a")
	],
	"team1": [
		Color("#b37c36"),
		Color("#d4aa48"),
		Color("#ffffa8")
	]
}

# the time in seconds between the player ui center triangle ticks
#   based on the bomb progress
# the ticks show how close the game_bomb is to exploding
const game_bomb_tick_stages = {
	0.25: 1.0/2.0,
	0.6: 1.0/4.0,
	0.85: 1.0/8.0,
	1: 1.0/16.0
}


@onready var main_node = $/root/main
var game_node : Game

#func _input(event):
	#if event.is_action_pressed("Ctrl + W"):
		#quit_program()

func start_as_lobby_host(lobby_name : String, player_name : String):
	if not Config.debug.multiplayer_enabled:
		main_node.get_node("MainMenu").queue_free()
		load_game_scene()
		game_node._on_multiplayer_ready.call_deferred()
		return
	
	# init the multiplayer node
	var multiplayer_node : WebRTCLobbyHost = Network.init_host_node(lobby_name, player_name)
	main_node.add_child(multiplayer_node)
	
	# connect log signal to print
	if Config.debug.print_network_logs:
		multiplayer_node.Log.connect(print)
	
	main_node.get_node("MainMenu").queue_free()
	load_game_scene()
	
	multiplayer_node.LobbyReady.connect(game_node._on_multiplayer_ready)

func start_as_player_client():
	# init the multiplayer node
	var multiplayer_node : WebRTCPlayerClient = Network.init_player_node()
	main_node.add_child(multiplayer_node)
	
	multiplayer_node.ConnectedToSignalingServer.connect(
		func(): (main_node.get_node("MainMenu")._on_connected_to_signaling_server.call_deferred()),
		CONNECT_ONE_SHOT
	)
	
	multiplayer_node.ReceivedLobbyDict.connect(print)
	
	# connect log signal to print
	if Config.debug.print_network_logs:
		multiplayer_node.Log.connect(print)

func player_client_join_lobby(lobby_id : String, player_name : String):
	print("lobby id ", lobby_id)
	print("name ", player_name)
	var multiplayer_node : WebRTCPlayerClient = main_node.get_node("WebRTCPlayerClient")
	multiplayer_node.join_lobby(lobby_id, "", player_name)
	
	main_node.get_node("MainMenu").queue_free()
	load_game_scene()
	
	multiplayer_node.ConnectedToServer.connect(game_node._on_multiplayer_ready)

func load_game_scene():
	game_node = scenes.game.instantiate()
	main_node.add_child(game_node)

func to_main_menu():
	game_node.queue_free()
	Network.shutdown()
	main_node.add_child(scenes.main_menu.instantiate())

func quit_program():
	get_tree().quit()



# called only on peer 1, aka the lobby host
@rpc("any_peer", "call_local")
func spawn_projectile(
			projectile_scene_name : String,
			owner_node_name : String,
			rotation : float,
			position : Vector2,
			dmg = null, # int | null,
			throw_distance = null # float | null
		):
	
	var player_node = game_node.get_player(owner_node_name)
	var new_projectile = scenes.get(projectile_scene_name).instantiate()
	
	if new_projectile is ThrowableProjectile: new_projectile.setup(player_node, rotation, position, throw_distance)
	else: new_projectile.setup(player_node, rotation, position, dmg)
	
	game_node.add_child(new_projectile, true)

# called only on the peer that should be flashed
@rpc("any_peer", "call_local")
func flash_peer():
	var flash = scenes.screen_flash.instantiate()
	
	flash.source = game_node.get_player(multiplayer.get_unique_id())
	
	game_node.player_camera.add_child(flash, true)

# called only on the peer that should be stunned
@rpc("any_peer", "call_local")
func stun_peer(peak_stun_factor : float):
	var stun = scenes.player_stun.instantiate()
	
	stun.source = game_node.get_player(multiplayer.get_unique_id())
	stun.peak_stun_factor = peak_stun_factor
	
	game_node.player_camera.add_child(stun, true)

# called only on peer 1, aka the lobby host
@rpc("any_peer", "call_local")
func spawn_smoke_cloud(position):
	var smoke_cloud = scenes.smoke_cloud.instantiate()
	smoke_cloud.position = position
	smoke_cloud.seed = randi()
	smoke_cloud.emitting = true
	
	game_node.add_child(smoke_cloud, true)

# called only on peer 1, aka the lobby host
@rpc("any_peer", "call_local")
func spawn_tripwire(
			owner_node_name : String,
			position_1 : Vector2,
			rotation_1 : float,
			position_2 : Vector2,
			rotation_2 : float
		):
	
	
	print("spawn tripwire %s %s" % [game_node.get_player(owner_node_name), owner_node_name])
	
	var tripwire = scenes.tripwire.instantiate()
	tripwire.owner_team = game_node.get_player(owner_node_name).team
	tripwire.position_1 = position_1
	tripwire.rotation_1 = rotation_1
	tripwire.position_2 = position_2
	tripwire.rotation_2 = rotation_2
	
	game_node.add_child(tripwire, true)

# called on all peers
@rpc("any_peer", "call_local")
func update_team_menu_players(team_menu_players : Dictionary):
	var team_menu = game_node.player_camera.game_team_menu
	team_menu.update_player_status(team_menu_players)

# called only on peer 1, aka the lobby host
@rpc("any_peer", "call_local")
func move_team_menu_player(node_path : String, new_parent_path : String):
	# get the nodes at the given paths
	var node_to_move = get_node(node_path)
	var new_parent = get_node(new_parent_path)
	
	# move the node and call the team nenu update on all peers only if
	#   the node's new parent is different from the current parent
	if node_to_move.get_parent() != new_parent:
		node_to_move.reparent(new_parent, false)
	
		# call the team menu update on all peers
		game_node.player_camera.game_team_menu.init_player_status_synch()

# called on all peers
@rpc("any_peer", "call_local")
func start_game(teams : Dictionary):
	game_node.start_game(teams)

# called on all peers
@rpc("any_peer", "call_local")
func game_bomb_planted(position : Vector2):
	if multiplayer.is_server():
		var game_bomb = scenes.game_bomb.instantiate()
		game_bomb.position = position
		game_node.add_child(game_bomb, true)
	
	game_node.game_bomb_planted = true

# called on all peers
@rpc("any_peer", "call_local")
func game_bomb_diffused():
	if multiplayer.is_server():
		var game_bomb = game_node.get_node("GameBomb")
		if game_bomb: game_bomb.queue_free()
	
	print("game bomb diffused, winning team 1")
	game_node.game_bomb_diffused = true
	game_node.game_winning_team = 1

# called on all peers
@rpc("any_peer", "call_local")
func return_to_lobby():
	# show the team menu screen
	var player_camera = game_node.player_camera
	player_camera.show_screen(player_camera.game_team_menu)
	
	# ensure player inputs are disabled
	var peer_id = multiplayer.get_unique_id()
	var player : Player = game_node.get_player(peer_id)
	player.inputs_enabled = false
	
	game_node.reset()

# called on one peer
@rpc("any_peer", "call_local")
func player_take_dmg(dmg : int):
	var player = game_node.get_player(multiplayer.get_unique_id())
	player.take_dmg(dmg)

# called on all peers
@rpc("any_peer", "call_local")
func check_win():
	game_node.check_win()
