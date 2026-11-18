#include "terrain_liquids.h"

#include "chunked_terrain_world.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>

namespace godot {

static const char *LIQUID_MATERIAL_PATH = "res://materials/terrain_liquid.tres";

static const Vector3i SIDEWAYS[4] = { Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1) };
static const Vector3i FACES[6] = { Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1) };
static const Vector3i UP = Vector3i(0, 1, 0);

// A lake equalises to this; spreading onto a dry cell needs `SPREAD_MIN`.
static constexpr float LEVEL_MIN = 0.0005f;

void LiquidChunk::make_wet() {
	if (is_wet()) {
		return;
	}
	uint32_t count = solid.size();
	mass.resize(count);
	kind.resize(count);
	awake.resize(count);
	for (uint32_t cell = 0; cell < count; cell++) {
		mass[cell] = 0.0f;
		kind[cell] = TerrainLiquids::KIND_NONE;
		awake[cell] = 0;
	}
}

void LiquidSeedJob::run(void *p_userdata) {
	LiquidSeedJob *job = static_cast<LiquidSeedJob *>(p_userdata);
	job->seeds.resize(job->chunk_coordinates.size());
	for (uint32_t position = 0; position < job->chunk_coordinates.size(); position++) {
		job->seeds[position] = LiquidSeed::build(job->chunk_coordinates[position], job->settings);
	}
}

TerrainLiquids::~TerrainLiquids() {
	wait_for_seed_jobs();
	for (KeyValue<Vector3i, LiquidChunk *> &entry : chunks) {
		memdelete(entry.value);
	}
	chunks.clear();
}

// --- Lifetime -------------------------------------------------------------------------------------

void TerrainLiquids::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
			set_process(true);
			break;
		case NOTIFICATION_PROCESS:
			process_frame(get_process_delta_time());
			break;
		case NOTIFICATION_EXIT_TREE:
			wait_for_seed_jobs();
			break;
		default:
			break;
	}
}

void TerrainLiquids::process_frame(double p_delta) {
	if (Engine::get_singleton()->is_editor_hint()) {
		remesh_stale(MESH_BUDGET_USEC);
		return;
	}
	poll_seed_jobs();
	step_time = MIN(step_time + p_delta, STEP_SECONDS * (double)MAX_STEPS_PER_FRAME);
	uint64_t deadline = Time::get_singleton()->get_ticks_usec() + FLOW_BUDGET_USEC;
	while (true) {
		bool under_way = awake_cursor < awake_now.size();
		if (!under_way) {
			if (step_time < STEP_SECONDS) {
				break;
			}
			step_time -= STEP_SECONDS;
			if (!begin_step()) {
				continue;
			}
		}
		if (!run_step(deadline)) {
			break;
		}
	}
	fill_seed_jobs();
	remesh_stale(MESH_BUDGET_USEC);
}

void TerrainLiquids::configure(int p_cells, double p_step, const Vector3 &p_grid_world_origin,
		const Vector3 &p_grid_local_origin, const Vector3i &p_chunk_grid) {
	bool same = p_cells == cells && tmath::approx(p_step, step_size) &&
			p_grid_world_origin.is_equal_approx(grid_world_origin) && p_chunk_grid == chunk_grid;
	if (!same) {
		clear();
	}
	cells = p_cells;
	cell_shift = -1;
	for (int shift = 0; shift < 16; shift++) {
		if ((1 << shift) == cells) {
			cell_shift = shift;
		}
	}
	step_size = p_step;
	grid_world_origin = p_grid_world_origin;
	grid_local_origin = p_grid_local_origin;
	chunk_grid = p_chunk_grid.max(Vector3i());
	if (!same) {
		table.resize(chunk_grid.x * chunk_grid.y * chunk_grid.z);
		for (uint32_t position = 0; position < table.size(); position++) {
			table[position] = nullptr;
		}
	}
}

void TerrainLiquids::insert_chunk(const Vector3i &p_chunk_coordinate, LiquidChunk *p_chunk) {
	chunks.insert(p_chunk_coordinate, p_chunk);
	table[table_index(p_chunk_coordinate)] = p_chunk;
}

void TerrainLiquids::erase_chunk(const Vector3i &p_chunk_coordinate) {
	chunks.erase(p_chunk_coordinate);
	table[table_index(p_chunk_coordinate)] = nullptr;
}

void TerrainLiquids::clear() {
	wait_for_seed_jobs();
	for (KeyValue<Vector3i, LiquidChunk *> &entry : chunks) {
		free_chunk(entry.value);
	}
	chunks.clear();
	for (uint32_t position = 0; position < table.size(); position++) {
		table[position] = nullptr;
	}
	awake_now.clear();
	awake_cursor = 0;
	awake_next.clear();
	stale_chunks.clear();
	wanted.clear();
	seeding.clear();
	step_time = 0.0;
}

void TerrainLiquids::free_chunk(LiquidChunk *p_chunk) {
	if (p_chunk->mesh != nullptr) {
		p_chunk->mesh->queue_free();
		p_chunk->mesh = nullptr;
	}
	memdelete(p_chunk);
}

// --- The grid -------------------------------------------------------------------------------------

Vector3i TerrainLiquids::cell_of(const Vector3 &p_world_position) const {
	Vector3 local = (p_world_position - grid_world_origin) / (real_t)step_size;
	return Vector3i(tmath::roundi(local.x), tmath::roundi(local.y), tmath::roundi(local.z));
}

Vector3i TerrainLiquids::chunk_coordinate_of(const Vector3i &p_cell) const {
	if (cell_shift >= 0) {
		// An arithmetic shift floors negative cells too.
		return Vector3i(p_cell.x >> cell_shift, p_cell.y >> cell_shift, p_cell.z >> cell_shift);
	}
	return Vector3i(tmath::floor_div(p_cell.x, cells), tmath::floor_div(p_cell.y, cells),
			tmath::floor_div(p_cell.z, cells));
}

Vector3i TerrainLiquids::local_of(const Vector3i &p_cell, const Vector3i &p_chunk_coordinate) const {
	return p_cell - p_chunk_coordinate * cells;
}

bool TerrainLiquids::in_grid(const Vector3i &p_chunk_coordinate) const {
	return p_chunk_coordinate.x >= 0 && p_chunk_coordinate.y >= 0 && p_chunk_coordinate.z >= 0 &&
			p_chunk_coordinate.x < chunk_grid.x && p_chunk_coordinate.y < chunk_grid.y &&
			p_chunk_coordinate.z < chunk_grid.z;
}

LiquidChunk *TerrainLiquids::find_chunk(const Vector3i &p_chunk_coordinate) const {
	if (!in_grid(p_chunk_coordinate)) {
		return nullptr;
	}
	return table[table_index(p_chunk_coordinate)];
}

TerrainLiquids::CellState TerrainLiquids::resolve(const Vector3i &p_cell, LiquidChunk *&r_chunk, int &r_index) const {
	r_chunk = nullptr;
	r_index = 0;
	if (cells <= 0) {
		return CELL_SOLID;
	}
	Vector3i chunk_coordinate = chunk_coordinate_of(p_cell);
	if (!in_grid(chunk_coordinate)) {
		return CELL_SOLID;
	}
	LiquidChunk *chunk = table[table_index(chunk_coordinate)];
	if (chunk == nullptr) {
		return CELL_MISSING;
	}
	Vector3i local = local_of(p_cell, chunk_coordinate);
	r_chunk = chunk;
	r_index = local.x + (local.y + local.z * cells) * cells;
	return chunk->solid[r_index] != 0 ? CELL_SOLID : CELL_OPEN;
}

double TerrainLiquids::mass_at_cell(const Vector3i &p_cell) const {
	LiquidChunk *chunk = nullptr;
	int index = 0;
	if (resolve(p_cell, chunk, index) != CELL_OPEN || !chunk->is_wet()) {
		return 0.0;
	}
	return chunk->mass[index];
}

int TerrainLiquids::kind_at_cell(const Vector3i &p_cell) const {
	LiquidChunk *chunk = nullptr;
	int index = 0;
	if (resolve(p_cell, chunk, index) != CELL_OPEN || !chunk->is_wet() || chunk->mass[index] <= 0.0f) {
		return KIND_NONE;
	}
	return chunk->kind[index];
}

bool TerrainLiquids::is_waiting_for(const Vector3i &p_chunk_coordinate) const {
	return wanted.has(p_chunk_coordinate) || seeding.has(p_chunk_coordinate);
}

// --- Seeds ----------------------------------------------------------------------------------------

void TerrainLiquids::take_seed(const Ref<LiquidSeed> &p_seed) {
	if (p_seed.is_null() || cells <= 0 || p_seed->cells != cells) {
		return;
	}
	Vector3i chunk_coordinate = p_seed->chunk_coordinate;
	if (!in_grid(chunk_coordinate)) {
		return;
	}
	bool asked = wanted.has(chunk_coordinate) || seeding.has(chunk_coordinate);
	wanted.erase(chunk_coordinate);
	seeding.erase(chunk_coordinate);
	LiquidChunk *existing = find_chunk(chunk_coordinate);
	if (existing != nullptr) {
		update_solids(existing, chunk_coordinate, p_seed);
		return;
	}
	if (!asked && p_seed->is_dry() && !borders_wet(chunk_coordinate)) {
		return;
	}
	LiquidChunk *chunk = memnew(LiquidChunk);
	int count = cells * cells * cells;
	chunk->solid.resize(count);
	const uint8_t *solid = p_seed->solid.ptr();
	for (int cell = 0; cell < count; cell++) {
		chunk->solid[cell] = solid[cell];
	}
	if (!p_seed->is_dry()) {
		chunk->make_wet();
		const float *mass = p_seed->mass.ptr();
		const uint8_t *kind = p_seed->kind.ptr();
		for (int cell = 0; cell < count; cell++) {
			chunk->mass[cell] = mass[cell];
			chunk->kind[cell] = kind[cell];
		}
	}
	insert_chunk(chunk_coordinate, chunk);
	wake_seams(chunk_coordinate);
	if (chunk->is_wet()) {
		for (int offset_z = -1; offset_z < 2; offset_z++) {
			for (int offset_y = -1; offset_y < 2; offset_y++) {
				for (int offset_x = -1; offset_x < 2; offset_x++) {
					mark_chunk_stale(chunk_coordinate + Vector3i(offset_x, offset_y, offset_z));
				}
			}
		}
	}
}

bool TerrainLiquids::borders_wet(const Vector3i &p_chunk_coordinate) const {
	for (const Vector3i &face : FACES) {
		LiquidChunk *neighbour = find_chunk(p_chunk_coordinate + face);
		if (neighbour != nullptr && neighbour->is_wet()) {
			return true;
		}
	}
	return false;
}

// Wakes the cells on each face the new chunk shares with one already here whose liquid can now
// cross it: a fuller cell beside an emptier one, or liquid over a cell with room.
void TerrainLiquids::wake_seams(const Vector3i &p_chunk_coordinate) {
	for (const Vector3i &face : FACES) {
		if (find_chunk(p_chunk_coordinate + face) == nullptr) {
			continue;
		}
		int axis = face.x != 0 ? 0 : (face.y != 0 ? 1 : 2);
		int along = (face.x + face.y + face.z) > 0 ? cells - 1 : 0;
		for (int first = 0; first < cells; first++) {
			for (int second = 0; second < cells; second++) {
				Vector3i local;
				if (axis == 0) {
					local = Vector3i(along, first, second);
				} else if (axis == 1) {
					local = Vector3i(first, along, second);
				} else {
					local = Vector3i(first, second, along);
				}
				Vector3i inside = p_chunk_coordinate * cells + local;
				Vector3i outside = inside + face;
				LiquidChunk *inside_chunk = nullptr;
				LiquidChunk *outside_chunk = nullptr;
				int inside_index = 0;
				int outside_index = 0;
				if (resolve(inside, inside_chunk, inside_index) != CELL_OPEN ||
						resolve(outside, outside_chunk, outside_index) != CELL_OPEN) {
					continue;
				}
				float inside_mass = inside_chunk->is_wet() ? inside_chunk->mass[inside_index] : 0.0f;
				float outside_mass = outside_chunk->is_wet() ? outside_chunk->mass[outside_index] : 0.0f;
				if (face.y == 0) {
					if (inside_mass - outside_mass > LEVEL_MIN) {
						wake(inside);
					} else if (outside_mass - inside_mass > LEVEL_MIN) {
						wake(outside);
					}
				} else if (face.y < 0) {
					if (inside_mass > 0.0f && outside_mass < 1.0f) {
						wake(inside);
					}
				} else if (outside_mass > 0.0f && inside_mass < 1.0f) {
					wake(outside);
				}
			}
		}
	}
}

// The chunk was built again (a dig or a fill): cells that opened wake their neighbours, and the
// liquid in cells that filled in is pushed up out of the ground.
void TerrainLiquids::update_solids(LiquidChunk *p_chunk, const Vector3i &p_chunk_coordinate,
		const Ref<LiquidSeed> &p_seed) {
	const uint8_t *solid = p_seed->solid.ptr();
	Vector3i corner = p_chunk_coordinate * cells;
	for (int z = 0; z < cells; z++) {
		for (int y = 0; y < cells; y++) {
			for (int x = 0; x < cells; x++) {
				int index = x + (y + z * cells) * cells;
				if (p_chunk->solid[index] == solid[index]) {
					continue;
				}
				p_chunk->solid[index] = solid[index];
				Vector3i cell = corner + Vector3i(x, y, z);
				if (solid[index] != 0 && p_chunk->is_wet() && p_chunk->mass[index] > 0.0f) {
					float displaced = p_chunk->mass[index];
					uint8_t kind = p_chunk->kind[index];
					p_chunk->mass[index] = 0.0f;
					p_chunk->kind[index] = KIND_NONE;
					p_chunk->touched = true;
					push_up(cell, displaced, kind);
				}
				wake_around(cell);
				mark_stale(cell);
			}
		}
	}
}

void TerrainLiquids::push_up(const Vector3i &p_cell, float p_amount, uint8_t p_kind) {
	float remaining = p_amount;
	Vector3i cell = p_cell;
	for (int climb = 0; climb < 8 && remaining > 0.0f; climb++) {
		cell += UP;
		LiquidChunk *chunk = nullptr;
		int index = 0;
		if (resolve(cell, chunk, index) != CELL_OPEN) {
			continue;
		}
		chunk->make_wet();
		float room = 1.0f - chunk->mass[index];
		if (room <= 0.0f) {
			continue;
		}
		float put = MIN(room, remaining);
		if (chunk->mass[index] < put) {
			chunk->kind[index] = p_kind;
		}
		chunk->mass[index] += put;
		chunk->touched = true;
		remaining -= put;
		wake(cell);
		mark_stale(cell);
	}
}

void TerrainLiquids::unload(const Vector3i &p_chunk_coordinate) {
	LiquidChunk *chunk = find_chunk(p_chunk_coordinate);
	if (chunk == nullptr || chunk->touched) {
		return;
	}
	free_chunk(chunk);
	erase_chunk(p_chunk_coordinate);
}

void TerrainLiquids::want(const Vector3i &p_cell) {
	Vector3i chunk_coordinate = chunk_coordinate_of(p_cell);
	if (!in_grid(chunk_coordinate) || chunks.has(chunk_coordinate) || seeding.has(chunk_coordinate)) {
		return;
	}
	wanted.insert(chunk_coordinate);
}

void TerrainLiquids::request_chunk(const Vector3i &p_chunk_coordinate) {
	if (!in_grid(p_chunk_coordinate) || chunks.has(p_chunk_coordinate) || seeding.has(p_chunk_coordinate)) {
		return;
	}
	wanted.insert(p_chunk_coordinate);
}

void TerrainLiquids::fill_seed_jobs() {
	if (world == nullptr) {
		return;
	}
	while ((int)seed_jobs.size() < SEED_JOBS && !wanted.is_empty()) {
		LocalVector<Vector3i> taken;
		for (const Vector3i &chunk_coordinate : wanted) {
			if ((int)taken.size() >= SEED_JOB_CHUNKS) {
				break;
			}
			taken.push_back(chunk_coordinate);
		}
		LiquidSeedJob *job = memnew(LiquidSeedJob);
		for (const Vector3i &chunk_coordinate : taken) {
			wanted.erase(chunk_coordinate);
			if (chunks.has(chunk_coordinate) || seeding.has(chunk_coordinate)) {
				continue;
			}
			seeding.insert(chunk_coordinate);
			job->chunk_coordinates.push_back(chunk_coordinate);
		}
		if (job->chunk_coordinates.is_empty()) {
			memdelete(job);
			continue;
		}
		job->settings = world->_make_thread_settings_snapshot();
		job->task_id = WorkerThreadPool::get_singleton()->add_native_task(&LiquidSeedJob::run, job, true,
				"Liquid seeds");
		seed_jobs.push_back(job);
	}
}

void TerrainLiquids::poll_seed_jobs() {
	uint32_t position = 0;
	while (position < seed_jobs.size()) {
		LiquidSeedJob *job = seed_jobs[position];
		if (!WorkerThreadPool::get_singleton()->is_task_completed(job->task_id)) {
			position++;
			continue;
		}
		WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
		for (const Ref<LiquidSeed> &seed : job->seeds) {
			if (seeding.has(seed->chunk_coordinate)) {
				take_seed(seed);
			}
		}
		memdelete(job);
		seed_jobs.remove_at_unordered(position);
	}
}

void TerrainLiquids::wait_for_seed_jobs() {
	for (LiquidSeedJob *job : seed_jobs) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(job->task_id);
		memdelete(job);
	}
	seed_jobs.clear();
	seeding.clear();
}

// --- The flow -------------------------------------------------------------------------------------

void TerrainLiquids::wake(const Vector3i &p_cell) {
	LiquidChunk *chunk = nullptr;
	int index = 0;
	if (resolve(p_cell, chunk, index) != CELL_OPEN || !chunk->is_wet()) {
		return;
	}
	if (chunk->awake[index] != 0 || chunk->mass[index] <= 0.0f) {
		return;
	}
	chunk->awake[index] = 1;
	awake_next.push_back(p_cell);
}

void TerrainLiquids::wake_around(const Vector3i &p_cell) {
	wake(p_cell);
	for (const Vector3i &face : FACES) {
		wake(p_cell + face);
	}
}

bool TerrainLiquids::begin_step() {
	if (awake_cursor < awake_now.size()) {
		return true;
	}
	if (awake_next.is_empty()) {
		return false;
	}
	tick += 1;
	awake_now = awake_next;
	awake_next.clear();
	awake_cursor = 0;
	return true;
}

bool TerrainLiquids::run_step(uint64_t p_deadline_usec) {
	uint32_t count = awake_now.size();
	while (awake_cursor < count) {
		// The clock is read every so many cells: it costs more than a cell.
		if (p_deadline_usec > 0 && (awake_cursor & 255) == 255 &&
				Time::get_singleton()->get_ticks_usec() >= p_deadline_usec) {
			return false;
		}
		Vector3i cell = awake_now[awake_cursor];
		awake_cursor += 1;
		LiquidChunk *chunk = nullptr;
		int index = 0;
		if (resolve(cell, chunk, index) == CELL_MISSING || chunk == nullptr || !chunk->is_wet()) {
			continue;
		}
		chunk->awake[index] = 0;
		flow_cell(cell);
	}
	awake_now.clear();
	awake_cursor = 0;
	return true;
}

void TerrainLiquids::step() {
	if (begin_step()) {
		run_step(0);
	}
}

int TerrainLiquids::settle(int p_max_steps) {
	int taken = 0;
	while (taken < p_max_steps && get_awake_count() > 0) {
		step();
		taken += 1;
	}
	return taken;
}

void TerrainLiquids::flow_cell(const Vector3i &p_cell) {
	LiquidChunk *chunk = nullptr;
	int index = 0;
	if (resolve(p_cell, chunk, index) != CELL_OPEN || !chunk->is_wet()) {
		return;
	}
	float mass = chunk->mass[index];
	if (mass <= 0.0f) {
		return;
	}
	if (mass < MIN_MASS) {
		chunk->mass[index] = 0.0f;
		chunk->kind[index] = KIND_NONE;
		mark_stale(p_cell);
		return;
	}
	// Down first, as much as the cell under has room for.
	Vector3i below = p_cell - UP;
	LiquidChunk *below_chunk = nullptr;
	int below_index = 0;
	CellState below_state = resolve(below, below_chunk, below_index);
	bool moved = false;
	if (below_state == CELL_OPEN) {
		float below_mass = below_chunk->is_wet() ? below_chunk->mass[below_index] : 0.0f;
		float room = 1.0f - below_mass;
		if (room > 0.0f) {
			float flow = MIN(mass, room);
			move(chunk, index, p_cell, below_chunk, below_index, below, flow);
			mass -= flow;
			if (flow >= WAKE_MIN) {
				wake(below);
				moved = true;
			}
		}
	} else if (below_state == CELL_MISSING) {
		want(below);
	}
	if (mass < MIN_MASS) {
		if (moved) {
			wake_left(p_cell);
		}
		return;
	}
	// Then sideways, a quarter of the difference to each lower neighbour (starting from a
	// different side each step so no side is favoured).
	LiquidChunk *targets[4];
	int target_indices[4];
	Vector3i target_cells[4];
	float flows[4];
	int target_count = 0;
	int first = (tick + p_cell.x + p_cell.z) & 3;
	for (int turn = 0; turn < 4; turn++) {
		Vector3i neighbour = p_cell + SIDEWAYS[(first + turn) & 3];
		LiquidChunk *neighbour_chunk = nullptr;
		int neighbour_index = 0;
		CellState state = resolve(neighbour, neighbour_chunk, neighbour_index);
		if (state == CELL_MISSING) {
			if (mass > SPREAD_MIN) {
				want(neighbour);
			}
			continue;
		}
		if (state != CELL_OPEN) {
			continue;
		}
		float neighbour_mass = neighbour_chunk->is_wet() ? neighbour_chunk->mass[neighbour_index] : 0.0f;
		float difference = mass - neighbour_mass;
		float least = neighbour_mass > 0.0f ? LEVEL_MIN : SPREAD_MIN;
		if (difference <= least) {
			continue;
		}
		targets[target_count] = neighbour_chunk;
		target_indices[target_count] = neighbour_index;
		target_cells[target_count] = neighbour;
		flows[target_count] = difference * 0.25f;
		target_count += 1;
	}
	for (int target = 0; target < target_count; target++) {
		move(chunk, index, p_cell, targets[target], target_indices[target], target_cells[target], flows[target]);
		if (flows[target] >= WAKE_MIN) {
			wake(target_cells[target]);
			moved = true;
		}
	}
	if (moved) {
		wake_left(p_cell);
	}
}

// A cell gave liquid away: it may give more, and the cells over and beside it may now pour in.
void TerrainLiquids::wake_left(const Vector3i &p_cell) {
	wake(p_cell);
	wake(p_cell + UP);
	for (const Vector3i &side : SIDEWAYS) {
		wake(p_cell + side);
	}
}

void TerrainLiquids::move(LiquidChunk *p_from, int p_from_index, const Vector3i &p_from_cell, LiquidChunk *p_to,
		int p_to_index, const Vector3i &p_to_cell, float p_amount) {
	if (p_amount <= 0.0f) {
		return;
	}
	p_to->make_wet();
	p_from->mass[p_from_index] -= p_amount;
	float before = p_to->mass[p_to_index];
	p_to->mass[p_to_index] = before + p_amount;
	if (before < p_amount) {
		p_to->kind[p_to_index] = p_from->kind[p_from_index];
	}
	if (p_from->mass[p_from_index] <= 0.0f) {
		p_from->mass[p_from_index] = 0.0f;
		p_from->kind[p_from_index] = KIND_NONE;
	}
	p_from->touched = true;
	p_to->touched = true;
	mark_stale(p_from_cell);
	mark_stale(p_to_cell);
}

// --- Adding and asking ----------------------------------------------------------------------------

double TerrainLiquids::add_liquid(const Vector3 &p_world_position, double p_volume, int p_kind) {
	if (cells <= 0 || p_volume <= 0.0 || p_kind <= KIND_NONE || p_kind >= KIND_COUNT) {
		return 0.0;
	}
	double cell_volume = step_size * step_size * step_size;
	float remaining = (float)(p_volume / cell_volume);
	float wanted_mass = remaining;
	Vector3i cell = cell_of(p_world_position);
	for (int climb = 0; climb < 16 && remaining > 0.0f; climb++, cell += UP) {
		LiquidChunk *chunk = nullptr;
		int index = 0;
		CellState state = resolve(cell, chunk, index);
		if (state == CELL_MISSING) {
			want(cell);
			break;
		}
		if (state == CELL_SOLID) {
			continue;
		}
		chunk->make_wet();
		float room = 1.0f - chunk->mass[index];
		if (room <= 0.0f) {
			continue;
		}
		float put = MIN(room, remaining);
		if (chunk->mass[index] < put) {
			chunk->kind[index] = (uint8_t)p_kind;
		}
		chunk->mass[index] += put;
		chunk->touched = true;
		remaining -= put;
		wake(cell);
		mark_stale(cell);
	}
	return (double)(wanted_mass - remaining) * cell_volume;
}

Dictionary TerrainLiquids::liquid_at(const Vector3 &p_world_position) const {
	Dictionary result;
	result["kind"] = KIND_NONE;
	result["depth"] = -1000000.0;
	result["surface"] = -1000000.0;
	if (cells <= 0) {
		return result;
	}
	Vector3i cell = cell_of(p_world_position);
	Vector3i top = cell;
	if (mass_at_cell(cell) < SHOWN_MASS) {
		top = cell - UP;
		if (mass_at_cell(top) < SHOWN_MASS) {
			return result;
		}
	} else {
		for (int climb = 0; climb < MAX_COLUMN; climb++) {
			if (mass_at_cell(top + UP) < SHOWN_MASS) {
				break;
			}
			top += UP;
		}
	}
	double top_mass = tmath::mind(mass_at_cell(top), 1.0);
	double surface = (double)grid_world_origin.y + ((double)top.y - 0.5 + top_mass) * step_size;
	result["kind"] = kind_at_cell(top);
	result["depth"] = surface - (double)p_world_position.y;
	result["surface"] = surface;
	return result;
}

double TerrainLiquids::get_total_volume() const {
	double total = 0.0;
	for (const KeyValue<Vector3i, LiquidChunk *> &entry : chunks) {
		const LiquidChunk *chunk = entry.value;
		if (!chunk->is_wet()) {
			continue;
		}
		for (uint32_t cell = 0; cell < chunk->mass.size(); cell++) {
			total += (double)chunk->mass[cell];
		}
	}
	return total * step_size * step_size * step_size;
}

PackedVector3Array TerrainLiquids::surface_points(int p_limit) const {
	PackedVector3Array points;
	for (const KeyValue<Vector3i, LiquidChunk *> &entry : chunks) {
		const LiquidChunk *chunk = entry.value;
		if (!chunk->is_wet()) {
			continue;
		}
		Vector3i corner = entry.key * cells;
		for (int z = 0; z < cells; z++) {
			for (int y = 0; y < cells; y++) {
				for (int x = 0; x < cells; x++) {
					int index = x + (y + z * cells) * cells;
					if (chunk->solid[index] != 0 || chunk->mass[index] < 0.5f) {
						continue;
					}
					Vector3i above = corner + Vector3i(x, y + 1, z);
					LiquidChunk *above_chunk = nullptr;
					int above_index = 0;
					if (resolve(above, above_chunk, above_index) != CELL_OPEN || mass_at_cell(above) >= SHOWN_MASS) {
						continue;
					}
					Vector3i cell = corner + Vector3i(x, y, z);
					double surface = (double)grid_world_origin.y +
							((double)cell.y - 0.5 + (double)MIN(chunk->mass[index], 1.0f)) * step_size;
					points.push_back(Vector3(grid_world_origin.x + (real_t)((double)cell.x * step_size), (real_t)surface,
							grid_world_origin.z + (real_t)((double)cell.z * step_size)));
					if (points.size() >= p_limit) {
						return points;
					}
				}
			}
		}
	}
	return points;
}

int TerrainLiquids::get_wet_chunk_count() const {
	int count = 0;
	for (const KeyValue<Vector3i, LiquidChunk *> &entry : chunks) {
		if (entry.value->is_wet()) {
			count += 1;
		}
	}
	return count;
}

// Stored linear: the shader takes the vertex colour as it is.
Color TerrainLiquids::kind_color(int p_kind) {
	Color color;
	switch (p_kind) {
		case KIND_SEWAGE:
			color = Color(0.27, 0.3, 0.12, 0.92);
			break;
		case KIND_HOT_WATER:
			color = Color(0.55, 0.68, 0.78, 0.55);
			break;
		default:
			color = Color(0.04, 0.38, 0.68, 0.62);
			break;
	}
	Color linear = color.srgb_to_linear();
	linear.a = color.a;
	return linear;
}

// --- Meshes ---------------------------------------------------------------------------------------

void TerrainLiquids::mark_chunk_stale(const Vector3i &p_chunk_coordinate) {
	LiquidChunk *chunk = find_chunk(p_chunk_coordinate);
	if (chunk == nullptr || chunk->stale) {
		return;
	}
	chunk->stale = true;
	stale_chunks.push_back(p_chunk_coordinate);
}

// A cell's chunk is meshed again, and so is each neighbour whose mesh reads it (a cell on a face
// is the last sample of the chunk before it and a neighbour of the first sample of the next).
void TerrainLiquids::mark_stale(const Vector3i &p_cell) {
	Vector3i chunk_coordinate = chunk_coordinate_of(p_cell);
	Vector3i local = local_of(p_cell, chunk_coordinate);
	Vector3i low = Vector3i(local.x <= 1 ? -1 : 0, local.y <= 1 ? -1 : 0, local.z <= 1 ? -1 : 0);
	Vector3i high = Vector3i(local.x == cells - 1 ? 1 : 0, local.y == cells - 1 ? 1 : 0, local.z == cells - 1 ? 1 : 0);
	for (int offset_z = low.z; offset_z <= high.z; offset_z++) {
		for (int offset_y = low.y; offset_y <= high.y; offset_y++) {
			for (int offset_x = low.x; offset_x <= high.x; offset_x++) {
				mark_chunk_stale(chunk_coordinate + Vector3i(offset_x, offset_y, offset_z));
			}
		}
	}
}

void TerrainLiquids::remesh_all() {
	remesh_stale(0);
}

void TerrainLiquids::remesh_stale(uint64_t p_budget_usec) {
	if (stale_chunks.is_empty()) {
		return;
	}
	uint64_t started = Time::get_singleton()->get_ticks_usec();
	uint32_t done = 0;
	while (done < stale_chunks.size()) {
		Vector3i chunk_coordinate = stale_chunks[done];
		done += 1;
		LiquidChunk *chunk = find_chunk(chunk_coordinate);
		if (chunk == nullptr) {
			continue;
		}
		chunk->stale = false;
		apply_mesh(chunk_coordinate);
		if (p_budget_usec > 0 && Time::get_singleton()->get_ticks_usec() - started >= p_budget_usec) {
			break;
		}
	}
	LocalVector<Vector3i> left;
	for (uint32_t position = done; position < stale_chunks.size(); position++) {
		left.push_back(stale_chunks[position]);
	}
	stale_chunks = left;
}

void TerrainLiquids::apply_mesh(const Vector3i &p_chunk_coordinate) {
	LiquidChunk *chunk = find_chunk(p_chunk_coordinate);
	if (chunk == nullptr || !is_inside_tree()) {
		return;
	}
	Ref<TerrainMeshResult> result = build_mesh(p_chunk_coordinate);
	if (result->indices.is_empty()) {
		if (chunk->mesh != nullptr) {
			chunk->mesh->queue_free();
			chunk->mesh = nullptr;
		}
		return;
	}
	if (chunk->mesh == nullptr) {
		if (material.is_null()) {
			material = ResourceLoader::get_singleton()->load(LIQUID_MATERIAL_PATH);
		}
		chunk->mesh = memnew(MeshInstance3D);
		chunk->mesh->set_name("Liquid_" + itos(p_chunk_coordinate.x) + "_" + itos(p_chunk_coordinate.y) + "_" +
				itos(p_chunk_coordinate.z));
		chunk->mesh->set_material_override(material);
		chunk->mesh->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		double extent = (double)cells * step_size;
		chunk->mesh->set_position(grid_local_origin + (Vector3(p_chunk_coordinate) + Vector3(0.5, 0.5, 0.5)) * (real_t)extent);
		add_child(chunk->mesh);
	}
	chunk->mesh->set_mesh(FlyingEdgesMesher::to_array_mesh(result));
}

// The chunk's samples 0 to `cells` (the last is the next chunk's first) as a field below 0 inside
// the liquid: an open cell is 0.5 less how full it is drawn, so its surface lies where its liquid
// would; a solid cell under liquid counts as full and one beside liquid takes its neighbour's
// level, so the surface runs into the ground instead of walling off against it.
Ref<TerrainMeshResult> TerrainLiquids::build_mesh(const Vector3i &p_chunk_coordinate) const {
	Ref<TerrainMeshResult> empty;
	empty.instantiate();
	if (cells <= 0) {
		return empty;
	}
	// The cells from -1 to `cells` + 1 on each axis, read from the chunk and its neighbours (a
	// missing neighbour counts as dry ground).
	int padded = cells + 3;
	int padded_count = padded * padded * padded;
	LocalVector<float> masses;
	LocalVector<uint8_t> solids;
	LocalVector<uint8_t> kinds;
	masses.resize(padded_count);
	solids.resize(padded_count);
	kinds.resize(padded_count);
	LiquidChunk *around[27];
	bool any_wet = false;
	for (int offset = 0; offset < 27; offset++) {
		Vector3i neighbour = p_chunk_coordinate + Vector3i(offset % 3 - 1, (offset / 3) % 3 - 1, offset / 9 - 1);
		around[offset] = find_chunk(neighbour);
	}
	for (int padded_z = 0; padded_z < padded; padded_z++) {
		for (int padded_y = 0; padded_y < padded; padded_y++) {
			for (int padded_x = 0; padded_x < padded; padded_x++) {
				Vector3i local = Vector3i(padded_x - 1, padded_y - 1, padded_z - 1);
				Vector3i side = Vector3i(local.x < 0 ? -1 : (local.x >= cells ? 1 : 0),
						local.y < 0 ? -1 : (local.y >= cells ? 1 : 0), local.z < 0 ? -1 : (local.z >= cells ? 1 : 0));
				Vector3i inner = local - side * cells;
				LiquidChunk *chunk = around[(side.x + 1) + (side.y + 1) * 3 + (side.z + 1) * 9];
				int padded_index = padded_x + (padded_y + padded_z * padded) * padded;
				if (chunk == nullptr) {
					solids[padded_index] = 1;
					masses[padded_index] = 0.0f;
					kinds[padded_index] = KIND_NONE;
					continue;
				}
				int index = inner.x + (inner.y + inner.z * cells) * cells;
				solids[padded_index] = chunk->solid[index];
				float mass = chunk->is_wet() && chunk->solid[index] == 0 ? chunk->mass[index] : 0.0f;
				masses[padded_index] = mass;
				kinds[padded_index] = chunk->is_wet() ? chunk->kind[index] : (uint8_t)KIND_NONE;
				if (mass >= SHOWN_MASS) {
					any_wet = true;
				}
			}
		}
	}
	if (!any_wet) {
		return empty;
	}
	int stride_y = padded;
	int stride_z = padded * padded;
	int samples = cells + 1;
	Ref<SignedDensityField> field = SignedDensityField::make(Vector3i(samples, samples, samples));
	PackedFloat32Array values = field->values;
	float *out = values.ptrw();
	double lowest = tmath::INF_D;
	double highest = -tmath::INF_D;
	for (int z = 0; z < samples; z++) {
		for (int y = 0; y < samples; y++) {
			for (int x = 0; x < samples; x++) {
				int at = (x + 1) + (y + 1) * stride_y + (z + 1) * stride_z;
				float value = 0.5f;
				if (solids[at] != 0) {
					int above = at + stride_y;
					if (solids[above] == 0 && masses[above] >= SHOWN_MASS) {
						value = -1.0f;
					} else {
						int sides[4] = { at + 1, at - 1, at + stride_z, at - stride_z };
						for (int side : sides) {
							if (solids[side] != 0 || masses[side] < SHOWN_MASS) {
								continue;
							}
							float shown = MIN(masses[side], 1.0f);
							int under = side - stride_y;
							if (solids[under] == 0 && masses[under] < 0.99f) {
								shown = MAX(shown, FALLING_SHOWN);
							}
							value = MIN(value, 0.5f - shown);
						}
					}
				} else if (masses[at] >= SHOWN_MASS) {
					float shown = MIN(masses[at], 1.0f);
					int under = at - stride_y;
					if (solids[under] == 0 && masses[under] < 0.99f) {
						shown = MAX(shown, FALLING_SHOWN);
					}
					value = 0.5f - shown;
				}
				out[x + (y + z * samples) * samples] = value;
				lowest = tmath::mind(lowest, (double)value);
				highest = tmath::maxd(highest, (double)value);
			}
		}
	}
	field->values = values;
	field->min_value = lowest;
	field->max_value = highest;
	double extent = (double)cells * step_size;
	Vector3 center = grid_local_origin + (Vector3(p_chunk_coordinate) + Vector3(0.5, 0.5, 0.5)) * (real_t)extent;
	Ref<TerrainMeshResult> sheet = FlyingEdgesMesher::build(field, extent, 0.0, p_chunk_coordinate * cells,
			grid_local_origin, center, nullptr, Vector3i(), Vector3i(-1, -1, -1), nullptr);
	if (sheet->indices.is_empty()) {
		return sheet;
	}
	// Drops the triangles sunk wholly in the ground (under a lake's bed), and colours each vertex
	// by the liquid nearest it.
	Ref<TerrainMeshResult> kept;
	kept.instantiate();
	const Vector3 *vertices = sheet->vertices.ptr();
	const Vector3 *normals = sheet->normals.ptr();
	const int32_t *indices = sheet->indices.ptr();
	int64_t vertex_count = sheet->vertices.size();
	Vector3 chunk_offset = center - grid_local_origin;
	Vector3 chunk_first = Vector3(p_chunk_coordinate * cells);
	LocalVector<int> remap;
	remap.resize(vertex_count);
	for (int64_t vertex = 0; vertex < vertex_count; vertex++) {
		remap[vertex] = -1;
	}
	for (int64_t corner = 0; corner + 2 < sheet->indices.size(); corner += 3) {
		int first = indices[corner];
		int second = indices[corner + 1];
		int third = indices[corner + 2];
		Vector3 middle = (vertices[first] + vertices[second] + vertices[third]) / 3.0f;
		Vector3 grid = (middle + chunk_offset) / (real_t)step_size - chunk_first;
		Vector3i base = Vector3i(tmath::floori(grid.x), tmath::floori(grid.y), tmath::floori(grid.z));
		base = base.clamp(Vector3i(-1, -1, -1), Vector3i(cells, cells, cells));
		bool buried = true;
		for (int offset = 0; offset < 8 && buried; offset++) {
			Vector3i sample = base + Vector3i(offset & 1, (offset >> 1) & 1, (offset >> 2) & 1) + Vector3i(1, 1, 1);
			if (solids[sample.x + sample.y * stride_y + sample.z * stride_z] == 0) {
				buried = false;
			}
		}
		if (buried) {
			continue;
		}
		int triangle[3] = { first, second, third };
		for (int old : triangle) {
			if (remap[old] < 0) {
				remap[old] = (int)kept->vertices.size();
				kept->vertices.push_back(vertices[old]);
				kept->normals.push_back(normals[old]);
				Vector3 at = (vertices[old] + chunk_offset) / (real_t)step_size - chunk_first;
				Vector3i nearest = Vector3i(tmath::roundi(at.x), tmath::roundi(at.y), tmath::roundi(at.z))
										   .clamp(Vector3i(-1, -1, -1), Vector3i(cells + 1, cells + 1, cells + 1));
				int kind = KIND_WATER;
				float fullest = 0.0f;
				for (int offset = 0; offset < 27; offset++) {
					Vector3i look = nearest + Vector3i(offset % 3 - 1, (offset / 3) % 3 - 1, offset / 9 - 1) +
							Vector3i(1, 1, 1);
					if (look.x < 0 || look.y < 0 || look.z < 0 || look.x >= padded || look.y >= padded ||
							look.z >= padded) {
						continue;
					}
					int look_index = look.x + look.y * stride_y + look.z * stride_z;
					if (masses[look_index] > fullest) {
						fullest = masses[look_index];
						kind = kinds[look_index];
					}
				}
				kept->colors.push_back(kind_color(kind));
			}
			kept->indices.push_back(remap[old]);
		}
	}
	return kept;
}

void TerrainLiquids::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "cells", "step", "grid_world_origin", "grid_local_origin", "chunk_grid"),
			&TerrainLiquids::configure);
	ClassDB::bind_method(D_METHOD("clear"), &TerrainLiquids::clear);
	ClassDB::bind_method(D_METHOD("take_seed", "seed"), &TerrainLiquids::take_seed);
	ClassDB::bind_method(D_METHOD("unload", "chunk_coordinate"), &TerrainLiquids::unload);
	ClassDB::bind_method(D_METHOD("step"), &TerrainLiquids::step);
	ClassDB::bind_method(D_METHOD("settle", "max_steps"), &TerrainLiquids::settle);
	ClassDB::bind_method(D_METHOD("request_chunk", "chunk_coordinate"), &TerrainLiquids::request_chunk);
	ClassDB::bind_method(D_METHOD("add_liquid", "world_position", "volume", "kind"), &TerrainLiquids::add_liquid);
	ClassDB::bind_method(D_METHOD("liquid_at", "world_position"), &TerrainLiquids::liquid_at);
	ClassDB::bind_method(D_METHOD("remesh_all"), &TerrainLiquids::remesh_all);
	ClassDB::bind_method(D_METHOD("build_mesh", "chunk_coordinate"), &TerrainLiquids::build_mesh);
	ClassDB::bind_static_method("TerrainLiquids", D_METHOD("kind_color", "kind"), &TerrainLiquids::kind_color);
	ClassDB::bind_method(D_METHOD("cell_of", "world_position"), &TerrainLiquids::cell_of);
	ClassDB::bind_method(D_METHOD("mass_at_cell", "cell"), &TerrainLiquids::mass_at_cell);
	ClassDB::bind_method(D_METHOD("kind_at_cell", "cell"), &TerrainLiquids::kind_at_cell);
	ClassDB::bind_method(D_METHOD("get_total_volume"), &TerrainLiquids::get_total_volume);
	ClassDB::bind_method(D_METHOD("surface_points", "limit"), &TerrainLiquids::surface_points);
	ClassDB::bind_method(D_METHOD("get_awake_count"), &TerrainLiquids::get_awake_count);
	ClassDB::bind_method(D_METHOD("get_chunk_count"), &TerrainLiquids::get_chunk_count);
	ClassDB::bind_method(D_METHOD("get_wet_chunk_count"), &TerrainLiquids::get_wet_chunk_count);
	ClassDB::bind_method(D_METHOD("get_cells"), &TerrainLiquids::get_cells);
	ClassDB::bind_method(D_METHOD("get_step_size"), &TerrainLiquids::get_step_size);
	ClassDB::bind_method(D_METHOD("has_chunk", "chunk_coordinate"), &TerrainLiquids::has_chunk);
	ClassDB::bind_method(D_METHOD("is_waiting_for", "chunk_coordinate"), &TerrainLiquids::is_waiting_for);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &TerrainLiquids::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &TerrainLiquids::get_material);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_material",
			"get_material");
	BIND_CONSTANT(KIND_NONE);
	BIND_CONSTANT(KIND_WATER);
	BIND_CONSTANT(KIND_SEWAGE);
	BIND_CONSTANT(KIND_HOT_WATER);
	BIND_CONSTANT(KIND_COUNT);
}

} // namespace godot
