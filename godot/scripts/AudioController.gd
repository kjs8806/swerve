extends Node

const ComboCalloutConfig := preload("res://scripts/ComboCalloutConfig.gd")

# Centralized, allocation-light audio integration for the race scene. Persistent
# players are reused for the whole session; gameplay code only calls semantic
# event methods and never needs to know about streams or mixing details.

const ENGINE_IDLE_DB := -16.0
const ENGINE_DRIVE_DB := -13.0
const ENGINE_DUCK_DB := -15.0
const MUSIC_PLAY_DB := -9.0
const MUSIC_TURBO_DUCK_DB := -13.0
const TURBO_SUSTAIN_DB := -12.0
const SILENT_DB := -60.0
const LOOP_FADE_TIME := 0.20
const MUSIC_FADE_IN_TIME := 0.75
const MUSIC_FADE_OUT_TIME := 0.80
const MUSIC_DUCK_TIME := 0.18
const TURBO_FADE_IN_TIME := 0.10
const TURBO_FADE_OUT_TIME := 0.15
const LANE_SOUND_COOLDOWN_MS := 80
const COLLISION_SOUND_COOLDOWN_MS := 350
const ROAD_HIT_SOUND_COOLDOWN_MS := 220

const STREAM_BACKGROUND_MUSIC := preload("res://assets/audio/music/coastal-velocity-loop.ogg")
const STREAM_ENGINE_IDLE := preload("res://assets/audio/engine-idle-loop.ogg")
const STREAM_ENGINE_DRIVE := preload("res://assets/audio/engine-drive-loop.ogg")
const STREAM_LANE_CHANGE := preload("res://assets/audio/lane-change-whoosh.wav")
const STREAM_COIN := preload("res://assets/audio/coin-pickup.wav")
const STREAM_COMBO := preload("res://assets/audio/combo-increment.wav")
const STREAM_COLLISION := preload("res://assets/audio/collision-impact.wav")
const STREAM_ROAD_HIT := preload("res://assets/audio/road-hit.wav")
const STREAM_TURBO_CHARGE := preload("res://assets/audio/turbo-charge.wav")
const STREAM_TURBO_ACTIVATION := preload("res://assets/audio/turbo-activation.wav")
const STREAM_TURBO_SUSTAIN := preload("res://assets/audio/turbo-sustain-loop.ogg")
const STREAM_COUNTDOWN := preload("res://assets/audio/countdown-warning.wav")
const STREAM_UI_TAP := preload("res://assets/audio/ui-tap.wav")
const STREAM_RACE_START := preload("res://assets/audio/race-start.wav")
const STREAM_FINISH_WIN := preload("res://assets/audio/finish-win.wav")
const STREAM_TIME_UP := preload("res://assets/audio/time-up-failure.wav")

var background_music: AudioStreamPlayer
var combo_voice: AudioStreamPlayer
var engine_idle: AudioStreamPlayer
var engine_drive: AudioStreamPlayer
var turbo_sustain: AudioStreamPlayer
var sfx_players: Dictionary = {}
var engine_fade: Tween
var music_fade: Tween
var turbo_fade: Tween
var engine_mode := "stopped"
var turbo_active := false
var paused_music_position := 0.0
var last_lane_sound_ms := -LANE_SOUND_COOLDOWN_MS
var last_collision_sound_ms := -COLLISION_SOUND_COOLDOWN_MS
var last_road_hit_sound_ms := -ROAD_HIT_SOUND_COOLDOWN_MS
var last_countdown_second := -1


func _ready() -> void:
	background_music = _make_player("BackgroundMusic", STREAM_BACKGROUND_MUSIC, SILENT_DB)
	combo_voice = _make_player("ComboVoice", ComboCalloutConfig.stream_for_combo(1), -4.0)
	engine_idle = _make_player("EngineIdle", STREAM_ENGINE_IDLE, ENGINE_IDLE_DB)
	engine_drive = _make_player("EngineDrive", STREAM_ENGINE_DRIVE, SILENT_DB)
	turbo_sustain = _make_player("TurboSustain", STREAM_TURBO_SUSTAIN, SILENT_DB)
	_set_loop(STREAM_BACKGROUND_MUSIC, true)
	_set_loop(STREAM_ENGINE_IDLE, true)
	_set_loop(STREAM_ENGINE_DRIVE, true)
	_set_loop(STREAM_TURBO_SUSTAIN, true)

	_add_sfx("lane_change", STREAM_LANE_CHANGE, -8.0, 2)
	_add_sfx("coin", STREAM_COIN, -5.0, 4)
	_add_sfx("combo", STREAM_COMBO, -7.0, 3)
	_add_sfx("collision", STREAM_COLLISION, -3.0)
	_add_sfx("road_hit", STREAM_ROAD_HIT, -6.0, 2)
	_add_sfx("turbo_charge", STREAM_TURBO_CHARGE, -8.0)
	_add_sfx("turbo_activation", STREAM_TURBO_ACTIVATION, -2.0)
	_add_sfx("countdown", STREAM_COUNTDOWN, -6.0)
	_add_sfx("ui_tap", STREAM_UI_TAP, -10.0, 2)
	_add_sfx("race_start", STREAM_RACE_START, -3.0)
	_add_sfx("finish_win", STREAM_FINISH_WIN, -4.0)
	_add_sfx("time_up", STREAM_TIME_UP, -5.0)
	set_engine_idle()


func _make_player(node_name: String, stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _add_sfx(key: String, stream: AudioStream, volume_db: float, polyphony: int = 1) -> void:
	var player := _make_player(key.to_pascal_case(), stream, volume_db)
	player.max_polyphony = polyphony
	sfx_players[key] = player


func _set_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = enabled


func _play(key: String) -> void:
	var player := sfx_players.get(key) as AudioStreamPlayer
	if player != null:
		player.play()


func _stop_one_shots() -> void:
	for player in sfx_players.values():
		(player as AudioStreamPlayer).stop()


func _replace_engine_fade() -> Tween:
	if engine_fade != null and engine_fade.is_valid():
		engine_fade.kill()
	engine_fade = create_tween().set_parallel(true)
	return engine_fade


func _replace_music_fade() -> Tween:
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	music_fade = create_tween()
	return music_fade


func start_background_music() -> void:
	var fade := _replace_music_fade()
	if not background_music.playing:
		background_music.volume_db = SILENT_DB
		background_music.play(paused_music_position)
	paused_music_position = 0.0
	fade.tween_property(background_music, "volume_db", MUSIC_PLAY_DB, MUSIC_FADE_IN_TIME)


func stop_background_music() -> void:
	paused_music_position = 0.0
	if not background_music.playing:
		return
	var fade := _replace_music_fade()
	fade.tween_property(background_music, "volume_db", SILENT_DB, MUSIC_FADE_OUT_TIME)
	fade.tween_callback(func(): background_music.stop())


func pause_background_music() -> void:
	if not background_music.playing:
		return
	paused_music_position = background_music.get_playback_position()
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	background_music.stop()


func stop_background_music_immediately() -> void:
	paused_music_position = 0.0
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	background_music.stop()
	background_music.volume_db = SILENT_DB


func _set_music_turbo_duck(active: bool) -> void:
	if not background_music.playing:
		return
	var fade := _replace_music_fade()
	var target_db := MUSIC_TURBO_DUCK_DB if active else MUSIC_PLAY_DB
	fade.tween_property(background_music, "volume_db", target_db, MUSIC_DUCK_TIME)


func set_engine_idle() -> void:
	if engine_mode == "idle":
		return
	engine_mode = "idle"
	if not engine_idle.playing:
		engine_idle.play()
	var fade := _replace_engine_fade()
	fade.tween_property(engine_idle, "volume_db", ENGINE_IDLE_DB, LOOP_FADE_TIME)
	fade.tween_property(engine_drive, "volume_db", SILENT_DB, LOOP_FADE_TIME)


func set_engine_driving() -> void:
	if engine_mode == "drive":
		return
	engine_mode = "drive"
	if not engine_idle.playing:
		engine_idle.play()
	if not engine_drive.playing:
		engine_drive.play()
	var fade := _replace_engine_fade()
	fade.tween_property(engine_idle, "volume_db", SILENT_DB, LOOP_FADE_TIME)
	fade.tween_property(engine_drive, "volume_db", ENGINE_DUCK_DB if turbo_active else ENGINE_DRIVE_DB, LOOP_FADE_TIME)


func stop_engine() -> void:
	if engine_mode == "stopped":
		return
	engine_mode = "stopped"
	var fade := _replace_engine_fade()
	fade.tween_property(engine_idle, "volume_db", SILENT_DB, LOOP_FADE_TIME)
	fade.tween_property(engine_drive, "volume_db", SILENT_DB, LOOP_FADE_TIME)


func begin_race(play_ui_tap: bool) -> void:
	_stop_one_shots()
	paused_music_position = 0.0
	set_turbo(false)
	last_countdown_second = -1
	last_lane_sound_ms = -LANE_SOUND_COOLDOWN_MS
	last_collision_sound_ms = -COLLISION_SOUND_COOLDOWN_MS
	last_road_hit_sound_ms = -ROAD_HIT_SOUND_COOLDOWN_MS
	if play_ui_tap:
		_play("ui_tap")
	_play("race_start")
	start_background_music()
	set_engine_driving()


func pause_race() -> void:
	pause_background_music()


func resume_race() -> void:
	start_background_music()


func lane_changed() -> void:
	var now := Time.get_ticks_msec()
	if now - last_lane_sound_ms >= LANE_SOUND_COOLDOWN_MS:
		last_lane_sound_ms = now
		_play("lane_change")


func coin_collected() -> void:
	_play("coin")


func combo_increased(combo_value: int = 1) -> void:
	_play("combo")
	# Only the newest praise line should be heard when combos increase quickly.
	combo_voice.stop()
	combo_voice.stream = ComboCalloutConfig.stream_for_combo(combo_value)
	combo_voice.play()


func collision(is_road_hazard: bool) -> void:
	var now := Time.get_ticks_msec()
	if is_road_hazard:
		if now - last_road_hit_sound_ms < ROAD_HIT_SOUND_COOLDOWN_MS:
			return
		last_road_hit_sound_ms = now
		_play("road_hit")
	else:
		if now - last_collision_sound_ms < COLLISION_SOUND_COOLDOWN_MS:
			return
		last_collision_sound_ms = now
		_play("collision")


func turbo_charged() -> void:
	_play("turbo_charge")


func set_turbo(active: bool) -> void:
	if active == turbo_active:
		return
	turbo_active = active
	_set_music_turbo_duck(active)
	if turbo_fade != null and turbo_fade.is_valid():
		turbo_fade.kill()
	turbo_fade = create_tween()
	if active:
		_play("turbo_activation")
		if not turbo_sustain.playing:
			turbo_sustain.volume_db = SILENT_DB
			turbo_sustain.play()
		turbo_fade.tween_property(turbo_sustain, "volume_db", TURBO_SUSTAIN_DB, TURBO_FADE_IN_TIME)
		if engine_mode == "drive":
			engine_drive.volume_db = ENGINE_DUCK_DB
	else:
		turbo_fade.tween_property(turbo_sustain, "volume_db", SILENT_DB, TURBO_FADE_OUT_TIME)
		turbo_fade.tween_callback(func(): turbo_sustain.stop())
		if engine_mode == "drive":
			engine_drive.volume_db = ENGINE_DRIVE_DB


func update_countdown(remaining: float) -> void:
	var second := int(ceil(remaining))
	if second >= 1 and second <= 3 and second != last_countdown_second:
		last_countdown_second = second
		_play("countdown")


func finish_race(won: bool) -> void:
	set_turbo(false)
	stop_background_music()
	stop_engine()
	_play("finish_win" if won else "time_up")
