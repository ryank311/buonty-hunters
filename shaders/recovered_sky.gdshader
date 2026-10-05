shader_type spatial;
// A recovered sky dome. The node follows the camera and every vertex is pushed
// out along its view direction to sky_distance, so the dome reads as infinitely
// far: no parallax, never clipped by the far plane, drawn behind the world.
// Toward the horizon it fades into the map's fog colour, as distant geometry does.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float sky_distance = 3000.0;
uniform bool use_alpha = false;
uniform vec3 fog_color : source_color = vec3(0.5);
// Elevation (sine) above which the sky is unfogged; 0 disables the fade.
uniform float horizon_fade = 0.0;
varying float elevation;

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	elevation = (INV_VIEW_MATRIX * vec4(normalize(view), 0.0)).y;
	POSITION = PROJECTION_MATRIX * vec4(normalize(view) * sky_distance, 1.0);
}

void fragment() {
	vec4 color = texture(albedo_texture, UV);
	float fog = horizon_fade > 0.0 ? 1.0 - smoothstep(0.0, horizon_fade, elevation) : 0.0;
	ALBEDO = mix(color.rgb, fog_color, fog);
	if (use_alpha) {
		ALPHA = color.a;
	}
}
