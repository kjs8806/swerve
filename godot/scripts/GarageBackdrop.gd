extends Control

# Resolution-independent service-bay architecture; no animation or input cost.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("090d13"))
	for i in range(24):
		var t := float(i) / 24.0
		draw_rect(Rect2(0, h * t, w, h / 24.0 + 1), Color("202b37").lerp(Color("080b11"), t))
	var vanishing := Vector2(w * 0.62, h * 0.48)
	for i in range(13):
		var x := float(i) * w / 12.0
		draw_line(Vector2(x, 0), Vector2(x, h * 0.48), Color("293440"), 2)
		draw_line(vanishing, Vector2((float(i) - 3.0) * w / 6.0, h), Color("26323d"), 1, true)
	for i in range(1, 8):
		var t := float(i) / 8.0
		var y := h * 0.48 + h * 0.52 * t * t
		draw_line(Vector2(0, y), Vector2(w, y), Color("26323d"), 1)
	for i in range(4):
		var x := w * (0.08 + float(i) * 0.25)
		draw_line(Vector2(x, h * 0.05), Vector2(x + w * 0.14, h * 0.05), Color(0.2, 0.8, 1.0, 0.08), 18, true)
		draw_line(Vector2(x, h * 0.05), Vector2(x + w * 0.14, h * 0.05), Color("c4e7f0"), 3, true)
	# Tool-cabinet drawers at the back of the workshop.
	for i in range(5):
		var r := Rect2(w * 0.025, h * (0.22 + float(i) * 0.044), w * 0.17, h * 0.035)
		draw_rect(r, Color("18222b"))
		draw_line(r.position + Vector2(12, 5), r.position + Vector2(r.size.x - 12, 5), Color("66727a"), 2)
