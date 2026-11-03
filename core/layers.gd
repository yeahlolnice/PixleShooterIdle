class_name Layers
extends RefCounted
## Physics layer bit values. Names match [layer_names] in project.godot.
## Use these instead of magic numbers for collision_layer / collision_mask.

const WORLD := 1 << 0     ## layer 1: arena blocks, static geometry
const PLAYER := 1 << 1    ## layer 2: the player body
const BOTS := 1 << 2      ## layer 3: bot movement bodies
const HITBOXES := 1 << 3  ## layer 4: bot head/body Area3D hitboxes (weapon raycasts)
const PICKUPS := 1 << 4   ## layer 5: coins and loot (Loot Magnet)
