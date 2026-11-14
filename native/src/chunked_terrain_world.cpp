#include "chunked_terrain_world.h"

#include "cave_carver.h"
#include "materials.h"

#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <tuple>

namespace godot {

static int64_t column_key(int x, int z) {
	return ((int64_t)x << 32) ^ (int64_t)(uint32_t)z;
}

static bool editor_hint() {
	return Engine::get_singleton()->is_editor_hint();
}

static uint64_t ticks_usec() {
	return Time::get_singleton()->get_ticks_usec();
}

int ChunkedTerrainWorld::world_build_in_flight() {
	static int value = 0;
	if (value == 0) {
		int cores = OS::get_singleton()->get_processor_count();
		value = CLAMP(cores - 4, 4, 12);
	}
	return value;
}

ChunkedTerrainWorld::ChunkedTerrainWorld() {
	edits.instantiate();
}

ChunkedTerrainWorld::~ChunkedTerrainWorld() {
	abandon_world_build();
	reset_stream();
	for (std::unique_ptr<BuildJob> &job : async_jobs) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
	}
	async_jobs.clear();
}

// --- Lifetime ---------------------------------------------------------------------------------

void ChunkedTerrainWorld::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
			set_process(true);
			set_physics_process(true);
			on_ready();
			break;
		case NOTIFICATION_PROCESS:
			process_frame();
			break;
		case NOTIFICATION_PHYSICS_PROCESS:
			physics_frame();
			break;
		case NOTIFICATION_EXIT_TREE:
			abandon_world_build();
			reset_stream();
			break;
		default:
			break;
	}
}

void ChunkedTerrainWorld::on_ready() {
	_ensure_world_defaults();
	if (is_playable_world) {
		add_to_group("terrain_world");
		_register_playable_groups();
	}
	if (rebuild_on_ready && !editor_hint()) {
		call_deferred("begin_build");
	}
}

void ChunkedTerrainWorld::process_frame() {
	if (editor_hint()) {
		return;
	}
	if (streaming()) {
		poll_stream();
	}
	if (world_building) {
		poll_world_build();
	}
	if (streaming()) {
		fill_stream();
	}
	poll_async_rebuilds();
	if (async_rebuild_requested) {
		async_rebuild_requested = false;
		_dispatch_pending_rebuilds();
	}
}

void ChunkedTerrainWorld::physics_frame() {
	if (editor_hint()) {
		return;
	}
	if (streaming()) {
		stream_tick += 1;
		if (stream_tick % STREAM_EVERY == 1) {
			look_for_streamed_chunks();
		}
	}
	if (world_building && !play_waiting) {
		order_tick += 1;
		if (order_tick % ORDER_EVERY == 1) {
			follow_local_player();
		}
	}
	if (streaming() || world_building) {
		hold_bodies_off_missing_ground();
	}
}

void ChunkedTerrainWorld::destroy_all() {
	clear_chunks();
	if (editor_hint()) {
		UtilityFunctions::print("[" + _get_world_log_name() + "] Destroyed terrain (editor)");
	}
}

void ChunkedTerrainWorld::rebuild_all() {
	abandon_world_build();
	_invalidate_bake_density();
	_ensure_world_defaults();
	clear_chunks();
	Ref<TerrainSettings> settings = _make_settings_snapshot();
	Vector3i grid_dimensions = _get_grid_dimensions();
	world_build_grid = grid_dimensions;
	// The deep marks are only the build's order; what is streamed stays measured.
	mark_deep_chunks(settings, grid_dimensions);
	deep.clear();
	rebuild_all_sync(settings, grid_dimensions);
}

// --- The build ----------------------------------------------------------------------------------

void ChunkedTerrainWorld::focus_build_at(const Vector3 &world_position, double radius, bool primary) {
	Vector4 focus = Vector4(world_position.x, world_position.y, world_position.z, (real_t)radius);
	build_focus.push_back(focus);
	double reach = radius;
	if (primary) {
		primary_focus.clear();
		primary_focus.push_back(focus);
		reach = tmath::maxd(radius, play_ring);
	}
	for (const Vector2i &column : _columns_touching(world_position, reach)) {
		if (play_column(column)) {
			continue;
		}
		Vector3i grid = _get_grid_dimensions();
		if ((int)play_columns.size() != grid.x * grid.z) {
			play_columns.assign(grid.x * grid.z, 0);
			play_column_count = 0;
		}
		play_columns[column.x + column.y * grid.x] = 1;
		play_column_count += 1;
	}
	for (const Vector3i &chunk_coordinate : _chunks_touching(world_position, radius)) {
		play_chunks.insert(chunk_coordinate);
	}
	if (world_building) {
		queue_stale = true;
	}
}

bool ChunkedTerrainWorld::play_column(const Vector2i &column) const {
	Vector3i grid = _get_grid_dimensions();
	if ((int)play_columns.size() != grid.x * grid.z || column.x < 0 || column.y < 0 || column.x >= grid.x ||
			column.y >= grid.z) {
		return false;
	}
	return play_columns[column.x + column.y * grid.x] != 0;
}

bool ChunkedTerrainWorld::is_ground_ready_around(const Vector3 &world_position, double radius) {
	if (!world_building && !streaming()) {
		return true;
	}
	return ground_complete(_ground_round(world_position, radius));
}

bool ChunkedTerrainWorld::play_ground_ready() {
	if (!world_building) {
		return true;
	}
	if (play_column_count == 0) {
		return false;
	}
	return ground_complete(play_ground());
}

double ChunkedTerrainWorld::get_built_reach(const Vector3 &world_position) const {
	if (!world_building || column_missing.empty()) {
		return tmath::INF_D;
	}
	double extent = world_build_settings.is_valid() ? world_build_settings->chunk_world_size : chunk_size;
	Vector3 origin = get_global_position() + _chunk_corner_local(Vector3i(), world_build_settings);
	Vector2 point = Vector2(world_position.x - origin.x, world_position.z - origin.z);
	double nearest = tmath::INF_D;
	for (int column_z = 0; column_z < world_build_grid.z; column_z++) {
		for (int column_x = 0; column_x < world_build_grid.x; column_x++) {
			if (column_missing[column_index(column_x, column_z)] <= 0) {
				continue;
			}
			Vector2 low = Vector2((real_t)column_x, (real_t)column_z) * (real_t)extent;
			Vector2 closest = point.clamp(low, low + Vector2(1, 1) * (real_t)extent);
			nearest = tmath::mind(nearest, point.distance_to(closest));
		}
	}
	return nearest;
}

ChunkedTerrainWorld::CoordSet ChunkedTerrainWorld::_ground_round(const Vector3 &world_position, double radius) {
	CoordSet out;
	for (const Vector2i &column : _columns_touching(world_position, radius)) {
		add_surface_band(column, out);
	}
	for (const Vector3i &chunk_coordinate : _chunks_touching(world_position, radius)) {
		out.insert(chunk_coordinate);
	}
	return out;
}

ChunkedTerrainWorld::CoordSet ChunkedTerrainWorld::play_ground() {
	CoordSet out = play_chunks;
	Vector3i grid = _get_grid_dimensions();
	if ((int)play_columns.size() == grid.x * grid.z) {
		for (int z = 0; z < grid.z; z++) {
			for (int x = 0; x < grid.x; x++) {
				if (play_columns[x + z * grid.x]) {
					add_surface_band(Vector2i(x, z), out);
				}
			}
		}
	}
	return out;
}

void ChunkedTerrainWorld::add_surface_band(const Vector2i &column, CoordSet &out) const {
	for (int chunk_y = streamed_below(column); chunk_y < world_build_grid.y; chunk_y++) {
		Vector3i chunk_coordinate(column.x, chunk_y, column.y);
		if (!deep.count(chunk_coordinate)) {
			out.insert(chunk_coordinate);
		}
	}
}

bool ChunkedTerrainWorld::ground_complete(const CoordSet &set) const {
	for (const Vector3i &chunk_coordinate : set) {
		if (!_stands(chunk_coordinate) || pending_rebuilds.count(chunk_coordinate) ||
				inflight_chunk_coordinates.count(chunk_coordinate)) {
			return false;
		}
	}
	return true;
}

bool ChunkedTerrainWorld::_stands(const Vector3i &chunk_coordinate) const {
	if (_is_streamed(chunk_coordinate)) {
		return stream_loaded.count(chunk_coordinate) > 0;
	}
	return !world_building || placed.count(chunk_coordinate) > 0;
}

Ref<TerrainSettings> ChunkedTerrainWorld::_build_settings() {
	return world_build_settings.is_valid() ? world_build_settings : _make_settings_snapshot();
}

void ChunkedTerrainWorld::begin_build() {
	if (!use_threaded()) {
		rebuild_all();
		return;
	}
	abandon_world_build();
	_invalidate_bake_density();
	_ensure_world_defaults();
	clear_chunks();
	world_build_settings = _make_settings_snapshot();
	world_build_grid = _get_grid_dimensions();
	mark_deep_chunks(world_build_settings, world_build_grid);
	queue_every_chunk();
	world_build_total = (int)world_build_queue.size();
	world_build_placed = 0;
	placed.clear();
	placed_order.clear();
	count_missing_columns();
	order_focus.clear();
	order_tick = 0;
	world_build_started_msec = Time::get_singleton()->get_ticks_msec();
	world_building = true;
	sort_world_build_queue();
	fill_world_build();
	emit_build_progress();
}

void ChunkedTerrainWorld::queue_every_chunk() {
	world_build_queue.clear();
	for (int chunk_z = 0; chunk_z < world_build_grid.z; chunk_z++) {
		for (int chunk_y = 0; chunk_y < world_build_grid.y; chunk_y++) {
			for (int chunk_x = 0; chunk_x < world_build_grid.x; chunk_x++) {
				Vector3i chunk_coordinate(chunk_x, chunk_y, chunk_z);
				if (!_is_streamed(chunk_coordinate)) {
					world_build_queue.push_back(chunk_coordinate);
				}
			}
		}
	}
}

void ChunkedTerrainWorld::mark_deep_chunks(const Ref<TerrainSettings> &settings, const Vector3i &grid) {
	deep.clear();
	stream_floor.clear();
	stream_grid = grid;
	Ref<WorldDensity> density = _get_bake_density();
	if (!density->open_terrain_enabled || grid.y < 2) {
		return;
	}
	std::vector<int> floors;
	if (stream_underground) {
		floors.assign(grid.x * grid.z, 0);
	}
	double extent = settings->chunk_world_size;
	Vector3 origin = get_global_position() + _chunk_corner_local(Vector3i(), settings);
	for (int column_x = 0; column_x < grid.x; column_x++) {
		for (int column_z = 0; column_z < grid.z; column_z++) {
			double lowest = tmath::INF_D;
			for (int sample_x = 0; sample_x < 3; sample_x++) {
				for (int sample_z = 0; sample_z < 3; sample_z++) {
					lowest = tmath::mind(lowest,
							density->sample_open_terrain_height(
									(double)origin.x + ((double)column_x + 0.5 * (double)sample_x) * extent,
									(double)origin.z + ((double)column_z + 0.5 * (double)sample_z) * extent));
				}
			}
			int streamed = 0;
			for (int chunk_y = 0; chunk_y < grid.y; chunk_y++) {
				double top = (double)origin.y + (double)(chunk_y + 1) * extent;
				if (top <= lowest - DEEP_MARGIN) {
					deep.insert(Vector3i(column_x, chunk_y, column_z));
				}
				if (top <= lowest - STREAM_MARGIN) {
					streamed = chunk_y + 1;
				}
			}
			if (stream_underground) {
				floors[column_x + column_z * grid.x] = streamed;
			}
		}
	}
	stream_floor = floors;
}

void ChunkedTerrainWorld::count_missing_columns() {
	column_missing.assign(world_build_grid.x * world_build_grid.z, 0);
	for (const Vector3i &chunk_coordinate : world_build_queue) {
		if (!deep.count(chunk_coordinate)) {
			column_missing[column_index(chunk_coordinate.x, chunk_coordinate.z)] += 1;
		}
	}
}

bool ChunkedTerrainWorld::job_done(BuildJob *job) {
	if (job->collected) {
		return true;
	}
	if (!WorkerThreadPool::get_singleton()->is_task_completed(job->task_id)) {
		return false;
	}
	WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
	job->collected = true;
	return true;
}

void ChunkedTerrainWorld::poll_world_build() {
	uint64_t deadline = ticks_usec() + PLACE_BUDGET_USEC;
	for (size_t i = 0; i < world_build_tasks.size();) {
		if (ticks_usec() >= deadline) {
			break;
		}
		BuildJob *job = world_build_tasks[i].get();
		if (!job_done(job)) {
			i++;
			continue;
		}
		while (job->placed < (int)job->chunk_coordinates.size() && ticks_usec() < deadline) {
			place_built_chunk(job, job->placed);
			job->placed += 1;
		}
		if (job->placed >= (int)job->chunk_coordinates.size()) {
			world_build_tasks.erase(world_build_tasks.begin() + i);
		} else {
			i++;
		}
	}
	fill_world_build();
	emit_build_progress();
	if (world_build_placed < world_build_total || !world_build_tasks.empty()) {
		return;
	}
	log_rebuild_complete((int)chunks.size(), world_build_settings, world_build_grid,
			(int64_t)Time::get_singleton()->get_ticks_msec() - world_build_started_msec);
	world_building = false;
	world_build_settings.unref();
	build_focus.clear();
	primary_focus.clear();
	order_focus.clear();
	play_columns.clear();
	play_column_count = 0;
	play_chunks.clear();
	deep.clear();
	column_missing.clear();
	emit_signal("built");
}

void ChunkedTerrainWorld::place_built_chunk(BuildJob *job, int index) {
	Vector3i chunk_coordinate = job->chunk_coordinates[index];
	if (placed.count(chunk_coordinate)) {
		return;
	}
	build_chunk_at(chunk_coordinate, job->results[index], job->settings);
	note_placed_chunk(chunk_coordinate);
	emit_signal("ground_placed", _get_chunk_world_aabb(chunk_coordinate, job->settings));
}

void ChunkedTerrainWorld::note_placed_chunk(const Vector3i &chunk_coordinate) {
	if (placed.count(chunk_coordinate)) {
		return;
	}
	placed.insert(chunk_coordinate);
	placed_order.push_back(chunk_coordinate);
	world_build_placed += 1;
	if (!deep.count(chunk_coordinate) && !column_missing.empty()) {
		column_missing[column_index(chunk_coordinate.x, chunk_coordinate.z)] -= 1;
	}
}

void ChunkedTerrainWorld::submit(std::vector<std::unique_ptr<BuildJob>> &tasks, std::unique_ptr<BuildJob> job,
		const String &description) {
	BuildJob *raw = job.get();
	raw->task_id = WorkerThreadPool::get_singleton()->add_native_task(&BuildJob::run, raw, true, description);
	tasks.push_back(std::move(job));
}

void ChunkedTerrainWorld::fill_world_build() {
	if (queue_stale) {
		sort_world_build_queue();
	}
	int in_flight = world_build_in_flight();
	int places = in_flight;
	if (stream_waiting()) {
		places -= play_waiting ? STREAM_TASKS_BEFORE_PLAY : in_flight - 1;
	}
	while ((int)world_build_tasks.size() < places && pool_load() < in_flight) {
		if (world_build_queue.empty()) {
			return;
		}
		std::unique_ptr<BuildJob> job = std::make_unique<BuildJob>();
		int wanted = build_task_chunks();
		while ((int)job->chunk_coordinates.size() < wanted && !world_build_queue.empty()) {
			Vector3i chunk_coordinate = world_build_queue.back();
			world_build_queue.pop_back();
			if (placed.count(chunk_coordinate) || inflight_chunk_coordinates.count(chunk_coordinate)) {
				continue;
			}
			// The edits so far go into this chunk's snapshot.
			pending_rebuilds.erase(chunk_coordinate);
			job->chunk_coordinates.push_back(chunk_coordinate);
		}
		if (job->chunk_coordinates.empty()) {
			continue;
		}
		job->settings = _make_thread_settings_snapshot();
		submit(world_build_tasks, std::move(job), _get_world_log_name() + " chunk build");
	}
}

int ChunkedTerrainWorld::build_task_chunks() const {
	int cells = world_build_settings->cells_per_axis;
	int samples = (cells + 1) * (cells + 1) * (cells + 1);
	return CLAMP(BUILD_TASK_SAMPLES / samples, 1, MAX(world_build_total / 64, 1));
}

void ChunkedTerrainWorld::sort_world_build_queue() {
	queue_stale = false;
	double extent = world_build_settings->chunk_world_size;
	Vector3 origin = get_global_position() + _chunk_corner_local(Vector3i(), world_build_settings);
	struct Keyed {
		int group;
		double distance;
		int neg_y;
		int x;
		int z;
		Vector3i coordinate;
	};
	std::vector<Keyed> keyed;
	keyed.reserve(world_build_queue.size());
	for (const Vector3i &c : world_build_queue) {
		Vector2 centre = Vector2((real_t)((double)origin.x + ((double)c.x + 0.5) * extent),
				(real_t)((double)origin.z + ((double)c.z + 0.5) * extent));
		keyed.push_back({ _build_group(c), focus_distance(centre), -c.y, c.x, c.z, c });
	}
	std::sort(keyed.begin(), keyed.end(), [](const Keyed &a, const Keyed &b) {
		return std::tie(a.group, a.distance, a.neg_y, a.x, a.z) < std::tie(b.group, b.distance, b.neg_y, b.x, b.z);
	});
	world_build_queue.clear();
	for (auto it = keyed.rbegin(); it != keyed.rend(); ++it) {
		world_build_queue.push_back(it->coordinate);
	}
}

int ChunkedTerrainWorld::_build_group(const Vector3i &chunk_coordinate) const {
	if (play_chunks.count(chunk_coordinate)) {
		return 0;
	}
	int is_deep = deep.count(chunk_coordinate) ? 1 : 0;
	if (play_column(Vector2i(chunk_coordinate.x, chunk_coordinate.z))) {
		return is_deep;
	}
	return 2 + is_deep;
}

double ChunkedTerrainWorld::focus_distance(const Vector2 &column_centre) const {
	const std::vector<Vector4> *foci = &order_focus;
	if (foci->empty()) {
		foci = !primary_focus.empty() ? &primary_focus : &build_focus;
	}
	if (foci->empty()) {
		Vector3 at = get_global_position();
		return column_centre.distance_to(Vector2(at.x, at.z));
	}
	double nearest = tmath::INF_D;
	for (const Vector4 &focus : *foci) {
		double distance = (double)column_centre.distance_to(Vector2(focus.x, focus.z)) - (double)focus.w;
		nearest = tmath::mind(nearest, tmath::maxd(distance, 0.0));
	}
	return nearest;
}

void ChunkedTerrainWorld::chunk_span(const Vector3 &world_position, double radius, Vector3i &low, Vector3i &high) {
	double extent = world_build_settings.is_valid() ? world_build_settings->chunk_world_size : chunk_size;
	Vector3i grid = _get_grid_dimensions();
	Vector3 origin = get_global_position() + _chunk_corner_local(Vector3i(), world_build_settings);
	Vector3 low_f = ((world_position - Vector3(1, 1, 1) * (real_t)radius - origin) / (real_t)extent).floor();
	Vector3 high_f = ((world_position + Vector3(1, 1, 1) * (real_t)radius - origin) / (real_t)extent).floor();
	low = Vector3i((int)low_f.x, (int)low_f.y, (int)low_f.z).max(Vector3i());
	high = Vector3i((int)high_f.x, (int)high_f.y, (int)high_f.z).min(grid - Vector3i(1, 1, 1));
}

std::vector<Vector2i> ChunkedTerrainWorld::_columns_touching(const Vector3 &world_position, double radius) {
	Vector3i low;
	Vector3i high;
	chunk_span(world_position, radius, low, high);
	std::vector<Vector2i> columns;
	for (int column_x = low.x; column_x < high.x + 1; column_x++) {
		for (int column_z = low.z; column_z < high.z + 1; column_z++) {
			columns.push_back(Vector2i(column_x, column_z));
		}
	}
	return columns;
}

std::vector<Vector3i> ChunkedTerrainWorld::_chunks_touching(const Vector3 &world_position, double radius) {
	Vector3i low;
	Vector3i high;
	chunk_span(world_position, radius, low, high);
	std::vector<Vector3i> out;
	for (int chunk_x = low.x; chunk_x < high.x + 1; chunk_x++) {
		for (int chunk_y = low.y; chunk_y < high.y + 1; chunk_y++) {
			for (int chunk_z = low.z; chunk_z < high.z + 1; chunk_z++) {
				out.push_back(Vector3i(chunk_x, chunk_y, chunk_z));
			}
		}
	}
	return out;
}

void ChunkedTerrainWorld::emit_build_progress() {
	play_waiting = world_building && !play_ground_ready();
	if (!play_waiting || world_build_placed >= world_build_total) {
		emit_signal("build_progress", MIN(world_build_placed, world_build_total), world_build_total);
		return;
	}
	int play_done = 0;
	int play_total = 0;
	for (const Vector3i &chunk_coordinate : play_ground()) {
		play_total += 1;
		if (_stands(chunk_coordinate)) {
			play_done += 1;
		}
	}
	if (play_column_count == 0) {
		double extent = world_build_settings.is_valid() ? world_build_settings->chunk_world_size : chunk_size;
		int ring = tmath::ceili(play_ring / extent);
		int band = tmath::ceili((double)world_build_total / (double)MAX(world_build_grid.x * world_build_grid.z, 1));
		play_total = (2 * ring + 1) * (2 * ring + 1) * band;
	}
	emit_signal("build_progress", play_done, play_total);
}

void ChunkedTerrainWorld::follow_local_player() {
	TypedArray<Node> fighters = get_tree()->get_nodes_in_group("fighter");
	for (int i = 0; i < fighters.size(); i++) {
		Node3D *body = Object::cast_to<Node3D>(fighters[i]);
		if (body != nullptr && body->is_inside_tree() && is_local_body(body)) {
			Vector3 at = body->get_global_position();
			order_focus.clear();
			order_focus.push_back(Vector4(at.x, at.y, at.z, 0.0f));
			queue_stale = true;
			return;
		}
	}
}

// --- Streaming the underground ------------------------------------------------------------------

bool ChunkedTerrainWorld::streaming() const {
	return stream_underground && !stream_floor.empty() && !editor_hint();
}

bool ChunkedTerrainWorld::_is_streamed(const Vector3i &chunk_coordinate) const {
	if (stream_floor.empty()) {
		return false;
	}
	if (chunk_coordinate.x < 0 || chunk_coordinate.z < 0 || chunk_coordinate.x >= stream_grid.x ||
			chunk_coordinate.z >= stream_grid.z) {
		return false;
	}
	return chunk_coordinate.y < stream_floor[chunk_coordinate.x + chunk_coordinate.z * stream_grid.x];
}

int ChunkedTerrainWorld::streamed_below(const Vector2i &column) const {
	if (stream_floor.empty() || column.x < 0 || column.y < 0 || column.x >= stream_grid.x || column.y >= stream_grid.z) {
		return 0;
	}
	return stream_floor[column.x + column.y * stream_grid.x];
}

Vector3 ChunkedTerrainWorld::_grid_corner() const {
	return get_global_position() - Vector3(stream_grid) * (real_t)chunk_size * 0.5f;
}

bool ChunkedTerrainWorld::is_local_body(Node3D *body) {
	Variant local = body->get("is_local");
	if (local.get_type() == Variant::BOOL) {
		return (bool)local;
	}
	return body->is_in_group("player");
}

void ChunkedTerrainWorld::look_for_streamed_chunks() {
	CoordMap<double> wanted;
	CoordSet keep;
	TypedArray<Node> fighters = get_tree()->get_nodes_in_group("fighter");
	for (int i = 0; i < fighters.size(); i++) {
		Node3D *body = Object::cast_to<Node3D>(fighters[i]);
		if (body == nullptr || !body->is_inside_tree()) {
			continue;
		}
		double reach = is_local_body(body) ? STREAM_VIEW : STREAM_BODY;
		want_round(body->get_global_position(), reach, wanted, keep);
	}
	for (const Vector4 &focus : build_focus) {
		want_round(Vector3(focus.x, focus.y, focus.z), tmath::maxd(focus.w, 0.0) + STREAM_BODY, wanted, keep);
	}
	std::vector<Vector3i> loaded(stream_loaded.begin(), stream_loaded.end());
	for (const Vector3i &chunk_coordinate : loaded) {
		if (!keep.count(chunk_coordinate)) {
			free_streamed_chunk(chunk_coordinate);
		}
	}
	stream_wanted = wanted;
	stream_keep = keep;
	std::vector<std::pair<double, Vector3i>> keyed;
	for (const auto &entry : wanted) {
		if (stream_loaded.count(entry.first) || stream_inflight.count(entry.first)) {
			continue;
		}
		keyed.push_back({ -entry.second, entry.first });
	}
	std::sort(keyed.begin(), keyed.end(), [](const auto &a, const auto &b) {
		if (a.first != b.first) {
			return a.first < b.first;
		}
		return a.second < b.second;
	});
	stream_queue.clear();
	for (const auto &entry : keyed) {
		stream_queue.push_back(entry.second);
	}
}

void ChunkedTerrainWorld::want_round(const Vector3 &point, double reach, CoordMap<double> &wanted, CoordSet &keep) const {
	double extent = chunk_size;
	Vector3 corner = _grid_corner();
	double far = reach + STREAM_KEEP;
	Vector3 low_f = ((point - Vector3(1, 1, 1) * (real_t)far - corner) / (real_t)extent).floor();
	Vector3 high_f = ((point + Vector3(1, 1, 1) * (real_t)far - corner) / (real_t)extent).floor();
	Vector3i low = Vector3i((int)low_f.x, (int)low_f.y, (int)low_f.z).max(Vector3i());
	Vector3i high = Vector3i((int)high_f.x, (int)high_f.y, (int)high_f.z).min(stream_grid - Vector3i(1, 1, 1));
	for (int chunk_x = low.x; chunk_x < high.x + 1; chunk_x++) {
		for (int chunk_z = low.z; chunk_z < high.z + 1; chunk_z++) {
			int floor_y = stream_floor[chunk_x + chunk_z * stream_grid.x];
			for (int chunk_y = low.y; chunk_y < MIN(high.y, floor_y - 1) + 1; chunk_y++) {
				Vector3i chunk_coordinate(chunk_x, chunk_y, chunk_z);
				Vector3 chunk_low = corner + Vector3(chunk_coordinate) * (real_t)extent;
				Vector3 nearest = point.clamp(chunk_low, chunk_low + Vector3(1, 1, 1) * (real_t)extent);
				double distance = point.distance_to(nearest);
				if (distance > far) {
					continue;
				}
				keep.insert(chunk_coordinate);
				auto found = wanted.find(chunk_coordinate);
				if (distance <= reach && (found == wanted.end() || distance < found->second)) {
					wanted[chunk_coordinate] = distance;
				}
			}
		}
	}
}

void ChunkedTerrainWorld::free_streamed_chunk(const Vector3i &chunk_coordinate) {
	auto found = chunks.find(chunk_coordinate);
	if (found != chunks.end() && found->second != nullptr) {
		remove_child(found->second);
		found->second->queue_free();
	}
	chunks.erase(chunk_coordinate);
	stream_loaded.erase(chunk_coordinate);
	field_cache.erase(chunk_coordinate);
	pending_rebuilds.erase(chunk_coordinate);
}

void ChunkedTerrainWorld::fill_stream() {
	int cells = get_cells_per_axis();
	int samples = (cells + 1) * (cells + 1) * (cells + 1);
	int per_task = CLAMP(BUILD_TASK_SAMPLES / samples, 1, 8);
	bool holding_back = world_building && play_waiting;
	int in_flight = world_build_in_flight();
	while (stream_waiting() && pool_load() < in_flight) {
		if (holding_back && (int)stream_tasks.size() >= STREAM_TASKS_BEFORE_PLAY) {
			return;
		}
		std::unique_ptr<BuildJob> job = std::make_unique<BuildJob>();
		while ((int)job->chunk_coordinates.size() < per_task && stream_waiting()) {
			Vector3i chunk_coordinate = stream_queue.back();
			stream_queue.pop_back();
			if (stream_loaded.count(chunk_coordinate) || stream_inflight.count(chunk_coordinate) ||
					inflight_chunk_coordinates.count(chunk_coordinate) || !stream_wanted.count(chunk_coordinate)) {
				continue;
			}
			pending_rebuilds.erase(chunk_coordinate);
			stream_inflight.insert(chunk_coordinate);
			job->chunk_coordinates.push_back(chunk_coordinate);
		}
		if (job->chunk_coordinates.empty()) {
			continue;
		}
		job->settings = _make_thread_settings_snapshot();
		submit(stream_tasks, std::move(job), _get_world_log_name() + " streamed chunk");
	}
}

bool ChunkedTerrainWorld::stream_waiting() const {
	if (stream_queue.empty()) {
		return false;
	}
	if (!(world_building && play_waiting)) {
		return true;
	}
	auto found = stream_wanted.find(stream_queue.back());
	double distance = found == stream_wanted.end() ? tmath::INF_D : found->second;
	return distance <= STREAM_URGENT;
}

void ChunkedTerrainWorld::poll_stream() {
	uint64_t deadline = ticks_usec() + PLACE_BUDGET_USEC;
	for (size_t i = 0; i < stream_tasks.size();) {
		if (ticks_usec() >= deadline) {
			break;
		}
		BuildJob *job = stream_tasks[i].get();
		if (!job_done(job)) {
			i++;
			continue;
		}
		while (job->placed < (int)job->chunk_coordinates.size() && ticks_usec() < deadline) {
			Vector3i chunk_coordinate = job->chunk_coordinates[job->placed];
			Ref<ChunkBuildResult> result = job->results[job->placed];
			job->placed += 1;
			stream_inflight.erase(chunk_coordinate);
			if (!stream_keep.count(chunk_coordinate) || stream_loaded.count(chunk_coordinate)) {
				continue;
			}
			build_chunk_at(chunk_coordinate, result, job->settings);
			stream_loaded.insert(chunk_coordinate);
			emit_signal("ground_placed", _get_chunk_world_aabb(chunk_coordinate, job->settings));
		}
		if (job->placed >= (int)job->chunk_coordinates.size()) {
			stream_tasks.erase(stream_tasks.begin() + i);
		} else {
			i++;
		}
	}
}

void ChunkedTerrainWorld::reset_stream() {
	for (std::unique_ptr<BuildJob> &job : stream_tasks) {
		if (!job->collected) {
			WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
		}
	}
	stream_tasks.clear();
	stream_inflight.clear();
	stream_loaded.clear();
	stream_wanted.clear();
	stream_keep.clear();
	stream_queue.clear();
	stream_tick = 0;
}

bool ChunkedTerrainWorld::ground_missing_under(Node3D *body) {
	if (body == nullptr || !(world_building || streaming())) {
		return false;
	}
	Vector3 feet = body->get_global_position();
	double fall = 0.0;
	CharacterBody3D *character = Object::cast_to<CharacterBody3D>(body);
	if (character != nullptr) {
		fall = tmath::maxd(-(double)character->get_velocity().y, 0.0) * 0.25;
	}
	double reach = GROUND_HOLD_REACH;
	Vector3 corner = _grid_corner();
	Vector3 low_point = v3((double)feet.x - reach, (double)feet.y - reach - fall, (double)feet.z - reach);
	Vector3 high_point = v3((double)feet.x + reach, (double)feet.y + reach, (double)feet.z + reach);
	Vector3 low_f = ((low_point - corner) / (real_t)chunk_size).floor();
	Vector3 high_f = ((high_point - corner) / (real_t)chunk_size).floor();
	Vector3i low = Vector3i((int)low_f.x, (int)low_f.y, (int)low_f.z).max(Vector3i());
	Vector3i high = Vector3i((int)high_f.x, (int)high_f.y, (int)high_f.z).min(stream_grid - Vector3i(1, 1, 1));
	for (int chunk_x = low.x; chunk_x < high.x + 1; chunk_x++) {
		for (int chunk_z = low.z; chunk_z < high.z + 1; chunk_z++) {
			for (int chunk_y = low.y; chunk_y < high.y + 1; chunk_y++) {
				if (!_stands(Vector3i(chunk_x, chunk_y, chunk_z))) {
					return true;
				}
			}
		}
	}
	return false;
}

void ChunkedTerrainWorld::hold_bodies_off_missing_ground() {
	TypedArray<Node> fighters = get_tree()->get_nodes_in_group("fighter");
	for (int i = 0; i < fighters.size(); i++) {
		Node3D *body = Object::cast_to<Node3D>(fighters[i]);
		if (body == nullptr || !body->has_method("hold_for_ground")) {
			continue;
		}
		if (ground_missing_under(body)) {
			body->call("hold_for_ground");
		}
	}
}

void ChunkedTerrainWorld::abandon_world_build() {
	if (!world_building) {
		return;
	}
	for (std::unique_ptr<BuildJob> &job : world_build_tasks) {
		if (!job->collected) {
			WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
		}
	}
	world_build_tasks.clear();
	world_build_queue.clear();
	world_building = false;
	placed.clear();
	placed_order.clear();
	column_missing.clear();
	world_build_settings.unref();
	build_focus.clear();
	primary_focus.clear();
	order_focus.clear();
	play_columns.clear();
	play_column_count = 0;
	play_chunks.clear();
	deep.clear();
	queue_stale = false;
}

// --- Blocking build -------------------------------------------------------------------------------

struct ParallelJob {
	std::vector<Vector3i> chunk_coordinates;
	std::vector<Ref<ChunkBuildResult>> results;
	Ref<TerrainSettings> settings;

	static void run_element(void *userdata, uint32_t index) {
		ParallelJob *job = static_cast<ParallelJob *>(userdata);
		job->results[index] = ChunkMeshBuilder::build_chunk(job->chunk_coordinates[index], job->settings);
	}
};

void ChunkedTerrainWorld::rebuild_all_sync(const Ref<TerrainSettings> &settings, const Vector3i &grid_dimensions) {
	uint64_t start = Time::get_singleton()->get_ticks_msec();
	ParallelJob job;
	job.settings = settings;
	for (int chunk_z = 0; chunk_z < grid_dimensions.z; chunk_z++) {
		for (int chunk_y = 0; chunk_y < grid_dimensions.y; chunk_y++) {
			for (int chunk_x = 0; chunk_x < grid_dimensions.x; chunk_x++) {
				Vector3i chunk_coordinate(chunk_x, chunk_y, chunk_z);
				if (_is_streamed(chunk_coordinate)) {
					continue;
				}
				job.chunk_coordinates.push_back(chunk_coordinate);
			}
		}
	}
	job.results.resize(job.chunk_coordinates.size());
	if (use_threaded_rebuild && job.chunk_coordinates.size() > 1) {
		int64_t group = WorkerThreadPool::get_singleton()->add_native_group_task(&ParallelJob::run_element, &job,
				(int)job.chunk_coordinates.size(), -1, true, _get_world_log_name() + " chunk rebuild");
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group);
	} else {
		for (uint32_t i = 0; i < job.chunk_coordinates.size(); i++) {
			ParallelJob::run_element(&job, i);
		}
	}
	for (size_t i = 0; i < job.chunk_coordinates.size(); i++) {
		build_chunk_at(job.chunk_coordinates[i], job.results[i], settings);
	}
	log_rebuild_complete((int)chunks.size(), settings, grid_dimensions,
			(int64_t)(Time::get_singleton()->get_ticks_msec() - start));
	int count = (int)job.chunk_coordinates.size();
	emit_signal("build_progress", count * 2, count * 2);
	emit_signal("built");
}

void ChunkedTerrainWorld::build_chunk_at(const Vector3i &chunk_coordinate, const Ref<ChunkBuildResult> &result,
		const Ref<TerrainSettings> &settings) {
	TerrainChunk *chunk = memnew(TerrainChunk);
	chunk->set_name("Chunk_" + itos(chunk_coordinate.x) + "_" + itos(chunk_coordinate.y) + "_" + itos(chunk_coordinate.z));
	chunk->chunk_coordinate = chunk_coordinate;
	if (!is_playable_world) {
		chunk->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	}
	add_child(chunk);
	chunk->apply_build_result(result, settings->rebuild_collision);
	if (settings->material.is_valid()) {
		chunk->set_material_override(settings->material);
	}
	// Built chunks are never part of the edited scene (no owner): the editor's Scene dock does
	// not list hundreds of them (its rows broke on a rebuild of them all) and a save leaves them
	// out.
	auto found = chunks.find(chunk_coordinate);
	if (found != chunks.end() && found->second != nullptr && found->second != chunk &&
			found->second->get_parent() == this) {
		// A chunk already stood here (a blocking rebuild over one in the tree): it goes.
		remove_child(found->second);
		found->second->queue_free();
	}
	chunks[chunk_coordinate] = chunk;
}

void ChunkedTerrainWorld::log_rebuild_complete(int chunk_count, const Ref<TerrainSettings> &settings,
		const Vector3i &grid_dimensions, int64_t elapsed_ms) {
	String line = "[" + _get_world_log_name() + "] Rebuilt " + itos(chunk_count) + " chunks (" +
			itos(settings->cells_per_axis) + " cells/axis, " + itos(grid_dimensions.x) + String::utf8("×") +
			itos(grid_dimensions.y) + String::utf8("×") + itos(grid_dimensions.z) + " grid) in " + itos(elapsed_ms) +
			" ms" + _world_summary(settings);
	UtilityFunctions::print(line);
}

// --- Measures -------------------------------------------------------------------------------------

int ChunkedTerrainWorld::get_total_vertex_count() const {
	int total = 0;
	for (const auto &entry : chunks) {
		if (entry.second == nullptr) {
			continue;
		}
		Ref<ArrayMesh> mesh = entry.second->get_mesh();
		if (mesh.is_null()) {
			continue;
		}
		for (int surface = 0; surface < mesh->get_surface_count(); surface++) {
			total += mesh->surface_get_array_len(surface);
		}
	}
	return total;
}

int ChunkedTerrainWorld::get_total_triangle_count() const {
	int total_indices = 0;
	for (const auto &entry : chunks) {
		if (entry.second == nullptr) {
			continue;
		}
		Ref<ArrayMesh> mesh = entry.second->get_mesh();
		if (mesh.is_null()) {
			continue;
		}
		for (int surface = 0; surface < mesh->get_surface_count(); surface++) {
			total_indices += mesh->surface_get_array_index_len(surface);
		}
	}
	return total_indices / 3;
}

int ChunkedTerrainWorld::get_base_cells_per_axis() const {
	return MAX(1, (int)std::round(chunk_size / voxel_size));
}

int ChunkedTerrainWorld::get_voxels_per_chunk() const {
	int cells = get_cells_per_axis();
	return cells * cells * cells;
}

Vector3 ChunkedTerrainWorld::get_world_extents() const {
	Vector3i grid = _get_grid_dimensions();
	return Vector3(grid) * (real_t)chunk_size;
}

double ChunkedTerrainWorld::get_bedrock_y() const {
	Vector3i grid = _get_grid_dimensions();
	return CaveCarver::bedrock_y(get_global_position().y, grid.y, chunk_size);
}

Dictionary ChunkedTerrainWorld::footing(const Vector3 &center, double half_x, double half_z, double top_y) const {
	double margin = get_voxel_size();
	bool along_z = half_z > half_x;
	double half_along = (along_z ? half_z : half_x) + margin;
	double half_across = (along_z ? half_x : half_z) + margin;
	double radius = half_across * std::sqrt(2.0);
	double bedrock = get_bedrock_y();
	Dictionary out;
	out["center"] = v3(center.x, bedrock, center.z);
	out["half_length"] = half_along - half_across + radius;
	out["radius"] = radius;
	out["height"] = tmath::maxd(top_y - bedrock, 0.0);
	out["along_z"] = along_z;
	out["ground"] = true;
	return out;
}

Vector3 ChunkedTerrainWorld::snap_to_sample(const Vector3 &world_position) const {
	Vector3 origin = get_grid_world_origin();
	real_t step = (real_t)get_voxel_size();
	return origin + ((world_position - origin) / step).round() * step;
}

// --- The brush and edits ----------------------------------------------------------------------

void ChunkedTerrainWorld::end_continuous_edit() {
	continuous_edit_depth = MAX(continuous_edit_depth - 1, 0);
	if (continuous_edit_depth > 0) {
		return;
	}
	if (!pending_rebuilds.empty()) {
		_dispatch_pending_rebuilds();
	}
}

void ChunkedTerrainWorld::prepare_edit_around(const Vector3 &world_position, double radius) {
	if (!use_threaded()) {
		return;
	}
	AABB box = AABB(world_position - Vector3(1, 1, 1) * (real_t)radius, Vector3(1, 1, 1) * (real_t)(radius * 2.0));
	for (const Vector3i &chunk_coordinate : _get_chunk_coordinates_intersecting_aabb(box)) {
		if (field_cache.count(chunk_coordinate) || inflight_chunk_coordinates.count(chunk_coordinate) ||
				pending_rebuilds.count(chunk_coordinate) || !chunks.count(chunk_coordinate) ||
				!_stands(chunk_coordinate)) {
			continue;
		}
		if (running_async_tasks >= max_concurrent_rebuild_tasks) {
			return;
		}
		start_single_chunk_async_rebuild(chunk_coordinate, false, AABB(), true);
	}
}

void ChunkedTerrainWorld::_queue_chunk_rebuild(const Vector3i &chunk_coordinate, const AABB &bounds) {
	auto found = pending_rebuilds.find(chunk_coordinate);
	if (found == pending_rebuilds.end()) {
		pending_rebuilds[chunk_coordinate] = bounds;
		pending_order.push_back(chunk_coordinate);
		return;
	}
	if (!found->second.has_volume() || !bounds.has_volume()) {
		found->second = AABB();
	} else {
		found->second = found->second.merge(bounds);
	}
}

bool ChunkedTerrainWorld::is_solid_at(const Vector3 &world_position) {
	return density_at(world_position) < iso_level;
}

double ChunkedTerrainWorld::density_at(const Vector3 &world_position, const Variant &cache_argument) {
	// A caller's dictionary is filled as it goes (it shares it across calls); without one, a
	// fresh one (a bound default would be one dictionary shared by every call).
	Dictionary sample_cache = cache_argument.get_type() == Variant::DICTIONARY ? (Dictionary)cache_argument : Dictionary();
	prepare_edits();
	Ref<WorldDensity> density = _get_bake_density();
	real_t step = (real_t)get_world_step();
	Vector3 origin = get_grid_world_origin();
	Vector3 local = (world_position - origin) / step;
	Vector3 base = local.floor();
	Vector3 frac = local - base;
	double value = 0.0;
	for (int corner = 0; corner < 8; corner++) {
		Vector3 offset = Vector3((real_t)(corner & 1), (real_t)((corner >> 1) & 1), (real_t)((corner >> 2) & 1));
		double weight = ((double)offset.x * frac.x + (1.0 - offset.x) * (1.0 - frac.x)) *
				((double)offset.y * frac.y + (1.0 - offset.y) * (1.0 - frac.y)) *
				((double)offset.z * frac.z + (1.0 - offset.z) * (1.0 - frac.z));
		if (weight <= 0.0) {
			continue;
		}
		Vector3 corner_f = base + offset;
		Vector3i key = Vector3i((int)corner_f.x, (int)corner_f.y, (int)corner_f.z);
		double sample;
		if (sample_cache.has(key)) {
			sample = sample_cache[key];
		} else {
			Vector3 sample_position = origin + corner_f * step;
			sample = density->evaluate(sample_position);
			if (edits.is_valid()) {
				sample = edits->apply_to_density(sample, sample_position);
			}
			sample_cache[key] = sample;
		}
		value += sample * weight;
	}
	return value;
}

bool ChunkedTerrainWorld::can_edit_at(const Vector3 &world_position) const {
	return edit_bounds.size == Vector3() || edit_bounds.has_point(world_position);
}

void ChunkedTerrainWorld::apply_brush(const Vector3 &world_position, double radius, bool add_solid, int material) {
	apply_edit(sphere_edit(world_position, radius, add_solid, material));
}

void ChunkedTerrainWorld::apply_box(const Vector3 &center, const Vector3 &half_extents, bool add_solid, int material) {
	apply_edit(box_edit(center, half_extents, add_solid, material));
}

Dictionary ChunkedTerrainWorld::sphere_edit(const Vector3 &world_position, double radius, bool add_solid, int material) {
	Dictionary edit;
	edit["kind"] = "sphere";
	edit["position"] = world_position;
	edit["radius"] = radius;
	edit["add"] = add_solid;
	edit["material"] = material;
	return edit;
}

Dictionary ChunkedTerrainWorld::box_edit(const Vector3 &center, const Vector3 &half_extents, bool add_solid, int material) {
	Dictionary edit;
	edit["kind"] = "box";
	edit["position"] = center;
	edit["half_extents"] = half_extents;
	edit["add"] = add_solid;
	edit["material"] = material;
	return edit;
}

bool ChunkedTerrainWorld::apply_edit(Dictionary edit) {
	Vector3 position = edit.get("position", Vector3());
	bool add_solid = (bool)edit.get("add", false);
	int material = (int)edit.get("material", 0);
	if (!can_edit_at(position)) {
		return false;
	}
	if (add_solid && buries_fighter(edit)) {
		return false;
	}
	if (!allows_edit(edit)) {
		return false;
	}
	prepare_edits();
	Ref<WorldDensity> density = _get_bake_density();
	WorldDensity *d = density.ptr();
	TerrainEdits::DensityFn procedural = [d](const Vector3 &p) -> double { return d->evaluate(p, true); };
	TerrainEdits::MaterialFn natural = [d](const Vector3 &p, double value) -> int { return d->ground_material(p, value); };
	bool changed;
	double reach;
	if (String(edit.get("kind", "sphere")) == "box") {
		Vector3 half_extents = edit.get("half_extents", Vector3(1, 1, 1));
		changed = edits->add_box_native(position, half_extents, add_solid, procedural, material, natural);
		reach = half_extents.length();
	} else {
		double radius = (double)edit.get("radius", 1.0);
		changed = edits->add_brush_native(position, radius, add_solid, procedural, material, natural);
		reach = radius;
	}
	if (!changed) {
		return false;
	}
	edit["removed"] = edits->last_removed.duplicate();
	edit["added"] = edits->last_added;
	if (!edit.has("sequence")) {
		edit["sequence"] = next_edit_sequence;
	}
	next_edit_sequence = MAX(next_edit_sequence, (int)edit["sequence"] + 1);
	edit_log.push_back(edit);
	rebuild_changed_chunks();
	emit_signal("brush_applied", position, reach);
	emit_signal("edit_applied", edit);
	return true;
}

bool ChunkedTerrainWorld::allows_edit(const Dictionary &edit) const {
	return !edit_gate.is_valid() || (bool)edit_gate.call(edit);
}

int ChunkedTerrainWorld::estimate_voxels(const Dictionary &edit, double p_voxel_size) {
	double volume;
	if (String(edit.get("kind", "sphere")) == "box") {
		Vector3 half = edit.get("half_extents", Vector3(1, 1, 1));
		volume = 8.0 * (double)half.x * (double)half.y * (double)half.z;
	} else {
		double radius = (double)edit.get("radius", 1.0);
		volume = 4.0 / 3.0 * 3.141592653589793 * radius * radius * radius;
	}
	return MAX(tmath::ceili(volume / (p_voxel_size * p_voxel_size * p_voxel_size)), 1);
}

TypedArray<Dictionary> ChunkedTerrainWorld::get_edit_log() const {
	TypedArray<Dictionary> out;
	for (const Dictionary &edit : edit_log) {
		out.push_back(edit);
	}
	return out;
}

Dictionary ChunkedTerrainWorld::export_edit_state() const {
	Dictionary state;
	state["next_sequence"] = next_edit_sequence;
	state["edits"] = edits->export_state();
	return state;
}

void ChunkedTerrainWorld::import_edit_state(const Dictionary &state) {
	prepare_edits();
	edits->import_state(state.get("edits", Dictionary()));
	next_edit_sequence = (int)state.get("next_sequence", 1);
	edit_log.clear();
	AABB bounds = edits->get_all_bounds();
	if (bounds.size == Vector3()) {
		return;
	}
	for (const Vector3i &chunk_coordinate : _get_chunk_coordinates_intersecting_aabb(bounds)) {
		_queue_chunk_rebuild(chunk_coordinate, AABB());
	}
	pending_rebuild_collision = true;
	_dispatch_pending_rebuilds();
}

bool ChunkedTerrainWorld::buries_fighter(const Dictionary &edit) {
	if (!is_inside_tree()) {
		return false;
	}
	TypedArray<Node> fighters = get_tree()->get_nodes_in_group("fighter");
	for (int i = 0; i < fighters.size(); i++) {
		Node3D *body = Object::cast_to<Node3D>(fighters[i]);
		if (body == nullptr || !body->is_inside_tree()) {
			continue;
		}
		if (body->has_method("is_in_play") && !(bool)body->call("is_in_play")) {
			continue;
		}
		if (edit_overlaps_body(edit, body)) {
			return true;
		}
	}
	return false;
}

bool ChunkedTerrainWorld::edit_overlaps_body(const Dictionary &edit, Node3D *body) {
	std::vector<Vector3> points;
	double capsule_radius = 0.6;
	CollisionShape3D *collider = nullptr;
	TypedArray<Node> children = body->get_children();
	for (int i = 0; i < children.size(); i++) {
		CollisionShape3D *shape = Object::cast_to<CollisionShape3D>(children[i]);
		if (shape != nullptr && Object::cast_to<CapsuleShape3D>(shape->get_shape().ptr()) != nullptr) {
			collider = shape;
			break;
		}
	}
	if (collider == nullptr) {
		points.push_back(body->get_global_position() + Vector3(0, 0.6f, 0));
	} else {
		Ref<CapsuleShape3D> capsule = collider->get_shape();
		Vector3 axis = collider->get_global_basis().get_column(1).normalized();
		double half_segment = tmath::maxd((double)capsule->get_height() * 0.5 - (double)capsule->get_radius(), 0.0);
		Vector3 center = collider->get_global_position();
		for (int index = 0; index < CAPSULE_SAMPLES; index++) {
			double t = (double)index / (double)(CAPSULE_SAMPLES - 1) * 2.0 - 1.0;
			points.push_back(center + axis * (real_t)(half_segment * t));
		}
		capsule_radius = capsule->get_radius();
	}
	Vector3 center = edit.get("position", Vector3());
	double limit = capsule_radius + FIGHTER_CLEARANCE;
	if (String(edit.get("kind", "sphere")) == "box") {
		Vector3 half_extents = edit.get("half_extents", Vector3(1, 1, 1));
		for (const Vector3 &point : points) {
			Vector3 outside = ((point - center).abs() - half_extents).max(Vector3());
			if ((double)outside.length() < limit) {
				return true;
			}
		}
		return false;
	}
	double radius = (double)edit.get("radius", 1.0);
	for (const Vector3 &point : points) {
		if ((double)point.distance_to(center) < radius + limit) {
			return true;
		}
	}
	return false;
}

void ChunkedTerrainWorld::prepare_edits() {
	edits->set_voxel_size(get_voxel_size());
	edits->set_grid_origin(get_grid_world_origin());
}

void ChunkedTerrainWorld::rebuild_changed_chunks() {
	AABB changed = edits->get_last_changed_bounds();
	for (const Vector3i &chunk_coordinate : _get_chunk_coordinates_intersecting_aabb(changed)) {
		_queue_chunk_rebuild(chunk_coordinate, changed);
	}
	pending_rebuild_collision = true;
	_dispatch_pending_rebuilds();
}

// --- Settings ---------------------------------------------------------------------------------

Ref<TerrainSettings> ChunkedTerrainWorld::_make_settings_snapshot() {
	mat::ensure();
	Ref<TerrainSettings> settings;
	settings.instantiate();
	Vector3i grid_dimensions = _get_grid_dimensions();
	double world_step = get_world_step();
	settings->chunks_x = grid_dimensions.x;
	settings->chunks_y = grid_dimensions.y;
	settings->chunks_z = grid_dimensions.z;
	settings->cells_per_axis = get_cells_per_axis();
	settings->voxel_size = world_step;
	settings->bounds_clip_inset = tmath::maxd(chunk_size * 0.05, 0.25);
	settings->chunk_world_size = chunk_size;
	settings->chunk_resolution = chunk_resolution;
	settings->iso_level = iso_level;
	settings->world_origin = get_global_position();
	settings->noise_enabled = noise_enabled;
	settings->noise_seed = noise_seed;
	settings->noise_frequency = noise_frequency;
	settings->noise_amplitude = noise_amplitude;
	settings->noise_octaves = noise_octaves;
	settings->noise_lacunarity = noise_lacunarity;
	settings->noise_gain = noise_gain;
	settings->generate_collision = generate_collision;
	settings->loose_rock_voxels = loose_rock_voxels;
	settings->caves_enabled = caves_enabled;
	settings->material = _effective_material();
	settings->bounds_center = get_global_position();
	settings->bounds_half = get_world_extents() * 0.5f;
	settings->terrain_edits = edits;
	settings->solids = solids;
	settings->rebuild_collision = settings->generate_collision;
	_apply_world_specific_settings(settings);
	// The density every chunk copies, built once (its rolls and cave systems are a few
	// milliseconds) and remade when a setting or the node's place changes.
	if (density_prototype.is_null() || !prototype_origin.is_equal_approx(get_global_position())) {
		density_prototype = _build_world_density(settings);
		prototype_origin = get_global_position();
	}
	settings->density_prototype = density_prototype;
	return settings;
}

Ref<TerrainSettings> ChunkedTerrainWorld::_make_thread_settings_snapshot() {
	Ref<TerrainSettings> settings = _make_settings_snapshot();
	if (settings->terrain_edits.is_valid()) {
		settings->terrain_edits = settings->terrain_edits->duplicate_for_thread();
	}
	return settings;
}

Ref<WorldDensity> ChunkedTerrainWorld::_build_world_density(const Ref<TerrainSettings> &settings) {
	return WorldDensity::create(settings->noise_enabled, settings->noise_seed, settings->noise_frequency,
			settings->noise_amplitude, settings->noise_octaves, settings->noise_lacunarity, settings->noise_gain,
			settings->bounds_center, settings->bounds_half, settings->bounds_clip_inset);
}

void ChunkedTerrainWorld::_invalidate_bake_density() {
	bake_density.unref();
	density_prototype.unref();
}

Ref<WorldDensity> ChunkedTerrainWorld::_get_bake_density() {
	if (bake_density.is_null() || !prototype_origin.is_equal_approx(get_global_position())) {
		Ref<TerrainSettings> settings = _make_settings_snapshot();
		bake_density = settings->density_prototype->clone_for_build();
		bake_density->set_solids(settings->solids);
	}
	return bake_density;
}

void ChunkedTerrainWorld::settings_changed() {
	_invalidate_bake_density();
	_request_rebuild();
}

void ChunkedTerrainWorld::set_solids(const Array &v) {
	solids = v;
	bake_density.unref();
	if (!chunks.empty()) {
		_request_rebuild();
	}
}

TypedArray<Dictionary> ChunkedTerrainWorld::get_solids() const {
	TypedArray<Dictionary> out;
	for (int i = 0; i < solids.size(); i++) {
		out.push_back(solids[i]);
	}
	return out;
}

void ChunkedTerrainWorld::clear_chunks() {
	TypedArray<Node> children = get_children();
	for (int i = 0; i < children.size(); i++) {
		Node *child = Object::cast_to<Node>(children[i]);
		if (child == nullptr) {
			continue;
		}
		if (Object::cast_to<TerrainChunk>(child) == nullptr && !String(child->get_name()).begins_with("Chunk_")) {
			continue;
		}
		remove_child(child);
		child->queue_free();
	}
	reset_stream();
	chunks.clear();
	field_cache.clear();
	field_cache_order.clear();
	pending_rebuilds.clear();
	pending_order.clear();
}

void ChunkedTerrainWorld::_request_rebuild() {
	if (!is_node_ready()) {
		return;
	}
	if (editor_hint() && !auto_rebuild_in_editor) {
		return;
	}
	if (rebuild_queued) {
		return;
	}
	rebuild_queued = true;
	call_deferred("_deferred_rebuild");
}

void ChunkedTerrainWorld::deferred_rebuild() {
	rebuild_queued = false;
	rebuild_all();
}

bool ChunkedTerrainWorld::use_threaded() const {
	return use_threaded_rebuild && !editor_hint();
}

// --- Brush rebuilds -------------------------------------------------------------------------------

void ChunkedTerrainWorld::_dispatch_pending_rebuilds() {
	if (pending_rebuilds.empty()) {
		pending_order.clear();
		return;
	}
	bool rebuild_collision = pending_rebuild_collision;
	if (rebuild_collision) {
		pending_rebuild_collision = false;
	}
	std::vector<Vector3i> order;
	for (const Vector3i &c : pending_order) {
		if (pending_rebuilds.count(c) && std::find(order.begin(), order.end(), c) == order.end()) {
			order.push_back(c);
		}
	}
	pending_order.clear();
	std::vector<Vector3i> deferred_chunks;
	for (const Vector3i &chunk_coordinate : order) {
		if (_is_streamed(chunk_coordinate) && !chunks.count(chunk_coordinate) && !stream_inflight.count(chunk_coordinate)) {
			pending_rebuilds.erase(chunk_coordinate);
			continue;
		}
		if (inflight_chunk_coordinates.count(chunk_coordinate) || !chunks.count(chunk_coordinate)) {
			deferred_chunks.push_back(chunk_coordinate);
			continue;
		}
		if (running_async_tasks >= max_concurrent_rebuild_tasks) {
			deferred_chunks.push_back(chunk_coordinate);
			continue;
		}
		AABB bounds = pending_rebuilds[chunk_coordinate];
		pending_rebuilds.erase(chunk_coordinate);
		start_single_chunk_async_rebuild(chunk_coordinate, rebuild_collision, bounds);
	}
	for (const Vector3i &chunk_coordinate : deferred_chunks) {
		// Kept as queued, whole: the scripts re-added each deferred chunk at the end.
		auto found = pending_rebuilds.find(chunk_coordinate);
		if (found != pending_rebuilds.end()) {
			AABB kept = found->second;
			pending_rebuilds.erase(found);
			pending_rebuilds[chunk_coordinate] = kept;
		} else {
			pending_rebuilds[chunk_coordinate] = AABB();
		}
		pending_order.push_back(chunk_coordinate);
	}
	if (rebuild_collision && !deferred_chunks.empty()) {
		pending_rebuild_collision = true;
	}
}

void ChunkedTerrainWorld::start_single_chunk_async_rebuild(const Vector3i &chunk_coordinate, bool rebuild_collision,
		const AABB &bounds, bool prepare_only) {
	inflight_chunk_coordinates.insert(chunk_coordinate);
	std::unique_ptr<BuildJob> job = std::make_unique<BuildJob>();
	job->chunk_coordinates.push_back(chunk_coordinate);
	job->rebuild_collision = rebuild_collision;
	job->prepare_only = prepare_only;
	job->settings = _make_thread_settings_snapshot();
	job->settings->keep_field = true;
	auto cached = field_cache.find(chunk_coordinate);
	if (bounds.has_volume() && cached != field_cache.end()) {
		job->settings->cached_field = cached->second.field;
		job->settings->cached_blocks = cached->second.blocks;
		job->settings->resample_bounds = bounds;
	}
	submit(async_jobs, std::move(job), "Chunk rebuild");
	running_async_tasks += 1;
}

void ChunkedTerrainWorld::poll_async_rebuilds() {
	if (!async_jobs.empty()) {
		std::vector<std::unique_ptr<BuildJob>> completed;
		for (size_t i = 0; i < async_jobs.size();) {
			if (WorkerThreadPool::get_singleton()->is_task_completed(async_jobs[i]->task_id)) {
				completed.push_back(std::move(async_jobs[i]));
				async_jobs.erase(async_jobs.begin() + i);
			} else {
				i++;
			}
		}
		for (std::unique_ptr<BuildJob> &job : completed) {
			WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
			running_async_tasks = MAX(running_async_tasks - 1, 0);
			apply_async_job(job.get());
		}
	}
	if (running_async_tasks < max_concurrent_rebuild_tasks && !pending_rebuilds.empty()) {
		_dispatch_pending_rebuilds();
	}
}

void ChunkedTerrainWorld::apply_async_job(BuildJob *job) {
	for (size_t i = 0; i < job->chunk_coordinates.size(); i++) {
		Vector3i chunk_coordinate = job->chunk_coordinates[i];
		inflight_chunk_coordinates.erase(chunk_coordinate);
		auto found = chunks.find(chunk_coordinate);
		if (found == chunks.end() || found->second == nullptr) {
			continue;
		}
		TerrainChunk *chunk = found->second;
		Ref<ChunkBuildResult> result = i < job->results.size() ? job->results[i] : Ref<ChunkBuildResult>();
		if (result.is_null()) {
			continue;
		}
		if (!job->prepare_only) {
			chunk->apply_build_result(result, generate_collision);
			emit_signal("chunk_rebuilt", _get_chunk_world_aabb(chunk_coordinate, job->settings));
			if (_effective_material().is_valid()) {
				chunk->set_material_override(_effective_material());
			}
		}
		if (result->field.is_valid()) {
			ChunkCache cache;
			cache.field = result->field;
			cache.blocks = result->blocks;
			if (field_cache.count(chunk_coordinate)) {
				auto at = std::find(field_cache_order.begin(), field_cache_order.end(), chunk_coordinate);
				if (at != field_cache_order.end()) {
					field_cache_order.erase(at);
				}
			}
			field_cache[chunk_coordinate] = cache;
			field_cache_order.push_back(chunk_coordinate);
			while ((int)field_cache.size() > FIELD_CACHE_CHUNKS && !field_cache_order.empty()) {
				field_cache.erase(field_cache_order.front());
				field_cache_order.pop_front();
			}
		}
	}
}

// --- Grid lookups -------------------------------------------------------------------------------

std::vector<Vector3i> ChunkedTerrainWorld::_get_chunk_coordinates_intersecting_aabb(const AABB &bounds) {
	std::vector<Vector3i> out;
	double extent = world_build_settings.is_valid() ? world_build_settings->chunk_world_size : chunk_size;
	AABB search = bounds.grow((real_t)(get_voxel_size() * 2.0));
	Vector3 origin = get_global_position() + _chunk_corner_local(Vector3i(), world_build_settings);
	Vector3i grid = world_building ? world_build_grid : _get_grid_dimensions();
	Vector3 low_f = ((search.position - origin) / (real_t)extent).floor();
	Vector3 high_f = ((search.get_end() - origin) / (real_t)extent).ceil();
	Vector3i low = Vector3i((int)low_f.x, (int)low_f.y, (int)low_f.z).max(Vector3i());
	Vector3i high = (Vector3i((int)high_f.x, (int)high_f.y, (int)high_f.z) - Vector3i(1, 1, 1)).min(grid - Vector3i(1, 1, 1));
	for (int chunk_z = low.z; chunk_z < high.z + 1; chunk_z++) {
		for (int chunk_y = low.y; chunk_y < high.y + 1; chunk_y++) {
			for (int chunk_x = low.x; chunk_x < high.x + 1; chunk_x++) {
				Vector3i chunk_coordinate(chunk_x, chunk_y, chunk_z);
				if (_is_streamed(chunk_coordinate)) {
					if (chunks.count(chunk_coordinate) || stream_inflight.count(chunk_coordinate)) {
						out.push_back(chunk_coordinate);
					}
				} else if (world_building || chunks.count(chunk_coordinate)) {
					out.push_back(chunk_coordinate);
				}
			}
		}
	}
	return out;
}

AABB ChunkedTerrainWorld::_get_chunk_world_aabb(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings) const {
	double extent = settings.is_valid() ? settings->chunk_world_size : chunk_size;
	Vector3 corner_local = _chunk_corner_local(chunk_coordinate, settings);
	return AABB(get_global_position() + corner_local, Vector3(1, 1, 1) * (real_t)extent);
}

Vector3 ChunkedTerrainWorld::_chunk_corner_local(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings) const {
	real_t extent;
	Vector3 grid;
	if (settings.is_valid()) {
		extent = (real_t)settings->chunk_world_size;
		grid = Vector3((real_t)settings->chunks_x, (real_t)settings->chunks_y, (real_t)settings->chunks_z);
	} else {
		extent = (real_t)chunk_size;
		grid = Vector3(_get_grid_dimensions());
	}
	Vector3 grid_origin = -grid * extent * 0.5f;
	return grid_origin + Vector3(chunk_coordinate) * extent;
}

// --- Script views of the internals ----------------------------------------------------------------

Dictionary ChunkedTerrainWorld::set_to_dict(const CoordSet &set) {
	Dictionary out;
	for (const Vector3i &c : set) {
		out[c] = true;
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_placed_dict() const {
	Dictionary out;
	for (const Vector3i &c : placed_order) {
		out[c] = true;
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_async_jobs_dict() const {
	Dictionary out;
	for (const std::unique_ptr<BuildJob> &job : async_jobs) {
		out[job->task_id] = job->chunk_coordinates.empty() ? Vector3i() : job->chunk_coordinates[0];
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_chunks_dict() const {
	Dictionary out;
	for (const auto &entry : chunks) {
		out[entry.first] = entry.second;
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_play_columns_dict() const {
	Dictionary out;
	Vector3i grid = _get_grid_dimensions();
	if ((int)play_columns.size() != grid.x * grid.z) {
		return out;
	}
	for (int z = 0; z < grid.z; z++) {
		for (int x = 0; x < grid.x; x++) {
			if (play_columns[x + z * grid.x]) {
				out[Vector2i(x, z)] = true;
			}
		}
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_pending_rebuilds_dict() const {
	Dictionary out;
	for (const auto &entry : pending_rebuilds) {
		out[entry.first] = entry.second;
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_field_cache_dict() const {
	Dictionary out;
	for (const auto &entry : field_cache) {
		out[entry.first] = entry.second.field;
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_get_world_build_tasks_dict() const {
	Dictionary out;
	for (const std::unique_ptr<BuildJob> &job : world_build_tasks) {
		TypedArray<Vector3i> coordinates;
		for (const Vector3i &c : job->chunk_coordinates) {
			coordinates.push_back(c);
		}
		out[job->task_id] = coordinates;
	}
	return out;
}

TypedArray<Vector3i> ChunkedTerrainWorld::_get_world_build_queue() const {
	TypedArray<Vector3i> out;
	for (const Vector3i &c : world_build_queue) {
		out.push_back(c);
	}
	return out;
}

TypedArray<Vector3i> ChunkedTerrainWorld::_get_stream_queue() const {
	TypedArray<Vector3i> out;
	for (const Vector3i &c : stream_queue) {
		out.push_back(c);
	}
	return out;
}

TypedArray<Vector3i> ChunkedTerrainWorld::_chunks_touching_bound(const Vector3 &world_position, double radius) {
	TypedArray<Vector3i> out;
	for (const Vector3i &c : _chunks_touching(world_position, radius)) {
		out.push_back(c);
	}
	return out;
}

TypedArray<Vector2i> ChunkedTerrainWorld::_columns_touching_bound(const Vector3 &world_position, double radius) {
	TypedArray<Vector2i> out;
	for (const Vector2i &c : _columns_touching(world_position, radius)) {
		out.push_back(c);
	}
	return out;
}

Dictionary ChunkedTerrainWorld::_ground_round_bound(const Vector3 &world_position, double radius) {
	return set_to_dict(_ground_round(world_position, radius));
}

TypedArray<Vector3i> ChunkedTerrainWorld::_get_chunk_coordinates_intersecting_aabb_bound(const AABB &bounds) {
	TypedArray<Vector3i> out;
	for (const Vector3i &c : _get_chunk_coordinates_intersecting_aabb(bounds)) {
		out.push_back(c);
	}
	return out;
}

TypedArray<Vector3i> ChunkedTerrainWorld::_get_chunk_coordinates_intersecting_sphere_bound(const Vector3 &center, double radius) {
	return _get_chunk_coordinates_intersecting_aabb_bound(
			AABB(center - Vector3(1, 1, 1) * (real_t)radius, Vector3(1, 1, 1) * (real_t)(radius * 2.0)));
}

// --- Setters --------------------------------------------------------------------------------------

void ChunkedTerrainWorld::set_chunk_size(double v) {
	chunk_size = tmath::maxd(v, 1.0);
	settings_changed();
}
void ChunkedTerrainWorld::set_chunk_resolution(int v) {
	chunk_resolution = MAX(v, 1);
	settings_changed();
}
void ChunkedTerrainWorld::set_voxel_size(double v) {
	voxel_size = tmath::maxd(v, 0.05);
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_enabled(bool v) {
	noise_enabled = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_seed(int v) {
	noise_seed = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_frequency(double v) {
	noise_frequency = tmath::maxd(v, 0.001);
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_amplitude(double v) {
	noise_amplitude = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_octaves(int v) {
	noise_octaves = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_lacunarity(double v) {
	noise_lacunarity = tmath::maxd(v, 1.0);
	settings_changed();
}
void ChunkedTerrainWorld::set_noise_gain(double v) {
	noise_gain = tmath::clampd(v, 0.01, 1.0);
	settings_changed();
}
void ChunkedTerrainWorld::set_caves_enabled(bool v) {
	caves_enabled = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_iso_level(double v) {
	iso_level = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_generate_collision(bool v) {
	generate_collision = v;
	settings_changed();
}
void ChunkedTerrainWorld::set_loose_rock_voxels(int v) {
	loose_rock_voxels = v;
	settings_changed();
}

// --- Binding ----------------------------------------------------------------------------------------

void ChunkedTerrainWorld::_bind_methods() {
	ADD_SIGNAL(MethodInfo("brush_applied", PropertyInfo(Variant::VECTOR3, "world_position"), PropertyInfo(Variant::FLOAT, "radius")));
	ADD_SIGNAL(MethodInfo("edit_applied", PropertyInfo(Variant::DICTIONARY, "edit")));
	ADD_SIGNAL(MethodInfo("build_progress", PropertyInfo(Variant::INT, "done"), PropertyInfo(Variant::INT, "total")));
	ADD_SIGNAL(MethodInfo("built"));
	ADD_SIGNAL(MethodInfo("ground_placed", PropertyInfo(Variant::AABB, "box")));
	ADD_SIGNAL(MethodInfo("chunk_rebuilt", PropertyInfo(Variant::AABB, "box")));

	StringName cls = get_class_static();
	ClassDB::bind_integer_constant(cls, "", "REBUILD_THREADS", REBUILD_THREADS);
	ClassDB::bind_integer_constant(cls, "", "FIELD_CACHE_CHUNKS", FIELD_CACHE_CHUNKS);
	ClassDB::bind_integer_constant(cls, "", "CAPSULE_SAMPLES", CAPSULE_SAMPLES);
	ClassDB::bind_integer_constant(cls, "", "PLACE_BUDGET_USEC", PLACE_BUDGET_USEC);
	ClassDB::bind_integer_constant(cls, "", "WORLD_BUILD_IN_FLIGHT", world_build_in_flight());
	ClassDB::bind_integer_constant(cls, "", "BUILD_TASK_SAMPLES", BUILD_TASK_SAMPLES);
	ClassDB::bind_integer_constant(cls, "", "DEEP_MARGIN", (int)DEEP_MARGIN);
	ClassDB::bind_integer_constant(cls, "", "STREAM_MARGIN", (int)STREAM_MARGIN);
	ClassDB::bind_integer_constant(cls, "", "STREAM_VIEW", (int)STREAM_VIEW);
	ClassDB::bind_integer_constant(cls, "", "STREAM_BODY", (int)STREAM_BODY);
	ClassDB::bind_integer_constant(cls, "", "STREAM_KEEP", (int)STREAM_KEEP);
	ClassDB::bind_integer_constant(cls, "", "STREAM_EVERY", STREAM_EVERY);
	ClassDB::bind_integer_constant(cls, "", "STREAM_URGENT", (int)STREAM_URGENT);
	ClassDB::bind_integer_constant(cls, "", "STREAM_TASKS_BEFORE_PLAY", STREAM_TASKS_BEFORE_PLAY);
	ClassDB::bind_integer_constant(cls, "", "GROUND_HOLD_REACH", (int)GROUND_HOLD_REACH);
	ClassDB::bind_integer_constant(cls, "", "ORDER_EVERY", ORDER_EVERY);
	ClassDB::bind_static_method(cls, D_METHOD("fighter_clearance"), &ChunkedTerrainWorld::fighter_clearance);

	ClassDB::bind_method(D_METHOD("destroy_all"), &ChunkedTerrainWorld::destroy_all);
	ClassDB::bind_method(D_METHOD("rebuild_all_editor"), &ChunkedTerrainWorld::rebuild_all_editor);
	ClassDB::bind_method(D_METHOD("rebuild_all"), &ChunkedTerrainWorld::rebuild_all);
	ClassDB::bind_method(D_METHOD("is_building"), &ChunkedTerrainWorld::is_building);
	ClassDB::bind_method(D_METHOD("focus_build_at", "world_position", "radius", "primary"), &ChunkedTerrainWorld::focus_build_at, DEFVAL(0.0), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("is_ground_ready_around", "world_position", "radius"), &ChunkedTerrainWorld::is_ground_ready_around, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("play_ground_ready"), &ChunkedTerrainWorld::play_ground_ready);
	ClassDB::bind_method(D_METHOD("get_built_reach", "world_position"), &ChunkedTerrainWorld::get_built_reach);
	ClassDB::bind_method(D_METHOD("begin_build"), &ChunkedTerrainWorld::begin_build);
	ClassDB::bind_method(D_METHOD("ground_missing_under", "body"), &ChunkedTerrainWorld::ground_missing_under);
	ClassDB::bind_method(D_METHOD("get_surface_datum_y"), &ChunkedTerrainWorld::get_surface_datum_y);
	ClassDB::bind_method(D_METHOD("get_chunk_count"), &ChunkedTerrainWorld::get_chunk_count);
	ClassDB::bind_method(D_METHOD("get_total_vertex_count"), &ChunkedTerrainWorld::get_total_vertex_count);
	ClassDB::bind_method(D_METHOD("get_total_triangle_count"), &ChunkedTerrainWorld::get_total_triangle_count);
	ClassDB::bind_method(D_METHOD("get_edited_voxel_count"), &ChunkedTerrainWorld::get_edited_voxel_count);
	ClassDB::bind_method(D_METHOD("get_grid_dimensions"), &ChunkedTerrainWorld::get_grid_dimensions);
	ClassDB::bind_method(D_METHOD("get_base_cells_per_axis"), &ChunkedTerrainWorld::get_base_cells_per_axis);
	ClassDB::bind_method(D_METHOD("get_cells_per_axis"), &ChunkedTerrainWorld::get_cells_per_axis);
	ClassDB::bind_method(D_METHOD("get_voxels_per_chunk"), &ChunkedTerrainWorld::get_voxels_per_chunk);
	ClassDB::bind_method(D_METHOD("get_chunk_world_extent"), &ChunkedTerrainWorld::get_chunk_world_extent);
	ClassDB::bind_method(D_METHOD("get_world_step"), &ChunkedTerrainWorld::get_world_step);
	ClassDB::bind_method(D_METHOD("get_voxel_size"), &ChunkedTerrainWorld::get_voxel_size);
	ClassDB::bind_method(D_METHOD("get_world_extents"), &ChunkedTerrainWorld::get_world_extents);
	ClassDB::bind_method(D_METHOD("get_bedrock_y"), &ChunkedTerrainWorld::get_bedrock_y);
	ClassDB::bind_method(D_METHOD("footing", "center", "half_x", "half_z", "top_y"), &ChunkedTerrainWorld::footing);
	ClassDB::bind_method(D_METHOD("get_settings_snapshot"), &ChunkedTerrainWorld::get_settings_snapshot);
	ClassDB::bind_method(D_METHOD("get_terrain_edits"), &ChunkedTerrainWorld::get_terrain_edits);
	ClassDB::bind_method(D_METHOD("get_grid_world_origin"), &ChunkedTerrainWorld::get_grid_world_origin);
	ClassDB::bind_method(D_METHOD("snap_to_sample", "world_position"), &ChunkedTerrainWorld::snap_to_sample);
	ClassDB::bind_method(D_METHOD("get_grid_origin_local"), &ChunkedTerrainWorld::get_grid_origin_local);
	ClassDB::bind_method(D_METHOD("begin_continuous_edit"), &ChunkedTerrainWorld::begin_continuous_edit);
	ClassDB::bind_method(D_METHOD("end_continuous_edit"), &ChunkedTerrainWorld::end_continuous_edit);
	ClassDB::bind_method(D_METHOD("prepare_edit_around", "world_position", "radius"), &ChunkedTerrainWorld::prepare_edit_around);
	ClassDB::bind_method(D_METHOD("is_solid_at", "world_position"), &ChunkedTerrainWorld::is_solid_at);
	ClassDB::bind_method(D_METHOD("density_at", "world_position", "sample_cache"), &ChunkedTerrainWorld::density_at, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("can_edit_at", "world_position"), &ChunkedTerrainWorld::can_edit_at);
	ClassDB::bind_method(D_METHOD("apply_brush", "world_position", "radius", "add_solid", "material"), &ChunkedTerrainWorld::apply_brush, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("apply_box", "center", "half_extents", "add_solid", "material"), &ChunkedTerrainWorld::apply_box, DEFVAL(0));
	ClassDB::bind_static_method(cls, D_METHOD("sphere_edit", "world_position", "radius", "add_solid", "material"), &ChunkedTerrainWorld::sphere_edit);
	ClassDB::bind_static_method(cls, D_METHOD("box_edit", "center", "half_extents", "add_solid", "material"), &ChunkedTerrainWorld::box_edit);
	ClassDB::bind_method(D_METHOD("apply_edit", "edit"), &ChunkedTerrainWorld::apply_edit);
	ClassDB::bind_method(D_METHOD("allows_edit", "edit"), &ChunkedTerrainWorld::allows_edit);
	ClassDB::bind_static_method(cls, D_METHOD("estimate_voxels", "edit", "voxel_size"), &ChunkedTerrainWorld::estimate_voxels);
	ClassDB::bind_method(D_METHOD("get_edit_log"), &ChunkedTerrainWorld::get_edit_log);
	ClassDB::bind_method(D_METHOD("export_edit_state"), &ChunkedTerrainWorld::export_edit_state);
	ClassDB::bind_method(D_METHOD("import_edit_state", "state"), &ChunkedTerrainWorld::import_edit_state);
	ClassDB::bind_method(D_METHOD("buries_fighter", "edit"), &ChunkedTerrainWorld::buries_fighter);

	ClassDB::bind_method(D_METHOD("_make_settings_snapshot"), &ChunkedTerrainWorld::_make_settings_snapshot);
	ClassDB::bind_method(D_METHOD("_make_thread_settings_snapshot"), &ChunkedTerrainWorld::_make_thread_settings_snapshot);
	ClassDB::bind_method(D_METHOD("_get_bake_density"), &ChunkedTerrainWorld::_get_bake_density);
	ClassDB::bind_method(D_METHOD("_invalidate_bake_density"), &ChunkedTerrainWorld::_invalidate_bake_density);
	ClassDB::bind_method(D_METHOD("_build_settings"), &ChunkedTerrainWorld::_build_settings);
	ClassDB::bind_method(D_METHOD("_chunk_corner_local", "chunk_coordinate", "settings"), &ChunkedTerrainWorld::_chunk_corner_local);
	ClassDB::bind_method(D_METHOD("_get_chunk_world_aabb", "chunk_coordinate", "settings"), &ChunkedTerrainWorld::_get_chunk_world_aabb);
	ClassDB::bind_method(D_METHOD("_is_streamed", "chunk_coordinate"), &ChunkedTerrainWorld::_is_streamed);
	ClassDB::bind_method(D_METHOD("_stands", "chunk_coordinate"), &ChunkedTerrainWorld::_stands);
	ClassDB::bind_method(D_METHOD("_chunks_touching", "world_position", "radius"), &ChunkedTerrainWorld::_chunks_touching_bound);
	ClassDB::bind_method(D_METHOD("_columns_touching", "world_position", "radius"), &ChunkedTerrainWorld::_columns_touching_bound);
	ClassDB::bind_method(D_METHOD("_grid_corner"), &ChunkedTerrainWorld::_grid_corner);
	ClassDB::bind_method(D_METHOD("_queue_chunk_rebuild", "chunk_coordinate", "bounds"), &ChunkedTerrainWorld::_queue_chunk_rebuild);
	ClassDB::bind_method(D_METHOD("_dispatch_pending_rebuilds"), &ChunkedTerrainWorld::_dispatch_pending_rebuilds);
	ClassDB::bind_method(D_METHOD("_ground_round", "world_position", "radius"), &ChunkedTerrainWorld::_ground_round_bound);
	ClassDB::bind_method(D_METHOD("_build_group", "chunk_coordinate"), &ChunkedTerrainWorld::_build_group);
	ClassDB::bind_method(D_METHOD("_get_chunk_coordinates_intersecting_aabb", "bounds"), &ChunkedTerrainWorld::_get_chunk_coordinates_intersecting_aabb_bound);
	ClassDB::bind_method(D_METHOD("_get_chunk_coordinates_intersecting_sphere", "center", "radius"), &ChunkedTerrainWorld::_get_chunk_coordinates_intersecting_sphere_bound);
	ClassDB::bind_method(D_METHOD("_world_summary", "settings"), &ChunkedTerrainWorld::_world_summary_bound);
	ClassDB::bind_method(D_METHOD("_build_world_density", "settings"), &ChunkedTerrainWorld::_build_world_density_bound);
	ClassDB::bind_method(D_METHOD("_get_grid_dimensions"), &ChunkedTerrainWorld::_get_grid_dimensions_bound);
	ClassDB::bind_method(D_METHOD("_deferred_rebuild"), &ChunkedTerrainWorld::deferred_rebuild);

	ClassDB::bind_method(D_METHOD("_get_chunks_dict"), &ChunkedTerrainWorld::_get_chunks_dict);
	ClassDB::bind_method(D_METHOD("_get_deep_dict"), &ChunkedTerrainWorld::_get_deep_dict);
	ClassDB::bind_method(D_METHOD("_get_placed_dict"), &ChunkedTerrainWorld::_get_placed_dict);
	ClassDB::bind_method(D_METHOD("_get_play_columns_dict"), &ChunkedTerrainWorld::_get_play_columns_dict);
	ClassDB::bind_method(D_METHOD("_get_play_chunks_dict"), &ChunkedTerrainWorld::_get_play_chunks_dict);
	ClassDB::bind_method(D_METHOD("_get_stream_loaded_dict"), &ChunkedTerrainWorld::_get_stream_loaded_dict);
	ClassDB::bind_method(D_METHOD("_get_stream_inflight_dict"), &ChunkedTerrainWorld::_get_stream_inflight_dict);
	ClassDB::bind_method(D_METHOD("_get_inflight_dict"), &ChunkedTerrainWorld::_get_inflight_dict);
	ClassDB::bind_method(D_METHOD("_get_pending_rebuilds_dict"), &ChunkedTerrainWorld::_get_pending_rebuilds_dict);
	ClassDB::bind_method(D_METHOD("_get_field_cache_dict"), &ChunkedTerrainWorld::_get_field_cache_dict);
	ClassDB::bind_method(D_METHOD("_get_world_build_tasks_dict"), &ChunkedTerrainWorld::_get_world_build_tasks_dict);
	ClassDB::bind_method(D_METHOD("_get_world_build_queue"), &ChunkedTerrainWorld::_get_world_build_queue);
	ClassDB::bind_method(D_METHOD("_get_stream_queue"), &ChunkedTerrainWorld::_get_stream_queue);
	ClassDB::bind_method(D_METHOD("_get_world_build_placed"), &ChunkedTerrainWorld::_get_world_build_placed);
	ClassDB::bind_method(D_METHOD("_get_world_build_total"), &ChunkedTerrainWorld::_get_world_build_total);
	ClassDB::bind_method(D_METHOD("_get_running_async_tasks"), &ChunkedTerrainWorld::_get_running_async_tasks);
	ClassDB::bind_method(D_METHOD("_get_async_jobs_count"), &ChunkedTerrainWorld::_get_async_jobs_count);
	ClassDB::bind_method(D_METHOD("_get_async_jobs_dict"), &ChunkedTerrainWorld::_get_async_jobs_dict);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_async_jobs", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "_get_async_jobs_dict");
	ClassDB::bind_method(D_METHOD("_get_held_waiting"), &ChunkedTerrainWorld::_get_held_waiting);
	const int hidden = PROPERTY_USAGE_NONE;
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_chunks", PROPERTY_HINT_NONE, "", hidden), "", "_get_chunks_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_deep", PROPERTY_HINT_NONE, "", hidden), "", "_get_deep_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_placed", PROPERTY_HINT_NONE, "", hidden), "", "_get_placed_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_play_columns", PROPERTY_HINT_NONE, "", hidden), "", "_get_play_columns_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_play_chunks", PROPERTY_HINT_NONE, "", hidden), "", "_get_play_chunks_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_stream_loaded", PROPERTY_HINT_NONE, "", hidden), "", "_get_stream_loaded_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_stream_inflight", PROPERTY_HINT_NONE, "", hidden), "", "_get_stream_inflight_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_inflight_chunk_coordinates", PROPERTY_HINT_NONE, "", hidden), "", "_get_inflight_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_pending_rebuild_chunk_coordinates", PROPERTY_HINT_NONE, "", hidden), "", "_get_pending_rebuilds_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_field_cache", PROPERTY_HINT_NONE, "", hidden), "", "_get_field_cache_dict");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "_world_build_tasks", PROPERTY_HINT_NONE, "", hidden), "", "_get_world_build_tasks_dict");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "_world_build_queue", PROPERTY_HINT_NONE, "", hidden), "", "_get_world_build_queue");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "_stream_queue", PROPERTY_HINT_NONE, "", hidden), "", "_get_stream_queue");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "_world_build_placed", PROPERTY_HINT_NONE, "", hidden), "", "_get_world_build_placed");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "_world_build_total", PROPERTY_HINT_NONE, "", hidden), "", "_get_world_build_total");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "_running_async_tasks", PROPERTY_HINT_NONE, "", hidden), "", "_get_running_async_tasks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "_async_jobs_count", PROPERTY_HINT_NONE, "", hidden), "", "_get_async_jobs_count");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "_play_waiting", PROPERTY_HINT_NONE, "", hidden), "", "_get_held_waiting");

#define CTW_BIND(name, vtype, hint, hint_string)                                                    \
	ClassDB::bind_method(D_METHOD("set_" #name, "value"), &ChunkedTerrainWorld::set_##name);         \
	ClassDB::bind_method(D_METHOD("get_" #name), &ChunkedTerrainWorld::get_##name);                  \
	ADD_PROPERTY(PropertyInfo(Variant::vtype, #name, hint, hint_string), "set_" #name, "get_" #name);

	ADD_GROUP("Terrain Grid", "");
	CTW_BIND(chunk_size, FLOAT, PROPERTY_HINT_RANGE, "1,128,0.5,or_greater")
	CTW_BIND(chunk_resolution, INT, PROPERTY_HINT_RANGE, "1,16,1")
	ClassDB::bind_method(D_METHOD("set_voxel_size", "value"), &ChunkedTerrainWorld::set_voxel_size);
	ClassDB::bind_method(D_METHOD("get_voxel_size_setting"), &ChunkedTerrainWorld::get_voxel_size_setting);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "voxel_size", PROPERTY_HINT_RANGE, "0.25,8,0.25"), "set_voxel_size", "get_voxel_size_setting");
	ADD_GROUP("Noise", "");
	CTW_BIND(noise_enabled, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(noise_seed, INT, PROPERTY_HINT_NONE, "")
	CTW_BIND(noise_frequency, FLOAT, PROPERTY_HINT_RANGE, "0.004,0.01,0.0005")
	CTW_BIND(noise_amplitude, FLOAT, PROPERTY_HINT_RANGE, "0,40,0.1")
	CTW_BIND(noise_octaves, INT, PROPERTY_HINT_RANGE, "1,5,1")
	CTW_BIND(noise_lacunarity, FLOAT, PROPERTY_HINT_RANGE, "1.8,2.6,0.05")
	CTW_BIND(noise_gain, FLOAT, PROPERTY_HINT_RANGE, "0.3,0.65,0.01")
	ADD_GROUP("Caves", "");
	CTW_BIND(caves_enabled, BOOL, PROPERTY_HINT_NONE, "")
	ADD_GROUP("Meshing", "");
	CTW_BIND(iso_level, FLOAT, PROPERTY_HINT_NONE, "")
	CTW_BIND(generate_collision, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(loose_rock_voxels, INT, PROPERTY_HINT_RANGE, "0,64,1")
	ClassDB::bind_method(D_METHOD("set_terrain_material", "value"), &ChunkedTerrainWorld::set_terrain_material);
	ClassDB::bind_method(D_METHOD("get_terrain_material"), &ChunkedTerrainWorld::get_terrain_material);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_terrain_material", "get_terrain_material");
	ADD_GROUP("Runtime", "");
	CTW_BIND(is_playable_world, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(rebuild_on_ready, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(auto_rebuild_in_editor, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(use_threaded_rebuild, BOOL, PROPERTY_HINT_NONE, "")
	CTW_BIND(max_concurrent_rebuild_tasks, INT, PROPERTY_HINT_RANGE, "1,8,1")
	CTW_BIND(play_ring, FLOAT, PROPERTY_HINT_RANGE, "0,256,1,suffix:m")
	CTW_BIND(stream_underground, BOOL, PROPERTY_HINT_NONE, "")
	ADD_GROUP("", "");
	const int script_only = PROPERTY_USAGE_NONE;
	ClassDB::bind_method(D_METHOD("set_edit_bounds", "value"), &ChunkedTerrainWorld::set_edit_bounds);
	ClassDB::bind_method(D_METHOD("get_edit_bounds"), &ChunkedTerrainWorld::get_edit_bounds);
	ADD_PROPERTY(PropertyInfo(Variant::AABB, "edit_bounds", PROPERTY_HINT_NONE, "", script_only), "set_edit_bounds", "get_edit_bounds");
	ClassDB::bind_method(D_METHOD("set_solids", "value"), &ChunkedTerrainWorld::set_solids);
	ClassDB::bind_method(D_METHOD("get_solids"), &ChunkedTerrainWorld::get_solids);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "solids", PROPERTY_HINT_NONE, "", script_only), "set_solids", "get_solids");
	ClassDB::bind_method(D_METHOD("set_edit_gate", "value"), &ChunkedTerrainWorld::set_edit_gate);
	ClassDB::bind_method(D_METHOD("get_edit_gate"), &ChunkedTerrainWorld::get_edit_gate);
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "edit_gate", PROPERTY_HINT_NONE, "", script_only), "set_edit_gate", "get_edit_gate");
#undef CTW_BIND
}

} // namespace godot
