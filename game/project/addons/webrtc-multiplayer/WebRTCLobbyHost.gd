## Lobby host side of my WebRTC multiplayer setup. This client also acts as a player. 
## Signal Log is emitted for every log message. 
## Signal FatalError is emitted after a fatal error and right before this Node is freed.
## This must be used with the provided signaling server. 

@icon("MultiplayerSynchronizer.svg")

extends WebRTC
class_name WebRTCLobbyHost

# peer_id will always be 1 for the lobby host (godot enforced)
# player_id 
var player_id # : String | int, used as lobby_id
var player_name : String


var lobby_size : int:
	set(new_value):
		if lobby_size != new_value: _on_lobby_settings_changed("lobby_size", new_value)
		lobby_size = new_value
var accepting_new_players : bool:
	set(new_value):
		if accepting_new_players != new_value: _on_lobby_settings_changed("accepting_new_players", new_value)
		accepting_new_players = new_value
var lobby_name : String:
	set(new_value):
		if lobby_name != new_value: _on_lobby_settings_changed("lobby_name", new_value)
		lobby_name = new_value
var password_enabled : bool:
	set(new_value):
		if password_enabled != new_value: _on_lobby_settings_changed("password_enabled", new_value)
		password_enabled = new_value
var password : String

var json : JSON

var multip_peer : WebRTCMultiplayerPeer
var signaling_server: WebSocketPeer
var signaling_server_old_state : WebSocketPeer.State

var peers : Dictionary[int, Peer] = {}

# signaling server related signals
signal ReceivedPlayerID(new_id) # new_id : String | int
signal JoinRequestReceived(src : int, password_attempt : String, player_name : String)
signal LobbyReady

signal SignalingServerStateChanged(state : WebSocketPeer.State)
signal ConnectedToSignalingServer
signal DisconnectedFromSignalingServer

# multiplayer signals
signal PeerConnected(remote_peer_id : int)
signal PeerDisconnected(remote_peer_id : int)

# signal which emits WebRTCLobbyHost log messages
signal Log(text : String)
signal FatalError(error_type : WebRTC.ErrorTypes)


## A Peer object is simply put a container for the WebRTCPeerConnection between the lobby host and a player client
class Peer:
	var player_id : int
	var peer_id : int
	var player_name : String
	
	# parent inherited stuff
	var parent_player_id : String
	var parent_multip_peer : WebRTCMultiplayerPeer
	var signaling_server : WebSocketPeer
	var WebRTC_url_config : Dictionary
	
	# local WebRTC related objects
	var peer_connection : WebRTCPeerConnection
	var data_channel : WebRTCDataChannel
	
	# timer used to close this Peer instance if the connection attempt takes too long
	var peer_connection_timer : Timer
	# the WebRTCLobbyHost parents _on_peer_connection_closed
	var _on_peer_connection_closed : Callable
	# log is a signal that's emitted for every log message
	var log : Signal
	
	signal RTCOfferReceived(sdp : String)
	signal RTCIceReceived(media: String, index: int, candidate_name: String)
	
	func _init(
			player_id : int,
			peer_id : int,
			parent_player_id : String,
			player_name : String,
			WebRTC_url_config : Dictionary,
			parent_multip_peer : WebRTCMultiplayerPeer,
			signaling_server : WebSocketPeer,
			_on_peer_connection_closed : Callable,
			peer_connection_timer : Timer,
			log : Signal):
		self.player_id = player_id
		self.peer_id = peer_id
		self.player_name = player_name
		
		self.parent_player_id = parent_player_id
		self.WebRTC_url_config = WebRTC_url_config
		self.parent_multip_peer = parent_multip_peer
		self.signaling_server = signaling_server
		
		self._on_peer_connection_closed = _on_peer_connection_closed
		self.peer_connection_timer = peer_connection_timer
		self.log = log
		
		self.peer_connection_timer.timeout.connect(self._on_peer_connection_timer_timeout)
		
		self.RTCOfferReceived.connect(self._on_rtc_offer_received)
		self.RTCIceReceived.connect(self._on_rtc_ice_received)
		
		# setup the webrtc peer connection
		self.init_WebRTCConnection()
	
	func init_WebRTCConnection():
		self.peer_connection_timer.start()
		
		# setup the WebRTCPeerConnection to later use with WebRTCMultiplayerPeer
		self.peer_connection = WebRTCPeerConnection.new()
		self.peer_connection.initialize(self.WebRTC_url_config)
		self.peer_connection.ice_candidate_created.connect(self._on_ice_candidate_created)
		self.peer_connection.session_description_created.connect(self._on_session_description_created)
		
		# create a data channel to handle p2p communication named "c1"
		# passing a channel name is required although it doesnt have an effect, thereby
		#   the channel's name can be anything
		self.data_channel = self.peer_connection.create_data_channel("c1")
		
		self.log.emit("[lobby %s player %s %s] init webrtc conn" % [self.parent_player_id, self.player_id, self.peer_id])
	
	func _on_ice_candidate_created(media: String, index: int, candidate_name: String):
		self.log.emit("[lobby %s player %s %s] ice candidate created" % [self.parent_player_id, self.player_id, self.peer_id])
		
		# Send the ICE candidate to the other peer via the signaling server
		self.log.emit("[lobby %s player %s %s] sending ice candidate" % [self.parent_player_id, self.player_id, self.peer_id])
		self.send_packet(
			PacketTypes.RTCIce,
			{
				"media": media,
				"index": index,
				"candidate_name": candidate_name
			})
	
	func _on_session_description_created(type: String, sdp: String):
		self.log.emit("[lobby %s player %s %s] session created (%s)" % [self.parent_player_id, self.player_id, self.peer_id, type])
		
		var err = self.peer_connection.set_local_description(type, sdp)
		self.log.emit("[lobby %s player %s %s] set local desc (%s)" % [self.parent_player_id, self.player_id, self.peer_id, err])
		
		# Send the SDP to the other peer via the signaling server
		self.log.emit("[lobby %s player %s %s] sending desc" % [self.parent_player_id, self.player_id, self.peer_id])
		send_packet(PacketTypes.RTCOffer if type == "offer" else PacketTypes.RTCAnswer, {"sdp": sdp})
	
	func _on_rtc_offer_received(sdp : String):
		# add_peer must be called before set_remote_description because add_peer requires
		#   the WebRTCPeerConnection to be STATE_NEW. set_remote_description sets the state
		#   of the WebRTCPeerConnection to something other than STATE_NEW
		var add_peer_err = self.parent_multip_peer.add_peer(self.peer_connection, self.peer_id)
		var remote_desc_err = self.peer_connection.set_remote_description("offer", sdp)
		self.log.emit("[lobby %s player %s %s] received rtc offer (add peer: %s, set remote desc: %s)" % [self.parent_player_id, self.player_id, self.peer_id, add_peer_err, remote_desc_err])
		
		self.send_packet(PacketTypes.RemotePeerICEReady)
	
	func _on_rtc_ice_received(media: String, index: int, candidate_name: String):
		var err = self.peer_connection.add_ice_candidate(media, index, candidate_name)
		self.log.emit("[lobby %s player %s %s] ice candidate received (%s)" % [self.parent_player_id, self.player_id, self.peer_id, err])
	
	func _on_peer_connection_timer_timeout():
		var bad_connection_state = self.peer_connection.get_connection_state() in [
			WebRTCPeerConnection.ConnectionState.STATE_CONNECTING,
			WebRTCPeerConnection.ConnectionState.STATE_NEW]
		var bad_gathering_state = self.peer_connection.get_gathering_state() in [ # (gathering state refers to the gathering of ice candidates)
			WebRTCPeerConnection.GatheringState.GATHERING_STATE_GATHERING,
			WebRTCPeerConnection.GatheringState.GATHERING_STATE_NEW]
		
		# if the connection has failed, has a bad connection state or has a bad gathering state:
		#   close self because its taking too long
		if not self.is_peer_connected() or bad_connection_state or bad_gathering_state:
			self.log.emit("[lobby %s player %s %s] WebRTC connection timer timeout" % [self.parent_player_id, self.player_id, self.peer_id])
			self.close()
		
		self.peer_connection_timer.queue_free()
	
	func parse_packet(data : Dictionary):
		match data.type:
			PacketTypes.RTCOffer:
				self.RTCOfferReceived.emit(data.sdp)
			
			PacketTypes.RTCIce:
				self.RTCIceReceived.emit(data.media, data.index, data.candidate_name)
	
	## Send a packet to the signaling server through the websocket connection
	## This packet contains type, destination, source and optional data values
	func send_packet(type : int, data : Dictionary = {}):
		# create a dictionary object containing the necessary type, dst and src data
		# then merge it with the data argument without overriding keys in the type, dst src dict
		
		# JSON.stringify isnt used since it automatically converts all integers to type Number, which doesnt differentiate from int or float
		var packet : Dictionary = {
			"type": type,
			"dst": self.player_id,
			"src": self.parent_player_id
			}.merged(data)
		
		self.signaling_server.send(str(packet).to_ascii_buffer())
		self.log.emit("[lobby %s player %s %s] sending packet\n\t%s" % [self.parent_player_id, self.player_id, self.peer_id, packet])
	
	## Poll the WebRTC peer connection. If the connection is broken: close self
	func poll():
		self.peer_connection.poll()
		self.data_channel.poll()
		
		# if the WebRTC connection is broken: close/delete self
		if not self.is_peer_connected():
			self.close()
	
	## Check if the peer connection has successfully connected. Returns true if connected
	func is_peer_connected() -> bool:
		var good_signaling_state = self.peer_connection.get_signaling_state() != WebRTCPeerConnection.SignalingState.SIGNALING_STATE_CLOSED
		var good_connection_state = self.peer_connection.get_connection_state() not in [
			WebRTCPeerConnection.ConnectionState.STATE_CLOSED,
			WebRTCPeerConnection.ConnectionState.STATE_DISCONNECTED,
			WebRTCPeerConnection.ConnectionState.STATE_FAILED]
		
		return good_signaling_state and good_connection_state
	
	func close():
		self.log.emit("[lobby %s player %s %s] closing self\n\tsignaling state: %s\n\tgathering state: %s\n\tconnections state: %s" % [self.parent_player_id, self.player_id, self.peer_id, self.peer_connection.get_signaling_state(), self.peer_connection.get_gathering_state(), self.peer_connection.get_connection_state()])
		self.peer_connection.close() # also closes data_channel
		self._on_peer_connection_closed.call_deferred(player_id)

#region init
func _init(
		signaling_server_url : String,
		lobby_size : int,
		accepting_new_players : bool,
		lobby_name : String,
		password_enabled : bool,
		password : String = "",
		player_name : String = "-",
		log_debug : bool = false):
	
	assert(MinLobbySize <= lobby_size, "Lobby size %s is too small. Minimum size is %s" % [lobby_size, MinLobbySize])
	assert(lobby_size <= MaxLobbySize, "Lobby size %s is too large. Maximum size is %s" % [lobby_size, MaxLobbySize])
	assert(lobby_name != "", "Lobby name can't be an empty string")
	assert(not (password_enabled and password.is_empty()), "Password can't be an empty string when password_enabled is true")
	
	name = "WebRTCLobbyHost"
	self.signaling_server_url = signaling_server_url
	self.lobby_size = lobby_size
	self.accepting_new_players = accepting_new_players
	self.lobby_name = lobby_name
	self.password_enabled = password_enabled
	self.password = password
	self.player_name = player_name
	self.log_debug = log_debug

func _ready():
	json = JSON.new()
	init_signaling_server_conn()
	init_WebRTCMultiplayerPeer()
	FatalError.connect(_on_fatal_error)
	
	if log_debug:
		get_tree().create_timer(1).timeout.connect(log_debug_func)

func log_debug_func():
	Log.emit(
		"[lobby %s]: " % player_id + " - ".join(peers.values().map(func(p : Peer): return " ".join([p.data_channel.get_ready_state(), p.peer_connection.get_connection_state(), p.peer_connection.get_gathering_state(), p.peer_connection.get_signaling_state()]))
		) + " " + str(multiplayer.multiplayer_peer.get_peers().values().map(func(rtc_p): return " ".join([rtc_p, rtc_p.channels.map(func(i : WebRTCDataChannel): return i.get_ready_state())])) if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer else "")
	)
	
	get_tree().create_timer(1).timeout.connect(log_debug_func)

func init_signaling_server_conn():
	# start a connection attempt to the signaling server. built in timeout is ~90s
	signaling_server = WebSocketPeer.new()
	signaling_server.connect_to_url(signaling_server_url)
	
	# connect SignalingServer related signals
	ReceivedPlayerID.connect(_on_peer_assigned_id)
	JoinRequestReceived.connect(_on_join_request_received)
	SignalingServerStateChanged.connect(_on_signaling_server_state_changed)
	
	Log.emit("[lobby %s] init signaling server" % player_id)

func init_WebRTCMultiplayerPeer():
	# setup WebRTCMultiplayerPeer
	multip_peer = WebRTCMultiplayerPeer.new()
	multip_peer.create_server()
	multiplayer.multiplayer_peer = multip_peer
	
	# connect multiplayer signals
	multiplayer.peer_connected.connect(PeerConnected.emit)
	multiplayer.peer_disconnected.connect(_on_multip_peer_disconnected)
	
	PeerConnected.connect(_on_multip_peer_connected)
	
	Log.emit("[lobby %s] init multiplayer" % player_id)
#endregion

#region signal reactions
func _on_peer_assigned_id(new_id):
	player_id = new_id
	Log.emit("[lobby %s] new player id" % [player_id])
	
	# all peers are at first assigned a player id of type int
	# therefore, if the new_id is int, send a packet to the signaling server
	#   stating that this is a lobby host
	# the new peer id will be type string
	if typeof(new_id) == TYPE_INT:
		send_packet(
			PacketTypes.DeclareLobbyHost,
			SignalingServerAddress,
			{
				"accepting_new_players": accepting_new_players,
				"lobby_size": lobby_size,
				"curr_player_count": get_curr_player_count(),
				"lobby_name": lobby_name,
				"password_enabled": password_enabled
			})
	
	else:
		LobbyReady.emit()

func _on_join_request_received(src : int, password_attempt : String, player_name : String):
	var curr_player_count = get_curr_player_count()
	Log.emit("[lobby %s] deciding join request answer:\n\taccepting_new_players: %s\n\tcurr_player_count: %s\n\tlobby_size: %s\n\tpass enabled: %s\n\tpassword: %s\n\tpass attempt: %s" % [player_id, accepting_new_players, curr_player_count, lobby_size, password_enabled, password, password_attempt])
	
	# ensure password_enabled isnt true while the password is empty/unset
	assert(not (password_enabled and password.is_empty()), "Password can't be an empty string when password_enabled is true")
	
	if accepting_new_players and curr_player_count < lobby_size and (password_enabled == false or password_attempt == password):
		accept_join_request(src, player_name)
	
	else:
		deny_join_request(src, password_attempt, curr_player_count)
	
func accept_join_request(src : int, player_name : String):
	# this is a timer which is used to ensure the WebRTC connection was established before
	#   WebRTCConnectionTimeout seconds has elapsed
	var peer_connection_timer = Timer.new()
	peer_connection_timer.wait_time = WebRTCConnectionTimeout
	peer_connection_timer.one_shot = true
	add_child(peer_connection_timer)
	
	var new_peer_id = gen_peer_id()
	
	peers[src] = Peer.new(
		src,
		new_peer_id,
		player_id,
		player_name,
		self.WebRTC_url_config,
		multip_peer,
		signaling_server,
		_on_peer_connection_closed,
		peer_connection_timer,
		Log)
	
	# the peer_id key tells the player its answer Yes
	send_packet(PacketTypes.JoinRequestAnswer, src, {"peer_id": new_peer_id})

func deny_join_request(src : int, password_attempt : String, curr_player_count : int):
	var deny_reasons = []
	if not accepting_new_players: deny_reasons.append(ErrorTypes.JoinRequestDenied_NotAcceptingNewPlayers)
	if not curr_player_count < lobby_size: deny_reasons.append(ErrorTypes.JoinRequestDenied_LobbyFull)
	if password_enabled and password_attempt != password: deny_reasons.append(ErrorTypes.JoinRequestDenied_IncorrectPassword)
	
	# the reasons key tells the player its answer No
	send_packet(PacketTypes.JoinRequestAnswer, src, {"reasons": deny_reasons})

func _on_signaling_server_state_changed(new_state : WebSocketPeer.State):
	Log.emit("[lobby %s] new signaling state: %s" % [player_id, new_state])
	
	if new_state == WebSocketPeer.State.STATE_OPEN:
		ConnectedToSignalingServer.emit()
	
	elif new_state == WebSocketPeer.State.STATE_CLOSED:
		DisconnectedFromSignalingServer.emit()
		FatalError.emit(ErrorTypes.SignalingServerDisconnected)

func _on_multip_peer_connected(remote_peer_id : int):
	Log.emit("[lobby %s] PeerConnected - ID: %s" % [player_id, remote_peer_id])
	send_packet(
		PacketTypes.LobbyHostSettingsChanged,
		SignalingServerAddress,
		{"setting": ["curr_player_count", get_curr_player_count()]}
	)

func _on_multip_peer_disconnected(remote_peer_id : int):
	Log.emit("[lobby %s] PeerDisconnected - ID: %s" % [player_id, remote_peer_id])
	
	# condition should always return true but is put in an if statement just in case
	if peers.has(remote_peer_id):
		peers[remote_peer_id].close()
	
	send_packet(
		PacketTypes.LobbyHostSettingsChanged,
		SignalingServerAddress,
		{"setting": ["curr_player_count", get_curr_player_count()]}
	)
	
	PeerDisconnected.emit(remote_peer_id)

func _on_lobby_settings_changed(property_name : String, new_value : Variant):
	# ensure the signaling server is connected before trying to send any setting changes
	if not (signaling_server and signaling_server.get_ready_state() == WebSocketPeer.STATE_OPEN):
		return
	
	# ensure the lobby size isnt below minimum
	if property_name == "lobby_size":
		assert(MinLobbySize <= new_value, "Lobby size %s is too small. Minimum size is %s" % [new_value, MinLobbySize])
		assert(new_value <= MaxLobbySize, "Lobby size %s is too large. Maximum size is %s" % [new_value, MaxLobbySize])
	
	# password_enabled cant be true while password is "". this isnt enforced here but in _on_join_request_received
	#   to allow projects where this plugin is used to change password_enabled then password right after without worrying about throwing errors
	
	Log.emit("[lobby %s] attribute %s changed to %s" % [player_id, property_name, new_value])
	send_packet(
		PacketTypes.LobbyHostSettingsChanged,
		SignalingServerAddress,
		{"setting": [property_name, new_value]}
	)

## This gets called whenever a Peer object closes itself due to its WebRTC connection being broken
func _on_peer_connection_closed(id : int):
	peers.erase(id)

func _on_fatal_error(error_type : WebRTC.ErrorTypes):
	Log.emit("[lobby %s] Fatal error:\n\t%s\n\t%s" % [player_id, ErrorTypes.find_key(error_type), ErrorTypeExplanation.get(error_type)])
	queue_free()
#endregion

#region packet handling
func parse_packet(packet : String):
	Log.emit("[lobby %s] parsing packet" % player_id)
	
	var parse_err = json.parse(packet)
	if parse_err == OK:
		# decide what to do based on the `type` value in the packet
		var data : Dictionary = correct_packet_dict_value_types(json.data)
		
		Log.emit("\t" + str(data))
		
		# if the packet data doesnt contain the type, dst and src keys then its invalid, therefore return
		if not (data.has("type") and data.has("dst") and data.has("src")):
			return
		
		match data.type:
			PacketTypes.PeerAssignedID:
				Log.emit("[lobby %s] received packet of type PeerAssignedID" % player_id)
				ReceivedPlayerID.emit(data.dst)
			
			PacketTypes.JoinRequest:
				Log.emit("[lobby %s] received packet of type JoinRequest" % player_id)
				JoinRequestReceived.emit(data.src, data.password, data.name)
			
			PacketTypes.RTCOffer, PacketTypes.RTCIce:
				Log.emit("[lobby %s] received packet of type RTCOffer or RTCIce" % player_id)
				var dst_peer : Peer = peers.get(data.src)
				if dst_peer:
					dst_peer.parse_packet(data)

## Send a packet to the signaling server through the websocket connection
## This packet contains type, destination, source and optional data values
func send_packet(type : int, dst : int, data : Dictionary = {}):
	# create a dictionary object containing the necessary type, dst and src data
	# then merge it with the data argument without overriding keys in the type, dst src dict
	
	# JSON.stringify isnt used since it automatically converts all integers to type Number, which doesnt differentiate from int or float
	var packet : Dictionary = {
		"type": type,
		"dst": dst,
		"src": player_id
		}.merged(data)
	
	signaling_server.send(str(packet).to_ascii_buffer())
	
	Log.emit("[lobby %s] sending packet\n\t%s" % [player_id, packet])
#endregion

#region interface functions
func get_curr_player_count() -> int:
	return len(multiplayer.get_peers()) + 1 # +1 because self is a player

## NOTE: Excludes self
func get_curr_connected_peer_ids() -> Array:
	return Array(multiplayer.get_peers())

## NOTE: Excludes self
func get_curr_connected_peer_objects() -> Array[Peer]:
	# any Peers in peers that arent in the list of connected peer ids is queued for deletion
	# therefore filter them out
	var peer_ids = get_curr_connected_peer_ids()
	return peers.values().filter(func(peer : Peer): return peer.peer_id in peer_ids)

func kick_player(peer_id : int):
	# peers_to_kick is an array of length 0 or 1
	var peers_to_kick : Array = peers.values().filter(func(peer : Peer): return peer.peer_id == peer_id)
	
	# Peer | null
	var peer_to_kick = peers_to_kick[0] if len(peers_to_kick) else null
	
	if peer_to_kick != null:
		peer_to_kick.close()
#endregion

func gen_peer_id() -> int:
	var avail_ids = range(2, MaxLobbySize).filter(func(val): return val not in peers)
	return avail_ids.pick_random()

## Returns the player name of the peer with the given peer_id
## Returns null if the peer wasnt found or String containig the player name
func get_player_name_by_peer_id(peer_id : int): # -> String | null
	var peer = peers.get(peer_id)
	if peer == null:
		return
	
	return peer.player_name

func _process(_delta):
	if multip_peer:
		# although multip_peer and multiplayer.multiplayer_peer is supposed to be pointing to the same object,
		#   polling both of them is vital for ice candidate generation in web export
		multip_peer.poll()
		multiplayer.multiplayer_peer.poll()
	
	for p : Peer in peers.values():
		p.poll()

	if not signaling_server:
		return

	signaling_server.poll()
	
	var new_signaling_server_state = signaling_server.get_ready_state()
	if new_signaling_server_state != signaling_server_old_state:
		signaling_server_old_state = new_signaling_server_state
		SignalingServerStateChanged.emit(new_signaling_server_state)
	
	# check if theres a packet available
	# `if` is used in favor of `while` because it limits packet parsing to 1 packet/frame
	#   this allows the data to be properly parsed before reading the next packet
	if signaling_server.get_available_packet_count():
		var packet : PackedByteArray = signaling_server.get_packet()
		parse_packet(packet.get_string_from_ascii())



func _input(event):
	if event.is_action_pressed("ui_up"):
		for p : Peer in peers.values():
			Log.emit(" ".join([
				p,
				p.data_channel.get_ready_state(),
				p.peer_connection.get_connection_state(),
				p.peer_connection.get_gathering_state(),
				p.peer_connection.get_signaling_state()
				])
			)
		for rtc_p in multiplayer.multiplayer_peer.get_peers().values():
			var channels : Array = rtc_p.channels
			Log.emit(" ".join([rtc_p, channels.map(func(i : WebRTCDataChannel): return i.get_ready_state())]))


func _exit_tree():
	if signaling_server: signaling_server.close()
	if multip_peer: multip_peer.close()
	for p : Peer in peers.values():
		p.close()
	
	multiplayer.multiplayer_peer = null
