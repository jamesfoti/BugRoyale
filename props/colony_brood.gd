class_name ColonyBrood
extends RefCounted
## What the colony lives on, and grows by: the food its foragers carry to the entrance, the
## eggs the queen lays from it (one a day at most, each costing FOOD_PER_EGG), the room dug
## for them under the ground, and the workers the eggs become. An egg laid by day hatches at
## the next dawn if it is still there; the colony's size (workers up plus eggs waiting) never
## exceeds what the room allows: the founding four, plus one per ROOM_PER_WORKER_M3 dug below
## the surface once the nest itself is done. Pure numbers: Burrow owns one, the tests another.

## The numbers changed (a delivery, an egg, a hatching, a loss, new room).
signal changed

const STARTING_WORKERS: int = 4
const FOOD_PER_EGG: int = 6
const EGGS_PER_DAY: int = 1
const ROOM_PER_WORKER_M3: float = 40.0

## Food at the entrance, not yet turned into an egg.
var food: int = 0
## Eggs in the chamber, waiting for dawn.
var eggs: int = 0
## Eggs laid since the last dawn.
var laid_today: int = 0
## Cubic metres dug below the surface after the nest was finished.
var room_m3: float = 0.0


## How many the colony may be: workers up plus eggs waiting.
func capacity() -> int:
	return STARTING_WORKERS + int(room_m3 / ROOM_PER_WORKER_M3)


## Whether the queen can lay now, with this many workers up.
func can_lay(workers_alive: int) -> bool:
	return food >= FOOD_PER_EGG and laid_today < EGGS_PER_DAY and workers_alive + eggs < capacity()


## Lays an egg from the food in store; false (and nothing spent) when she cannot.
func lay(workers_alive: int) -> bool:
	if not can_lay(workers_alive):
		return false
	food -= FOOD_PER_EGG
	eggs += 1
	laid_today += 1
	changed.emit()
	return true


## Food carried to the entrance.
func deliver(count: int) -> void:
	if count <= 0:
		return
	food += count
	changed.emit()


## Dawn: every egg waiting hatches, and the queen may lay again. Returns how many hatched.
func dawn() -> int:
	var hatched: int = eggs
	eggs = 0
	laid_today = 0
	if hatched > 0:
		changed.emit()
	return hatched


## An egg destroyed in the chamber.
func lose_egg() -> void:
	if eggs <= 0:
		return
	eggs -= 1
	changed.emit()


## Ground dug out below the surface, in cubic metres.
func add_room(cubic_metres: float) -> void:
	if cubic_metres <= 0.0:
		return
	room_m3 += cubic_metres
	changed.emit()


## "Food 4  ·  Eggs 1" for the status line.
func text() -> String:
	return "Food %d  ·  Eggs %d" % [food, eggs]


func export_state() -> Dictionary:
	return {"food": food, "eggs": eggs, "laid_today": laid_today, "room_m3": room_m3}


func import_state(state: Dictionary) -> void:
	food = int(state.get("food", food))
	eggs = int(state.get("eggs", eggs))
	laid_today = int(state.get("laid_today", laid_today))
	room_m3 = float(state.get("room_m3", room_m3))
	changed.emit()
