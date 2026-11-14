@tool
extends RefCounted
## Watches the terrain library the editor runs (the debug one each platform lists in
## bin/terrain.gdextension) for a new build. The editor runs a copy taken when it started and
## the extension is not reloadable, so a new build only counts after a restart; the Terrain
## Editor plugin restarts the editor (saving the open scenes) once look() says so. A new stamp
## must hold still for STEADY_LOOKS looks first, so a library the linker is still writing is
## never picked up half done.

const LIBRARY_CONFIG: String = "res://bin/terrain.gdextension"
const STEADY_LOOKS: int = 2

## The stamp the editor started with, a newer one seen, and how many looks it has held still.
var _stamp: int = 0
var _newer: int = 0
var _steady: int = 0


func _init(stamp: int) -> void:
	_stamp = stamp


## One look at the library's stamp now: true once a newer one has held still long enough (and
## on every look after, until the restart).
func look(now: int) -> bool:
	if now == _stamp:
		_newer = 0
		_steady = 0
		return false
	if now != _newer:
		_newer = now
		_steady = 0
		return false
	_steady += 1
	return _steady >= STEADY_LOOKS


## The newest modified time of the debug libraries the config lists (0 when there are none).
static func library_stamp(config_path: String = LIBRARY_CONFIG) -> int:
	var config := ConfigFile.new()
	if config.load(config_path) != OK or not config.has_section("libraries"):
		return 0
	var newest: int = 0
	for key: String in config.get_section_keys("libraries"):
		if not key.contains(".debug"):
			continue
		var path: String = str(config.get_value("libraries", key))
		if FileAccess.file_exists(path):
			newest = maxi(newest, FileAccess.get_modified_time(path))
	return newest
