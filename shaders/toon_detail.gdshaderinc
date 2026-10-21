// Procedural surface detail for the toon surface shader: wood grain, concrete speckle, and
// block or brick mortar grids, computed from the mesh's own (object-space) position so every
// procedurally sized box gets a seamless pattern with no image textures. Kept soft and
// large-scale on purpose: cel shading flattens the light, and fine noise would read as mud.
//
// detail: 0 none, 1 wood, 2 concrete, 3 block wall (running bond), 4 brick, 5 poured concrete.
// detail_scale: world metres per real metre (the crawlspace builds at 100), so mortar joints
// land at real block spacing. grain_axis: the object axis the wood runs along (0 x, 1 y, 2 z).

uniform int detail = 0;
uniform float detail_scale = 1.0;
uniform int grain_axis = 0;

float detail_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float detail_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = detail_hash(i);
	float n100 = detail_hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = detail_hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = detail_hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = detail_hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = detail_hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = detail_hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = detail_hash(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

// Streaks stretched along the grain axis, two tones plus sparse dark lines.
vec3 detail_wood(vec3 base, vec3 local) {
	float metre = 1.0 / max(detail_scale, 0.001);
	vec3 p = local * metre;
	vec3 stretch = vec3(26.0);
	if (grain_axis == 0) {
		stretch.x = 0.6;
	} else if (grain_axis == 1) {
		stretch.y = 0.6;
	} else {
		stretch.z = 0.6;
	}
	float grain = detail_noise(p * stretch);
	grain = grain * 0.7 + detail_noise(p * stretch * 2.3) * 0.3;
	float lines = smoothstep(0.62, 0.72, detail_noise(p * stretch * 4.0 + 7.0));
	vec3 color = mix(base * 0.76, base * 1.14, grain);
	return mix(color, base * 0.55, lines * 0.6);
}

// Fine speckle, with soft blotches so a large wall isn't uniform.
vec3 detail_concrete(vec3 base, vec3 local) {
	float metre = 1.0 / max(detail_scale, 0.001);
	vec3 p = local * metre;
	float speckle = detail_noise(p * 120.0) - 0.5;
	float blotch = detail_noise(p * 3.0) - 0.5;
	return base * (1.0 + speckle * 0.09 + blotch * 0.08);
}

// Mortar joints on the vertical faces of a block or brick wall, in running bond. The course
// coordinate is the object's Y; the run coordinate is whichever horizontal axis the face
// spans. Top and bottom faces get plain concrete.
vec3 detail_masonry(vec3 base, vec3 local, vec3 local_normal, vec2 unit, float joint) {
	vec3 concrete = detail_concrete(base, local);
	if (abs(local_normal.y) > 0.7) {
		return concrete;
	}
	float metre = 1.0 / max(detail_scale, 0.001);
	float run = (abs(local_normal.x) > abs(local_normal.z) ? local.z : local.x) * metre;
	float course = local.y * metre;
	float row = floor(course / unit.y);
	float offset = mod(row, 2.0) * unit.x * 0.5;
	float along = fract((run + offset) / unit.x) * unit.x;
	float up = fract(course / unit.y) * unit.y;
	float in_joint = step(along, joint) + step(up, joint);
	float block_tone = 0.94 + 0.12 * detail_hash(vec3(floor((run + offset) / unit.x), row, 0.0));
	vec3 face = concrete * block_tone;
	return mix(face, base * 0.55, clamp(in_joint, 0.0, 1.0));
}

// Poured concrete: speckle and blotches plus faint horizontal form-board lines on the
// vertical faces, every 0.6 m of real height.
vec3 detail_poured(vec3 base, vec3 local, vec3 local_normal) {
	vec3 concrete = detail_concrete(base, local);
	if (abs(local_normal.y) > 0.7) {
		return concrete;
	}
	float metre = 1.0 / max(detail_scale, 0.001);
	float course = fract(local.y * metre / 0.6) * 0.6;
	float seam = 1.0 - smoothstep(0.0, 0.012, course);
	float board = 0.97 + 0.06 * detail_hash(vec3(floor(local.y * metre / 0.6), 3.0, 1.0));
	return mix(concrete * board, base * 0.8, seam * 0.6);
}

vec3 apply_detail(vec3 base, vec3 local, vec3 local_normal) {
	if (detail == 1) {
		return detail_wood(base, local);
	}
	if (detail == 2) {
		return detail_concrete(base, local);
	}
	if (detail == 3) {
		return detail_masonry(base, local, local_normal, vec2(0.4, 0.2), 0.012);
	}
	if (detail == 4) {
		return detail_masonry(base, local, local_normal, vec2(0.2, 0.065), 0.01);
	}
	if (detail == 5) {
		return detail_poured(base, local, local_normal);
	}
	return base;
}
