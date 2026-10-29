extends Node
class_name FighterController
## Decides what a FighterBody does each physics frame, as a FighterInput. A body asks its
## controller child once per physics step; the body never looks at the keyboard itself. The
## local player's controller reads Input and the camera, a bot's runs its AI, and a network
## peer's will replay what arrived over the wire.

## A disabled controller hands back an empty input: the body stands still (gravity still applies).
var enabled: bool = true


## Override: the body is the FighterBody asking; delta is the physics step.
func sample(_body: CharacterBody3D, _delta: float) -> FighterInput:
	return FighterInput.new()


## True for the one controller reading this machine's keyboard and mouse.
func is_local() -> bool:
	return false
