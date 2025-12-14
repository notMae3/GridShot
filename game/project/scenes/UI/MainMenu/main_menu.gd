extends Control


@onready var host_player_name = $Host/VBoxContainer/PlayerName/LobbyPlayerNameLineEdit
@onready var host_lobby_name = $Host/VBoxContainer/LobbyName/LobbyNameLineEdit
@onready var host_start_lobby_button = $Host/VBoxContainer/StartLobbyButton

@onready var join_player_name = $Join/VBoxContainer/PlayerName/JoinPlayerNameLineEdit
@onready var join_lobby_id = $Join/VBoxContainer/LobbyID/LobbyIDLineEdit
@onready var join_lobby_button = $Join/VBoxContainer/JoinLobbyButton


func _ready():
	$Main/RightsLabel.text = "All rights reserved\nMade by %s for a school assignment\n(Gridshot is partially unfinished because I ran out of time)" % Config.credit_name

func _on_host_button_pressed():
	$Host.visible = true
	$Main.visible = false

func _on_join_button_pressed():
	$Join.visible = true
	$Main.visible = false

func _on_back_button_pressed():
	$Host.visible = false
	$Join.visible = false
	$Main.visible = true

func _process(_delta):
	# enable/disable join/start lobby button depending on if the text fields are filled in
	host_start_lobby_button.disabled = host_player_name.text == "" or host_lobby_name.text == ""
	join_lobby_button.disabled = join_player_name.text == "" or join_lobby_id.text == ""

func _on_start_lobby_button_pressed():
	Globals.start_as_lobby_host(host_lobby_name.text, host_player_name.text)

func _on_join_lobby_button_pressed():
	Globals.start_as_player_client()
	$Join.visible = false

func _on_connected_to_signaling_server():
	Globals.player_client_join_lobby(join_lobby_id.text, join_player_name.text)


func _on_quit_button_pressed():
	Globals.quit_program()
