shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D billows : repeat_enable, filter_linear;
uniform sampler2D recovered_puff : repeat_disable, filter_nearest;
uniform float radius = 8.0;
uniform float age = 0.0;
uniform float lifetime = 18.0;
uniform vec3 bounds = vec3(6.3, 4.5, 6.3);
uniform vec3 source = vec3(0.0, -4.05, 0.0);
varying flat vec3 camera_local;
varying flat mat4 local_from_view;

void vertex() {
	local_from_view = inverse(MODEL_MATRIX) * INV_VIEW_MATRIX;
	camera_local = (local_from_view * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

float lobe(vec3 p, vec3 center, vec3 size) {
	vec3 q = (p - center) / size;
	return max(0.0, 1.0 - dot(q, q));
}

float smoke(vec3 point) {
	vec3 p = point - source;
	float dispersal = smoothstep(lifetime * 0.68, lifetime, age);
	float growth = 1.0 - exp(-max(0.0, age - 0.25) / 1.35);
	float width = max(0.06, radius * growth * (1.0 + 0.22 * dispersal));
	float height = max(0.06, min(radius, 4.5) * growth * (1.0 + 0.22 * dispersal));
	// New smoke starts at the vent; the body rises and spreads as it matures.
	vec3 q = p / vec3(width, height, width);
	q.xz -= vec2(0.055, -0.028) * age * growth / radius;
	q.y -= dispersal * 0.18;
	vec3 flow = p * 0.115 - vec3(age * 0.012, age * 0.047, -age * 0.008);
	float coarse = texture(billows, flow).r;
	float fine = texture(billows, flow * 2.7 + vec3(0.17, age * 0.011, 0.33)).r;
	vec3 curl = vec3(texture(billows, flow + vec3(0.37, 0.13, 0.0)).r, coarse, texture(billows, flow + vec3(0.0, 0.53, 0.24)).r) - vec3(0.5);
	q += curl * 0.55;
	float shape = lobe(q, vec3(0.0, 0.35, 0.0), vec3(0.83, 0.52, 0.8));
	shape += 0.8 * lobe(q, vec3(-0.28, 0.69, 0.08), vec3(0.65, 0.45, 0.62));
	shape += 0.85 * lobe(q, vec3(0.38, 0.42, 0.12), vec3(0.65, 0.48, 0.67));
	shape += 0.7 * lobe(q, vec3(-0.4, 0.27, -0.23), vec3(0.61, 0.39, 0.59));
	float noise = coarse * 0.75 + fine * 0.25;
	float puff = texture(recovered_puff, q.xz * 0.34 + vec2(0.5)).a;
	float body = max(0.0, min(shape, 1.4) - (1.0 - noise) * 0.86);
	body *= (0.65 + puff * 0.6) * (0.65 + fine * 0.7);
	body *= smoothstep(0.3, 1.1, age);
	// A narrow rising feed connects the screen to the canister until burnout.
	float feed = 1.0 - smoothstep(lifetime * 0.54, lifetime * 0.68, age);
	float jet_height = min(age * 1.7, min(radius, 4.5) * 0.45);
	vec3 jet = p - vec3(sin(p.y * 5.0 - age * 3.5) * p.y * 0.045, jet_height * 0.5, 0.0);
	float stem = lobe(jet, vec3(0.0), vec3(0.1 + jet_height * 0.12, max(0.04, jet_height * 0.62), 0.1 + jet_height * 0.1));
	float density = body * 2.6 * (1.0 - dispersal) + stem * feed * 3.0;
	return density * smoothstep(-0.06, 0.12, p.y) * smoothstep(0.0, 0.22, age);
}

void fragment() {
	// March one shared ray per 3x3 game-pixel cell, with matching grain and
	// stepped greys. The smoke retains volume but fits the low-resolution art.
	vec2 cell = floor(FRAGCOORD.xy / 3.0);
	vec2 smoke_uv = (cell + 0.5) * 3.0 / VIEWPORT_SIZE;
	vec4 ray_view = INV_PROJECTION_MATRIX * vec4(smoke_uv * 2.0 - 1.0, 0.5, 1.0);
	ray_view /= ray_view.w;
	vec3 direction = normalize((local_from_view * ray_view).xyz - camera_local);
	vec3 safe_dir = mix(vec3(0.00001), direction, greaterThan(abs(direction), vec3(0.00001)));
	// Tighten the integration region while the initial jet is still tiny.
	float span = 0.22 + radius * (1.0 - exp(-max(0.0, age - 0.25) / 1.35)) * 1.5;
	vec3 live_min = max(-bounds, source + vec3(-span, -0.08, -span));
	vec3 live_max = min(bounds, source + vec3(span, span * 1.25, span));
	vec3 near_plane = (live_min - camera_local) / safe_dir;
	vec3 far_plane = (live_max - camera_local) / safe_dir;
	vec3 lo = min(near_plane, far_plane);
	vec3 hi = max(near_plane, far_plane);
	float entry = max(0.0, max(lo.x, max(lo.y, lo.z)));
	float exit_at = min(hi.x, min(hi.y, hi.z));
	// Opaque depth clips the volume against floors, walls and characters.
	// Integrating from the eye also works with the camera inside the smoke.
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene_view /= scene_view.w;
	vec3 scene_local = (local_from_view * scene_view).xyz;
	exit_at = min(exit_at, length(scene_local - camera_local));
	if (exit_at <= entry) { discard; }
	float step_size = (exit_at - entry) / 48.0;
	float jitter = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float travel = entry + step_size * jitter;
	float transmission = 1.0;
	vec3 color = vec3(0.0);
	for (int i = 0; i < 48; i++) {
		vec3 p = camera_local + direction * travel;
		float density = smoke(p);
		if (density > 0.015) {
			float toward_light = smoke(p + vec3(-0.6, 0.9, 0.4));
			float light = 0.22 + 0.78 * exp(-toward_light * 0.85);
			vec3 tint = mix(vec3(0.16, 0.18, 0.17), vec3(0.65, 0.68, 0.64), light);
			float opacity = 1.0 - exp(-density * step_size);
			color += transmission * opacity * tint;
			transmission *= 1.0 - opacity;
		}
		travel += step_size;
		if (transmission < 0.012) { break; }
	}
	float opacity = 1.0 - transmission;
	ALPHA = floor(opacity * 32.0 + 0.5) / 32.0;
	ALBEDO = floor(color / max(opacity, 0.0001) * 18.0 + 0.5) / 18.0;
}
