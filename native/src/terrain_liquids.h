// The liquids in a terrain's caves and on its ground: water, sewage and hot water held in the
// terrain's own voxel grid, one cell a sample, each cell with how full it is (0 to 1) and which
// liquid it holds. A chunk's cells come from its build (`LiquidSeed`): which are solid ground, and
// the water the map starts with. Thirty times a second liquid falls into the open cell under it
// and spreads sideways into lower neighbours, but only in the cells that are awake (that changed,
// or whose neighbour did), so a still lake costs nothing. A dig rebuilds its chunks, their new
// seeds say which cells opened or filled in, and the cells round them wake: the water runs into
// the hole and the level it left drops. Liquid reaching a chunk the terrain has not built asks for
// that chunk's cells and waits at its face until they come. Each chunk with liquid is meshed as
// the zero crossing of a field made from how full its cells are, coloured by liquid.
#pragma once

#include "common.h"
#include "flying_edges_mesher.h"
#include "liquid_seed.h"

#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/templates/local_vector.hpp>

namespace godot {

class ChunkedTerrainWorld;
class TerrainSettings;

// One chunk's cells. The liquid arrays stay empty while the chunk is dry.
struct LiquidChunk {
	LocalVector<uint8_t> solid;
	LocalVector<float> mass;
	LocalVector<uint8_t> kind;
	// 1 while the cell is on the next step's list.
	LocalVector<uint8_t> awake;
	// The liquid has moved here since the seed: the chunk is kept when the terrain unloads it.
	bool touched = false;
	// On the list of chunks to mesh again.
	bool stale = false;
	MeshInstance3D *mesh = nullptr;

	bool is_wet() const { return !mass.is_empty(); }
	void make_wet();
};

// Chunks the liquid reached before the terrain built them, seeded on a worker.
struct LiquidSeedJob {
	LocalVector<Vector3i> chunk_coordinates;
	Ref<TerrainSettings> settings;
	LocalVector<Ref<LiquidSeed>> seeds;
	int64_t task_id = -1;

	static void run(void *p_userdata);
};

class TerrainLiquids : public Node3D {
	GDCLASS(TerrainLiquids, Node3D)

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	enum Kind {
		KIND_NONE = 0,
		KIND_WATER = 1,
		KIND_SEWAGE = 2,
		KIND_HOT_WATER = 3,
		KIND_COUNT = 4,
	};

	// A cell holding less than this dries up.
	static constexpr float MIN_MASS = 0.002f;
	// A cell does not spread into a neighbour less than this lower than itself.
	static constexpr float SPREAD_MIN = 0.01f;
	// A move smaller than this does not wake the cells round it.
	static constexpr float WAKE_MIN = 0.0005f;
	// The least a cell holds to be drawn, and how full a falling cell is drawn (a thin stream
	// shows as a column).
	static constexpr float SHOWN_MASS = 0.04f;
	static constexpr float FALLING_SHOWN = 0.7f;
	static constexpr double STEP_SECONDS = 1.0 / 30.0;
	static constexpr int MAX_STEPS_PER_FRAME = 3;
	// The frame's time for the flow: a step that does not fit carries on next frame, so a big
	// flood runs slower instead of holding the frame up.
	static constexpr int FLOW_BUDGET_USEC = 1500;
	static constexpr int MESH_BUDGET_USEC = 3000;
	static constexpr int SEED_JOBS = 2;
	static constexpr int SEED_JOB_CHUNKS = 4;
	// How far up a column `liquid_at` climbs to its surface.
	static constexpr int MAX_COLUMN = 512;

	// The terrain that seeds the chunks the liquid reaches first (none in the tests).
	ChunkedTerrainWorld *world = nullptr;

	~TerrainLiquids();

	// The terrain's grid: cells a chunk side, the cell size, where sample 0 is (in the world and
	// in this node's frame) and how many chunks there are. A change clears the liquid.
	void configure(int p_cells, double p_step, const Vector3 &p_grid_world_origin, const Vector3 &p_grid_local_origin,
			const Vector3i &p_chunk_grid);
	void clear();
	// A chunk's cells from its build: new chunks are kept when they hold liquid or something
	// waits for them; a chunk already here takes the new solid cells and wakes round the change.
	void take_seed(const Ref<LiquidSeed> &p_seed);
	// The terrain freed a chunk: its cells go unless the liquid in them has moved.
	void unload(const Vector3i &p_chunk_coordinate);
	// One step of the flow over the awake cells.
	void step();
	// Steps until nothing is awake (or the limit); the steps taken.
	int settle(int p_max_steps);
	// Asks for a chunk's cells (kept when they come, even dry): somewhere liquid is about to go.
	void request_chunk(const Vector3i &p_chunk_coordinate);
	// Pours liquid into the open cells at a point and up its column; the volume that fitted.
	double add_liquid(const Vector3 &p_world_position, double p_volume, int p_kind);
	// The liquid at a point: {kind, depth (how far under the surface, below 0 over it),
	// surface (its height)}; kind is KIND_NONE when there is none in reach.
	Dictionary liquid_at(const Vector3 &p_world_position) const;
	// Meshes every chunk waiting to be meshed now.
	void remesh_all();
	Ref<TerrainMeshResult> build_mesh(const Vector3i &p_chunk_coordinate) const;
	static Color kind_color(int p_kind);

	Vector3i cell_of(const Vector3 &p_world_position) const;
	double mass_at_cell(const Vector3i &p_cell) const;
	int kind_at_cell(const Vector3i &p_cell) const;
	double get_total_volume() const;
	// Where liquid meets open air over it (a pool's surface), up to a limit of points.
	PackedVector3Array surface_points(int p_limit) const;
	int get_awake_count() const { return (int)(awake_next.size() + awake_now.size() - awake_cursor); }
	int get_chunk_count() const { return (int)chunks.size(); }
	int get_wet_chunk_count() const;
	int get_cells() const { return cells; }
	double get_step_size() const { return step_size; }
	bool has_chunk(const Vector3i &p_chunk_coordinate) const { return chunks.has(p_chunk_coordinate); }
	bool is_waiting_for(const Vector3i &p_chunk_coordinate) const;
	void set_material(const Ref<Material> &p_material) { material = p_material; }
	Ref<Material> get_material() const { return material; }

private:
	enum CellState {
		CELL_OPEN,
		CELL_SOLID,
		CELL_MISSING,
	};

	int cells = 0;
	// log2 of `cells` when it is a power of two (every map's is), else -1: shifts, not divisions.
	int cell_shift = -1;
	double step_size = 1.0;
	Vector3 grid_world_origin;
	Vector3 grid_local_origin;
	Vector3i chunk_grid;
	HashMap<Vector3i, LiquidChunk *> chunks;
	// The same chunks by place in the grid (x fastest), for the flow's lookups.
	LocalVector<LiquidChunk *> table;
	LocalVector<Vector3i> awake_now;
	// How far through `awake_now` the step under way has got.
	uint32_t awake_cursor = 0;
	LocalVector<Vector3i> awake_next;
	LocalVector<Vector3i> stale_chunks;
	HashSet<Vector3i> wanted;
	HashSet<Vector3i> seeding;
	LocalVector<LiquidSeedJob *> seed_jobs;
	double step_time = 0.0;
	int tick = 0;
	Ref<Material> material;

	Vector3i chunk_coordinate_of(const Vector3i &p_cell) const;
	Vector3i local_of(const Vector3i &p_cell, const Vector3i &p_chunk_coordinate) const;
	bool in_grid(const Vector3i &p_chunk_coordinate) const;
	LiquidChunk *find_chunk(const Vector3i &p_chunk_coordinate) const;
	CellState resolve(const Vector3i &p_cell, LiquidChunk *&r_chunk, int &r_index) const;
	void wake(const Vector3i &p_cell);
	void wake_around(const Vector3i &p_cell);
	void wake_left(const Vector3i &p_cell);
	void flow_cell(const Vector3i &p_cell);
	// Starts a step when none is under way; false when nothing is awake.
	bool begin_step();
	// Moves the step under way on until it ends or the time is up (0: no limit); true when it ended.
	bool run_step(uint64_t p_deadline_usec);
	void move(LiquidChunk *p_from, int p_from_index, const Vector3i &p_from_cell, LiquidChunk *p_to, int p_to_index,
			const Vector3i &p_to_cell, float p_amount);
	void insert_chunk(const Vector3i &p_chunk_coordinate, LiquidChunk *p_chunk);
	void erase_chunk(const Vector3i &p_chunk_coordinate);
	int table_index(const Vector3i &p_chunk_coordinate) const {
		return p_chunk_coordinate.x + (p_chunk_coordinate.y + p_chunk_coordinate.z * chunk_grid.y) * chunk_grid.x;
	}
	void mark_stale(const Vector3i &p_cell);
	void mark_chunk_stale(const Vector3i &p_chunk_coordinate);
	void want(const Vector3i &p_cell);
	bool borders_wet(const Vector3i &p_chunk_coordinate) const;
	void wake_seams(const Vector3i &p_chunk_coordinate);
	void update_solids(LiquidChunk *p_chunk, const Vector3i &p_chunk_coordinate, const Ref<LiquidSeed> &p_seed);
	void push_up(const Vector3i &p_cell, float p_amount, uint8_t p_kind);
	void free_chunk(LiquidChunk *p_chunk);
	void process_frame(double p_delta);
	void fill_seed_jobs();
	void poll_seed_jobs();
	void wait_for_seed_jobs();
	void remesh_stale(uint64_t p_budget_usec);
	void apply_mesh(const Vector3i &p_chunk_coordinate);
};

} // namespace godot
