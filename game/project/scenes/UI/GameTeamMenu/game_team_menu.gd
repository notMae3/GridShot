extends PlayerCameraEffect

@onready var unsorted_player_container = $Players/HBoxContainer/Unsorted/HFlowContainer
@onready var team0_player_container = $Players/HBoxContainer/Teams/Team0/VBoxContainer
@onready var team1_player_container = $Players/HBoxContainer/Teams/Team1/VBoxContainer

var team_names = ["unsorted", "team0", "team1"]

func get_team_members(team : String) -> Array:
	#team is either "team0", "team1" or "unsorted"
	
	var relevant_container : Control = {
		"unsorted": unsorted_player_container,
		"team0": team0_player_container,
		"team1": team1_player_container
	}[team]
	
	# the player member containers also contain labels and stuff, therefore filter to only include TeamMenuPlayerBars
	var team_members = relevant_container.get_children().filter(func(node): return node is TeamMenuPlayerBar)
	
	return team_members

func setup():
	var player_camera = Globals.game_node.player_camera
	player_camera.show_screen(player_camera.game_team_menu)
	
	# choose which prompt and buttons to show the player depending on wether they're the lobby host
	var is_server = multiplayer.is_server()
	$LobbyHostControls.visible = is_server
	$WaitingForLobbyHost.visible = not is_server
	
	var lobby_info = Network.get_connected_lobby_info()
	$LobbyHeader/LobbyNameLabel.text = lobby_info.lobby_name
	$LobbyHeader/LobbyIDLabel.text = lobby_info.lobby_id

# this is only ever called on peer 1, aka the lobby host
func get_player_status() -> Dictionary:
	# formatted_players example:
	# {
	# 	 "unsorted": {1: {"name": player host's player name", "color": "#ffffff"}},
	# 	 "team0": {16: {"name": "player's name", "color": "#ffffff"}},
	# 	 "team1": {}
	# }
	
	var formatted_players : Dictionary = {
		"unsorted": {},
		"team0": {},
		"team1": {}
	}
	
	# connected player names is a dict strucutred like {peer_id: player_name}
	var connected_player_names : Dictionary[int, String] = Network.get_connected_player_names()
	var connected_peer_ids = connected_player_names.keys()
	
	for team in team_names:
		var relevant_player_bars = get_team_members(team)
		
		# the player color is based on their idx in the team
		# the player color of all players is sent by rpc for team menu but synched using multiplayer
		#   symchronizers for the in game player nodes
		var player_bar_idx = 0
		for player_bar : TeamMenuPlayerBar in relevant_player_bars:
			var peer_id = player_bar.peer_id
			var player_name = connected_player_names.get(peer_id)
			var player_color = Color.TRANSPARENT if team == "unsorted" else Globals.team_member_colors[team][player_bar_idx]
			
			if peer_id in connected_peer_ids:
				formatted_players[team][peer_id] = {"name": player_name, "color": player_color}
			
			player_bar_idx += 1
	
	return formatted_players

func update_player_status(formatted_players : Dictionary):
	# formatted_players example:
	# {
	# 	 "unsorted": {1: {"name": player host's player name", "color": "#ffffff"}},
	# 	 "team0": {16: {"name": "player's name", "color": "#ffffff"}},
	# 	 "team1": {}
	# }
	
	var team_containers = {
		"unsorted": unsorted_player_container,
		"team0": team0_player_container,
		"team1": team1_player_container
	}
	
	# go through all player_bars and ensure theyre up to date
	# go through each team
	for team_name in team_containers.keys():
		var connected_peer_ids = formatted_players[team_name].keys()
		
		var current_container = team_containers[team_name]
		var current_container_team_members = get_team_members(team_name)
		var peer_ids_in_current_container = current_container_team_members.map(func(player_bar): return player_bar.peer_id)
		
		# for each team go through all the peer_ids that are supposed to have a player_bar representative
		for peer_id in connected_peer_ids:
			var player_name = formatted_players[team_name][peer_id].name
			var player_color = formatted_players[team_name][peer_id].color
			
			# if the peer_id already has a player_bar representative: ensure its text and color is correct
			if peer_id in peer_ids_in_current_container:
				var player_bar = current_container.get_node(str(peer_id))
				if player_bar.text != player_name:   player_bar.text = player_name
				if player_bar.color != player_color: player_bar.color = player_color
			
			# if the peer_id doesnt have a player_bar representative: add one and set its text and color
			else:
				_add_player_bar(
					current_container,
					peer_id,
					player_name,
					player_color
				)
		
			# if this peer owns the in-game player_node corresponding to peer_id: change its color
			if multiplayer.get_unique_id() == peer_id:
				var player_node : Player = Globals.game_node.get_player(peer_id)
				player_node.color = player_color
		
		# remove player_bars that arent in formatted_players
		# these exist because a player switched to another team or left the lobby
		var player_bars_to_delete = current_container_team_members.filter(
			func(player_bar : TeamMenuPlayerBar): return player_bar.peer_id not in connected_peer_ids)
		player_bars_to_delete.map(
			func(player_bar : TeamMenuPlayerBar): player_bar.queue_free())
	
	# if each team doesnt have at least 1 player disable the lobby host start button and show a warning label
	var team_player_count_invalid = formatted_players["team0"].size() == 0 or formatted_players["team1"].size() == 0
	$LobbyHostControls/VBoxContainer/StartButton.disabled = team_player_count_invalid
	$LobbyHostControls/VBoxContainer/StartButton/TeamPlayerLabel.visible = team_player_count_invalid

# only ever called from peer 1, aka the lobby host
func init_player_status_synch():
	Globals.update_team_menu_players.rpc(get_player_status())

func add_unsorted_player(peer_id : int):
	# name is set to "-" since only the lobby host knows all the player names
	# the player name is later set once update_player_status is called, which happens on all peers
	_add_player_bar(unsorted_player_container, peer_id, "-", Color.TRANSPARENT)

func _add_player_bar(parent_node, peer_id : int, player_name : String, player_color : Color):
	var new_player_bar : TeamMenuPlayerBar = Globals.scenes.team_menu_player_bar.instantiate()
	new_player_bar.peer_id = peer_id
	new_player_bar.text = player_name
	new_player_bar.color = player_color
	
	parent_node.add_child(new_player_bar)


# can be called on any peer
func _on_team_join_button_pressed(team : int):
	# gets the player_bar_node corresponding to this peer's peer_id
	# from the player_bar_node it's absolute node path is fetched
	# then the to-be node path of the player_bar_node is fetched
	# the to-be path is the path post moving the player_bar_node
	
	var peer_id : int = multiplayer.get_unique_id()
	
	# the player_bar representing peer_id, aka this peer
	var this_peer_player_bar : TeamMenuPlayerBar
	
	# go through each team until the player_bar representing this peer is found
	for team_name in team_names:
		var team_members = get_team_members(team_name)
		for player_bar : TeamMenuPlayerBar in team_members:
			if player_bar.peer_id == peer_id:
				this_peer_player_bar = player_bar
				break
		
		if this_peer_player_bar: break
	
	var player_bar_path = str(this_peer_player_bar.get_path())
	var player_bar_new_container = team0_player_container if team == 0 else team1_player_container
	var player_bar_new_container_path = str(player_bar_new_container.get_path())
	
	Globals.game_node.get_player(peer_id).team = team
	Globals.move_team_menu_player.rpc_id(1, player_bar_path, player_bar_new_container_path)

# can only be called on peer 1, aka the lobby host
func _on_start_button_pressed():
	var player_status = get_player_status()
	Globals.start_game.rpc(player_status)

# can be called on any peer
func _on_exit_lobby_button_pressed():
	Globals.to_main_menu()
