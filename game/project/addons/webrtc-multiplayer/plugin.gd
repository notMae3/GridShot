@tool
extends EditorPlugin

func _exit_tree():
	remove_custom_type("WebRTC")
	remove_custom_type("WebRTCLobbyHost")
	remove_custom_type("WebRTCPlayerClient")
