extends Node2D

# Renders the beach and sea background and maintains the split line
# (the indifferent consumer position) as set by Main.

@export var beach_margin := 0.0  # padding left/right
@export var beach_y := 360.0      # vertical position
@export var beach_width := 1120.0 # drawable width (will be recalculated in _ready)
@export var beach_height := 800.0
@export var band_height := 20.0   # thickness of the darker shoreline strip
@export var band_color := Color.hex(0xDBCBAAFF)  # tweak color if you like
@export var sea_top_color := Color.hex(0x99D9FFFF)   # lighter blue near shore
@export var sea_bottom_color := Color.hex(0x005577FF) # deeper blue further down
@export var sea_gradient_steps := 200  # increase for smoother gradient

var split_x_px := -1.0  # where the indifferent consumer is (in pixels), -1 if none

func _ready() -> void:
	# Recompute width from viewport
	var vpw = get_viewport_rect().size.x
	beach_width = vpw - 2.0 * beach_margin
	queue_redraw()

func norm_to_px(x_norm: float) -> Vector2:
	# map x in [0,1] to pixel point on beach center line
	x_norm = clampf(x_norm, 0.0, 1.0)
	var x = beach_margin + x_norm * beach_width
	return Vector2(x, beach_y)

func px_to_norm(x_px: float) -> float:
	return clampf((x_px - beach_margin) / beach_width, 0.0, 1.0)

func set_split_x_from_norm(x_norm: float) -> void:
	split_x_px = norm_to_px(x_norm).x
	queue_redraw()

func clear_split() -> void:
	split_x_px = -1.0
	queue_redraw()

func _draw() -> void:
	var left = beach_margin
	var right = beach_margin + beach_width
	var screen_h = get_viewport_rect().size.y
	var dark_sand_prop = 0.1

	# where the beach ends (its bottom edge), based on the centerline + half height
	var beach_bottom_y = beach_y + beach_height * 0.5

	# --- SAND: from the top of the screen down to the shoreline ---
	var sand_rect = Rect2(
		Vector2(left, 0.0),
		Vector2(beach_width, beach_bottom_y)
	)
	draw_rect(sand_rect, Color.hex(0xE6DFC6FF))  # sandy

	# optional: draw a darker strip for the "beach band" if you like a boundary
	# shoreline band (darker strip at water's edge)
	var band_top = beach_bottom_y - band_height
	var band_rect = Rect2(
		Vector2(left, band_top),
		Vector2(beach_width, band_height)
	)
	draw_rect(band_rect, band_color)

	# --- SEA: vertical gradient from shoreline to bottom (manual draw) ---
	var sea_rect = Rect2(
		Vector2(left, beach_bottom_y),
		Vector2(beach_width, screen_h - beach_bottom_y)
	)
	var sea_h: int = int(round(sea_rect.size.y))
	if sea_h > 0:
		var steps: int = clamp(sea_gradient_steps, 2, 2000)
		for i in range(steps):
			var t: float = float(i) / float(steps - 1)              # 0 at shore → 1 at bottom
			var c: Color = sea_top_color.lerp(sea_bottom_color, t)  # interpolate color

			# slice this step's y-interval
			var y0: float = beach_bottom_y + floor(i * sea_h / steps)
			var y1: float = beach_bottom_y + floor((i + 1) * sea_h / steps)
			var h: float = max(1.0, y1 - y0)

			draw_rect(Rect2(Vector2(left, y0), Vector2(beach_width, h)), c)



	# split line (indifferent consumer), if any
	if split_x_px >= 0.0:
		draw_line(
			Vector2(split_x_px, beach_y - 40),
			Vector2(split_x_px, beach_y + 40),
			Color.hex(0x333333FF), 2.0
		)
