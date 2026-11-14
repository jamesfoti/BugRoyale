extends GutTest
## The Terrain Editor's watch on the terrain library: a new build counts only once its stamp
## has held still, never on the stamp the editor started with, and the stamp is the newest
## debug library the extension config lists.

const LibraryWatch = preload("res://addons/terrain_editor/library_watch.gd")


func test_a_new_build_counts_once_it_holds_still() -> void:
	var watch: RefCounted = LibraryWatch.new(100)
	assert_false(watch.look(100), "the library the editor started with")
	assert_false(watch.look(105), "a new stamp, maybe still being written")
	assert_false(watch.look(106), "still changing")
	assert_false(watch.look(106), "holding still once")
	assert_true(watch.look(106), "holding still twice: restart")
	assert_true(watch.look(106), "and it keeps saying so until the restart")


func test_the_old_library_back_is_no_new_build() -> void:
	var watch: RefCounted = LibraryWatch.new(100)
	watch.look(105)
	watch.look(105)
	assert_false(watch.look(100), "the stamp went back to the one the editor runs")
	assert_false(watch.look(100))
	assert_false(watch.look(100))


func test_the_stamp_is_the_newest_debug_library_listed() -> void:
	var stamp: int = LibraryWatch.library_stamp()
	assert_gt(stamp, 0, "this platform's debug library is there")
	var config := ConfigFile.new()
	config.load(LibraryWatch.LIBRARY_CONFIG)
	var newest: int = 0
	for key: String in config.get_section_keys("libraries"):
		var path: String = str(config.get_value("libraries", key))
		if key.contains(".debug") and FileAccess.file_exists(path):
			newest = maxi(newest, FileAccess.get_modified_time(path))
	assert_eq(stamp, newest)
	assert_eq(LibraryWatch.library_stamp("res://no_such.gdextension"), 0)
