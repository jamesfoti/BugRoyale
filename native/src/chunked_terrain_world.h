// Shared chunked voxel terrain orchestration for the open and boxed-in worlds: the map's
// build behind the game (every chunk once, at full detail, the ground round the player
// first), the underground streamed round the bodies, the holds that keep a body off ground
// not built yet, the brush and its rebuilds, and the edits as saved and shared.
#pragma once

#include "chunk_mesh_builder.h"
#include "terrain_chunk.h"
#include "terrain_edits.h"
#include "world_density.h"

#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/node3d.hpp>

#include <deque>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {

class ChunkedTerrainWorld : public Node3D {
	GDCLASS(ChunkedTerrainWorld, Node3D)

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	using CoordSet = std::unordered_set<Vector3i, Vector3iHash>;
	template <typename T>
	using CoordMap = std::unordered_map<Vector3i, T, Vector3iHash>;

	static constexpr int REBUILD_THREADS = 4;
	static constexpr int FIELD_CACHE_CHUNKS = 512;
	static constexpr double FIGHTER_CLEARANCE = 0.1;
	static constexpr int CAPSULE_SAMPLES = 6;
	static constexpr int PLACE_BUDGET_USEC = 8000;
	static constexpr int BUILD_TASK_SAMPLES = 40000;
	static constexpr double DEEP_MARGIN = 8.0;
	static constexpr double STREAM_MARGIN = 32.0;
	static constexpr double STREAM_VIEW = 48.0;
	static constexpr double STREAM_BODY = 16.0;
	static constexpr double STREAM_KEEP = 16.0;
	static constexpr int STREAM_EVERY = 10;
	static constexpr double STREAM_URGENT = 8.0;
	static constexpr int STREAM_TASKS_BEFORE_PLAY = 2;
	static constexpr double GROUND_HOLD_REACH = 2.0;
	static constexpr int ORDER_EVERY = 120;

	// Tasks of the map's build on the pool at once (set from the processor count).
	static int world_build_in_flight();

	ChunkedTerrainWorld();
	~ChunkedTerrainWorld();

	// --- Exported settings ---
	double chunk_size = 12.0;
	int chunk_resolution = 1;
	double voxel_size = 1.0;
	bool noise_enabled = true;
	int noise_seed = 42;
	double noise_frequency = 0.008;
	double noise_amplitude = 3.0;
	int noise_octaves = 3;
	double noise_lacunarity = 2.0;
	double noise_gain = 0.5;
	bool caves_enabled = false;
	double iso_level = 0.0;
	bool generate_collision = true;
	int loose_rock_voxels = 8;
	Ref<Material> terrain_material;
	bool is_playable_world = true;
	bool rebuild_on_ready = true;
	bool auto_rebuild_in_editor = false;
	bool use_threaded_rebuild = true;
	int max_concurrent_rebuild_tasks = 4;
	double play_ring = 96.0;
	bool stream_underground = false;

	AABB edit_bounds;
	Array solids;
	Callable edit_gate;

	// --- Hooks a kind of world overrides ---
	virtual void _ensure_world_defaults() {}
	virtual void _register_playable_groups() {}
	virtual Vector3i _get_grid_dimensions() const { return Vector3i(3, 3, 3); }
	virtual String _get_world_log_name() const { return "Terrain"; }
	virtual void _apply_world_specific_settings(const Ref<TerrainSettings> &settings) {}
	virtual String _world_summary(const Ref<TerrainSettings> &settings) { return ""; }
	virtual Ref<WorldDensity> _build_world_density(const Ref<TerrainSettings> &settings);
	virtual double get_surface_datum_y() const { return get_global_position().y; }
	virtual Ref<Material> _effective_material() const { return terrain_material; }
	virtual void _request_rebuild();
	virtual void rebuild_all();
	virtual void on_ready();

	// --- The build ---
	void destroy_all();
	void rebuild_all_editor() { rebuild_all(); }
	bool is_building() const { return world_building; }
	void focus_build_at(const Vector3 &world_position, double radius = 0.0, bool primary = false);
	bool is_ground_ready_around(const Vector3 &world_position, double radius = 0.0);
	bool play_ground_ready();
	double get_built_reach(const Vector3 &world_position) const;
	void begin_build();
	bool ground_missing_under(Node3D *body);

	// --- Measures ---
	int get_chunk_count() const { return (int)chunks.size(); }
	int get_total_vertex_count() const;
	int get_total_triangle_count() const;
	int get_edited_voxel_count() const { return edits->get_override_count(); }
	Vector3i get_grid_dimensions() const { return _get_grid_dimensions(); }
	int get_base_cells_per_axis() const;
	int get_cells_per_axis() const { return get_base_cells_per_axis() * chunk_resolution; }
	int get_voxels_per_chunk() const;
	double get_chunk_world_extent() const { return chunk_size; }
	double get_world_step() const { return chunk_size / (double)get_cells_per_axis(); }
	double get_voxel_size() const { return get_world_step(); }
	Vector3 get_world_extents() const;
	double get_bedrock_y() const;
	Dictionary footing(const Vector3 &center, double half_x, double half_z, double top_y) const;
	Ref<TerrainSettings> get_settings_snapshot() { return _make_settings_snapshot(); }
	Ref<TerrainEdits> get_terrain_edits() const { return edits; }
	Vector3 get_grid_world_origin() const { return get_global_position() + get_grid_origin_local(); }
	Vector3 snap_to_sample(const Vector3 &world_position) const;
	Vector3 get_grid_origin_local() const { return -get_world_extents() * 0.5f; }

	// --- The brush and edits ---
	void begin_continuous_edit() { continuous_edit_depth += 1; }
	void end_continuous_edit();
	void prepare_edit_around(const Vector3 &world_position, double radius);
	bool is_solid_at(const Vector3 &world_position);
	double density_at(const Vector3 &world_position, const Variant &sample_cache = Variant());
	bool can_edit_at(const Vector3 &world_position) const;
	void apply_brush(const Vector3 &world_position, double radius, bool add_solid, int material = 0);
	void apply_box(const Vector3 &center, const Vector3 &half_extents, bool add_solid, int material = 0);
	static Dictionary sphere_edit(const Vector3 &world_position, double radius, bool add_solid, int material);
	static Dictionary box_edit(const Vector3 &center, const Vector3 &half_extents, bool add_solid, int material);
	bool apply_edit(Dictionary edit);
	bool allows_edit(const Dictionary &edit) const;
	static int estimate_voxels(const Dictionary &edit, double p_voxel_size);
	TypedArray<Dictionary> get_edit_log() const;
	Dictionary export_edit_state() const;
	void import_edit_state(const Dictionary &state);
	bool buries_fighter(const Dictionary &edit);
	static double fighter_clearance() { return FIGHTER_CLEARANCE; }

	// --- Internals the scripts and tests reach ---
	Ref<TerrainSettings> _make_settings_snapshot();
	Ref<TerrainSettings> _make_thread_settings_snapshot();
	Ref<WorldDensity> _get_bake_density();
	void _invalidate_bake_density();
	Ref<TerrainSettings> _build_settings();
	Vector3 _chunk_corner_local(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings) const;
	AABB _get_chunk_world_aabb(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings) const;
	bool _is_streamed(const Vector3i &chunk_coordinate) const;
	bool _stands(const Vector3i &chunk_coordinate) const;
	TypedArray<Vector3i> _chunks_touching_bound(const Vector3 &world_position, double radius);
	TypedArray<Vector2i> _columns_touching_bound(const Vector3 &world_position, double radius);
	Vector3 _grid_corner() const;
	void _queue_chunk_rebuild(const Vector3i &chunk_coordinate, const AABB &bounds);
	void _dispatch_pending_rebuilds();
	Dictionary _ground_round_bound(const Vector3 &world_position, double radius);
	int _build_group(const Vector3i &chunk_coordinate) const;
	TypedArray<Vector3i> _get_chunk_coordinates_intersecting_aabb_bound(const AABB &bounds);
	TypedArray<Vector3i> _get_chunk_coordinates_intersecting_sphere_bound(const Vector3 &center, double radius);
	String _world_summary_bound(const Ref<TerrainSettings> &settings) { return _world_summary(settings); }
	Ref<WorldDensity> _build_world_density_bound(const Ref<TerrainSettings> &settings) { return _build_world_density(settings); }
	Vector3i _get_grid_dimensions_bound() const { return _get_grid_dimensions(); }

	Dictionary _get_chunks_dict() const;
	Dictionary _get_deep_dict() const { return set_to_dict(deep); }
	Dictionary _get_placed_dict() const;
	Dictionary _get_async_jobs_dict() const;
	Dictionary _get_play_columns_dict() const;
	Dictionary _get_play_chunks_dict() const { return set_to_dict(play_chunks); }
	Dictionary _get_stream_loaded_dict() const { return set_to_dict(stream_loaded); }
	Dictionary _get_stream_inflight_dict() const { return set_to_dict(stream_inflight); }
	Dictionary _get_inflight_dict() const { return set_to_dict(inflight_chunk_coordinates); }
	Dictionary _get_pending_rebuilds_dict() const;
	Dictionary _get_field_cache_dict() const;
	Dictionary _get_world_build_tasks_dict() const;
	TypedArray<Vector3i> _get_world_build_queue() const;
	TypedArray<Vector3i> _get_stream_queue() const;
	int _get_world_build_placed() const { return world_build_placed; }
	int _get_world_build_total() const { return world_build_total; }
	int _get_running_async_tasks() const { return running_async_tasks; }
	int _get_async_jobs_count() const { return (int)async_jobs.size(); }
	bool _get_held_waiting() const { return play_waiting; }

	// --- Property accessors ---
	void set_chunk_size(double v);
	double get_chunk_size() const { return chunk_size; }
	void set_chunk_resolution(int v);
	int get_chunk_resolution() const { return chunk_resolution; }
	void set_voxel_size(double v);
	double get_voxel_size_setting() const { return voxel_size; }
	void set_noise_enabled(bool v);
	bool get_noise_enabled() const { return noise_enabled; }
	void set_noise_seed(int v);
	int get_noise_seed() const { return noise_seed; }
	void set_noise_frequency(double v);
	double get_noise_frequency() const { return noise_frequency; }
	void set_noise_amplitude(double v);
	double get_noise_amplitude() const { return noise_amplitude; }
	void set_noise_octaves(int v);
	int get_noise_octaves() const { return noise_octaves; }
	void set_noise_lacunarity(double v);
	double get_noise_lacunarity() const { return noise_lacunarity; }
	void set_noise_gain(double v);
	double get_noise_gain() const { return noise_gain; }
	void set_caves_enabled(bool v);
	bool get_caves_enabled() const { return caves_enabled; }
	void set_iso_level(double v);
	double get_iso_level() const { return iso_level; }
	void set_generate_collision(bool v);
	bool get_generate_collision() const { return generate_collision; }
	void set_loose_rock_voxels(int v);
	int get_loose_rock_voxels() const { return loose_rock_voxels; }
	void set_terrain_material(const Ref<Material> &v) { terrain_material = v; }
	Ref<Material> get_terrain_material() const { return terrain_material; }
	void set_is_playable_world(bool v) { is_playable_world = v; }
	bool get_is_playable_world() const { return is_playable_world; }
	void set_rebuild_on_ready(bool v) { rebuild_on_ready = v; }
	bool get_rebuild_on_ready() const { return rebuild_on_ready; }
	void set_auto_rebuild_in_editor(bool v) { auto_rebuild_in_editor = v; }
	bool get_auto_rebuild_in_editor() const { return auto_rebuild_in_editor; }
	void set_use_threaded_rebuild(bool v) { use_threaded_rebuild = v; }
	bool get_use_threaded_rebuild() const { return use_threaded_rebuild; }
	void set_max_concurrent_rebuild_tasks(int v) { max_concurrent_rebuild_tasks = v; }
	int get_max_concurrent_rebuild_tasks() const { return max_concurrent_rebuild_tasks; }
	void set_play_ring(double v) { play_ring = v; }
	double get_play_ring() const { return play_ring; }
	void set_stream_underground(bool v) { stream_underground = v; }
	bool get_stream_underground() const { return stream_underground; }
	void set_edit_bounds(const AABB &v) { edit_bounds = v; }
	AABB get_edit_bounds() const { return edit_bounds; }
	void set_solids(const Array &v);
	TypedArray<Dictionary> get_solids() const;
	void set_edit_gate(const Callable &v) { edit_gate = v; }
	Callable get_edit_gate() const { return edit_gate; }

protected:
	// Setters call this: the density caches are stale and a rebuild may be due.
	void settings_changed();
	static Dictionary set_to_dict(const CoordSet &set);
	std::vector<Vector3i> _chunks_touching(const Vector3 &world_position, double radius);
	std::vector<Vector2i> _columns_touching(const Vector3 &world_position, double radius);
	CoordSet _ground_round(const Vector3 &world_position, double radius);
	std::vector<Vector3i> _get_chunk_coordinates_intersecting_aabb(const AABB &bounds);

	CoordMap<TerrainChunk *> chunks;
	bool rebuild_queued = false;
	Ref<TerrainEdits> edits;
	std::vector<Dictionary> edit_log;
	int next_edit_sequence = 1;
	int continuous_edit_depth = 0;
	Ref<WorldDensity> bake_density;
	Ref<WorldDensity> density_prototype;
	Vector3 prototype_origin;
	CoordMap<AABB> pending_rebuilds;
	std::vector<Vector3i> pending_order;
	struct ChunkCache {
		Ref<SignedDensityField> field;
		Ref<ChunkMeshBlocks> blocks;
	};
	CoordMap<ChunkCache> field_cache;
	std::deque<Vector3i> field_cache_order;
	bool pending_rebuild_collision = false;
	bool async_rebuild_requested = false;
	std::vector<std::unique_ptr<BuildJob>> async_jobs;
	int running_async_tasks = 0;
	CoordSet inflight_chunk_coordinates;

	bool world_building = false;
	std::vector<Vector3i> world_build_queue;
	std::vector<std::unique_ptr<BuildJob>> world_build_tasks;
	Ref<TerrainSettings> world_build_settings;
	Vector3i world_build_grid;
	int world_build_total = 0;
	int world_build_placed = 0;
	int64_t world_build_started_msec = 0;
	std::vector<Vector4> build_focus;
	std::vector<Vector4> primary_focus;
	std::vector<Vector4> order_focus;
	int order_tick = 0;
	bool queue_stale = false;
	std::vector<uint8_t> play_columns;
	int play_column_count = 0;
	CoordSet play_chunks;
	CoordSet deep;
	CoordSet placed;
	// The order the map's build placed its chunks in (the scripts' _placed kept it).
	std::vector<Vector3i> placed_order;
	std::vector<int> column_missing;

	std::vector<int> stream_floor;
	Vector3i stream_grid;
	CoordSet stream_loaded;
	CoordSet stream_inflight;
	std::vector<std::unique_ptr<BuildJob>> stream_tasks;
	CoordMap<double> stream_wanted;
	CoordSet stream_keep;
	std::vector<Vector3i> stream_queue;
	int stream_tick = 0;
	bool play_waiting = true;

	void process_frame();
	void physics_frame();
	void abandon_world_build();
	void reset_stream();
	void clear_chunks();
	void rebuild_all_sync(const Ref<TerrainSettings> &settings, const Vector3i &grid_dimensions);
	void build_chunk_at(const Vector3i &chunk_coordinate, const Ref<ChunkBuildResult> &result,
			const Ref<TerrainSettings> &settings);
	void log_rebuild_complete(int chunk_count, const Ref<TerrainSettings> &settings, const Vector3i &grid_dimensions,
			int64_t elapsed_ms);
	void deferred_rebuild();
	bool use_threaded() const;
	void queue_every_chunk();
	void mark_deep_chunks(const Ref<TerrainSettings> &settings, const Vector3i &grid);
	void count_missing_columns();
	void poll_world_build();
	void place_built_chunk(BuildJob *job, int index);
	void note_placed_chunk(const Vector3i &chunk_coordinate);
	void fill_world_build();
	int pool_load() const { return (int)(world_build_tasks.size() + stream_tasks.size()) + running_async_tasks; }
	int build_task_chunks() const;
	void sort_world_build_queue();
	double focus_distance(const Vector2 &column_centre) const;
	void chunk_span(const Vector3 &world_position, double radius, Vector3i &low, Vector3i &high);
	CoordSet play_ground();
	void add_surface_band(const Vector2i &column, CoordSet &out) const;
	bool ground_complete(const CoordSet &set) const;
	void emit_build_progress();
	void follow_local_player();
	bool streaming() const;
	int streamed_below(const Vector2i &column) const;
	void look_for_streamed_chunks();
	void want_round(const Vector3 &point, double reach, CoordMap<double> &wanted, CoordSet &keep) const;
	void free_streamed_chunk(const Vector3i &chunk_coordinate);
	void fill_stream();
	bool stream_waiting() const;
	void poll_stream();
	void hold_bodies_off_missing_ground();
	static bool is_local_body(Node3D *body);
	void prepare_edits();
	void rebuild_changed_chunks();
	void start_single_chunk_async_rebuild(const Vector3i &chunk_coordinate, bool rebuild_collision,
			const AABB &bounds = AABB(), bool prepare_only = false);
	void poll_async_rebuilds();
	void apply_async_job(BuildJob *job);
	void rebuild_chunk_coordinates(const std::vector<Vector3i> &chunk_coordinates, Ref<TerrainSettings> settings);
	bool edit_overlaps_body(const Dictionary &edit, Node3D *body);
	void submit(std::vector<std::unique_ptr<BuildJob>> &tasks, std::unique_ptr<BuildJob> job, const String &description);
	bool job_done(BuildJob *job);
	int column_index(int x, int z) const { return x + z * world_build_grid.x; }
	bool play_column(const Vector2i &column) const;
};

} // namespace godot
