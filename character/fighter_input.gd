extends RefCounted
class_name FighterInput
## What a fighter wants to do this physics frame. A FighterBody reads nothing but this, so the
## same body serves the keyboard (LocalFighterController), a bot (BotBrain) or, later, a network
## peer that sends these over the wire.

## Movement relative to view_forward: x is right (+) / left (-), y is forward (+) / back (-).
var move: Vector2 = Vector2.ZERO
## The direction "forward" means for move (the camera's forward for a human, the heading a bot
## wants) and the matching up; the body flattens both onto the surface it stands on.
var view_forward: Vector3 = Vector3.FORWARD
var view_up: Vector3 = Vector3.UP
var run: bool = false
## Edge: pressed this frame. Jump on the ground, take off in the air (flyers), rise while flying.
var jump_pressed: bool = false
var jump_held: bool = false
## Edge: grab or let go of a climbable surface.
var climb_pressed: bool = false
var descend_held: bool = false
## Edge and hold for the trigger; automatic weapons keep firing while held.
var shoot_pressed: bool = false
var shoot_held: bool = false
## Over-the-shoulder stance: the body squares up to view_forward whichever way it moves.
var aiming: bool = false
## The camera is being dragged around the body: the body keeps its facing.
var orbiting: bool = false
## Where a shot leaves from and heads, in world space. Humans aim through the camera instead
## (has_aim false); bots and remote players supply the ray.
var has_aim: bool = false
var aim_origin: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.FORWARD


func is_moving() -> bool:
	return move.length_squared() > 0.0001
