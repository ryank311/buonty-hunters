shader_type spatial;
render_mode diffuse_lambert;
uniform vec4 tint : source_color = vec4(0.6, 0.59, 0.53, 1.0);
uniform float grid_strength = 0.08;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	vec2 edge = abs(fract(p + 0.5) - 0.5);
	vec2 width = max(fwidth(p), vec2(0.001));
	float line = 1.0 - min(smoothstep(0.008, 0.008 + width.x, edge.x), smoothstep(0.008, 0.008 + width.y, edge.y));
	ALBEDO = tint.rgb * (1.0 - line * grid_strength);
	ROUGHNESS = 0.95;
}
