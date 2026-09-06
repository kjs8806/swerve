extends Node2D

# Port of web/game.js - see DESIGN.md for the design rationale and
# tuned balance constants. Logic mirrors the JS version closely so the
# already-validated feel and numbers carry over; only the rendering
# approach changes (Godot's immediate-mode _draw() instead of Canvas2D).

# ---------- Config ----------
const LANES := 5
const RACE_TIME := 60.0
const FINISH_DISTANCE := 13000.0
const ROAD_LENGTH := 260.0

const BASE_SPEED_START := 150.0
const BASE_SPEED_RAMP := 3.2
const BASE_SPEED_MAX := 340.0

const COLLISION_PENALTY_MULT := 0.22
const COLLISION_RECOVER_TIME := 1.7
const BOOST_MULT := 1.28
const BOOST_TIME := 1.4
const TURBO_MULT := 1.9
const TURBO_GAUGE_MAX := 100.0
const TURBO_GAIN_PER_COIN := 20.0
const TURBO_DRAIN_PER_SEC := TURBO_GAUGE_MAX / 4.2

const DANGER_ZONE_START := 0.83
const COLLIDE_AT := 0.97
const PASS_AT := 1.08
const REMOVE_AT := 1.6
const FINISH_REVEAL_RANGE := ROAD_LENGTH * 2.5

const LANE_CHANGE_TIME := 0.14

enum State { READY, PLAYING, WIN, LOSE }

# ---------- State ----------
var state: int = State.READY
var time: float = 0.0
var distance: float = 0.0
var coins: int = 0
var combo: int = 0
var best_combo: int = 0
var player_lane: int = int((LANES - 1) / 2)
var player_lane_visual: float = float(player_lane)
var lane_anim_t: float = 1.0
var lane_anim_from: float = float(player_lane)
var turbo_gauge: float = 0.0
var is_turbo: bool = false
var invincible: bool = false
var penalty_t: float = 0.0
var boost_t: float = 0.0
var hit_flash: float = 0.0
var win_flash: float = 0.0
var road_scroll: float = 0.0
var obstacles: Array = []
var coins_list: Array = []
var obstacle_timer: float = 0.0
var coin_timer: float = 0.0

var elapsed_t: float = 0.0
var lane_change_lock_until: int = 0
var combo_popup_timer: float = 0.0
var vignette_tex: GradientTexture2D

# ---------- HUD refs ----------
@onready var timer_label: Label = $HUD/Root/TimerLabel
@onready var coin_label: Label = $HUD/Root/CoinLabel
@onready var progress_track: Control = $HUD/Root/ProgressTrack
@onready var progress_fill: ColorRect = $HUD/Root/ProgressTrack/ProgressFill
@onready var player_marker: ColorRect = $HUD/Root/ProgressTrack/PlayerMarker
@onready var turbo_gauge_track: Control = $HUD/Root/TurboGaugeTrack
@onready var turbo_fill: ColorRect = $HUD/Root/TurboGaugeTrack/TurboFill
@onready var turbo_banner: Label = $HUD/Root/TurboBanner
@onready var combo_popup: Label = $HUD/Root/ComboPopup
@onready var btn_left: Button = $HUD/Root/BtnLeft
@onready var btn_right: Button = $HUD/Root/BtnRight
@onready var overlay: Control = $HUD/Root/Overlay
@onready var overlay_title: Label = $HUD/Root/Overlay/OverlayCard/OverlayTitle
@onready var overlay_subtitle: Label = $HUD/Root/Overlay/OverlayCard/OverlaySubtitle
@onready var overlay_button: Button = $HUD/Root/Overlay/OverlayCard/OverlayButton
@onready var overlay_stats: Label = $HUD/Root/Overlay/OverlayCard/OverlayStats


func _ready() -> void:
	randomize()
	_build_vignette_texture()
	btn_left.pressed.connect(func(): try_swerve(-1))
	btn_right.pressed.connect(func(): try_swerve(1))
	overlay_button.pressed.connect(func(): reset_game())
	set_process_unhandled_key_input(true)


func _build_vignette_texture() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.47, 0.0, 0.0))
	grad.set_color(1, Color(1.0, 0.35, 0.0, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.6)
	tex.fill_to = Vector2(1.0, 0.6)
	tex.width = 256
	tex.height = 256
	vignette_tex = tex


# ---------- Perspective helpers (mirror the JS lane/road math exactly) ----------
func get_w() -> float:
	return get_viewport_rect().size.x

func get_h() -> float:
	return get_viewport_rect().size.y

func horizon_y() -> float:
	return get_h() * 0.14

func player_row_y() -> float:
	return get_h() * 0.80

func center_x() -> float:
	return get_w() * 0.5

func ease_p(p: float) -> float:
	return pow(clampf(p, 0.0, 2.0), 1.35)

func half_width_at(p: float) -> float:
	var top_half := get_w() * 0.10
	var bot_half := get_w() * 0.44
	return lerp(top_half, bot_half, ease_p(p))

func lane_fraction(lane_index: float) -> float:
	return (lane_index - (LANES - 1) / 2.0) / ((LANES - 1) / 2.0)

func lane_x(lane_index: float, p: float) -> float:
	return center_x() + lane_fraction(lane_index) * half_width_at(p)

func row_y(p: float) -> float:
	return lerp(horizon_y(), player_row_y(), ease_p(p))

func scale_at(p: float) -> float:
	return lerp(0.28, 1.0, ease_p(p))


# ---------- Game state ----------
func reset_game() -> void:
	state = State.PLAYING
	time = 0.0
	distance = 0.0
	coins = 0
	combo = 0
	best_combo = 0
	player_lane = int((LANES - 1) / 2)
	player_lane_visual = float(player_lane)
	lane_anim_from = float(player_lane)
	lane_anim_t = 1.0
	turbo_gauge = 0.0
	is_turbo = false
	invincible = false
	penalty_t = 0.0
	boost_t = 0.0
	hit_flash = 0.0
	win_flash = 0.0
	road_scroll = 0.0
	obstacles.clear()
	coins_list.clear()
	obstacle_timer = 0.6
	coin_timer = 0.9
	overlay.visible = false


func base_speed() -> float:
	return minf(BASE_SPEED_MAX, BASE_SPEED_START + BASE_SPEED_RAMP * time)


func current_speed() -> float:
	var mult := 1.0
	if penalty_t > 0.0:
		var tt: float = 1.0 - penalty_t / COLLISION_RECOVER_TIME
		mult *= lerp(COLLISION_PENALTY_MULT, 1.0, clampf(tt, 0.0, 1.0))
	if boost_t > 0.0:
		mult *= BOOST_MULT
	if is_turbo:
		mult *= TURBO_MULT
	return base_speed() * mult


func popup_combo(text: String, color: Color) -> void:
	combo_popup.text = text
	combo_popup.add_theme_color_override("font_color", color)
	combo_popup.modulate = Color(1, 1, 1, 1)
	combo_popup.visible = true
	combo_popup_timer = 0.65


# ---------- Input ----------
func try_swerve(dir: int) -> void:
	if state != State.PLAYING:
		return
	var now := Time.get_ticks_msec()
	if now < lane_change_lock_until:
		return
	lane_change_lock_until = now + 90
	var target: int = clampi(player_lane + dir, 0, LANES - 1)
	if target == player_lane:
		return
	_check_near_miss_on_leave(player_lane)
	lane_anim_from = player_lane_visual
	player_lane = target
	lane_anim_t = 0.0


func _check_near_miss_on_leave(from_lane: int) -> void:
	for o in obstacles:
		if o["resolved"]:
			continue
		if o["lane"] == from_lane and o["p"] >= DANGER_ZONE_START and o["p"] < COLLIDE_AT:
			o["dodged"] = true


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			try_swerve(-1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			try_swerve(1)
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if state != State.PLAYING:
				reset_game()


# ---------- Spawning ----------
func _spawn_obstacle_wave() -> void:
	var t := time
	var open_lanes: int = (LANES - 1) if t < 8.0 else (LANES - 2)
	var count: int
	if t < 8.0:
		count = 1
	elif t < 20.0:
		count = 1 if randf() < 0.6 else 2
	else:
		count = 2 if randf() < 0.5 else 3
	count = clampi(count, 1, LANES - maxi(1, LANES - open_lanes))
	count = mini(count, LANES - 1)

	var lanes: Array = []
	for i in range(LANES):
		lanes.append(i)
	for i in range(lanes.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = lanes[i]
		lanes[i] = lanes[j]
		lanes[j] = tmp

	for i in range(count):
		obstacles.append({
			"lane": lanes[i], "p": 0.0, "resolved": false,
			"dodged": false, "was_near": false,
		})


func _spawn_coins() -> void:
	var lane := randi() % LANES
	var run_len := 1 + (randi() % 3)
	for i in range(run_len):
		coins_list.append({"lane": lane, "p": -i * 0.06, "collected": false})


# ---------- Update ----------
func _process(delta: float) -> void:
	elapsed_t += delta
	_update_game(delta)
	queue_redraw()
	_update_hud()


func _update_game(dt: float) -> void:
	if state != State.PLAYING:
		return

	time += dt

	if lane_anim_t < 1.0:
		lane_anim_t = clampf(lane_anim_t + dt / LANE_CHANGE_TIME, 0.0, 1.0)
		player_lane_visual = lerp(lane_anim_from, float(player_lane), lane_anim_t)

	if penalty_t > 0.0:
		penalty_t = maxf(0.0, penalty_t - dt)
	if boost_t > 0.0:
		boost_t = maxf(0.0, boost_t - dt)

	if is_turbo:
		turbo_gauge = maxf(0.0, turbo_gauge - TURBO_DRAIN_PER_SEC * dt)
		if turbo_gauge <= 0.0:
			is_turbo = false
			invincible = false
			turbo_gauge = 0.0

	var speed := current_speed()
	distance += speed * dt
	var dp: float = (speed / ROAD_LENGTH) * dt
	road_scroll += speed * dt

	# Obstacles: position always advances, even once resolved (hit or
	# passed) - otherwise a resolved car freezes in place forever instead
	# of continuing off-screen and becoming eligible for removal.
	for o in obstacles:
		o["p"] += dp
		if o["resolved"]:
			continue

		if o["lane"] == player_lane and o["p"] >= DANGER_ZONE_START and o["p"] < COLLIDE_AT:
			o["was_near"] = true

		if o["p"] >= COLLIDE_AT and o["lane"] == player_lane:
			if invincible:
				o["resolved"] = true
			else:
				o["resolved"] = true
				penalty_t = COLLISION_RECOVER_TIME
				boost_t = 0.0
				combo = 0
				hit_flash = 0.25
				popup_combo("HIT!", Color(1.0, 0.3, 0.3))
		elif o["p"] >= PASS_AT:
			o["resolved"] = true
			if o["dodged"] or o["was_near"]:
				boost_t = BOOST_TIME
				combo += 1
				best_combo = maxi(best_combo, combo)
				popup_combo("NICE! x%d" % combo, Color(0.208, 0.878, 0.631))

	obstacles = obstacles.filter(func(o): return o["p"] < REMOVE_AT)

	for c in coins_list:
		if c["collected"]:
			continue
		c["p"] += dp
		if c["lane"] == player_lane and c["p"] >= DANGER_ZONE_START and c["p"] < COLLIDE_AT + 0.05:
			c["collected"] = true
			coins += 1
			if not is_turbo:
				turbo_gauge = minf(TURBO_GAUGE_MAX, turbo_gauge + TURBO_GAIN_PER_COIN)
				if turbo_gauge >= TURBO_GAUGE_MAX:
					is_turbo = true
					invincible = true
					popup_combo("TURBO!", Color(1.0, 0.478, 0.102))

	coins_list = coins_list.filter(func(c): return not c["collected"] and c["p"] < REMOVE_AT)

	obstacle_timer -= dt
	if obstacle_timer <= 0.0:
		_spawn_obstacle_wave()
		var t := time
		var interval: float
		if t < 8.0:
			interval = 1.3
		elif t < 20.0:
			interval = 1.0
		elif t < 40.0:
			interval = 0.78
		else:
			interval = 0.6
		obstacle_timer = interval * (0.85 + randf() * 0.3)

	coin_timer -= dt
	if coin_timer <= 0.0:
		_spawn_coins()
		coin_timer = 1.6 + randf() * 1.2

	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - dt)
	if win_flash > 0.0:
		win_flash = maxf(0.0, win_flash - dt)

	if combo_popup_timer > 0.0:
		combo_popup_timer -= dt
		if combo_popup_timer <= 0.0:
			combo_popup.visible = false

	if distance >= FINISH_DISTANCE:
		state = State.WIN
		win_flash = 0.5
		_show_end_screen(true)
	elif time >= RACE_TIME:
		state = State.LOSE
		_show_end_screen(false)


func _show_end_screen(won: bool) -> void:
	overlay.visible = true
	overlay_title.text = "FINISH!" if won else "TIME UP"
	overlay_subtitle.text = ("You crossed the finish line in time." if won
		else "You didn't reach the finish line before the clock ran out.")
	overlay_button.text = "PLAY AGAIN"
	var time_used: float = minf(time, RACE_TIME)
	overlay_stats.text = "Time: %.1fs\nDistance: %d / %d\nCoins: %d\nBest Combo: x%d" % [
		time_used, int(distance), int(FINISH_DISTANCE), coins, best_combo,
	]


# ---------- HUD ----------
func _update_hud() -> void:
	var remaining: float = maxf(0.0, RACE_TIME - time)
	timer_label.text = "%.1f" % remaining
	timer_label.modulate = Color8(0xff, 0x4d, 0x4d) if remaining < 10.0 else Color8(0xff, 0xcc, 0x33)
	coin_label.text = "COIN %d" % coins

	var pct: float = clampf(distance / FINISH_DISTANCE, 0.0, 1.0)
	var track_w: float = progress_track.size.x
	progress_fill.size.x = track_w * pct
	player_marker.position.x = clampf(track_w * pct - player_marker.size.x * 0.5, 0.0, maxf(0.0, track_w - player_marker.size.x))

	var gauge_pct: float = turbo_gauge / TURBO_GAUGE_MAX
	turbo_fill.size.x = turbo_gauge_track.size.x * gauge_pct
	turbo_banner.visible = is_turbo
	if is_turbo:
		var glow: float = 0.8 + 0.2 * sin(elapsed_t * 8.0)
		turbo_banner.modulate = Color(glow, glow, glow, 1.0)


# ---------- Rendering ----------
func _draw() -> void:
	_draw_road()
	if is_turbo:
		_draw_speed_lines(elapsed_t)

	# Everything on the road - coins, traffic, the finish tape, and the
	# player - is drawn in a single depth-sorted pass so a just-passed
	# obstacle (p > 1, "closer to camera" than the player) renders in
	# front of the player as it exits instead of behind it.
	var draw_items: Array = []
	for c in coins_list:
		if c["p"] < -0.1:
			continue
		draw_items.append({"p": c["p"], "cb": func(): _draw_coin(Vector2(lane_x(c["lane"], c["p"]), row_y(c["p"])), scale_at(c["p"]))})
	for o in obstacles:
		draw_items.append({"p": o["p"], "cb": func(): _draw_car(Vector2(lane_x(o["lane"], o["p"]), row_y(o["p"])), scale_at(o["p"]), Color8(0x4d, 0x7c, 0xff))})

	var remaining: float = FINISH_DISTANCE - distance
	if remaining <= FINISH_REVEAL_RANGE and remaining > -FINISH_REVEAL_RANGE * 0.4:
		var finish_p: float = 1.0 - remaining / FINISH_REVEAL_RANGE
		draw_items.append({"p": finish_p, "cb": func(): _draw_finish_tape(finish_p)})

	var px := lane_x(player_lane_visual, 1.0)
	var py := player_row_y()
	var p_scale := scale_at(1.0) * 1.05
	var p_color: Color
	if is_turbo:
		p_color = Color8(0xff, 0x7a, 0x1a)
	elif penalty_t > 0.0:
		p_color = Color8(0xff, 0x4d, 0x4d)
	else:
		p_color = Color8(0xff, 0x2d, 0x55)
	var turbo_now := is_turbo
	var t_now := elapsed_t
	draw_items.append({"p": 1.001, "cb": func():
		if turbo_now:
			_draw_flame_trail(Vector2(px, py), p_scale, t_now)
		_draw_car(Vector2(px, py), p_scale, p_color)
	})

	draw_items.sort_custom(func(a, b): return a["p"] < b["p"])
	for item in draw_items:
		item["cb"].call()

	var sz := get_viewport_rect().size
	if hit_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, hit_flash * 0.35))
	if win_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, win_flash * 0.6))
	if is_turbo:
		var pulse: float = 0.5 + 0.5 * sin(elapsed_t * 8.0)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.549, 0.078, 0.08 + pulse * 0.05))
		draw_texture_rect(vignette_tex, Rect2(Vector2.ZERO, sz), false, Color(1, 1, 1, 0.35 + pulse * 0.25))


func _draw_vgrad(rect: Rect2, c_top: Color, c_bottom: Color, steps: int = 16) -> void:
	var step_h: float = rect.size.y / float(steps)
	for i in range(steps):
		var tt: float = float(i) / float(max(steps - 1, 1))
		var col := c_top.lerp(c_bottom, tt)
		draw_rect(Rect2(rect.position.x, rect.position.y + i * step_h, rect.size.x, step_h + 1.0), col)


func _draw_dashed_line(p1: Vector2, p2: Vector2, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var dir: Vector2 = p2 - p1
	var length := dir.length()
	if length <= 0.0:
		return
	dir = dir / length
	var pattern := dash + gap
	var pos := fmod(-offset, pattern)
	if pos < 0.0:
		pos += pattern
	while pos < length:
		var seg_start: float = maxf(pos, 0.0)
		var seg_end: float = minf(pos + dash, length)
		if seg_end > seg_start:
			draw_line(p1 + dir * seg_start, p1 + dir * seg_end, color, width)
		pos += pattern


func _draw_road() -> void:
	var w := get_w()
	var h := get_h()
	draw_rect(Rect2(0, 0, w, h), Color8(0x0b, 0x12, 0x20))

	var hy := horizon_y()
	_draw_vgrad(Rect2(0, 0, w, hy), Color8(0x1c, 0x2b, 0x4a), Color8(0x3a, 0x5a, 0x86))

	var cx := center_x()
	var top_half := half_width_at(0.0) * (1.0 + 1.0 / (LANES - 1))
	var bot_half := half_width_at(1.0) * (1.0 + 1.0 / (LANES - 1))
	var poly := PackedVector2Array([
		Vector2(cx - top_half, hy),
		Vector2(cx + top_half, hy),
		Vector2(cx + bot_half, h),
		Vector2(cx - bot_half, h),
	])
	draw_colored_polygon(poly, Color8(0x33, 0x39, 0x4a))

	for i in range(1, LANES):
		var frac := lane_fraction(i - 0.5)
		var x0: float = cx + frac * half_width_at(0.0)
		var x1: float = cx + frac * half_width_at(1.0)
		_draw_dashed_line(Vector2(x0, hy), Vector2(x1, h), Color(1, 1, 1, 0.55), 3.0, 14.0, 16.0, fmod(road_scroll, 30.0))

	draw_line(Vector2(cx - top_half, hy), Vector2(cx - bot_half, h), Color8(0xff, 0xcc, 0x33), 3.0)
	draw_line(Vector2(cx + top_half, hy), Vector2(cx + bot_half, h), Color8(0xff, 0xcc, 0x33), 3.0)


func _ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = (float(i) / segments) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_round_rect(rect: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	draw_style_box(sb, rect)


func _draw_car(pos: Vector2, scale: float, color: Color) -> void:
	var w: float = 46.0 * scale
	var h: float = 74.0 * scale
	draw_set_transform(pos, 0.0, Vector2.ONE)
	draw_colored_polygon(_ellipse_points(Vector2(0, h * 0.42), w * 0.55, h * 0.14), Color(0, 0, 0, 0.35))
	_draw_round_rect(Rect2(-w / 2.0, -h / 2.0, w, h), color, w * 0.28)
	_draw_round_rect(Rect2(-w / 2.0 + w * 0.14, -h / 2.0 + h * 0.18, w * 0.72, h * 0.32), Color(1, 1, 1, 0.85), w * 0.16)
	draw_rect(Rect2(-w / 2.0 + w * 0.08, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_rect(Rect2(w / 2.0 - w * 0.26, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_coin(pos: Vector2, scale: float) -> void:
	draw_set_transform(pos, 0.0, Vector2.ONE)
	var r: float = 13.0 * scale
	draw_circle(Vector2.ZERO, r, Color8(0xff, 0xd9, 0x3d))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color8(0xb8, 0x86, 0x0b), 2.0)
	var font := ThemeDB.fallback_font
	var font_size: int = int(14 * scale)
	draw_string(font, Vector2(-4.0 * scale, 5.0 * scale), "$", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color8(0xb8, 0x86, 0x0b))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_finish_tape(p: float) -> void:
	var y := row_y(p)
	var scale := scale_at(p)
	var cx := center_x()
	var hw: float = half_width_at(p) * (1.0 + 1.0 / (LANES - 1))
	var band_h: float = 24.0 * scale
	var pole_w: float = 6.0 * scale
	var pole_h: float = band_h * 2.6

	draw_rect(Rect2(cx - hw - pole_w, y - pole_h, pole_w, pole_h), Color8(0xc0, 0x2c, 0x46))
	draw_rect(Rect2(cx + hw, y - pole_h, pole_w, pole_h), Color8(0xc0, 0x2c, 0x46))

	var cols := 16
	var cw: float = (hw * 2.0) / cols
	for i in range(cols):
		var col: Color = Color8(0x11, 0x13, 0x18) if i % 2 == 0 else Color8(0xf5, 0xf5, 0xf5)
		draw_rect(Rect2(cx - hw + i * cw, y - band_h, cw, band_h), col)
	draw_rect(Rect2(cx - hw, y - band_h, hw * 2.0, band_h), Color(0, 0, 0, 0.5), false, 2.0 * scale)

	var font := ThemeDB.fallback_font
	var font_size: int = int(15 * scale)
	var text_pos := Vector2(cx - font.get_string_size("FINISH", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x / 2.0, y - band_h / 2.0 + 5.0 * scale)
	draw_string_outline(font, text_pos, "FINISH", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, maxi(2, int(3 * scale)), Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, "FINISH", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _draw_speed_lines(t: float) -> void:
	var cx := center_x()
	var cy := horizon_y()
	var w := get_w()
	var h := get_h()
	var count := 14
	for i in range(count):
		var angle: float = (float(i) / count) * TAU + t * 0.6
		var wobble: float = 0.85 + 0.15 * sin(t * 4.0 + i)
		var length: float = maxf(w, h) * 0.75 * wobble
		var p1 := Vector2(cx + cos(angle) * 18.0, cy + sin(angle) * 18.0 * 0.4)
		var p2 := Vector2(cx + cos(angle) * length, cy + sin(angle) * length * 0.4)
		draw_line(p1, p2, Color(1.0, 0.784, 0.47, 0.5), 2.0 + 2.0 * wobble)


func _draw_flame_trail(pos: Vector2, scale: float, t: float) -> void:
	var flicker: float = 0.7 + 0.3 * sin(t * 30.0)
	var origin: Vector2 = pos + Vector2(0, 30.0 * scale)
	var pts := PackedVector2Array([
		origin + Vector2(-12.0 * scale, 0),
		origin + Vector2(12.0 * scale, 0),
		origin + Vector2(0, 36.0 * scale * flicker),
	])
	var colors := PackedColorArray([
		Color(1.0, 0.949, 0.769, flicker),
		Color(1.0, 0.949, 0.769, flicker),
		Color(1.0, 0.376, 0.0, 0.0),
	])
	draw_polygon(pts, colors)
