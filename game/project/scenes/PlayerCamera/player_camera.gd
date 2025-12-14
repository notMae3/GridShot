extends Camera2D
class_name PlayerCamera

@onready var loading_screen : Control = $LoadingScreen
@onready var game_team_menu : Control = $GameTeamMenu
@onready var player_ui : Control = $PlayerUI
@onready var game_over_screen : Control = $GameOverScreen
@onready var shop_menu : Control = $ShopMenu

@onready var all_screens = [loading_screen, game_team_menu, player_ui, game_over_screen, shop_menu]

var target: # Player | null
	set = _on_target_set

func _on_target_set(new_value):
	target = new_value
	
	if target == null:
		position = Vector2.ZERO
		rotation = 0
	
	$PlayerUI.source = target
	$ShopMenu.source = target

func _ready():
	show_screen(loading_screen)

func _process(_delta):
	if target == null:
		return
	
	position = target.position

## Show a given screen and hide all other
## the screen argument is one of the defined variables at the top of this file
func show_screen(screen_to_show : Control):
	var screens_to_hide = all_screens.filter(func(screen): return screen != screen_to_show)
	screens_to_hide.map(func(screen): screen.visible = false)
	
	screen_to_show.visible = true

func reset():
	# go through all children of the player camera and remove the non-persistent ones
	var nodes_to_delete = get_children().filter(func(child): return child not in all_screens)
	nodes_to_delete.map(func(child): child.queue_free())
