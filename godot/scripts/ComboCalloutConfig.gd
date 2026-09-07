extends RefCounted

# Reorder or replace entries here to change both the displayed praise and its
# matching voice. Combo values above the final entry reuse the final callout.
const CALLOUTS: Array[Dictionary] = [
	{"text": "Good!", "stream": preload("res://assets/audio/combo-voice/callout-01-good.wav")},
	{"text": "Great!", "stream": preload("res://assets/audio/combo-voice/callout-02-great.wav")},
	{"text": "Nice!", "stream": preload("res://assets/audio/combo-voice/callout-03-nice.wav")},
	{"text": "Wow!", "stream": preload("res://assets/audio/combo-voice/callout-04-wow.wav")},
	{"text": "Excellent!", "stream": preload("res://assets/audio/combo-voice/callout-05-excellent.wav")},
	{"text": "Amazing!", "stream": preload("res://assets/audio/combo-voice/callout-06-amazing.wav")},
	{"text": "Fabulous", "stream": preload("res://assets/audio/combo-voice/callout-07-fabulous.wav")},
	{"text": "Spectacular!", "stream": preload("res://assets/audio/combo-voice/callout-08-spectacular.wav")},
	{"text": "Wicked!", "stream": preload("res://assets/audio/combo-voice/callout-09-wicked.wav")},
	{"text": "Swerve!", "stream": preload("res://assets/audio/combo-voice/callout-10-swerve.wav")},
]


static func for_combo(combo_value: int) -> Dictionary:
	var index := clampi(combo_value, 1, CALLOUTS.size()) - 1
	return CALLOUTS[index]


static func stream_for_combo(combo_value: int) -> AudioStream:
	return for_combo(combo_value)["stream"] as AudioStream
