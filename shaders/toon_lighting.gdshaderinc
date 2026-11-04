// Shared cel-shading light pass. Include at the end of any spatial shader; fragment() still
// sets ALBEDO, ROUGHNESS and so on, and this replaces Godot's Lambert/GGX lighting with three
// flat bands (shadow, half-lit, lit) and a hard specular dot.
//
// The sun keeps flat bands everywhere, dropping into the shadow band where its shadow map says
// so. Bulbs, spots and other positional lights are banded by angle but still fade with distance,
// otherwise every light in range would add a full flat band and a room with a few bulbs would
// blow out to white.

// Brightness of the shadow and half-lit bands, relative to full light.
const float TOON_SHADOW_BAND = 0.26;
const float TOON_HALF_BAND = 0.62;

// A surface shader may set these before including this file:
//   TOON_BAND_SOFTNESS  how wide the two terminators are, as a multiple of the crisp default
//                       (the ground uses a few: a soft gradient over rolling lawn instead of a
//                       hard edge that stair-steps along the 2 m mesh grid);
//   TOON_BAND_SHIFT     a per-fragment push of both terminators along the light angle (the
//                       ground sets it from its own grain, so the edge wanders with the grass).
#ifndef TOON_BAND_SOFTNESS
#define TOON_BAND_SOFTNESS 1.0
#endif
#ifndef TOON_BAND_SHIFT
#define TOON_BAND_SHIFT 0.0
#endif

void light() {
	float n_dot_l = dot(NORMAL, LIGHT) + TOON_BAND_SHIFT;
	// Two terminators, each softened over a sliver (0.06 at softness 1) so edges don't shimmer.
	float half_width = 0.03 * TOON_BAND_SOFTNESS;
	float lit = smoothstep(0.03 - half_width, 0.03 + half_width, n_dot_l);
	float bright = smoothstep(0.43 - half_width, 0.43 + half_width, n_dot_l);
	float band = mix(TOON_SHADOW_BAND, mix(TOON_HALF_BAND, 1.0, bright), lit);

	float strength;
	float highlight_scale;
	if (LIGHT_IS_DIRECTIONAL) {
		// ATTENUATION is the shadow factor: shadowed surfaces fall into the shadow band.
		float in_light = smoothstep(0.2, 0.5, ATTENUATION);
		strength = mix(TOON_SHADOW_BAND, band, in_light);
		highlight_scale = in_light;
	} else {
		// ATTENUATION is distance falloff times shadow; keep it continuous so lights have reach.
		strength = band * ATTENUATION;
		highlight_scale = ATTENUATION;
	}
	// LIGHT_COLOR carries energy * PI; dividing by PI matches Lambert's brightness.
	DIFFUSE_LIGHT += strength * LIGHT_COLOR / PI;

	// A crisp highlight that only appears on smoother surfaces.
	vec3 half_vector = normalize(VIEW + LIGHT);
	float gloss = clamp(1.0 - ROUGHNESS, 0.0, 1.0);
	float cutoff = mix(0.998, 0.94, gloss);
	float spec = smoothstep(cutoff, cutoff + 0.012, dot(NORMAL, half_vector)) * gloss * lit * highlight_scale;
	SPECULAR_LIGHT += spec * LIGHT_COLOR / PI * 0.25;
}
