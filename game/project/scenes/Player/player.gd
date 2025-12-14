extends CharacterBody2D
class_name Player

@export var id : int
@export var team : int
@export var color : Color: 
	set(new_value):
		color = new_value
		$PlayerColor.color = color
@export var hp : int

var gun : Gun:
	set(new_value):
		if gun != null:
			gun.delete()
		
		gun = new_value
		in_hand = gun
		
		$WeaponFireCooldownTimer.wait_time = 1.0 / new_value.firing_speed
		$WeaponFireCooldownTimer.start()

var utils = []

var in_hand:
	set(new_value):
		# the is_in_hand determines wehter throwable preview is visible
		if in_hand is Throwable: in_hand.is_in_hand = false
		in_hand = new_value
		if in_hand is Throwable: in_hand.is_in_hand = true

const movement_speed       = Config.player.movement_speed
const movement_ads_speed   = Config.player.movement_ads_speed
const movement_halt_speed  = Config.player.movement_halt_speed
const rotation_speed       = Config.player.rotation_speed
const rotation_ads_speed   = Config.player.rotation_ads_speed
const rotation_halt_speed  = Config.player.rotation_halt_speed
const throw_distace        = Config.throwables.throw_distance
const ads_throw_distace    = Config.throwables.ads_throw_distance
const plant_duration       = Config.game_bomb.plant_duration
const diffuse_duration     = Config.game_bomb.diffuse_duration
const max_hp               = Config.player.max_hp

var rotation_velocity = 0

@export var ads_factor : float = 0
@onready var ads_anim_player = $AnimationPlayer

@export var stun_factor : float = 0

var inputs_enabled : bool = false

var can_plant : bool = false
var is_planting : bool = false
var plant_start_time : float = 0
var plant_progress : float = 0

var can_diffuse : bool = false
var is_diffusing : bool = false
var diffuse_start_time : float = 0
var diffuse_progress : float = 0


func _enter_tree():
	# ensures this instance's nodes' attributes cant be changed by other game instances
	id = int(name)
	set_multiplayer_authority(id)

func _ready():
	if is_multiplayer_authority():
		$DirectionMarker.z_index = 6
		hp = max_hp
	
	# sets the length of the throwabled preview raycast
	# its global rotation is based on player rotation, therefore it pointing to the right is correct
	$ThrowablePreviewRaycast.target_position = Vector2.RIGHT * get_current_throw_distance()

func _input(event):
	if not is_multiplayer_authority() or not inputs_enabled:
		return
	
	if event.is_action_pressed("E"):
		if team == 0: start_planting()
		else:         start_diffusing()
		return
	
	elif event.is_action_released("E"):
		if team == 0: stop_planting()
		else:         stop_diffusing()
		return
	
	if event.is_action_pressed("Arrow up"):
		ads_anim_player.play("to ads")
	
	if event.is_action_released("Arrow up"):
		ads_anim_player.play_backwards("to ads")
	
	if event.is_action_pressed("R"):
		if in_hand is Gun:
			in_hand.reload()
	
	if event.is_action_pressed("1"): in_hand = gun
	if event.is_action_pressed("2"): in_hand = utils[0]
	if event.is_action_pressed("3"): in_hand = utils[1]
	if event.is_action_pressed("4"): in_hand = utils[2]
	if event.is_action_pressed("5"): in_hand = utils[3]

func _physics_process(delta):
	if not is_multiplayer_authority() or not inputs_enabled:
		move_and_slide()
		return
	
	if is_planting:
		progress_planting()
	
	elif is_diffusing:
		progress_diffusing()
	
	elif Input.is_action_pressed("Space"):
		fire_weapon()
	
	# if the sum of the input strength of W and S isnt 0: set x velocity to movement speed in the appropriate direction
	# otherwise: decrease x velocity
	# the movement_halt_speed is multiplied by delta to compensate for fps irregularites.
	#   movement_speed isnt multiplied by delta since its a constant velocity and thus not affected by fps
	var movement_vector = Input.get_vector("A", "D", "W", "S") if not is_planting else Vector2.ZERO
	if movement_vector.x: velocity.x = get_current_movement_speed() * movement_vector.x
	else:                 velocity.x = move_toward(velocity.x, 0, movement_halt_speed * delta)
	
	# the the same as above but with the y axis
	if movement_vector.y: velocity.y = get_current_movement_speed() * movement_vector.y
	else:                 velocity.y = move_toward(velocity.y, 0, movement_halt_speed * delta)
	
	# modify velocity to push players away from eachother if they're overlapping
	var overlapping_players : Array = $PlayerRepulsionArea2D.get_overlapping_bodies().filter(func(body : Node2D): return body != self)
	if overlapping_players:
		# 1 repulsion vector per overlapping player
		var repulsion_vectors = []
		
		for player : Player in overlapping_players:
			# player_distance is minimum 1 since value 0 would cause a division error
			var player_distance = max(1, position.distance_to(player.position))
			
			# if two players have the exact same cords the opposite_direction is (0,0)
			# therefore choose a random direction in which this player will be pushed
			var opposite_direction = -position.direction_to(player.position)
			if opposite_direction == Vector2.ZERO:
				opposite_direction = Vector2.from_angle(2*PI * randf())
			
			repulsion_vectors.append(opposite_direction * 90 * wrap((30/player_distance)**2, 0.5, 1))
		
		# sum the repulsion vectors and add the result to velocity
		var repulsion_vector_sum = repulsion_vectors.reduce(func(sum, vector): return sum + vector)
		velocity += repulsion_vector_sum
	
	# handle rotation in the same way as movement
	var rotation_direction = Input.get_axis("Arrow left", "Arrow right") if not is_planting else 0.0
	if rotation_direction: rotation_velocity = get_current_rotation_speed() * rotation_direction
	else:                  rotation_velocity = move_toward(rotation_velocity, 0, rotation_halt_speed * delta)
	rotation += rotation_velocity * delta
	
	# update the throwable preview raycast if weapon is throwable
	if in_hand is Throwable:
		$ThrowablePreviewRaycast.target_position = Vector2.RIGHT * get_current_throw_distance()
	
	move_and_slide()


#region ads based stuff
func get_current_movement_speed() -> float:
	# the current movement speed is dependent on ads_factor, which is
	#   dependent on the to_ads animation progress
	
	var movement_speed_delta = movement_speed - movement_ads_speed
	var current_speed = movement_speed - movement_speed_delta * ads_factor
	current_speed *= 1-stun_factor
	
	return current_speed

func get_current_rotation_speed() -> float:
	# the current rotation speed is dependent on ads_factor, which is
	#   dependent on the to_ads animation progress
	
	var rotation_speed_delta = rotation_speed - rotation_ads_speed
	var current_speed = rotation_speed - rotation_speed_delta * ads_factor
	current_speed = current_speed * (1 - stun_factor)
	
	return current_speed

func get_current_throw_distance() -> float:
	# the current throw distance is dependent on ads_factor, which is
	#   dependent on the to_ads animation progress
	
	var throw_distance_delta = throw_distace - ads_throw_distace
	var current_throw_distance = throw_distace - throw_distance_delta * ads_factor
	current_throw_distance *= 1-stun_factor
	
	return current_throw_distance
#endregion

func fire_weapon():
	var timer : Timer = $WeaponFireCooldownTimer
	
	if timer.time_left == 0:
		in_hand.fire(name, ads_factor, rotation, position)
		timer.start()

func take_dmg(dmg : int):
	hp = max(0, hp-dmg)
	
	if hp == 0:
		inputs_enabled = false
		modulate = Color("#999999")
		$PlayerRepulsionArea2D/CollisionShape2D.set_deferred("disabled", true)
		
		Globals.check_win.rpc()

#region planting
func start_planting():
	if can_plant and not Globals.game_node.game_bomb_planted:
		is_planting = true
		plant_start_time = Time.get_unix_time_from_system()
		$DirectionMarker.visible = false
		modulate = Color("#999999")

func stop_planting():
	is_planting = false
	$DirectionMarker.visible = true
	modulate = Color("#ffffff")

func finish_planting():
	if not Globals.game_node.game_bomb_planted:
		Globals.game_bomb_planted.rpc(position)
		Globals.game_node.game_bomb_planted = true
	stop_planting()

func progress_planting():
	var current_time = Time.get_unix_time_from_system()
	plant_progress = min(1, (current_time - plant_start_time)/plant_duration)
	
	if plant_progress == 1:
		finish_planting()
#endregion

#region diffusing
func start_diffusing():
	if can_diffuse:
		is_diffusing = true
		diffuse_start_time = Time.get_unix_time_from_system()
		$DirectionMarker.visible = false
		modulate = Color("#999999")

func stop_diffusing():
	is_diffusing = false
	$DirectionMarker.visible = true
	modulate = Color("#ffffff")

func finish_diffusing():
	if not Globals.game_node.game_bomb_diffused:
		Globals.game_bomb_diffused.rpc()
		Globals.game_node.game_bomb_diffused = true
	stop_diffusing()

func progress_diffusing():
	var current_time = Time.get_unix_time_from_system()
	diffuse_progress = min(1, (current_time - diffuse_start_time)/diffuse_duration)
	
	if diffuse_progress == 1:
		finish_diffusing()
#endregion
