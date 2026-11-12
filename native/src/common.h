// Shared helpers for the terrain extension: the math GDScript does (doubles for its floats,
// Godot's own vector types for its vectors, so a port gives the numbers the scripts gave),
// Godot's hashes, and FastNoiseLite as the engine wraps it.
#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/vector4i.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

#include "FastNoiseLite.h"

namespace godot {

namespace tmath {

constexpr double INF_D = std::numeric_limits<double>::infinity();

inline double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double mind(double a, double b) { return a < b ? a : b; }
inline double maxd(double a, double b) { return a > b ? a : b; }
inline int mini(int a, int b) { return a < b ? a : b; }
inline int maxi(int a, int b) { return a > b ? a : b; }
inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }

// GDScript's is_equal_approx on floats.
inline bool approx(double a, double b) {
	if (a == b) {
		return true;
	}
	double tolerance = 0.00001 * std::abs(a);
	if (tolerance < 0.00001) {
		tolerance = 0.00001;
	}
	return std::abs(a - b) < tolerance;
}

// GDScript's smoothstep (Math::smoothstep on doubles).
inline double smoothstep(double from, double to, double s) {
	if (approx(from, to)) {
		if (from <= to) {
			return s <= from ? 0.0 : 1.0;
		}
		return s <= to ? 1.0 : 0.0;
	}
	double t = clampd((s - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// GDScript's fposmod on floats.
inline double fposmod(double x, double y) {
	double value = std::fmod(x, y);
	if (((value < 0) && (y > 0)) || ((value > 0) && (y < 0))) {
		value += y;
	}
	value += 0.0;
	return value;
}

inline int floori(double v) { return (int)std::floor(v); }
inline int ceili(double v) { return (int)std::ceil(v); }
inline int roundi(double v) { return (int)std::round(v); }

// Integer division rounding toward negative infinity, as GDScript's floor of a quotient.
inline int floor_div(int value, int divisor) {
	int quotient = value / divisor;
	if ((value % divisor != 0) && ((value < 0) != (divisor < 0))) {
		quotient -= 1;
	}
	return quotient;
}

} // namespace tmath

// Godot's hash(Vector2i / Vector3i / Vector4i), as GDScript's hash() gives it.
namespace thash {

constexpr uint32_t SEED = 0x7F07C65;

inline uint32_t murmur3_one_32(uint32_t p_in, uint32_t p_seed = SEED) {
	p_in *= 0xcc9e2d51;
	p_in = (p_in << 15) | (p_in >> 17);
	p_in *= 0x1b873593;
	p_seed ^= p_in;
	p_seed = (p_seed << 13) | (p_seed >> 19);
	p_seed = p_seed * 5 + 0xe6546b64;
	return p_seed;
}

inline uint32_t fmix32(uint32_t h) {
	h ^= h >> 16;
	h *= 0x85ebca6b;
	h ^= h >> 13;
	h *= 0xc2b2ae35;
	h ^= h >> 16;
	return h;
}

inline int64_t of(int x, int y) {
	uint32_t h = murmur3_one_32(uint32_t(x));
	h = murmur3_one_32(uint32_t(y), h);
	return (int64_t)fmix32(h);
}

inline int64_t of(int x, int y, int z) {
	uint32_t h = murmur3_one_32(uint32_t(x));
	h = murmur3_one_32(uint32_t(y), h);
	h = murmur3_one_32(uint32_t(z), h);
	return (int64_t)fmix32(h);
}

inline int64_t of(int x, int y, int z, int w) {
	uint32_t h = murmur3_one_32(uint32_t(x));
	h = murmur3_one_32(uint32_t(y), h);
	h = murmur3_one_32(uint32_t(z), h);
	h = murmur3_one_32(uint32_t(w), h);
	return (int64_t)fmix32(h);
}

} // namespace thash

// FastNoiseLite as Godot's FastNoiseLite resource sets it up (its defaults: simplex smooth,
// frequency 0.01, five octaves of FBm), called directly instead of through the engine.
struct TNoise {
	fastnoiselite::FastNoiseLite fnl;
	bool valid = false;
	float frequency = 0.01f;

	enum Type {
		SIMPLEX = 0,
		SIMPLEX_SMOOTH = 1,
		CELLULAR = 2,
		PERLIN = 3,
		VALUE_CUBIC = 4,
		VALUE = 5,
	};

	TNoise() {
		fnl.SetNoiseType(fastnoiselite::FastNoiseLite::NoiseType_OpenSimplex2S);
		fnl.SetSeed(0);
		fnl.SetFrequency(0.01f);
		fnl.SetFractalType(fastnoiselite::FastNoiseLite::FractalType_FBm);
		fnl.SetFractalOctaves(5);
		fnl.SetFractalLacunarity(2.0f);
		fnl.SetFractalGain(0.5f);
		fnl.SetFractalWeightedStrength(0.0f);
		fnl.SetFractalPingPongStrength(2.0f);
		fnl.SetCellularDistanceFunction(fastnoiselite::FastNoiseLite::CellularDistanceFunction_Euclidean);
		fnl.SetCellularReturnType(fastnoiselite::FastNoiseLite::CellularReturnType_Distance);
		fnl.SetCellularJitter(1.0f);
	}

	// A noise as the scripts make one: seed, type, frequency, and FBm octaves (0 or 1: none).
	static TNoise make(int seed, Type type, double p_frequency, int octaves = 0) {
		TNoise n;
		n.valid = true;
		n.set_seed(seed);
		n.set_type(type);
		n.set_frequency(p_frequency);
		if (octaves > 1) {
			n.set_fbm(octaves);
		} else if (octaves >= 0) {
			n.set_no_fractal();
		}
		return n;
	}

	void set_seed(int seed) { fnl.SetSeed(seed); }
	void set_type(Type type) { fnl.SetNoiseType((fastnoiselite::FastNoiseLite::NoiseType)type); }
	void set_frequency(double p_frequency) {
		frequency = (float)p_frequency;
		fnl.SetFrequency(frequency);
	}
	void set_no_fractal() { fnl.SetFractalType(fastnoiselite::FastNoiseLite::FractalType_None); }
	void set_fbm(int octaves) {
		fnl.SetFractalType(fastnoiselite::FastNoiseLite::FractalType_FBm);
		fnl.SetFractalOctaves(octaves);
	}
	void set_lacunarity(double value) { fnl.SetFractalLacunarity((float)value); }
	void set_gain(double value) { fnl.SetFractalGain((float)value); }

	double get_2d(double x, double y) const { return (double)fnl.GetNoise((float)x, (float)y); }
	double get_3d(double x, double y, double z) const {
		return (double)fnl.GetNoise((float)x, (float)y, (float)z);
	}
	double get_3dv(const Vector3 &v) const { return (double)fnl.GetNoise(v.x, v.y, v.z); }
};

// A Vector3i key for unordered maps.
struct Vector3iHash {
	size_t operator()(const Vector3i &v) const {
		return (size_t)thash::of(v.x, v.y, v.z);
	}
};

// A Vector2 key (aquifer cache) by its bits.
struct Vector2Hash {
	size_t operator()(const Vector2 &v) const {
		uint32_t a;
		uint32_t b;
		memcpy(&a, &v.x, 4);
		memcpy(&b, &v.y, 4);
		return (size_t)thash::of((int)a, (int)b);
	}
};

// Vector3 of doubles made the way GDScript's Vector3(x, y, z) makes it.
inline Vector3 v3(double x, double y, double z) { return Vector3((real_t)x, (real_t)y, (real_t)z); }

// Common binding helpers: a plain field with a setter, a getter and a property.
#define TFIELD(T, name, def)                    \
	T name = def;                               \
	void set_##name(T p_value) { name = p_value; } \
	T get_##name() const { return name; }

#define TBIND(cls, vtype, name)                                                         \
	ClassDB::bind_method(D_METHOD("set_" #name, "value"), &cls::set_##name);            \
	ClassDB::bind_method(D_METHOD("get_" #name), &cls::get_##name);                     \
	ADD_PROPERTY(PropertyInfo(Variant::vtype, #name), "set_" #name, "get_" #name);

} // namespace godot
