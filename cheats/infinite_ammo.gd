class_name InfiniteAmmo
extends CheatBase
## Infinite Ammo (ladder #2): bigger magazines, then no reloads.
## Effects (cheats.json), both target weapon:
##   mag_mult         2x magazine at level 1 up to the max-level multiplier
##   infinite_reload  from max level: reload time is 0, so an empty magazine
##                    refills on the same shot ("never reload"); a reload
##                    already running finishes as soon as it is switched on
## CheatBase applies them through Weapon.set_modifier and restores the neutral
## values (1.0 / false) on remove(). CheatSystem re-applies on gun_equipped, so
## every new gun gets the modifiers too.
