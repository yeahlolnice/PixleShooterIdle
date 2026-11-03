class_name SpeedHack
extends CheatBase
## Speed Hack (ladder #1): multiplies the player's move speed.
## Effect (cheats.json): move_speed_mult, target player, +10% at level 1 to
## +150% at max. CheatBase.apply()/remove() do all the work through
## Player.set_stat_mod / clear_stat_mod, so turning it off restores base speed
## exactly. Auto Bhop's speed cap scales with this multiplier.

const STAT := &"move_speed_mult"
