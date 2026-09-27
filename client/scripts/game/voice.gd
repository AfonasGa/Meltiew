class_name Voice
extends Node
## Voice chat: the microphone button (next to chat) turns your mic on. While it's on,
## what you say (not silence) goes out in 100 ms pieces: 12 kHz mono squeezed with IMA
## ADPCM (4 bits a sample, ~48 kbit/s). The server passes it to players near you; here
## each speaker plays from their Melly, quieter with distance.

signal speaking_changed(on: bool)

const RATE := 12000
const CHUNK := 1200  # samples: 100 ms
const LOUD := 0.02  # RMS that counts as speech
const HANG := 0.4  # seconds kept sending after the last loud bit

var net: Node
var remotes: Dictionary  # user id -> RemotePlayer (the game's)
var mic_on := false

var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _bus := -1
var _pending := PackedFloat32Array()
var _phase := 0.0
var _quiet := 999.0
var _speaking := false
var _players := {}  # user id -> {player: AudioStreamPlayer3D, gen: AudioStreamGeneratorPlayback, at: Vector3}
var _talking := {}  # user id -> ms until their waves go away
static var _wave: Texture2D


func set_mic(on: bool) -> void:
	if on == mic_on:
		return
	if on and OS.get_name() == "Android" and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		OS.request_permissions()
	mic_on = on
	if on:
		_start_capture()
	elif _mic:
		_mic.stop()
		_set_speaking(false)
	_pending.clear()


func _start_capture() -> void:
	var dev := str(Session.settings.get("mic_device", "Default"))
	if dev in AudioServer.get_input_device_list():
		AudioServer.input_device = dev
	if _bus < 0:
		_bus = AudioServer.bus_count
		AudioServer.add_bus(_bus)
		AudioServer.set_bus_name(_bus, "VoiceMic")
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus, _capture)
		# Heard by the capture, never by your own speakers.
		AudioServer.set_bus_mute(_bus, true)
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = "VoiceMic"
		add_child(_mic)
	_capture.clear_buffer()
	_mic.play()


func _process(delta: float) -> void:
	if mic_on and _capture:
		_read_mic(delta)
	# Each voice comes from its speaker's Melly, or (someone the server doesn't show you,
	# behind a wall) from where the server says they are.
	for uid in _players:
		var e: Dictionary = _players[uid]
		if not is_instance_valid(e.player):
			continue
		var rp: Node3D = remotes.get(uid)
		var at: Vector3 = e.at
		if rp and is_instance_valid(rp) and rp.global_position.y > -1000.0:
			at = rp.global_position
		e.player.global_position = at + Vector3(0, 1.6, 0)
	var now := Time.get_ticks_msec()
	for uid in _talking.keys():
		if now > int(_talking[uid]):
			_talking.erase(uid)
			var rp: Node = remotes.get(uid)
			if rp and is_instance_valid(rp):
				rp.set_talking(false)


func _read_mic(delta: float) -> void:
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	# Down to 12 kHz mono: average the frames that fall into each output sample.
	var step := AudioServer.get_mix_rate() / RATE
	var acc := 0.0
	var count := 0
	for f in frames:
		acc += (f.x + f.y) * 0.5
		count += 1
		_phase += 1.0
		if _phase >= step:
			_phase -= step
			_pending.append(acc / count)
			acc = 0.0
			count = 0
	while _pending.size() >= CHUNK:
		var piece := _pending.slice(0, CHUNK)
		_pending = _pending.slice(CHUNK)
		var rms := 0.0
		for s in piece:
			rms += s * s
		rms = sqrt(rms / CHUNK)
		_quiet = 0.0 if rms > LOUD else _quiet + CHUNK / float(RATE)
		var talking := _quiet < HANG
		_set_speaking(talking)
		if talking and net:
			net.send({"t": "voice", "d": Marshalls.raw_to_base64(Adpcm.encode(piece))})


func _set_speaking(on: bool) -> void:
	if on != _speaking:
		_speaking = on
		speaking_changed.emit(on)


## A piece of someone's voice from the server (`at`: where they are).
func heard(user_id: int, data: String, at: Variant = null) -> void:
	var rp: Node3D = remotes.get(user_id)
	if rp == null or not Session.settings.get("voice_hear", true):
		return
	rp.set_talking(true)
	_talking[user_id] = Time.get_ticks_msec() + 350
	var e: Dictionary = _players.get(user_id, {})
	if e.is_empty() or not is_instance_valid(e.player):
		var p := AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.6
		p.stream = gen
		p.unit_size = 8.0
		p.max_distance = 50.0
		add_child(p)
		p.global_position = rp.global_position + Vector3(0, 1.6, 0)
		p.play()
		e = {"player": p, "gen": p.get_stream_playback(), "at": rp.global_position}
		_players[user_id] = e
	if at is Array and at.size() == 3:
		e.at = Vector3(float(at[0]), float(at[1]), float(at[2]))
	var pb: AudioStreamGeneratorPlayback = e.gen
	var samples := Adpcm.decode(Marshalls.base64_to_raw(data))
	if pb.get_frames_available() < samples.size():
		return  # too far behind: drop rather than pile up delay
	for s in samples:
		pb.push_frame(Vector2(s, s))


## Someone leaving: their voice player goes too.
func forget(user_id: int) -> void:
	var e: Dictionary = _players.get(user_id, {})
	if not e.is_empty() and is_instance_valid(e.player):
		e.player.queue_free()
	_players.erase(user_id)
	_talking.erase(user_id)


## The talking sign: a dot with two radio waves on each side, white (tinted where used).
static func wave_texture() -> Texture2D:
	if _wave:
		return _wave
	var w := 112
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := Vector2(w / 2.0, h / 2.0)
	for y in h:
		for x in w:
			var v := Vector2(x + 0.5, y + 0.5) - c
			var r := v.length()
			# Distance to the shapes: the dot, and arcs within 50 degrees of left and right.
			var d := r - 7.0
			if absf(v.y) < absf(v.x) * 1.2:
				d = minf(d, absf(r - 17.0) - 2.6)
				d = minf(d, absf(r - 27.0) - 2.6)
			var ink := clampf(0.5 - d, 0.0, 1.0)
			var edge := clampf(3.0 - d, 0.0, 1.0) * 0.75
			var col := Color(0.08, 0.07, 0.1).lerp(Color.WHITE, ink)
			col.a = maxf(ink, edge)
			img.set_pixel(x, y, col)
	_wave = ImageTexture.create_from_image(img)
	return _wave


## IMA ADPCM: 4 bits a sample. A packet: first sample (int16), step index, then nibbles.
class Adpcm:
	const STEPS := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
	const INDEX := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

	static func encode(samples: PackedFloat32Array) -> PackedByteArray:
		var out := PackedByteArray()
		var pred := clampi(int(samples[0] * 32767.0), -32768, 32767)
		# Start the step near the signal's size so the first few ms aren't a blur.
		var idx := 0
		var d0 := 0
		for i in mini(16, samples.size() - 1):
			d0 = maxi(d0, absi(int((samples[i + 1] - samples[i]) * 32767.0)))
		while idx < 88 and STEPS[idx] < d0:
			idx += 1
		out.resize(3 + (samples.size() + 1) / 2)
		out.encode_s16(0, pred)
		out[2] = idx
		var byte := 0
		for i in samples.size():
			var s := clampi(int(samples[i] * 32767.0), -32768, 32767)
			var step: int = STEPS[idx]
			var diff := s - pred
			var code := 0
			if diff < 0:
				code = 8
				diff = -diff
			var delta := step >> 3
			if diff >= step:
				code |= 4
				diff -= step
				delta += step
			if diff >= step >> 1:
				code |= 2
				diff -= step >> 1
				delta += step >> 1
			if diff >= step >> 2:
				code |= 1
				delta += step >> 2
			pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
			idx = clampi(idx + INDEX[code], 0, 88)
			if i % 2 == 0:
				byte = code
			else:
				out[3 + i / 2] = byte | (code << 4)
		if samples.size() % 2 == 1:
			out[3 + samples.size() / 2] = byte
		return out

	static func decode(data: PackedByteArray) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		if data.size() < 3:
			return out
		var pred := data.decode_s16(0)
		var idx := clampi(data[2], 0, 88)
		out.resize((data.size() - 3) * 2)
		for i in out.size():
			var b := data[3 + i / 2]
			var code := (b & 15) if i % 2 == 0 else (b >> 4)
			var step: int = STEPS[idx]
			var delta := step >> 3
			if code & 4:
				delta += step
			if code & 2:
				delta += step >> 1
			if code & 1:
				delta += step >> 2
			pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
			idx = clampi(idx + INDEX[code], 0, 88)
			out[i] = pred / 32768.0
		return out
