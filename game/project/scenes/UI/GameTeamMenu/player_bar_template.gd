extends Panel
class_name TeamMenuPlayerBar

@export var text : String:
	set(new_value):
		text = new_value
		$Label.text = text

@export var color : Color:
	set(new_value):
		color = new_value
		$ColorRect.color = color

@export var peer_id : int:
	set(new_value):
		peer_id = new_value
		name = str(peer_id)
