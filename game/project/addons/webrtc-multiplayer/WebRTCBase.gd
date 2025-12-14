@icon("MultiplayerSynchronizer.svg")

extends Node
class_name WebRTC

var signaling_server_url : String
var log_debug : bool # write extra info to log if true

var WebRTC_url_config = {
	"iceServers": [{
			"urls": [
				"stun:relay1.expressturn.com:3478",
				"stun:stun.l.google.com:19302"
			]
		},
		{
			"urls": [ "turn:relay1.expressturn.com:3478?transport=udp" ],
			"username": "efFLEL8MC8D5N5P1XL",
			"credential": "chHxbeNooOHKx2fC",
		}
	]
}

const SignalingServerAddress = -1

const JoinRequestAnswerTimeout = 10 # s
const WebRTCConnectionTimeout = 10 # s

const MinLobbySize = 1
const MaxLobbySize = 128
# ^ different browsers have different WebRTC connection limits
#   eg. chromium: 500, chrome: 256, firefox: unlimited
# the more connections the greater the performance impact
# the projects in which this plugin will be used will have their own limits,
#   therefore i dont expect to ever completely fill a lobby

enum PacketTypes {
	KeepAlive,
	InvalidDestination,
	PeerAssignedID,
	DeclareLobbyHost,
	LobbyHostSettingsChanged,
	ListLobbiesRequest,
	LobbyDict,
	LobbyDictNotNeeded,
	RTCOffer,
	RemotePeerICEReady,
	RTCAnswer,
	RTCIce,
	JoinRequest,
	JoinRequestAnswer
}

enum ErrorTypes {
	SignalingServerDisconnected,              ## When the matchmaking/signaling server websocket connection disconnects
	PacketReturnedInvalidDestination,         ## When the signaling server couldn't find the passed destination `dst`
	WebRTCPeerConnectionFailed,               ## When the WebRTC offer creation returns an error
	ConnectionToLobbyHostFailed,              ## When connection to remote peer (lobby host) fails. Emitted by godots multiplayer API
	LobbyHostServerDisconnected,              ## When the lobby host disconnects after a stable connection was established
	JoinRequestAnswerTimeout,                 ## When the player client hasn't received a JoinRequestResponse in a reasonable time frame
	WebRTCConnectionTimeout,                  ## When the WebRTC connection attempt took too long. See ./README/WebRTC_limitations.txt
	JoinRequestDenied_NotAcceptingNewPlayers, ## When the player's join request was denied because the lobby host isn't accepting new players
	JoinRequestDenied_LobbyFull,              ## When the player's join request was denied because the lobby is full
	JoinRequestDenied_IncorrectPassword       ## When the player's join request was denied because the lobby password was incorrect
}

const ErrorTypeExplanation = {
	ErrorTypes.SignalingServerDisconnected :              "Matchmaking server disconnected",
	ErrorTypes.PacketReturnedInvalidDestination :         "Matchmaking server couldn't find lobby",
	ErrorTypes.WebRTCPeerConnectionFailed :               "Couldn't start connection to lobby",
	ErrorTypes.ConnectionToLobbyHostFailed :              "Failed while connecting to lobby",
	ErrorTypes.LobbyHostServerDisconnected :              "Lobby host disconnected",
	ErrorTypes.JoinRequestAnswerTimeout :                 "The lobby join request answer took too long",
	ErrorTypes.WebRTCConnectionTimeout :                  "The lobby connection attempt took too long (WebRTC failure)",
	ErrorTypes.JoinRequestDenied_NotAcceptingNewPlayers : "Join request denied - Not accepting new players",
	ErrorTypes.JoinRequestDenied_LobbyFull :              "Join request denied - Lobby full",
	ErrorTypes.JoinRequestDenied_IncorrectPassword :      "Join request denied - Incorrect password",
}


## Corrects packet values that get messed up from JSON conversion
func correct_packet_dict_value_types(dict : Dictionary):
	# all packets
	if dict.has("type"): dict.type = int(dict.type)
	if dict.has("src"): dict.src = int(dict.src) if str(dict.src).is_valid_float() else str(dict.src)
	if dict.has("dst"): dict.dst = int(dict.dst) if str(dict.dst).is_valid_float() else str(dict.dst)
	
	# join request answer yes
	if dict.has("peer_id"): dict.peer_id = int(dict.peer_id)
	
	# join request answer no
	if dict.has("reasons"): dict.reasons = dict.reasons.map(func(reason): return int(reason))
	
	# list lobbies
	if dict.has("lobbies"):
		for lobby_id in dict.lobbies.keys():
			dict.lobbies[lobby_id].lobby_size = int(dict.lobbies[lobby_id].lobby_size)
			dict.lobbies[lobby_id].curr_player_count = int(dict.lobbies[lobby_id].curr_player_count)
	
	return dict
