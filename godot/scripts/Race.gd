extends Node2D

# Port of web/game.js - see DESIGN.md for the design rationale and
# tuned balance constants. Logic mirrors the JS version closely so the
# already-validated feel and numbers carry over; only the rendering
# approach changes (Godot's immediate-mode _draw() instead of Canvas2D).

# ---------- Config ----------
const LANES := 5
const LANE_EDGES: Array[float] = [-1.0, -0.70, -0.20, 0.20, 0.70, 1.0]
const LANE_CENTERS: Array[float] = [-0.85, -0.45, 0.0, 0.45, 0.85]
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
const TURBO_DURATION := 4.2
const TURBO_DRAIN_PER_SEC := TURBO_GAUGE_MAX / TURBO_DURATION
const TURBO_SPAWN_MIN := 7.0
const TURBO_SPAWN_MAX := 11.0

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

# Coin pickup feedback: a quick punch on the HUD counter plus a brief
# in-world sparkle (see spark_fx below) at the exact pickup point.
const COIN_PUNCH_DURATION := 0.18
const COIN_PUNCH_SCALE := 1.35
const COIN_PICKUP_FX_DURATION := 0.3
const COIN_SPARK_COLOR := Color(1.0, 0.85, 0.3)

# Near-miss feedback: same expanding-spark mechanic as a coin pickup (see
# spark_fx below), positioned at the dodged obstacle, plus a light screen
# tint - far more restrained than hit_flash since this rewards the player
# rather than punishing them.
const NEAR_MISS_FX_DURATION := 0.3
const NEAR_MISS_SPARK_COLOR := Color(0.208, 0.878, 0.631)
const NEAR_MISS_FLASH_DURATION := 0.18

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
const TEX_TURBO_PICKUP := preload("res://assets/collectibles/turbo-pickup.png")
const TURBO_SEGMENT_COUNT := 17
const TEX_TURBO_SEGMENT_RED := preload("res://assets/hud/turbo-segment-red.png")
const TEX_TURBO_SEGMENT_ORANGE := preload("res://assets/hud/turbo-segment-orange.png")
const TEX_TURBO_SEGMENT_YELLOW := preload("res://assets/hud/turbo-segment-yellow.png")

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
var coin_punch_t: float = 0.0
var near_miss_flash: float = 0.0
var spark_fx: Array = [] # {pos, scale, t, duration, color} - coin pickups + near-misses
var road_scroll: float = 0.0
var obstacles: Array = []
var coins_list: Array = []
var turbo_pickups: Array = []
var obstacle_timer: float = 0.0
var coin_timer: float = 0.0
var turbo_spawn_timer: float = 0.0

var elapsed_t: float = 0.0
var lane_change_lock_until: int = 0
var combo_popup_timer: float = 0.0
var combo_badge_tween: Tween
var vignette_tex: GradientTexture2D
var cloud_seeds: Array = []
var rock_seeds: Array = []
var audio_controller

# ---------- HUD refs ----------
@onready var timer_label: Label = $HUD/Root/TimerPanel/TimerLabel
@onready var coin_label: Label = $HUD/Root/CoinPanel/CoinLabel
@onready var combo_panel: Control = $HUD/Root/ComboPanel
@onready var combo_art: TextureRect = $HUD/Root/ComboPanel/ComboArt
@onready var combo_label: Label = $HUD/Root/ComboPanel/ComboLabel
@onready var progress_track: Control = $HUD/Root/ProgressTrack
@onready var player_marker: TextureRect = $HUD/Root/ProgressTrack/PlayerMarker
@onready var turbo_gauge_track: Control = $HUD/Root/TurboGaugeTrack
@onready var turbo_segments: Control = $HUD/Root/TurboGaugeTrack/TurboSegments
@onready var turbo_banner: Label = get_node_or_null("HUD/Root/TurboBanner") as Label
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
	# Audio must never prevent the race scene from starting. Load the optional
	# controller at runtime so an unavailable decoder/resource degrades to a
	# silent game instead of making Race.gd fail during its preload phase.
	var controller_script := load("res://scripts/AudioController.gd")
	if controller_script is Script and controller_script.can_instantiate():
		audio_controller = controller_script.new()
		audio_controller.name = "AudioController"
		add_child(audio_controller)
	_build_vignette_texture()
	_build_scenery_seeds()
	_build_turbo_segments()
	btn_left.pressed.connect(func(): try_swerve(-1))
	btn_right.pressed.connect(func(): try_swerve(1))
	overlay_button.pressed.connect(func(): reset_game(true))
	set_process_unhandled_key_input(true)


func _audio_call(method: StringName, args: Array = []) -> void:
	if audio_controller != null and audio_controller.has_method(method):
		audio_controller.callv(method, args)


func _build_turbo_segments() -> void:
	for child in turbo_segments.get_children():
		child.queue_free()
	# Pixel-matched to the approved 840x100 gauge artwork at its 420x50
	# runtime size. The base contains the frame, label, and 17 dark slots;
	# these colored overlays are revealed as the live gauge fills.
	const SEGMENT_X: Array[float] = [
		105.16, 120.68, 135.99, 151.40, 166.60, 181.91,
		197.32, 212.73, 228.56, 244.39, 260.33, 276.47,
		292.40, 308.23, 324.27, 340.31, 356.56,
	]
	for i in range(TURBO_SEGMENT_COUNT):
		var segment := TextureRect.new()
		if i < 3:
			segment.texture = TEX_TURBO_SEGMENT_RED
		elif i < 8:
			segment.texture = TEX_TURBO_SEGMENT_ORANGE
		else:
			segment.texture = TEX_TURBO_SEGMENT_YELLOW
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		segment.position = Vector2(SEGMENT_X[i], 14.0)
		segment.size = Vector2(25.0, 25.0)
		segment.visible = false
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turbo_segments.add_child(segment)


func _build_scenery_seeds() -> void:
	for i in range(5):
		cloud_seeds.append({
			"x": randf(), "y": 0.15 + randf() * 0.55, "scale": 0.6 + randf() * 0.8,
		})
	for i in range(6):
		rock_seeds.append({
			"side": -1 if i % 2 == 0 else 1,
			"x": 0.55 + randf() * 0.4, "scale": 0.5 + randf() * 0.9,
		})


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
	var top_half := get_w() * 0.095
	var bot_half := get_w() * 0.50
	return lerp(top_half, bot_half, ease_p(p))

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
func reset_game(play_ui_tap: bool = false) -> void:
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
	coin_punch_t = 0.0
	near_miss_flash = 0.0
	spark_fx.clear()
	position = Vector2.ZERO
	road_scroll = 0.0
	obstacles.clear()
	coins_list.clear()
	turbo_pickups.clear()
	obstacle_timer = 0.6
	coin_timer = 0.9
	turbo_spawn_timer = randf_range(TURBO_SPAWN_MIN, TURBO_SPAWN_MAX)
	overlay.visible = false
	_audio_call(&"begin_race", [play_ui_tap])


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


func _spawn_spark(pos: Vector2, scale: float, duration: float, color: Color) -> void:
	spark_fx.append({"pos": pos, "scale": scale, "t": duration, "duration": duration, "color": color})


func popup_combo(text: String, color: Color) -> void:
	combo_popup.text = text
	combo_popup.add_theme_color_override("font_color", color)
	combo_popup.modulate = Color(1, 1, 1, 1)
	combo_popup.visible = true
	combo_popup_timer = 0.65


func _play_combo_badge_fx() -> void:
	if combo_badge_tween != null and combo_badge_tween.is_valid():
		combo_badge_tween.kill()
	combo_panel.pivot_offset = combo_panel.size * Vector2(0.82, 0.5)
	combo_panel.scale = Vector2(0.72, 0.72)
	combo_panel.rotation = -0.045
	combo_panel.modulate = Color(1.0, 0.82, 0.42, 0.25)
	combo_art.position.x = 24.0
	combo_art.modulate = Color(1.35, 1.12, 0.72, 1.0)
	combo_badge_tween = create_tween().set_parallel(true)
	combo_badge_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	combo_badge_tween.tween_property(combo_panel, "scale", Vector2(1.12, 1.12), 0.14)
	combo_badge_tween.tween_property(combo_panel, "rotation", 0.0, 0.14)
	combo_badge_tween.tween_property(combo_panel, "modulate", Color.WHITE, 0.10)
	combo_badge_tween.tween_property(combo_art, "position:x", 0.0, 0.16)
	combo_badge_tween.tween_property(combo_art, "modulate", Color.WHITE, 0.22)
	combo_badge_tween.chain().set_parallel(false)
	combo_badge_tween.tween_property(combo_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	_audio_call(&"lane_changed")


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
# Spawn intervals shrink to well under an obstacle's ~1.2-1.5s travel time
# at high difficulty, so waves overlap on the road - picking lanes only
# from THIS wave's own set (the old approach) can't see obstacles a
# previous wave left in flight, and the two together can end up covering
# every lane at once (verified by simulation: possible with the old
# per-wave-only logic). Guaranteeing a stronger, simpler invariant instead
# - at least one lane is always completely free of any unresolved
# obstacle - makes that structurally impossible regardless of how waves
# overlap.
func _spawn_obstacle_wave() -> void:
	var t := time
	var count: int
	if t < 8.0:
		count = 1
	elif t < 20.0:
		count = 1 if randf() < 0.6 else 2
	else:
		count = 2 if randf() < 0.5 else 3

	var occupied_lanes: Dictionary = {}
	for o in obstacles:
		if not o["resolved"]:
			occupied_lanes[o["lane"]] = true

	var free_lanes: Array = []
	for i in range(LANES):
		if not occupied_lanes.has(i):
			free_lanes.append(i)

	# Leave at least one already-free lane untouched by this wave too.
	count = mini(count, maxi(0, free_lanes.size() - 1))
	if count <= 0:
		return

	for i in range(free_lanes.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = free_lanes[i]
		free_lanes[i] = free_lanes[j]
		free_lanes[j] = tmp

	for i in range(count):
		var is_hazard := randf() < 0.32
		obstacles.append({
			"lane": free_lanes[i], "p": 0.0, "resolved": false,
			"dodged": false, "was_near": false,
			"kind": "hazard" if is_hazard else "traffic",
			"variant": randi() % (HAZARD_TEXTURES.size() if is_hazard else TRAFFIC_TEXTURES.size()),
		})


func _spawn_coins() -> void:
	var lane := randi() % LANES
	var run_len := 1 + (randi() % 3)
	for i in range(run_len):
		coins_list.append({"lane": lane, "p": -i * 0.06, "collected": false})


func _spawn_turbo_pickup() -> void:
	# Lane indices keep pickups centered using the live lane geometry.
	var lane := randi() % LANES
	turbo_pickups.append({"lane": lane, "p": 0.0, "collected": false})


func _activate_timed_turbo() -> void:
	var was_active := is_turbo
	turbo_gauge = TURBO_GAUGE_MAX
	is_turbo = true
	invincible = true
	popup_combo("TURBO! %.1fs" % TURBO_DURATION, Color(1.0, 0.478, 0.102))
	_audio_call(&"turbo_charged")
	if not was_active:
		turbo_ring_t = TURBO_RING_DURATION
		turbo_flash_t = TURBO_FLASH_DURATION
		_audio_call(&"set_turbo", [true])


func _deactivate_turbo(clear_gauge: bool = true) -> void:
	is_turbo = false
	invincible = false
	if clear_gauge:
		turbo_gauge = 0.0
	_audio_call(&"set_turbo", [false])


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
			_deactivate_turbo()

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
				shake_t = SHAKE_DURATION
				popup_combo("HIT!", Color(1.0, 0.3, 0.3))
				_audio_call(&"collision", [o["kind"] == "hazard"])
		elif o["p"] >= PASS_AT:
			o["resolved"] = true
			if o["dodged"] or o["was_near"]:
				boost_t = BOOST_TIME
				combo += 1
				best_combo = maxi(best_combo, combo)
				near_miss_flash = NEAR_MISS_FLASH_DURATION
				_spawn_spark(Vector2(lane_x(o["lane"], o["p"]), row_y(o["p"])), scale_at(o["p"]), NEAR_MISS_FX_DURATION, NEAR_MISS_SPARK_COLOR)
				popup_combo("NICE! x%d" % combo, Color(0.208, 0.878, 0.631))
				_play_combo_badge_fx()
				_audio_call(&"combo_increased")

	obstacles = obstacles.filter(func(o): return o["p"] < REMOVE_AT)

	for c in coins_list:
		if c["collected"]:
			continue
		c["p"] += dp
		if c["lane"] == player_lane and c["p"] >= DANGER_ZONE_START and c["p"] < COLLIDE_AT + 0.05:
			c["collected"] = true
			coins += 1
			coin_punch_t = COIN_PUNCH_DURATION
			_spawn_spark(Vector2(lane_x(c["lane"], c["p"]), row_y(c["p"])), scale_at(c["p"]), COIN_PICKUP_FX_DURATION, COIN_SPARK_COLOR)
			_audio_call(&"coin_collected")

	coins_list = coins_list.filter(func(c): return not c["collected"] and c["p"] < REMOVE_AT)

	for pickup in turbo_pickups:
		if pickup["collected"]:
			continue
		pickup["p"] += dp
		if pickup["lane"] == player_lane and pickup["p"] >= DANGER_ZONE_START and pickup["p"] < COLLIDE_AT + 0.05:
			pickup["collected"] = true
			_activate_timed_turbo()

	turbo_pickups = turbo_pickups.filter(func(pickup): return not pickup["collected"] and pickup["p"] < REMOVE_AT)

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

	turbo_spawn_timer -= dt
	if turbo_spawn_timer <= 0.0:
		_spawn_turbo_pickup()
		turbo_spawn_timer = randf_range(TURBO_SPAWN_MIN, TURBO_SPAWN_MAX)

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
	if coin_punch_t > 0.0:
		coin_punch_t = maxf(0.0, coin_punch_t - dt)
	if near_miss_flash > 0.0:
		near_miss_flash = maxf(0.0, near_miss_flash - dt)
	for fx in spark_fx:
		fx["t"] -= dt
	spark_fx = spark_fx.filter(func(fx): return fx["t"] > 0.0)

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
		_deactivate_turbo()
		turbo_pickups.clear()
		_audio_call(&"finish_race", [true])
		_show_end_screen(true)
	elif time >= RACE_TIME:
		state = State.LOSE
		_deactivate_turbo()
		turbo_pickups.clear()
		_audio_call(&"finish_race", [false])
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
	if state == State.PLAYING:
		_audio_call(&"update_countdown", [remaining])
	timer_label.text = "%.1f" % remaining
	timer_label.modulate = Color8(0xff, 0x4d, 0x4d) if remaining < 10.0 else Color8(0xff, 0xcc, 0x33)
	coin_label.text = "%d" % coins
	coin_label.pivot_offset = coin_label.size * 0.5
	var coin_punch_frac: float = coin_punch_t / COIN_PUNCH_DURATION
	coin_label.scale = Vector2.ONE * (1.0 + (COIN_PUNCH_SCALE - 1.0) * coin_punch_frac)
	combo_label.text = "%dx" % maxi(1, combo)

	var pct: float = clampf(distance / FINISH_DISTANCE, 0.0, 1.0)
	var track_w: float = progress_track.size.x
	# marker_start mirrors the track art's left inset (its leftmost opaque
	# pixel sits ~3px in) so the marker starts flush with the track's own
	# edge; marker_end mirrors the same inset from the right edge so the
	# marker finishes at the checkered flag instead of undershooting to the
	# last checkpoint dot (which sits at ~83% of the track's width).
	var marker_start := 3.0
	var marker_end := track_w - player_marker.size.x - marker_start
	player_marker.position.x = lerpf(marker_start, marker_end, pct)

	var gauge_pct: float = clampf(turbo_gauge / TURBO_GAUGE_MAX, 0.0, 1.0)
	var lit_count: int = clampi(ceili(gauge_pct * TURBO_SEGMENT_COUNT), 0, TURBO_SEGMENT_COUNT)
	for i in range(turbo_segments.get_child_count()):
		var segment := turbo_segments.get_child(i) as TextureRect
		segment.visible = i < lit_count
	if turbo_banner != null:
		turbo_banner.visible = is_turbo
	if is_turbo and turbo_banner != null:
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
	for pickup in turbo_pickups:
		if pickup["p"] < -0.1:
			continue
		draw_items.append({"p": pickup["p"], "cb": func(): _draw_turbo_pickup(pickup)})
	for o in obstacles:
		draw_items.append({"p": o["p"], "cb": func(): _draw_obstacle(o)})

	var remaining: float = FINISH_DISTANCE - distance
	if remaining <= FINISH_REVEAL_RANGE and remaining > -FINISH_REVEAL_RANGE * 0.4:
		var finish_p: float = 1.0 - remaining / FINISH_REVEAL_RANGE
		draw_items.append({"p": finish_p, "cb": func(): _draw_finish_tape(finish_p)})

	var px := lane_x(player_lane_visual, 1.0)
	var py := player_row_y()
	var p_scale := scale_at(1.0) * 1.05
	var turbo_now := is_turbo
	var t_now := elapsed_t
	draw_items.append({"p": 1.001, "cb": func():
		if turbo_now:
			_draw_flame_trail(Vector2(px, py), p_scale, t_now)
		_draw_sprite_centered(TEX_PLAYER, Vector2(px, py), p_scale)
	})

	draw_items.sort_custom(func(a, b): return a["p"] < b["p"])
	for item in draw_items:
		item["cb"].call()

	for fx in spark_fx:
		_draw_spark_fx(fx)

	if turbo_ring_t > 0.0:
		_draw_turbo_ring(px, py)
	if turbo_flash_t > 0.0:
		_draw_turbo_flash(px, py)

	var sz := get_viewport_rect().size
	if hit_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, hit_flash * 0.35))
	if near_miss_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.208, 0.878, 0.631, near_miss_flash / NEAR_MISS_FLASH_DURATION * 0.14))
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
	var hy := horizon_y()
	var cx := center_x()

	draw_texture_rect(TEX_BACKGROUND, Rect2(0, 0, w, h), false)

	var top_half := half_width_at(0.0)
	var bot_half := half_width_at(1.0)

	# Road surface: dark base + a lighter center band for a subtle
	# crowned-asphalt look instead of one flat fill.
	var poly := PackedVector2Array([
		Vector2(cx - top_half, hy), Vector2(cx + top_half, hy),
		Vector2(cx + bot_half, h), Vector2(cx - bot_half, h),
	])
	draw_colored_polygon(poly, Color8(0x2c, 0x30, 0x3d))
	var inset := 0.72
	var poly_hi := PackedVector2Array([
		Vector2(cx - top_half * inset, hy), Vector2(cx + top_half * inset, hy),
		Vector2(cx + bot_half * inset, h), Vector2(cx - bot_half * inset, h),
	])
	draw_colored_polygon(poly_hi, Color(0.28, 0.31, 0.4, 0.55))

	for i in range(1, LANES):
		var frac: float = LANE_EDGES[i]
		var x0: float = cx + frac * half_width_at(0.0)
		var x1: float = cx + frac * half_width_at(1.0)
		_draw_dashed_line(Vector2(x0, hy), Vector2(x1, h), Color(1, 1, 1, 0.88), 4.0, 16.0, 15.0, fmod(road_scroll, 31.0))

	draw_line(Vector2(cx - top_half, hy), Vector2(cx - bot_half, h), Color.WHITE, 4.0)
	draw_line(Vector2(cx + top_half, hy), Vector2(cx + bot_half, h), Color.WHITE, 4.0)
	draw_texture_rect(TEX_GUARDRAILS, Rect2(0, 0, w, h), false)


func _draw_sprite_centered(texture: Texture2D, pos: Vector2, scale: float) -> void:
	var size := texture.get_size() * scale
	draw_texture_rect(texture, Rect2(pos - size * 0.5, size), false)


func _draw_obstacle(obstacle: Dictionary) -> void:
	var p: float = obstacle["p"]
	var pos := Vector2(lane_x(obstacle["lane"], p), row_y(p))
	var visual_scale := scale_at(p)
	if obstacle["kind"] == "hazard":
		_draw_sprite_centered(HAZARD_TEXTURES[obstacle["variant"]], pos, visual_scale)
	else:
		_draw_sprite_centered(TRAFFIC_TEXTURES[obstacle["variant"]], pos, visual_scale * 0.82)


func _draw_sky(w: float, hy: float) -> void:
	_draw_vgrad(Rect2(0, 0, w, hy), Color8(0x5e, 0xc8, 0xea), Color8(0xbf, 0xe9, 0xf5))
	for seed in cloud_seeds:
		var drift: float = fmod(seed["x"] * w + elapsed_t * 6.0, w + 160.0) - 80.0
		var cy: float = hy * seed["y"]
		var s: float = seed["scale"]
		_draw_cloud(Vector2(drift, cy), s)


func _draw_cloud(pos: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.9)
	draw_circle(pos, 16.0 * s, col)
	draw_circle(pos + Vector2(16.0 * s, 3.0 * s), 12.0 * s, col)
	draw_circle(pos + Vector2(-15.0 * s, 4.0 * s), 11.0 * s, col)
	draw_circle(pos + Vector2(4.0 * s, -6.0 * s), 10.0 * s, col)


func _draw_scenery(w: float, h: float, hy: float, cx: float) -> void:
	# Ocean band beyond the road on both sides, from the horizon down.
	_draw_vgrad(Rect2(0, hy, w, h - hy), Color8(0x1f, 0xa8, 0xc9), Color8(0x0d, 0x6f, 0x8c))
	for i in range(10):
		var yy: float = hy + (h - hy) * (float(i) / 10.0)
		var wobble: float = sin(elapsed_t * 1.5 + i) * 4.0
		draw_line(Vector2(0, yy + wobble), Vector2(w, yy - wobble), Color(1, 1, 1, 0.10), 2.0)

	for seed in rock_seeds:
		var side: float = seed["side"]
		var s: float = seed["scale"]
		var rx: float = cx + side * w * seed["x"]
		var ry: float = hy - 2.0
		var pts := PackedVector2Array([
			Vector2(rx - 22.0 * s, ry), Vector2(rx - 6.0 * s, ry - 30.0 * s),
			Vector2(rx + 10.0 * s, ry - 14.0 * s), Vector2(rx + 24.0 * s, ry),
		])
		draw_colored_polygon(pts, Color8(0x6b, 0x53, 0x3c))


func _draw_guardrail(cx: float, hy: float, h: float, top_half: float, bot_half: float, side: float) -> void:
	var rail_w_top := 5.0
	var rail_w_bot := 16.0
	var inner_top: float = top_half * side
	var inner_bot: float = bot_half * side
	var outer_top: float = inner_top + side * rail_w_top
	var outer_bot: float = inner_bot + side * rail_w_bot
	var poly := PackedVector2Array([
		Vector2(cx + inner_top, hy), Vector2(cx + outer_top, hy),
		Vector2(cx + outer_bot, h), Vector2(cx + inner_bot, h),
	])
	draw_colored_polygon(poly, Color8(0xd8, 0xdf, 0xe6))

	var steps := 10
	for i in range(steps):
		var p0: float = float(i) / steps
		var p1: float = float(i + 1) / steps
		if i % 2 != 0:
			continue
		var s0 := scale_at(p0)
		var y0 := row_y(p0)
		var hw0: float = half_width_at(p0) * side + side * lerp(rail_w_top, rail_w_bot, ease_p(p0)) * 0.5
		var post_w: float = maxf(2.0, 4.0 * s0)
		var post_h: float = maxf(4.0, 10.0 * s0)
		draw_rect(Rect2(cx + hw0 - post_w * 0.5, y0 - post_h, post_w, post_h), Color8(0xc0, 0x2c, 0x46))


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

	draw_colored_polygon(_ellipse_points(Vector2(0, h * 0.44), w * 0.58, h * 0.15), Color(0, 0, 0, 0.38))

	# Base coat, then a darker lower half for body-side shading and a
	# bright top-down specular streak, so the paint reads as glossy
	# rather than a single flat fill.
	_draw_round_rect(Rect2(-w / 2.0, -h / 2.0, w, h), color, w * 0.28)
	var shade := color.darkened(0.35)
	shade.a = 0.55
	_draw_round_rect(Rect2(-w / 2.0, h * 0.05, w, h * 0.45), shade, w * 0.24)
	var gloss_pts := PackedVector2Array([
		Vector2(-w * 0.16, -h / 2.0 + h * 0.05), Vector2(w * 0.10, -h / 2.0 + h * 0.05),
		Vector2(w * 0.04, h / 2.0 - h * 0.08), Vector2(-w * 0.10, h / 2.0 - h * 0.08),
	])
	draw_colored_polygon(gloss_pts, Color(1, 1, 1, 0.22))

	_draw_round_rect(Rect2(-w / 2.0 + w * 0.14, -h / 2.0 + h * 0.18, w * 0.72, h * 0.32), Color(0.55, 0.75, 0.92, 0.9), w * 0.16)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w / 2.0 + w * 0.16, -h / 2.0 + h * 0.19), Vector2(-w / 2.0 + w * 0.4, -h / 2.0 + h * 0.19),
		Vector2(-w / 2.0 + w * 0.28, -h / 2.0 + h * 0.46), Vector2(-w / 2.0 + w * 0.16, -h / 2.0 + h * 0.46),
	]), Color(1, 1, 1, 0.5))

	draw_rect(Rect2(-w / 2.0 + w * 0.08, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_rect(Rect2(w / 2.0 - w * 0.26, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_coin(pos: Vector2, scale: float) -> void:
	var spin: float = 0.68 + 0.32 * abs(sin(elapsed_t * 5.0 + pos.x * 0.03))
	var size := TEX_COIN.get_size() * scale
	size.x *= spin
	draw_texture_rect(TEX_COIN, Rect2(pos - size * 0.5, size), false)


# Quick colored ring expanding from a world position - shared by coin
# pickups (gold) and near-misses (teal). No dedicated sparkle asset exists
# for either yet, so this stays procedural.
func _draw_spark_fx(fx: Dictionary) -> void:
	var t: float = 1.0 - fx["t"] / fx["duration"]
	var radius: float = lerp(4.0, 26.0, t) * fx["scale"]
	var alpha: float = 1.0 - t
	var col: Color = fx["color"]
	col.a = alpha * 0.9
	draw_arc(fx["pos"], radius, 0.0, TAU, 20, col, 3.0 * fx["scale"], true)


func _draw_turbo_pickup(pickup: Dictionary) -> void:
	var p: float = pickup["p"]
	var pos := Vector2(lane_x(pickup["lane"], p), row_y(p))
	var pulse := 0.92 + 0.08 * sin(elapsed_t * 7.0 + p * 4.0)
	var visual_scale := scale_at(p) * 0.30 * pulse
	_draw_sprite_centered(TEX_TURBO_PICKUP, pos, visual_scale)


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
