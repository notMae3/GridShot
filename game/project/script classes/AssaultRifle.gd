extends Gun
class_name AssaultRifle

const base_spread = Config.weapons.assault_rifle_base_spread
const ads_spread = Config.weapons.assault_rifle_ads_spread
const firing_speed = Config.weapons.assault_rifle_firing_speed
const projectile_type = "bullet"
const name = "AssaultRifle"

const dmg_factor = Config.weapons.assault_rifle_dmg_factor
const dmg = Config.weapons.bullet_dmg * dmg_factor
const mag_size = Config.weapons.assault_rifle_mag_size
var extra_bullets = Config.weapons.assault_rifle_extra_bullets
