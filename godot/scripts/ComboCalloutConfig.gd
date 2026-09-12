extends RefCounted

# The combo ladder is "swerve/shift" around the world, climbing to the English
# "Swerve!" at 10x and above. Every line is the same broadcaster voice as the
# rest of the pack. The displayed text is romanized because RacingSansOne
# carries no Hangul, CJK, Arabic or Devanagari glyphs and would draw the native
# spelling as blank boxes - the voice still says the real word.
const CALLOUTS: Array[Dictionary] = [
	{"text": "Scarto!", "stream": preload("res://assets/audio/combo-voice/callout-01-scarto.wav")},      # Italian
	{"text": "Virage!", "stream": preload("res://assets/audio/combo-voice/callout-02-virage.wav")},      # French
	{"text": "¡Desvía!", "stream": preload("res://assets/audio/combo-voice/callout-03-desvia.wav")},     # Spanish
	{"text": "Muda!", "stream": preload("res://assets/audio/combo-voice/callout-04-muda.wav")},          # Portuguese
	{"text": "Tahawwal!", "stream": preload("res://assets/audio/combo-voice/callout-05-tahawwal.wav")},  # Arabic
	{"text": "Badlo!", "stream": preload("res://assets/audio/combo-voice/callout-06-badlo.wav")},        # Hindi
	{"text": "Shifuto!", "stream": preload("res://assets/audio/combo-voice/callout-07-shifuto.wav")},    # Japanese
	{"text": "Huan Dang!", "stream": preload("res://assets/audio/combo-voice/callout-08-huandang.wav")}, # Chinese
	{"text": "Hoepi!", "stream": preload("res://assets/audio/combo-voice/callout-09-hoepi.wav")},        # Korean
	{"text": "Swerve!", "stream": preload("res://assets/audio/combo-voice/callout-10-swerve.wav")},      # English
]


static func for_combo(combo_value: int) -> Dictionary:
	var index := clampi(combo_value, 1, CALLOUTS.size()) - 1
	return CALLOUTS[index]


static func stream_for_combo(combo_value: int) -> AudioStream:
	return for_combo(combo_value)["stream"] as AudioStream
