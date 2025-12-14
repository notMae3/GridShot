extends Gun
class_name SubMachineGun

const base_spread = Config.weapons.sub_machine_gun_base_spread
const ads_spread = Config.weapons.sub_machine_gun_ads_spread
const firing_speed = Config.weapons.sub_machine_gun_firing_speed
const projectile_type = "bullet"
const name = "SubMachineGun"

const dmg_factor = Config.weapons.sub_machine_gun_dmg_factor
const dmg = Config.weapons.bullet_dmg * dmg_factor
const mag_size = Config.weapons.sub_machine_gun_mag_size
var extra_bullets = Config.weapons.sub_machine_gun_extra_bullets
