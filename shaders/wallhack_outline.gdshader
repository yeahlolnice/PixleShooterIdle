shader_type spatial;
// Wallhack ESP pass. Set as next_pass on a bot part's material: draws neon box
// edges plus a faint fill on top of everything (depth test off), so bots show
// through walls. Edges come from the BoxMesh UV layout (each face is one cell of
// a 3x2 grid), which fits the voxel bots; fwidth() keeps lines a fixed pixel width.
// Only GLSL ES 3.0 features, so it also compiles under the Compatibility renderer.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.224, 1.0, 0.078, 1.0);
uniform float line_width_px = 2.0;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.15;
uniform vec2 uv_cells = vec2(3.0, 2.0);

void fragment() {
	vec2 uv = UV * uv_cells;
	vec2 cell = fract(uv);
	vec2 dist = min(cell, vec2(1.0) - cell);
	vec2 width = max(fwidth(uv) * line_width_px, vec2(0.0001));
	vec2 line = vec2(1.0) - smoothstep(width * 0.5, width, dist);
	float edge = max(line.x, line.y);
	ALBEDO = outline_color.rgb;
	ALPHA = mix(fill_alpha, 1.0, edge) * outline_color.a;
}
