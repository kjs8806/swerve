shader_type canvas_item;

// Vertical 3-stop gradient recolor for Label fill glyphs, with an italic
// skew applied to every glyph quad. Godot draws a Label's outline and
// shadow passes as separate draw calls in the *same* bright font_color
// most fonts use for fill vs. the near-black colors typically used for
// outline/shadow - so this only re-tints a pass when the incoming color
// is bright, leaving the outline/shadow colors set in the theme alone.
uniform vec4 color_top : source_color = vec4(1.0);
uniform vec4 color_mid : source_color = vec4(1.0);
uniform vec4 color_bottom : source_color = vec4(1.0);
uniform float skew : hint_range(-1.0, 1.0) = 0.0;
uniform float fill_luminance_threshold : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	VERTEX.x -= VERTEX.y * skew;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 base = COLOR;
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = base.rgb;
	if (lum > fill_luminance_threshold) {
		float t = clamp(UV.y, 0.0, 1.0);
		vec3 grad = t < 0.5
			? mix(color_top.rgb, color_mid.rgb, t * 2.0)
			: mix(color_mid.rgb, color_bottom.rgb, (t - 0.5) * 2.0);
		rgb = grad;
	}
	COLOR = vec4(rgb, tex.a * base.a);
}
