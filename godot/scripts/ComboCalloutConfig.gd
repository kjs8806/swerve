extends RefCounted

# Combos 1-9 rotate through short driving words in Italian, French, and
# Korean. Combo 10 and every value above it use the recorded Swerve callout.
const SWERVE_STREAM := preload("res://assets/audio/combo-voice/callout-10-swerve.wav")
const CALLOUTS: Array[Dictionary] = [
	{"text": "Scarto!", "speech": "Scarto", "language": "it"},
	{"text": "Virage!", "speech": "Virage", "language": "fr"},
	{"text": "회피!", "speech": "회피", "language": "ko"},
	{"text": "Scarto!", "speech": "Scarto", "language": "it"},
	{"text": "Virage!", "speech": "Virage", "language": "fr"},
	{"text": "회피!", "speech": "회피", "language": "ko"},
	{"text": "Scarto!", "speech": "Scarto", "language": "it"},
	{"text": "Virage!", "speech": "Virage", "language": "fr"},
	{"text": "회피!", "speech": "회피", "language": "ko"},
]


static func for_combo(combo_value: int) -> Dictionary:
	if combo_value >= 10 or combo_value < 1:
		return {"text": "Swerve!", "stream": SWERVE_STREAM}
	var callout: Dictionary = CALLOUTS[combo_value - 1].duplicate()
	callout["stream"] = SWERVE_STREAM
	return callout


static func stream_for_combo(combo_value: int) -> AudioStream:
	return for_combo(combo_value)["stream"] as AudioStream
