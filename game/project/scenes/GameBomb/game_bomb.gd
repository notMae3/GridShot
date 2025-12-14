extends Node2D

const windup_time = Config.game_bomb.windup_duration
const dmg = Config.game_bomb.dmg

@onready var anim_player : AnimationPlayer = $AnimationPlayer

@export var plant_time : float
var progress : float = 0
var exploded = false

func _ready():
	Globals.game_node.game_bomb = self
	plant_time = Time.get_unix_time_from_system()

func _process(_delta):
	# if the bomb has detonated theres no need to execute the below code
	if exploded:
		return
	
	var current_time = Time.get_unix_time_from_system()
	progress = (current_time - plant_time)/windup_time
	
	if progress < 1:
		anim_player.speed_scale = max(1, progress * 10)
	else:
		if Globals.game_node.game_winning_team != null:
			anim_player.speed_scale = 1
			anim_player.play("explode")
			exploded = true
			
			print("game bomb detonated, winning team 0")
			Globals.game_node.game_winning_team = 0


func _on_diffusion_area_player_entered(player : Player):
	player.can_diffuse = true

func _on_diffusion_area_player_exited(player : Player):
	player.can_diffuse = false

func _on_explosion_area_player_entered(player : Player):
	player.take_dmg(dmg)
