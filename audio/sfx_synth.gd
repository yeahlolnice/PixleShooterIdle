class_name SfxSynth
extends RefCounted
## Procedural sound effects (TASK-028): every game sound is built here from
## tones, noise and sweeps, so the game ships with no audio files. Streams are
## 16-bit mono AudioStreamWAV, cached by name. Toy-like and punchy, per the plan.

const RATE := 22050

static var _cache := {}


## The named sound (see NAMES), built once and cached.
static func get_sound(sound_name: String) -> AudioStreamWAV:
	if not _cache.has(sound_name):
		_cache[sound_name] = _build(sound_name)
	return _cache[sound_name]


## Every sound the game uses.
const NAMES := [
	"hit", "headshot", "kill", "loot", "hurt", "death", "round_live", "round_end",
	"inject", "unlock", "buy", "menu_open", "menu_close", "reload", "scope",
	"shot_pistol", "shot_smg", "shot_shotgun", "shot_rifle", "shot_sniper", "shot_lmg", "shot_special",
]


## Gunshot for a guns.json category (unknown -> pistol).
static func shot(category: String) -> AudioStreamWAV:
	var key := "shot_" + category
	return get_sound(key if NAMES.has(key) else "shot_pistol")


static func _build(sound_name: String) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	match sound_name:
		"hit": s = _tone([2200.0], 0.05, 40.0, "square", 0.25)
		"headshot": s = _mix([_tone([1760.0, 2640.0], 0.35, 9.0, "sine", 0.5), _tone([3520.0], 0.12, 30.0, "sine", 0.2)])
		"kill": s = _seq([_tone([1318.5], 0.07, 12.0, "square", 0.25), _tone([1975.5], 0.18, 10.0, "square", 0.25)])
		"loot": s = _seq([_tone([1568.0], 0.05, 20.0, "sine", 0.35), _tone([2093.0], 0.05, 20.0, "sine", 0.35), _tone([2637.0], 0.12, 12.0, "sine", 0.35)])
		"hurt": s = _mix([_tone([110.0], 0.18, 14.0, "sine", 0.6), _noise(0.12, 25.0, 0.35, 0.3)])
		"death": s = _sweep(440.0, 110.0, 0.6, "square", 0.3)
		"round_live": s = _seq([_tone([523.3], 0.1, 6.0, "square", 0.25), _tone([784.0], 0.25, 5.0, "square", 0.25)])
		"round_end": s = _seq([_tone([784.0], 0.1, 6.0, "triangle", 0.3), _tone([659.3], 0.1, 6.0, "triangle", 0.3), _tone([523.3], 0.3, 4.0, "triangle", 0.3)])
		"inject": s = _mix([_sweep(200.0, 1600.0, 0.35, "saw", 0.22), _noise(0.35, 6.0, 0.1, 0.6)])
		"unlock": s = _seq([_tone([523.3], 0.08, 8.0, "square", 0.25), _tone([659.3], 0.08, 8.0, "square", 0.25), _tone([1046.5], 0.3, 5.0, "square", 0.25)])
		"buy": s = _seq([_noise(0.03, 60.0, 0.4, 0.2), _tone([880.0], 0.08, 20.0, "square", 0.2)])
		"menu_open": s = _sweep(500.0, 900.0, 0.07, "sine", 0.3)
		"menu_close": s = _sweep(900.0, 500.0, 0.07, "sine", 0.3)
		"reload": s = _seq([_noise(0.04, 50.0, 0.45, 0.15), _silence(0.08), _noise(0.05, 40.0, 0.5, 0.25)])
		"scope": s = _noise(0.06, 35.0, 0.3, 0.1)
		"shot_pistol": s = _gun(0.12, 30.0, 0.25, 180.0)
		"shot_smg": s = _gun(0.07, 45.0, 0.35, 220.0)
		"shot_shotgun": s = _gun(0.32, 9.0, 0.08, 70.0)
		"shot_rifle": s = _gun(0.15, 22.0, 0.2, 140.0)
		"shot_sniper": s = _gun(0.55, 6.0, 0.12, 90.0)
		"shot_lmg": s = _gun(0.1, 32.0, 0.22, 120.0)
		"shot_special": s = _mix([_gun(0.2, 14.0, 0.3, 150.0), _seq([_silence(0.05), _tone([1568.0, 2093.0], 0.25, 10.0, "sine", 0.25)])])
		_: s = _tone([440.0], 0.1, 20.0, "sine", 0.3)
	return _to_wav(s)


# --- Building blocks (all return samples in -1..1) ---------------------------------

## Sum of `freqs` with an exponential decay envelope (`decay` per second).
static func _tone(freqs: Array, dur: float, decay: float, wave: String, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += _wave(wave, float(f) * t)
		out[i] = v / freqs.size() * amp * exp(-decay * t) * minf(1.0, float(i) / 40.0)
	return out


## White noise, decaying, with a one-pole low-pass (`smooth` 0 = raw, toward 1 = duller).
static func _noise(dur: float, decay: float, amp: float, smooth: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 100000.0 + decay * 10.0)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		prev = lerpf(rng.randf_range(-1.0, 1.0), prev, smooth)
		out[i] = prev * amp * exp(-decay * t)
	return out


## Frequency glide f0 -> f1 (exponential), fading out at the end.
static func _sweep(f0: float, f1: float, dur: float, wave: String, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += f0 * pow(f1 / f0, k) / RATE
		out[i] = _wave(wave, phase) * amp * (1.0 - k)
	return out


## Gunshot: noise crack + low thump at `thump_hz`.
static func _gun(dur: float, decay: float, smooth: float, thump_hz: float) -> PackedFloat32Array:
	return _mix([_noise(dur, decay, 0.75, smooth), _sweep(thump_hz, thump_hz * 0.4, dur * 0.6, "sine", 0.5)])


static func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


## Layers sounds on top of each other (length of the longest).
static func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out


## Plays sounds one after another.
static func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


## One cycle per unit of `phase` (cycles).
static func _wave(wave: String, phase: float) -> float:
	var x := fposmod(phase, 1.0)
	match wave:
		"square": return 1.0 if x < 0.5 else -1.0
		"saw": return 2.0 * x - 1.0
		"triangle": return 4.0 * absf(x - 0.5) - 1.0
	return sin(TAU * x)


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	return wav
