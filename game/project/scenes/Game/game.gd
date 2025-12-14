extends Node2D
class_name Game

@onready var multiplayer_spawner : MultiplayerSpawner = $MultiplayerSpawner
@onready var player_camera : PlayerCamera = $PlayerCamera
@onready var map : Node2D = $Map

# nodes the shouldnt be deleted on game reset
@onready var persistent_nodes = [multiplayer_spawner, player_camera, map]

var player_spawn_positions : Dictionary[String, Array] = {}

var game_winning_team : # int | null
	set = _on_game_winning_team_set

var game_bomb_planted = false
var game_bomb_diffused = false
var game_bomb # Node2D | null, this is defined when the game bomb is planted

var game_started = false

func _ready():
	# read the player spawn positions from the map marker2D nodes
	player_spawn_positions["team0"] = map.get_node("SpawnPositions/Team0").get_children().map(func(node : Marker2D): return node.position)
	player_spawn_positions["team1"] = map.get_node("SpawnPositions/Team1").get_children().map(func(node : Marker2D): return node.position)

func get_player(peer_id): # -> Player | null
	return get_node(str(peer_id))

func _on_multiplayer_ready():
	player_camera.game_team_menu.setup()
	
	if not Config.debug.multiplayer_enabled:
		add_player()
	
	elif multiplayer.is_server():
		add_player()
		
		var multiplayer_node : WebRTCLobbyHost = Network.multiplayer_node
		multiplayer_node.PeerConnected.connect(add_player)
		multiplayer_node.PeerDisconnected.connect(remove_player)
	
	else:
		var multiplayer_node : WebRTCPlayerClient = Network.multiplayer_node
		multiplayer_node.LobbyServerDisconnected.connect(server_disconnected)

# this is only called on the lobby host
func add_player(peer_id : int = 1):
	# game player object
	var new_player = Globals.scenes.player.instantiate()
	new_player.name = str(peer_id)
	add_child(new_player)
	
	# game_team_menu player object
	player_camera.game_team_menu.add_unsorted_player(peer_id)
	player_camera.game_team_menu.init_player_status_synch()

# this is only called on the lobby host
func remove_player(peer_id : int):
	get_node(str(peer_id)).queue_free()
	player_camera.game_team_menu.init_player_status_synch()
	
	# if theres no players on one team the other team wins, check for this
	if not player_camera.game_over_screen.visible:
		Globals.check_win.rpc()

# this called on all peers
func start_game(teams : Dictionary):
	# teams = {
	# 	 "unsorted": {1: "player host's player name"},
	# 	 "team0": {16: "player's name"},
	# 	 "team1": {}
	# }
	
	if multiplayer.is_server():
		Network._on_start_game()
		
		# kick all players that havent chosen a team
		for peer_id in teams["unsorted"].keys():
			Network.kick_player(peer_id)
	
	var current_peer_id = multiplayer.get_unique_id()
	var current_player = get_player(current_peer_id)
	var current_team = "team%s" % current_player.team
	
	# give each player a start position depending on their team and team member idx (the order they joined)
	var peer_ids : Array = teams[current_team].keys()
	var team_player_idx = peer_ids.find(current_peer_id)
	var spawn_position = player_spawn_positions[current_team][team_player_idx]
	current_player.position = spawn_position
	
	# update camera stuff
	player_camera.show_screen(player_camera.shop_menu)
	player_camera.target = current_player
	player_camera.shop_menu.start_timer()

# this is called on all peers locally
func shopping_phase_completed(loadout):
	var current_peer_id = multiplayer.get_unique_id()
	var current_player : Player = get_player(current_peer_id)
	
	current_player.gun = loadout.gun
	
	# loadout.util is a array with each item being the amount of a certain util the player chose to have
	# the idx corresponds to which type of util
	for idx in range(len(loadout.util)):
		var curr_util_count = loadout.util[idx]
		current_player.utils[idx].ammo = curr_util_count
	
	player_camera.show_screen(player_camera.player_ui)
	current_player.inputs_enabled = true
	
	game_started = true

func _process(_delta):
	if game_started:
		check_win()

## Used to check if either team has won by elimination or having the opponents leave the lobby
# called on all peers
func check_win():
	if game_winning_team != null or Network.am_disconnected_peer() or not game_started:
		return
	
	# if theres no players on either team: set the winner as the opposite team
	var alive_players = {0: 0, 1: 0}
	
	var connected_peers = Array(multiplayer.get_peers()) + [multiplayer.get_unique_id()]
	for peer_id in connected_peers:
		var player = get_player(peer_id)
		#print("%s player %s, %s, hp %s" % [multiplayer.get_unique_id(), player.id, player.team, player.hp])
		if player != null and player.hp != 0:
			alive_players[player.team] += 1
	
	#print("checkwin ", alive_players)
	
	if alive_players[0] == 0: game_winning_team = 1
	elif alive_players[1] == 0: game_winning_team = 0

# called on all peers
func _on_game_winning_team_set(new_value):
	game_winning_team = new_value
	
	if new_value == null:
		return
	
	# prevents fatalerrors and ensures correct behavior for wins when either team completely disconnects
	# ensures both lobby host and player clients get the won screen when the other disconnects
	if not Network.am_disconnected_peer():
		var current_peer_id = multiplayer.get_unique_id()
		var current_player : Player = get_player(current_peer_id)
		if current_player: current_player.inputs_enabled = false
		
		player_camera.show_screen(player_camera.game_over_screen)
		player_camera.game_over_screen.game_over(game_winning_team)

# called on all peers
func reset():
	if multiplayer.is_server():
		Network._on_game_back_to_lobby()
		
		# go through all children of the game node and remove the non-persistent ones
		var nodes_to_delete = get_children().filter(func(child): return child not in persistent_nodes and child is not Player)
		nodes_to_delete.map(func(child): child.queue_free())
		
		# reset the variables only after the nodes to delete have been deleted, aka next frame
		_reset_variables.call_deferred()
	
	player_camera.reset()
	var peer_id = multiplayer.get_unique_id()
	var player = get_player(peer_id)
	player.hp = player.max_hp
	if player.get_node("DirectionMarker"): player.get_node("DirectionMarker").visible = true
	player.modulate = Color("#ffffff")
	if player.get_node("PlayerRepulsionArea2D/CollisionShape2D"): player.get_node("PlayerRepulsionArea2D/CollisionShape2D").set_deferred("disabled", false)

func _reset_variables():
	# game related
	game_winning_team = null
	game_bomb_planted = false
	game_bomb_diffused = false
	game_bomb = null
	
	game_started = false

# this is only called on the player client
func server_disconnected():
	Globals.to_main_menu()
