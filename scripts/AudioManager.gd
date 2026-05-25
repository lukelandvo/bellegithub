# AudioManager.gd
# Autoload singleton — owns all audio playback for BELLE.
# Add to Project > Project Settings > Autoload as "AudioManager".
#
# SFX triggered by string ID. Wire streams to IDs in the inspector.
# Music crossfades between two internal players so transitions are smooth.
# Rapid play_music calls queue behind the current crossfade safely.
# Missing SFX/music IDs are silently skipped during development.
#
# play_music(id)        — play by string ID from music_library
# play_music_stream(stream) — play a raw AudioStream directly (e.g. per-encounter music)

extends Node

const SFX_POOL_SIZE: int = 8

@export_group("Volume")
@export var master_music_volume: float = 0.0
@export var master_sfx_volume: float = 0.0

@export_group("Music")
@export var music_library: Dictionary = {}
@export var crossfade_duration: float = 1.0

@export_group("SFX")
@export var sfx_library: Dictionary = {}

@export_group("Footsteps")
@export var footstep_sound: AudioStream
@export var footstep_interval: float = 0.35
@export var run_footstep_interval: float = 0.2

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _inactive_music_player: AudioStreamPlayer

var _sfx_pool: Array[AudioStreamPlayer] = []
var _footstep_player: AudioStreamPlayer
var _confrontation_player: AudioStreamPlayer

var _footstep_timer: float = 0.0
var _footstep_active: bool = false
var _is_running: bool = false

var _current_music_id: String = ""
var _crossfade_tween: Tween = null
var _is_crossfading: bool = false
var _queued_music_id: String = ""

# Used to deduplicate play_music_stream calls the same way _current_music_id
# deduplicates play_music calls. Cleared when play_music() is called.
var _current_music_stream: AudioStream = null

func _ready() -> void:
	_music_a = _make_player(master_music_volume)
	_music_b = _make_player(master_music_volume)
	_active_music_player = _music_a
	_inactive_music_player = _music_b
	for i in SFX_POOL_SIZE:
		_sfx_pool.append(_make_player(master_sfx_volume))
	_footstep_player = _make_player(master_sfx_volume)
	_confrontation_player = _make_player(master_sfx_volume)

func _make_player(volume: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.volume_db = volume
	add_child(p)
	return p

func _process(delta: float) -> void:
	if not _footstep_active:
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = run_footstep_interval if _is_running else footstep_interval
		if footstep_sound:
			_footstep_player.stream = footstep_sound
			_footstep_player.play()

# ---------------------------------------------------------------------------
# Music — crossfade with queue support
# ---------------------------------------------------------------------------

func play_music(id: String, loop: bool = true) -> void:
	if id == _current_music_id:
		return
	if not music_library.has(id):
		return  # silently skip missing music during development
	_current_music_stream = null  # clear stream tracking when switching to ID-based music
	if _is_crossfading:
		_queued_music_id = id
		return
	await _do_crossfade(id, loop)
	if _queued_music_id != "" and _queued_music_id != _current_music_id:
		var next = _queued_music_id
		_queued_music_id = ""
		play_music(next, loop)

# Play a raw AudioStream directly — used for per-encounter battle music assigned
# in the Encounter resource inspector rather than registered in music_library.
func play_music_stream(stream: AudioStream, loop: bool = true) -> void:
	if stream == null:
		return
	if stream == _current_music_stream:
		return
	_current_music_id = ""  # clear ID tracking when switching to stream-based music
	_current_music_stream = stream
	if _is_crossfading:
		# Don't queue streams — just let the current crossfade finish
		return
	await _do_crossfade_stream(stream, loop)

func _do_crossfade(id: String, loop: bool) -> void:
	var stream: AudioStream = music_library[id]
	_set_stream_loop(stream, loop)
	_current_music_id = id

	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	var next_player = _inactive_music_player
	var prev_player = _active_music_player
	_active_music_player = next_player
	_inactive_music_player = prev_player

	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()

	_is_crossfading = true
	_crossfade_tween = get_tree().create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(next_player, "volume_db", master_music_volume, crossfade_duration)
	_crossfade_tween.tween_property(prev_player, "volume_db", -80.0, crossfade_duration)
	await _crossfade_tween.finished
	_is_crossfading = false
	prev_player.stop()
	prev_player.volume_db = master_music_volume

func _do_crossfade_stream(stream: AudioStream, loop: bool) -> void:
	_set_stream_loop(stream, loop)

	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	var next_player = _inactive_music_player
	var prev_player = _active_music_player
	_active_music_player = next_player
	_inactive_music_player = prev_player

	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()

	_is_crossfading = true
	_crossfade_tween = get_tree().create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(next_player, "volume_db", master_music_volume, crossfade_duration)
	_crossfade_tween.tween_property(prev_player, "volume_db", -80.0, crossfade_duration)
	await _crossfade_tween.finished
	_is_crossfading = false
	prev_player.stop()
	prev_player.volume_db = master_music_volume

func stop_music(fade_duration: float = 0.5) -> void:
	_current_music_id = ""
	_current_music_stream = null
	_queued_music_id = ""
	_is_crossfading = false
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(_music_a, "volume_db", -80.0, fade_duration)
	tween.tween_property(_music_b, "volume_db", -80.0, fade_duration)
	await tween.finished
	_music_a.stop()
	_music_b.stop()
	_music_a.volume_db = master_music_volume
	_music_b.volume_db = master_music_volume

func get_current_music_id() -> String:
	return _current_music_id

func _set_stream_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamMP3:
		stream.loop = loop
	elif stream is AudioStreamOggVorbis:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED

# ---------------------------------------------------------------------------
# Confrontation sting
# ---------------------------------------------------------------------------

func play_confrontation(id: String = "battle_confrontation") -> void:
	if not sfx_library.has(id):
		return  # silently skip missing confrontation sound during development
	var stream = sfx_library.get(id, null)
	if not stream:
		return
	_confrontation_player.stream = stream
	_confrontation_player.volume_db = master_sfx_volume
	_confrontation_player.play()

func stop_confrontation(fade_duration: float = 0.5) -> void:
	if not _confrontation_player.playing:
		return
	var tween = get_tree().create_tween()
	tween.tween_property(_confrontation_player, "volume_db", -80.0, fade_duration)
	await tween.finished
	_confrontation_player.stop()
	_confrontation_player.volume_db = master_sfx_volume

# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

func play_sfx(id: String) -> void:
	if not sfx_library.has(id):
		return  # silently skip missing SFX during development
	var stream: AudioStream = sfx_library[id]
	if not stream:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = master_sfx_volume
			p.play()
			return
	_sfx_pool[0].stream = stream
	_sfx_pool[0].volume_db = master_sfx_volume
	_sfx_pool[0].play()

# ---------------------------------------------------------------------------
# Footsteps
# ---------------------------------------------------------------------------

func start_footsteps(running: bool = false) -> void:
	_is_running = running
	if not _footstep_active:
		_footstep_active = true
		_footstep_timer = 0.0

func stop_footsteps() -> void:
	_footstep_active = false
	_footstep_timer = 0.0
	_is_running = false

# ---------------------------------------------------------------------------
# Volume control
# ---------------------------------------------------------------------------

func set_music_volume(volume_db: float) -> void:
	master_music_volume = volume_db
	if _active_music_player.playing:
		_active_music_player.volume_db = volume_db

func set_sfx_volume(volume_db: float) -> void:
	master_sfx_volume = volume_db
	for p in _sfx_pool:
		p.volume_db = volume_db
	_footstep_player.volume_db = volume_db
