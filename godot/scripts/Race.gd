extends Node2D

# Port of web/game.js - see DESIGN.md for the design rationale and
# tuned balance constants. Logic mirrors the JS version closely so the
# already-validated feel and numbers carry over; only the rendering
# approach changes (Godot's immediate-mode _draw() instead of Canvas2D).

# ---------- Config ----------
const LANES := 5
const LANE_EDGES: Array[float] = [-1.0, -0.60, -0.20, 0.20, 0.60, 1.0]
const LANE_CENTERS: Array[float] = [-0.80, -0.40, 0.0, 0.40, 0.80]
const RACE_TIME := 60.0
const FINISH_DISTANCE := 13000.0
const ROAD_LENGTH := 260.0

const BASE_SPEED_START := 150.0
const BASE_SPEED_RAMP := 3.2
const BASE_SPEED_MAX := 340.0
const TRAFFIC_SPEED_MULT := 0.8

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

# Impact/turbo feedback - kept brief, low-alpha, and/or geometrically
# confined (see _draw_turbo_ring/_draw_turbo_flash/_draw_speed_lines) so
# they read clearly without ever covering a lane or disabling input.
const SHAKE_DURATION := 0.22
const SHAKE_MAGNITUDE := 9.0
const TURBO_FLASH_DURATION := 0.28
const TURBO_RING_DURATION := 0.5
const SPEED_LINE_ALPHA := 0.55
const SPEED_LINE_PULSE_SPEED := 3.0

const TEX_BACKGROUND := preload("res://assets/environment/ocean-sky.png")
const TEX_GUARDRAILS := preload("res://assets/environment/guardrails.png")
const TEX_PLAYER := preload("res://assets/vehicles/player-gray.png")
const TRAFFIC_TEXTURES := [
	preload("res://assets/vehicles/traffic-coral.png"),
	preload("res://assets/vehicles/traffic-yellow.png"),
	preload("res://assets/vehicles/traffic-blue.png"),
	preload("res://assets/vehicles/traffic-green.png"),
	preload("res://assets/vehicles/traffic-orange.png"),
]
const TEX_COIN := preload("res://assets/collectibles/coin.png")
const TEX_TURBO_SEGMENT := preload("res://assets/hud/turbo-segment.png")

# Approved turbo-effect sprites.
const TEX_TURBO_EXHAUST := preload("res://assets/effects/turbo-exhaust-flames.png")
const TEX_TURBO_RING := preload("res://assets/effects/turbo-energy-ring.png")
const TEX_TURBO_FLASH := preload("res://assets/effects/turbo-activation-flash.png")
const TEX_TURBO_SPEED_LINES := preload("res://assets/effects/turbo-speed-lines.png")
const HAZARD_TEXTURES := [
	preload("res://assets/obstacles/pothole.png"),
	preload("res://assets/obstacles/loose-tire.png"),
	preload("res://assets/obstacles/traffic-cone.png"),
]

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
var shake_t: float = 0.0
var turbo_ring_t: float = 0.0
var turbo_flash_t: float = 0.0
var obstacles: Array = []
var coins_list: Array = []
var obstacle_timer: float = 0.0
var coin_timer: float = 0.0

var elapsed_t: float = 0.0
var lane_change_lock_until: int = 0
var combo_popup_timer: float = 0.0

# ---------- HUD refs ----------
@onready var timer_label: Label = $HUD/Root/TimerPanel/TimerLabel
@onready var coin_label: Label = $HUD/Root/CoinPanel/CoinLabel
@onready var combo_panel: Control = $HUD/Root/ComboPanel
@onready var combo_label: Label = $HUD/Root/ComboPanel/ComboLabel
@onready var progress_track: Control = $HUD/Root/ProgressTrack
@onready var progress_fill: ColorRect = $HUD/Root/ProgressTrack/ProgressFill
@onready var player_marker: TextureRect = $HUD/Root/ProgressTrack/PlayerMarker
@onready var turbo_gauge_track: Control = $HUD/Root/TurboGaugeTrack
@onready var turbo_segments: Control = $HUD/Root/TurboGaugeTrack/TurboSegments
@onready var combo_popup: Label = $HUD/Root/ComboPopup
@onready var btn_left: TextureButton = $HUD/Root/BtnLeft
@onready var btn_right: TextureButton = $HUD/Root/BtnRight
@onready var overlay: Control = $HUD/Root/Overlay
@onready var overlay_title: Label = $HUD/Root/Overlay/OverlayCard/OverlayTitle
@onready var overlay_subtitle: Label = $HUD/Root/Overlay/OverlayCard/OverlaySubtitle
@onready var overlay_button: Button = $HUD/Root/Overlay/OverlayCard/OverlayButton
@onready var overlay_stats: Label = $HUD/Root/Overlay/OverlayCard/OverlayStats


func _ready() -> void:
	randomize()
	_build_turbo_segments()
	btn_left.pressed.connect(func(): try_swerve(-1))
	btn_right.pressed.connect(func(): try_swerve(1))
	overlay_button.pressed.connect(func(): reset_game())
	set_process_unhandled_key_input(true)


func _build_turbo_segments() -> void:
	for child in turbo_segments.get_children():
		child.queue_free()
	const SEGMENT_COUNT := 12
	const SEGMENT_WIDTH := 15.0
	const SEGMENT_GAP := 3.0
	for i in range(SEGMENT_COUNT):
		var segment := TextureRect.new()
		segment.texture = TEX_TURBO_SEGMENT
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		segment.position = Vector2(i * (SEGMENT_WIDTH + SEGMENT_GAP), 0.0)
		segment.size = Vector2(SEGMENT_WIDTH, turbo_segments.size.y)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turbo_segments.add_child(segment)


# ---------- Perspective helpers (mirror the JS lane/road math exactly) ----------
# ROAD_VANISH_Y_FRAC/ROAD_WIDTH_SLOPE were measured directly off the approved
# reference screenshot's road (higher, tighter vanishing point and a
# steeper widening rate than assets/environment/guardrails.png was drawn
# against). GUARDRAIL_Y0_FRAC/GUARDRAIL_H_FRAC re-project that fixed,
# pre-rendered guardrail art onto the new geometry - the art's own
# perspective can't change, so instead it's drawn into a taller, higher
# rect that makes its baked vanishing point and taper rate land in the
# same place the new road math puts them.
func get_w() -> float:
	return get_viewport_rect().size.x

func get_h() -> float:
	return get_viewport_rect().size.y

const ROAD_VANISH_Y_FRAC := 0.023
const ROAD_WIDTH_SLOPE := 0.653
const GUARDRAIL_Y0_FRAC := -0.0292
const GUARDRAIL_H_FRAC := 0.9158

func horizon_y() -> float:
	return get_h() * ROAD_VANISH_Y_FRAC

func player_row_y() -> float:
	return get_h() * 0.80

func center_x() -> float:
	return get_w() * 0.5

func ease_p(p: float) -> float:
	return pow(clampf(p, 0.0, 2.0), 1.35)

# The one and only definition of how wide the road is at a given screen
# row - used for drawing the road surface AND for placing every object on
# it, so the two can never drift apart again.
func road_half_width(y: float) -> float:
	return maxf(0.0, ROAD_WIDTH_SLOPE * get_w() * (y - horizon_y()) / get_h())

func half_width_at(p: float) -> float:
	return road_half_width(row_y(p))

func lane_fraction(lane_index: float) -> float:
	var lo := clampi(int(floor(lane_index)), 0, LANES - 1)
	var hi := clampi(int(ceil(lane_index)), 0, LANES - 1)
	return lerp(LANE_CENTERS[lo], LANE_CENTERS[hi], lane_index - floor(lane_index))

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
	shake_t = 0.0
	turbo_ring_t = 0.0
	turbo_flash_t = 0.0
	position = Vector2.ZERO
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
		var is_hazard := randf() < 0.32
		obstacles.append({
			"lane": lanes[i], "p": 0.0, "resolved": false,
			"dodged": false, "was_near": false,
			"kind": "hazard" if is_hazard else "traffic",
			"variant": randi() % (HAZARD_TEXTURES.size() if is_hazard else TRAFFIC_TEXTURES.size()),
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

	# Obstacles: position always advances, even once resolved (hit or
	# passed) - otherwise a resolved car freezes in place forever instead
	# of continuing off-screen and becoming eligible for removal.
	for o in obstacles:
		o["p"] += dp * (TRAFFIC_SPEED_MULT if o["kind"] == "traffic" else 1.0)
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
				shake_t = SHAKE_DURATION
				popup_combo("HIT!", Color(1.0, 0.3, 0.3))
		elif o["p"] >= PASS_AT:
			o["resolved"] = true
			if o["dodged"] or o["was_near"]:
				boost_t = BOOST_TIME
				combo += 1
				best_combo = maxi(best_combo, combo)
				if not is_turbo:
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
					turbo_ring_t = TURBO_RING_DURATION
					turbo_flash_t = TURBO_FLASH_DURATION
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
	if shake_t > 0.0:
		shake_t = maxf(0.0, shake_t - dt)
	if turbo_ring_t > 0.0:
		turbo_ring_t = maxf(0.0, turbo_ring_t - dt)
	if turbo_flash_t > 0.0:
		turbo_flash_t = maxf(0.0, turbo_flash_t - dt)

	# Camera shake only ever offsets this Node2D, never the HUD (a separate
	# CanvasLayer, immune to its parent's 2D transform) - so it can never
	# desync touch-button hit testing or the gameplay math, which reads the
	# viewport size directly rather than this node's transform.
	if shake_t > 0.0:
		var shake_frac: float = shake_t / SHAKE_DURATION
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAGNITUDE * shake_frac
	elif position != Vector2.ZERO:
		position = Vector2.ZERO

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
const TIMER_GRADIENT_NORMAL: Array[Color] = [Color(1, 1, 1), Color(0.9315, 0.961, 1), Color(0.863, 0.922, 1)]
const TIMER_GRADIENT_URGENT: Array[Color] = [Color8(0xff, 0x4d, 0x4d), Color8(0xff, 0x73, 0x83), Color8(0xff, 0x9a, 0x66)]

func _update_hud() -> void:
	var remaining: float = maxf(0.0, RACE_TIME - time)
	timer_label.text = "%.1f" % remaining
	var timer_mat := timer_label.material as ShaderMaterial
	var timer_grad := TIMER_GRADIENT_URGENT if remaining < 10.0 else TIMER_GRADIENT_NORMAL
	timer_mat.set_shader_parameter("color_top", timer_grad[0])
	timer_mat.set_shader_parameter("color_mid", timer_grad[1])
	timer_mat.set_shader_parameter("color_bottom", timer_grad[2])
	coin_label.text = "%d" % coins
	combo_label.text = "%dx" % combo
	combo_panel.visible = combo > 0

	var pct: float = clampf(distance / FINISH_DISTANCE, 0.0, 1.0)
	var track_w: float = progress_track.size.x
	var marker_start := 3.0
	var marker_end := track_w * 0.87 - player_marker.size.x
	player_marker.position.x = lerpf(marker_start, marker_end, pct)
	progress_fill.size.x = maxf(0.0, player_marker.position.x + player_marker.size.x * 0.5 - marker_start)

	var gauge_pct: float = turbo_gauge / TURBO_GAUGE_MAX
	var lit_count := ceili(gauge_pct * turbo_segments.get_child_count())
	for i in range(turbo_segments.get_child_count()):
		var segment := turbo_segments.get_child(i) as TextureRect
		if i < lit_count:
			segment.modulate = _turbo_segment_color(i)
		else:
			segment.modulate = Color(0.12, 0.16, 0.22, 0.55)


# Segments 1-3 red, 4-7 orange, 8-10 amber, 11-12 yellow - an approved
# stepped color progression rather than a smooth per-segment gradient.
func _turbo_segment_color(i: int) -> Color:
	if i < 3:
		return Color8(0xff, 0x24, 0x18)
	elif i < 7:
		return Color8(0xff, 0x78, 0x00)
	elif i < 10:
		return Color8(0xff, 0xc4, 0x00)
	else:
		return Color8(0xff, 0xf2, 0x00)


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
		draw_items.append({"p": o["p"], "cb": func(): _draw_obstacle(o)})

	var remaining: float = FINISH_DISTANCE - distance
	if remaining <= FINISH_REVEAL_RANGE and remaining > -FINISH_REVEAL_RANGE * 0.4:
		var finish_p: float = 1.0 - remaining / FINISH_REVEAL_RANGE
		draw_items.append({"p": finish_p, "cb": func(): _draw_finish_tape(finish_p)})

	var px := lane_x(player_lane_visual, 1.0)
	var py := player_row_y()
	var p_scale := scale_at(1.0) * 1.05 * 1.2
	var turbo_now := is_turbo
	var t_now := elapsed_t
	draw_items.append({"p": 1.001, "cb": func():
		if turbo_now:
			_draw_flame_trail(Vector2(px, py), p_scale, t_now)
		_draw_sprite_toward_vanishing_point(TEX_PLAYER, Vector2(px, py), p_scale)
	})

	draw_items.sort_custom(func(a, b): return a["p"] < b["p"])
	for item in draw_items:
		item["cb"].call()

	if turbo_ring_t > 0.0:
		_draw_turbo_ring(px, py)
	if turbo_flash_t > 0.0:
		_draw_turbo_flash(px, py)

	var sz := get_viewport_rect().size
	if hit_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, hit_flash * 0.35))
	if win_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, win_flash * 0.6))


func _draw_vgrad(rect: Rect2, c_top: Color, c_bottom: Color, steps: int = 16) -> void:
	var step_h: float = rect.size.y / float(steps)
	for i in range(steps):
		var tt: float = float(i) / float(max(steps - 1, 1))
		var col := c_top.lerp(c_bottom, tt)
		draw_rect(Rect2(rect.position.x, rect.position.y + i * step_h, rect.size.x, step_h + 1.0), col)


# p1 is the far (horizon) end and p2 is the near (player) end - each dash
# fades from alpha_far up to alpha_near so the lines don't compete for
# attention far up the road, matching the vanishing guardrails/road shading.
func _draw_dashed_line(p1: Vector2, p2: Vector2, color: Color, width: float, dash: float, gap: float, offset: float, alpha_far: float, alpha_near: float) -> void:
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
			var t: float = ((seg_start + seg_end) * 0.5) / length
			var seg_color := color
			seg_color.a = color.a * lerpf(alpha_far, alpha_near, t)
			draw_line(p1 + dir * seg_start, p1 + dir * seg_end, seg_color, width)
		pos += pattern


const ROAD_COLOR_FAR := Color8(0x45, 0x4b, 0x5c)
const ROAD_COLOR_NEAR := Color8(0x23, 0x25, 0x2f)
const ROAD_CROWN_INSET := 0.7
const ROAD_CROWN_COLOR := Color(1, 1, 1, 0.06)
const ROAD_GRADIENT_STEPS := 28

func _draw_road() -> void:
	var w := get_w()
	var h := get_h()
	var hy := horizon_y()
	var cx := center_x()

	draw_texture_rect(TEX_BACKGROUND, Rect2(0, 0, w, h), false)

	# The road surface is drawn from the true vanishing point (0 width) all
	# the way to the bottom of the screen, one thin trapezoid strip at a
	# time, so the width at every row is exactly road_half_width(y) - the
	# same function guardrails.png was measured against and that every car
	# and coin is placed with. That keeps the asphalt's edge glued to the
	# guardrail art with no gap, and gives a smooth shading gradient instead
	# of two flat, mismatched polygons stacked on each other.
	for i in range(ROAD_GRADIENT_STEPS):
		var y0: float = lerp(hy, h, float(i) / ROAD_GRADIENT_STEPS)
		var y1: float = lerp(hy, h, float(i + 1) / ROAD_GRADIENT_STEPS)
		var hw0 := road_half_width(y0)
		var hw1 := road_half_width(y1)
		var col: Color = ROAD_COLOR_FAR.lerp(ROAD_COLOR_NEAR, float(i + 1) / ROAD_GRADIENT_STEPS)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - hw0, y0), Vector2(cx + hw0, y0),
			Vector2(cx + hw1, y1), Vector2(cx - hw1, y1),
		]), col)

	# Subtle crowned-centerline highlight: a second trapezoid sharing the
	# exact same vanishing point, just narrower, so it nests inside the
	# road surface instead of drifting off at a different angle.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, hy), Vector2(cx, hy),
		Vector2(cx + road_half_width(h) * ROAD_CROWN_INSET, h),
		Vector2(cx - road_half_width(h) * ROAD_CROWN_INSET, h),
	]), ROAD_CROWN_COLOR)

	for i in range(1, LANES):
		var frac := LANE_EDGES[i]
		var x0: float = cx + frac * road_half_width(hy)
		var x1: float = cx + frac * road_half_width(h)
		_draw_dashed_line(Vector2(x0, hy), Vector2(x1, h), Color(1, 1, 1, 0.88), 4.0, 30.0, 34.0, 0.0, 0.08, 1.0)

	draw_line(Vector2(cx, hy), Vector2(cx - road_half_width(h), h), Color.WHITE, 4.0)
	draw_line(Vector2(cx, hy), Vector2(cx + road_half_width(h), h), Color.WHITE, 4.0)
	draw_texture_rect(TEX_GUARDRAILS, Rect2(0, h * GUARDRAIL_Y0_FRAC, w, h * GUARDRAIL_H_FRAC), false)


func _draw_sprite_centered(texture: Texture2D, pos: Vector2, scale: float) -> void:
	var size := texture.get_size() * scale
	draw_texture_rect(texture, Rect2(pos - size * 0.5, size), false)


# Lane divider lines all radiate outward from the road's vanishing point
# (which sits right behind the timer badge) - that radiating line is the
# lane itself, so a car actually driving down it would be angled to match
# exactly. For the player's car (closest to camera, most prominent) the
# full geometric angle reads as a banked/sloped road once you factor in a
# rigid car body, so it's heavily damped to a subtle lean; traffic further
# away uses the true, undamped angle so it stays parallel to its lane.
const SPRITE_TILT_DAMPING := 0.3

func _draw_sprite_toward_vanishing_point(texture: Texture2D, pos: Vector2, scale: float, damping: float = SPRITE_TILT_DAMPING) -> void:
	var size := texture.get_size() * scale
	var dx := pos.x - center_x()
	var dy := pos.y - horizon_y()
	var angle := (atan2(-dx, dy) if dy > 0.0 else 0.0) * damping
	draw_set_transform(pos, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_obstacle(obstacle: Dictionary) -> void:
	var p: float = obstacle["p"]
	var pos := Vector2(lane_x(obstacle["lane"], p), row_y(p))
	var visual_scale := scale_at(p)
	if obstacle["kind"] == "hazard":
		_draw_sprite_centered(HAZARD_TEXTURES[obstacle["variant"]], pos, visual_scale)
	else:
		_draw_sprite_toward_vanishing_point(TRAFFIC_TEXTURES[obstacle["variant"]], pos, visual_scale * 0.82 * 1.3, 1.0)


func _draw_coin(pos: Vector2, scale: float) -> void:
	var spin: float = 0.68 + 0.32 * abs(sin(elapsed_t * 5.0 + pos.x * 0.03))
	var size := TEX_COIN.get_size() * scale
	size.x *= spin
	draw_texture_rect(TEX_COIN, Rect2(pos - size * 0.5, size), false)


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


# Approved twin-exhaust-flame sprite (already a matched left/right pair in
# one image) anchored just behind the player's rear, scaled off the car's
# own perspective scale so it shrinks/grows with the car.
const FLAME_TEX_SCALE := 0.34

func _draw_flame_trail(pos: Vector2, scale: float, t: float) -> void:
	var flicker: float = 0.82 + 0.18 * sin(t * 30.0)
	var size: Vector2 = TEX_TURBO_EXHAUST.get_size() * (FLAME_TEX_SCALE * scale)
	var origin: Vector2 = pos + Vector2(0.0, 26.0 * scale)
	draw_texture_rect(TEX_TURBO_EXHAUST, Rect2(origin - Vector2(size.x * 0.5, 0.0), size), false, Color(1, 1, 1, flicker))


# Approved energy-ring sprite, scaled up and faded out over
# TURBO_RING_DURATION - centered on the player so it reads as "bursting
# outward from the car" rather than a generic screen-wide flash.
const RING_TEX_MIN_SCALE := 0.2
const RING_TEX_MAX_SCALE := 1.0

func _draw_turbo_ring(px: float, py: float) -> void:
	var t: float = 1.0 - turbo_ring_t / TURBO_RING_DURATION
	var scale: float = lerp(RING_TEX_MIN_SCALE, RING_TEX_MAX_SCALE, t)
	var alpha: float = 1.0 - t
	var size: Vector2 = TEX_TURBO_RING.get_size() * scale
	draw_texture_rect(TEX_TURBO_RING, Rect2(Vector2(px, py) - size * 0.5, size), false, Color(1, 1, 1, alpha))


# Approved activation-flash sprite - kept small and quick (TURBO_FLASH_DURATION)
# so the burst reads as a hit of energy without ever covering nearby lanes.
const FLASH_TEX_SCALE := 0.32

func _draw_turbo_flash(px: float, py: float) -> void:
	var t: float = 1.0 - turbo_flash_t / TURBO_FLASH_DURATION
	var scale: float = lerp(0.5, 1.0, t) * FLASH_TEX_SCALE
	var alpha: float = 1.0 - t
	var size: Vector2 = TEX_TURBO_FLASH.get_size() * scale
	draw_texture_rect(TEX_TURBO_FLASH, Rect2(Vector2(px, py) - size * 0.5, size), false, Color(1, 1, 1, alpha))


# Approved speed-line burst, stretched to cover the viewport - the art
# itself is mostly negative space between rays, so traffic/hazards stay
# readable through the gaps rather than being covered by a solid layer.
# Alpha is tied to the remaining turbo gauge (not just is_turbo) so it
# tapers off smoothly as turbo drains instead of vanishing on the frame
# is_turbo flips false.
func _draw_speed_lines(t: float) -> void:
	var pulse: float = 0.85 + 0.15 * sin(t * SPEED_LINE_PULSE_SPEED)
	var fade_out: float = clampf(turbo_gauge / (TURBO_GAUGE_MAX * 0.15), 0.0, 1.0)
	var alpha: float = SPEED_LINE_ALPHA * pulse * fade_out
	draw_texture_rect(TEX_TURBO_SPEED_LINES, Rect2(0, 0, get_w(), get_h()), false, Color(1, 1, 1, alpha))
