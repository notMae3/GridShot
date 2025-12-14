## Player sided version of my WebRTC multiplayer setup. 
## Use join_lobby(...) and refresh_lobby_list() as well as the appropriate signals. 
## signal Log is emitted for every log message. 
## signal FatalError is emitted after a fatal error and right before this Node is freed. 
## This must be used with the provided signaling server. 

@icon("MultiplayerSpawner.svg")

extends WebRTC
class_name WebRTCPlayerClient

var peer_id : int   # used for webrtc multiplayer connection
var player_id : int # used for matchmaking
var player_name : String # used for matchmaking

var lobby_to_conn_to : String # aka lobby_id
var JoinRequestAnswerTimer : Timer
var WebRTCConnectionTimer : Timer
var lobby_list_hash : String
var lobby_list : Dictionary

var json : JSON

var peer_connection : WebRTCPeerConnection
var data_channel : WebRTCDataChannel
var multip_peer : WebRTCMultiplayerPeer
var signaling_server : WebSocketPeer
var signaling_server_old_state : WebSocketPeer.State


# throttle the sending of ice candidates until the receiver has sent
#   a packet saying its ready, ie PacketTypes.RemotePeerICEReady
var outbound_ice_candidates = []
var throttle_ice = true

# signaling server related signals
signal ReceivedPlayerID(new_id : int)
signal ReceivedLobbyDict(lobby_dict : Dictionary, hash : String)
signal ReceivedLobbyDictNotNeeded
signal RemotePeerICEReady
signal RTCAnswerReceived(sdp : String)
signal RTCIceReceived(media : String, index : int, candidate_name : String)
signal JoinRequestAnswerReceived(answer : bool, new_peer_id, reasons) # new_peer_id : int | null, reasons : Array[int] | null
signal JoinRequestDenied(reasons : Array)
signal PeerIDReceived

signal PacketReturnedInvalidDestination
signal SignalingServerStateChanged(state : WebSocketPeer.State)
signal ConnectedToSignalingServer
signal DisconnectedFromSignalingServer

# webrtc connection related signals
signal WebRTCPeerConnectionFailed

# player client exclusive multiplayer signals
signal ConnectedToServer
signal ConnectionFailed
signal LobbyServerDisconnected

# other multiplayer signals
signal PeerConnected(remote_peer_id : int)
signal PeerDisconnected(remote_peer_id : int)

# signal which emits WebRTCLobbyHost log messages
signal Log(text : String)
signal FatalError(error_type : WebRTC.ErrorTypes)


#region init
func _init(signaling_server_url : String, log_debug : bool = false):
	name = "WebRTCPlayerClient"
	self.signaling_server_url = signaling_server_url
	self.log_debug = log_debug

func _ready():
	json = JSON.new()
	init_WebRTCConnection()
	init_signaling_server()
	init_fatal_error_signal_connections()
	
	if log_debug:
		get_tree().create_timer(1).timeout.connect(log_debug_func)

func log_debug_func():
	# this is meant to be functional, not pretty
	Log.emit("[player %s %s]: " % [player_id, peer_id] + " ".join(
		[data_channel.get_ready_state() if data_channel else "-", peer_connection.get_connection_state(), peer_connection.get_gathering_state(), peer_connection.get_signaling_state()]
		) + " " + str(multiplayer.multiplayer_peer.get_peers().values().map(func(rtc_p): return " ".join([rtc_p, rtc_p.channels.map(func(i : WebRTCDataChannel): return i.get_ready_state())])) if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer else "")
		)
	
	get_tree().create_timer(1).timeout.connect(log_debug_func)

func init_WebRTCConnection():
	# setup the timer which throws a fatal error if a webrtc connection isnt established
	# within WebRTCConnectionTimeout seconds
	WebRTCConnectionTimer = Timer.new()
	WebRTCConnectionTimer.wait_time = WebRTCConnectionTimeout
	WebRTCConnectionTimer.one_shot = true
	WebRTCConnectionTimer.timeout.connect(_on_webrtc_connection_timer_timeout)
	add_child(WebRTCConnectionTimer)

	# setup the WebRTCPeerConnection to later use with WebRTCMultiplayerPeer
	peer_connection = WebRTCPeerConnection.new()
	peer_connection.initialize(self.WebRTC_url_config)
	peer_connection.ice_candidate_created.connect(_on_ice_candidate_created)
	peer_connection.session_description_created.connect(_on_session_description_created)
	peer_connection.data_channel_received.connect(_on_data_channel_received)

	Log.emit("[player %s %s] init webrtc conn" % [player_id, peer_id])

func init_signaling_server():
	# setup the timer which throws a fatal error if a JoinRequestAnswer isnt received
	# wihin JoinRequestAnswerTimeout seconds
	JoinRequestAnswerTimer = Timer.new()
	JoinRequestAnswerTimer.wait_time = JoinRequestAnswerTimeout
	JoinRequestAnswerTimer.timeout.connect(_on_join_request_answer_timer_timeout)
	add_child(JoinRequestAnswerTimer)
	
	# start a connection attempt to the signaling server. built in timeout is ~90s
	signaling_server = WebSocketPeer.new()
	signaling_server_old_state = WebSocketPeer.STATE_CLOSED
	signaling_server.connect_to_url(signaling_server_url)
	
	# connect SignalingServer related signals
	ReceivedPlayerID.connect(_on_peer_assigned_player_id)
	ReceivedLobbyDict.connect(_on_received_lobby_list)
	RemotePeerICEReady.connect(func(): self.set("throttle_ice", false) ; outbound_ice_candidates.map(send_ice_candidate))
	RTCAnswerReceived.connect(_on_rtc_answer_received)
	RTCIceReceived.connect(_on_rtc_ice_received)
	JoinRequestAnswerReceived.connect(_on_join_request_answer_received)
	SignalingServerStateChanged.connect(_on_signaling_server_state_changed)

	Log.emit("[player %s %s] init signaling server" % [player_id, peer_id])

func init_WebRTCMultiplayerPeer():
	multip_peer = WebRTCMultiplayerPeer.new()
	multip_peer.create_client(peer_id)
	multiplayer.multiplayer_peer = multip_peer

	# connect multiplayer signals
	multiplayer.connected_to_server.connect(ConnectedToServer.emit)
	multiplayer.connection_failed.connect(ConnectionFailed.emit)
	multiplayer.server_disconnected.connect(LobbyServerDisconnected.emit)
	
	multiplayer.peer_connected.connect(PeerConnected.emit)
	multiplayer.peer_disconnected.connect(PeerDisconnected.emit)

	ConnectedToServer.connect(Log.emit.bind("[player %s %s] ConnectedToServer" % [player_id, peer_id]))
	ConnectionFailed.connect(Log.emit.bind("[player %s %s] ConnectionFailed" % [player_id, peer_id]))
	LobbyServerDisconnected.connect(Log.emit.bind("[player %s %s] LobbyServerDisconnected" % [player_id, peer_id]))
	PeerConnected.connect(_on_multip_peer_connected)
	PeerDisconnected.connect(func(remote_peer_id): Log.emit("[player %s %s] PeerDisconnected - ID: %s" % [player_id, peer_id, remote_peer_id]))

	Log.emit("[player %s %s] init WebRTCMultiplayerPeer" % [player_id, peer_id])

func init_fatal_error_signal_connections():
	JoinRequestDenied.connect(_on_join_request_denied)
	PacketReturnedInvalidDestination.connect(FatalError.emit.bind(ErrorTypes.PacketReturnedInvalidDestination))
	WebRTCPeerConnectionFailed.connect(FatalError.emit.bind(ErrorTypes.WebRTCPeerConnectionFailed))
	ConnectionFailed.connect(FatalError.emit.bind(ErrorTypes.ConnectionToLobbyHostFailed))
	LobbyServerDisconnected.connect(FatalError.emit.bind(ErrorTypes.LobbyHostServerDisconnected))
	FatalError.connect(_on_fatal_error)

	Log.emit("[player %s %s] setup fatal error signals" % [player_id, peer_id])
#endregion

#region signal reactions
func _on_ice_candidate_created(media: String, index: int, candidate_name: String):
	Log.emit("[player %s %s] ice candidate created" % [player_id, peer_id])

	var packaged_ice_candidate = {"media": media, "index": index, "candidate_name": candidate_name}

	# wait to send generated ice candidates until a greenlight signal (PacketTypes.RemotePeerICEReady) has been received from the lobby host
	if throttle_ice:
		Log.emit("\tice throttled")
		outbound_ice_candidates.append(packaged_ice_candidate)

	else:
		Log.emit("\tsending")
		send_ice_candidate(packaged_ice_candidate)

func send_ice_candidate(ice_candidate : Dictionary):
	Log.emit("[player %s %s] sending ice candidate" % [player_id, peer_id])

	send_packet(
		PacketTypes.RTCIce,
		lobby_to_conn_to,
		{
			"media": ice_candidate.media,
			"index": ice_candidate.index,
			"candidate_name": ice_candidate.candidate_name
		})

func _on_session_description_created(type: String, sdp: String):
	Log.emit("[player %s %s] session desc created: " % [player_id, peer_id] + str(type))

	var err = peer_connection.set_local_description(type, sdp)
	Log.emit("[player %s %s] set local desc (%s)" % [player_id, peer_id, err])

	# Send the SDP to the other peer via the signaling server
	Log.emit("[player %s %s] sending desc to lobby" % [player_id, peer_id])
	send_packet(
		PacketTypes.RTCOffer if type == "offer" else PacketTypes.RTCAnswer,
		lobby_to_conn_to,
		{"sdp": sdp})

func _on_data_channel_received(channel : WebRTCDataChannel):
	Log.emit("[player %s %s] data channel received" % [player_id, peer_id])
	data_channel = channel

func _on_rtc_answer_received(sdp : String):
	var err = peer_connection.set_remote_description("answer", sdp)
	Log.emit("[player %s %s] set remote desc (%s)" % [player_id, peer_id, err])

func _on_rtc_ice_received(media : String, index : int, candidate_name : String):
	var err = peer_connection.add_ice_candidate(media, index, candidate_name)
	Log.emit("[player %s %s] adding ice candidate (%s)" % [player_id, peer_id, err])

func _on_peer_assigned_player_id(new_id : int):
	player_id = new_id
	Log.emit("[player %s %s] new player id" % [player_id, peer_id])

	# at this point this peer has entered matchmaking and has received its player_id
	#   therefore ask for the list of lobbies
	send_packet(PacketTypes.ListLobbiesRequest, SignalingServerAddress, {"hash": ""})

func _on_received_lobby_list(lobby_dict : Dictionary, hash : String):
	Log.emit("[player %s %s] received lobby dict\n\t%s\n\t%s" % [player_id, peer_id, hash, lobby_dict])

	# the lobby list isnt stored here but is intead expected to be stored and parsed by the parent project

	# lobby_list_hash is used for lobby setting version control
	lobby_list_hash = hash
	lobby_list = lobby_dict
	
	Log.emit("[player %s %s] set lobby list hash to \"%s\"" % [player_id, peer_id, lobby_list_hash])

func _on_join_request_answer_received(new_peer_id, reasons):
	# new_peer_id : int if answer == true else null
	# reasons : Array[int] if answer == false else null

	JoinRequestAnswerTimer.stop()

	# asnwer Yes
	if new_peer_id != null:
		peer_id = new_peer_id
		PeerIDReceived.emit()

		init_WebRTCMultiplayerPeer()

		multip_peer.add_peer(peer_connection, 1)
		var err = peer_connection.create_offer()
		if err != OK:
			WebRTCPeerConnectionFailed.emit()
			Log.emit("[player %s %s] create offer error: %s" % [player_id, peer_id, err])
		else:
			WebRTCConnectionTimer.start()
		
		Log.emit("[player %s %s] creating offer" % [player_id, peer_id])
	
	# answer No
	else:
		JoinRequestDenied.emit(reasons)

func _on_join_request_denied(reasons : Array):
	# the deny reasons are sorted after importance
	# ie 1. Not accepting players, 2. Lobby full, 3. Incorrect password
	FatalError.emit(reasons[0])

func _on_signaling_server_state_changed(new_state : WebSocketPeer.State):
	Log.emit("[player %s %s] new signaling state: %s" % [player_id, peer_id, new_state])

	if new_state == WebSocketPeer.State.STATE_OPEN:
		ConnectedToSignalingServer.emit()

	elif new_state == WebSocketPeer.State.STATE_CLOSED:
		DisconnectedFromSignalingServer.emit()

		# if the matchmaking/signaling server connection closed without the playerclient being connected
		#   to a lobby: emit FatalError
		if not len(multiplayer.get_peers()):
			FatalError.emit(ErrorTypes.SignalingServerDisconnected)

## If the lobby host hasn't responsed with a JoinRequestAnswer within JoinRequestAnswerTimeout
## seconds after the join request was sent: throw FatalError. This is generally only used when
## the lobby is hosted on a throttled browser tab and thereby can't respond.
func _on_join_request_answer_timer_timeout():
	FatalError.emit(ErrorTypes.JoinRequestAnswerTimeout)

## If this player client hasn't connected to the lobby host within WebRTCConnectionTimeout
## seconds after the offer was created: throw FatalError
func _on_webrtc_connection_timer_timeout():
	FatalError.emit(ErrorTypes.WebRTCConnectionTimeout)

func _on_multip_peer_connected(remote_peer_id : int):
	Log.emit("[player %s %s] PeerConnected - ID: %s" % [player_id, peer_id, remote_peer_id])

	# remote peer with id 1 is the lobby host
	# after connecting to a lobby the matchmaking/signaling server connection isnt used, therefore disconnect
	# use a WebRTCConnectionTimeout second margin to ensure all ice candidates are sent
	if remote_peer_id == 1:
		WebRTCConnectionTimer.stop()
		get_tree().create_timer(WebRTCConnectionTimeout).timeout.connect(signaling_server.close)

func _on_fatal_error(error_type : WebRTC.ErrorTypes):
	Log.emit("[player %s %s] Fatal error:\n\t%s\n\t%s" % [player_id, peer_id, ErrorTypes.find_key(error_type), ErrorTypeExplanation.get(error_type)])
	queue_free()
#endregion

#region packet handling
func parse_packet(packet : String):
	Log.emit("[player %s %s] parsing packet" % [player_id, peer_id])

	var parse_err = json.parse(packet)
	if parse_err == OK:
		# decide what to do based on the `type` value in the packet
		var data : Dictionary = json.data
		data = correct_packet_dict_value_types(data)

		Log.emit("\t" + str(data))

		# if the packet data doesnt contain the type, dst and src keys then its invalid, therefore return
		if not (data.has("type") and data.has("dst") and data.has("src")):
			return

		match data.type:
			PacketTypes.PeerAssignedID:
				Log.emit("[player %s %s] received packet of type PeerAssignedID" % [player_id, peer_id])
				ReceivedPlayerID.emit(data.dst)

			PacketTypes.InvalidDestination:
				Log.emit("[player %s %s] received packet of type InvalidDestination" % [player_id, peer_id])
				PacketReturnedInvalidDestination.emit()

			PacketTypes.LobbyDict:
				Log.emit("[player %s %s] received packet of type LobbyDict\n\t%s" % [player_id, peer_id, data.lobbies])
				ReceivedLobbyDict.emit(data.lobbies, data.hash)

			PacketTypes.LobbyDictNotNeeded:
				Log.emit("[player %s %s] received packet of type LobbyDictNotNeeded" % [player_id, peer_id])
				ReceivedLobbyDictNotNeeded.emit()

			PacketTypes.RemotePeerICEReady:
				Log.emit("[player %s %s] received packet of type RemotePeerICEReady" % [player_id, peer_id])
				RemotePeerICEReady.emit()

			PacketTypes.RTCAnswer:
				Log.emit("[player %s %s] received packet of type RTCAnswer" % [player_id, peer_id])
				RTCAnswerReceived.emit(data.sdp)

			PacketTypes.RTCIce:
				Log.emit("[player %s %s] received packet of type RTCIce" % [player_id, peer_id])
				RTCIceReceived.emit(data.media, data.index, data.candidate_name)

			PacketTypes.JoinRequestAnswer:
				Log.emit("[player %s %s] received packet of type JoinRequestAnswer (%s)" % [player_id, peer_id, data.has("peer_id")])
				JoinRequestAnswerReceived.emit(data.get("peer_id"), data.get("reasons"))

## Send a packet to the signaling server through the websocket connection
## This packet contains type, destination, source and optional data values
func send_packet(type : int, dst, data : Dictionary = {}):
	# create a dictionary object containing the necessary type, dst and src data
	#   then merge it with the data argument without overriding keys in the type, dst src dict

	# JSON.stringify isnt used since it automatically converts all integers to type Number, which doesnt differentiate from int or float
	var packet : Dictionary = {
		"type": type,
		"dst": dst,
		"src": player_id
		}.merged(data)

	signaling_server.send(str(packet).to_ascii_buffer())
	Log.emit("[player %s %s] sending packet\n\t%s" % [player_id, peer_id, packet])
#endregion

func _process(_delta):
	if multip_peer:
		# although multip_peer and multiplayer.multiplayer_peer is supposed to be pointing to the same object,
		#   polling both of them is vital for ice candidate generation in web export
		multip_peer.poll()
		multiplayer.multiplayer_peer.poll()

	if peer_connection:
		peer_connection.poll()
	
	if data_channel:
		data_channel.poll()

	if not signaling_server:
		return

	signaling_server.poll()

	var new_signaling_server_state = signaling_server.get_ready_state()
	if new_signaling_server_state != signaling_server_old_state:
		signaling_server_old_state = new_signaling_server_state
		SignalingServerStateChanged.emit(new_signaling_server_state)

	# check if theres a packet available
	# if` is used in favor of `while` because it limits packet parsing to 1 packet/frame
	#   this allows the data to be properly parsed before reading the next packet
	if signaling_server.get_available_packet_count():
		var packet : PackedByteArray = signaling_server.get_packet()
		parse_packet(packet.get_string_from_ascii())

## Request to join a lobby by first sending a JoinRequest over the signaling server.
## The actual join logic happens in `_on_join_request_answer_received`.
func join_lobby(lobby_id : String, password : String = "", player_name : String = "-"):
	lobby_to_conn_to = lobby_id
	self.player_name = player_name
	send_packet(PacketTypes.JoinRequest, lobby_id, {"password": password, "name": player_name})
	JoinRequestAnswerTimer.start()

## Request a list (actually a dictionary) from the signaling server containing data about all the
## currently online lobbies. If the lobby list hasn't changed since the last refresh, as checked by
## `lobby_list_hash`, then the response is type `LobbyDictNotNeeded`.
func refresh_lobby_list():
	send_packet(PacketTypes.ListLobbiesRequest, SignalingServerAddress, {"hash": lobby_list_hash})


func _input(event):
	if event.is_action_pressed("ui_up"):
		Log.emit(" ".join([
			data_channel.get_ready_state(),
			peer_connection.get_connection_state(),
			peer_connection.get_gathering_state(),
			peer_connection.get_signaling_state()
			])
		)
		for rtc_p in multiplayer.multiplayer_peer.get_peers().values():
			var channels : Array = rtc_p.channels
			Log.emit(" ".join([rtc_p, channels.map(func(i : WebRTCDataChannel): return i.get_ready_state())]))


func _exit_tree():
	if signaling_server: signaling_server.close()
	if peer_connection: peer_connection.close()
	if data_channel: data_channel.close()
	if multip_peer: multip_peer.close()
	multiplayer.multiplayer_peer = null
