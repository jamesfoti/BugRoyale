shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Chain-link fence fabric on a flat quad: two families of wire at 45 degrees weave the diamond
// mesh, and everything between the wires is cut away. Sizes are in world metres, so the same
// material fits any span: set sheet_size to the quad's width and height.
uniform vec4 wire_color : source_color = vec4(0.62, 0.64, 0.65, 1.0);
uniform vec2 sheet_size = vec2(100.0, 100.0);
// Spacing between parallel wires (a 2-inch mesh is 0.05 m at full size).
uniform float mesh_pitch = 4.0;
// Wire thickness.
uniform float wire_width = 0.3;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.5;

varying vec2 sheet_pos;

void vertex() {
	sheet_pos = UV * sheet_size;
}

// How much of this pixel a wire family at this spacing covers, antialiased by the pixel size.
float wire_cover(float along) {
	float dist = abs(fract(along / mesh_pitch + 0.5) - 0.5) * mesh_pitch;
	float blur = fwidth(along) * 0.75;
	return 1.0 - smoothstep(wire_width * 0.5 - blur, wire_width * 0.5 + blur, dist);
}

void fragment() {
	float a = (sheet_pos.x + sheet_pos.y) * 0.70710678;
	float b = (sheet_pos.x - sheet_pos.y) * 0.70710678;
	float cover = max(wire_cover(a), wire_cover(b));
	// A faint highlight on the wire that lies "over" the other where they cross.
	float sheen = 0.9 + 0.2 * step(wire_cover(a), wire_cover(b));
	ALBEDO = wire_color.rgb * sheen;
	ROUGHNESS = roughness_value;
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

#include "res://shaders/toon_lighting.gdshaderinc"
