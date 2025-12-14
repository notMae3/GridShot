extends Node

var multiplayer_node

func init_host_node(lobby_name : String, player_name : String):
	multiplayer_node = WebRTCLobbyHost.new(
		Config.network.signaling_server_url,
		Config.network.lobby_size,
		true,  # accepting new players
		lobby_name,
		false, # password enabled
		"",    # password
		player_name,
		Config.debug.network_logs_verbose
	)
	
	multiplayer_node.FatalError.connect(func(_error_reason): Globals.to_main_menu())
	
	return multiplayer_node

func init_player_node():
	multiplayer_node = WebRTCPlayerClient.new(
		Config.network.signaling_server_url,
		Config.debug.network_logs_verbose
	)
	
	multiplayer_node.FatalError.connect(func(_error_reason): Globals.to_main_menu())
	
	return multiplayer_node

# only called on peer 1, aka the lobby host
func _on_start_game():
	if multiplayer_node is WebRTCLobbyHost:
		multiplayer_node.accepting_new_players = false

# only called on peer 1, aka the lobby host
func _on_game_back_to_lobby():
	if multiplayer_node is WebRTCLobbyHost:
		multiplayer_node.accepting_new_players = true

## Wrapper function for WebRTCLobbyHost's 'get_player_name_by_peer_id' func
## Can only be called on the lobby host
func get_player_name_by_peer_id(peer_id):
	if multiplayer_node is WebRTCLobbyHost:
		multiplayer_node.get_player_name_by_peer_id(peer_id)

## Returns the this peer's player_name
## Can be called on both player client and lobby host
func get_current_peer_player_name():
	return multiplayer_node.player_name

## Can only be called on the lobby host
## Returns a dictionary structured like {peer_id: player_name}
func get_connected_player_names() -> Dictionary[int, String]:
	var player_name_dict : Dictionary[int, String] = {1: multiplayer_node.player_name}
	
	if multiplayer_node is WebRTCLobbyHost:
		# NOTE: self is excluded in peer_object_list
		var peer_object_list = multiplayer_node.get_curr_connected_peer_objects()
		for peer in peer_object_list:
			player_name_dict[peer.peer_id] = peer.player_name
	
	return player_name_dict

## Can be called on both lobby host and player client
func get_connected_lobby_info() -> Dictionary[String, String]:
	var lobby_info : Dictionary[String, String] = {}
	
	if multiplayer_node is WebRTCLobbyHost:
		lobby_info["lobby_id"] = multiplayer_node.player_id
		lobby_info["lobby_name"] = multiplayer_node.lobby_name
	
	else:
		lobby_info["lobby_id"] = multiplayer_node.lobby_to_conn_to
		lobby_info["lobby_name"] = multiplayer_node.lobby_list[lobby_info.lobby_id].lobby_name
	
	return lobby_info

## Called by either player client or lobby host
func am_disconnected_peer():
	if multiplayer_node is WebRTCLobbyHost:
		return false
	else:
		return multiplayer_node.multip_peer.get_connection_status() != MultiplayerPeer.ConnectionStatus.CONNECTION_CONNECTED

## Can only be called on the lobby host
## Does nothing if the peer_id doesnt exist
func kick_player(peer_id : int):
	if multiplayer_node is WebRTCLobbyHost:
		multiplayer_node.kick_player(peer_id)

func shutdown():
	multiplayer_node.queue_free()
