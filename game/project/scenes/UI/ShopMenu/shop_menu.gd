extends PlayerCameraEffect

var weapon_types = {
	0: AssaultRifle,
	1: SubMachineGun,
	2: Shotgun,
	3: Molotov,
	4: FlashGrenade,
	5: SmokeGrenade,
	6: Tripwire
}

@onready var buttons = {
	0: $Gun/VBoxContainer/VBoxContainer/AssaultRifle,
	1: $Gun/VBoxContainer/VBoxContainer/SubMachineGun,
	2: $Gun/VBoxContainer/VBoxContainer/Shotgun,
	3: $Util/VBoxContainer/GridContainer/Molotov,
	4: $Util/VBoxContainer/GridContainer/FlashGrenade,
	5: $Util/VBoxContainer/GridContainer/SmokeGrenade,
	6: $Util/VBoxContainer/GridContainer/Tripwire
}

@onready var gun_count_label = $Gun/VBoxContainer/CountLabel
@onready var util_count_label = $Util/VBoxContainer/CountLabel
@onready var start_time_label = $StartTimeLabel
@onready var start_game_timer = $StartGameTimer

var current_gun : int # int corresponding to weapon_types
var current_util : Array[int] = [] # arary of ints corresponding to weapon_types


func start_timer():
	# resets the players utils right when this screen gets shown
	source.utils = [
		Molotov.new(source),
		FlashGrenade.new(source),
		SmokeGrenade.new(source),
		Tripwire.new(source)
	]
	
	start_game_timer.start()

func _process(delta):
	super._process(delta)
	
	start_time_label.text = "Starting in %ss" % int(round(start_game_timer.time_left))

# called locally on all peers
func _on_start_game_timer_timeout():
	# youre given an assaultrifle if you dont select your gun on time
	if current_gun == null:
		current_gun = 0
	
	var current_util_types = current_util.map(func(weapon_type): return weapon_types[weapon_type])
	
	var loadout = {
		"gun": weapon_types[current_gun].new(),
		"util": [Molotov, FlashGrenade, SmokeGrenade, Tripwire].map(
			func(weapon_type): return 1 if weapon_type in current_util_types else 0)
	}
	Globals.game_node.shopping_phase_completed(loadout)

func _on_gun_button_pressed(weapon_type):
	# lift the old button
	var old_button : Button = buttons[current_gun]
	old_button.button_pressed = false
	
	# update current gun
	current_gun = weapon_type
	
	# update the count label
	gun_count_label.text = "1/1"

func _on_util_button_pressed(weapon_type):
	var current_button : Button = buttons[weapon_type]
	
	# if 3 buttons are down and the fourth one is being pressed: unpress it and do nothing
	if len(current_util) == 3 and weapon_type not in current_util:
		current_button.button_pressed = false
		return
	
	
	if weapon_type not in current_util:
		current_util.append(weapon_type)
	else:
		current_util.erase(weapon_type)
	
	# update the count label
	util_count_label.text = "%s/3" % len(current_util)
