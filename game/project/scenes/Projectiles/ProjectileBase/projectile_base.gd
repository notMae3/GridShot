extends CharacterBody2D
class_name ProjectileBase

var source : Player
var direction : Vector2
var start_position : Vector2
var movement_speed : int

signal CollidedWithSource
signal CollidedWithPlayer(player : Player)
signal CollidedWithEnvironment

func _physics_process(_delta):
	if not is_multiplayer_authority():
		move_and_slide()
		return
	
	velocity = direction * movement_speed
	move_and_slide()

func _on_body_entered(body : Node2D):
	if not is_multiplayer_authority():
		return
	
	if body == source:
		CollidedWithSource.emit()

	if body is Player:
		CollidedWithPlayer.emit(body)
	
	elif body is TileMapLayer:
		CollidedWithEnvironment.emit()
