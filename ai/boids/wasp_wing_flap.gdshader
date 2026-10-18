shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// Buzzing wings for MultiMesh wasp drones: wing vertices bend up and down more the farther they
// are from the body's center line, with each instance on its own phase so the swarm isn't in sync.
uniform vec4 wing_color : source_color = vec4(0.42, 0.48, 0.58, 0.65);
uniform float flap_speed = 42.0;
uniform float flap_amount = 0.9;

void vertex() {
	float phase = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453) * 6.28318;
	VERTEX.y += sin(TIME * flap_speed + phase) * abs(VERTEX.x) * flap_amount;
}

void fragment() {
	ALBEDO = wing_color.rgb;
	ALPHA = wing_color.a;
	ROUGHNESS = 0.15;
}
