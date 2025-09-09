# scripts/FloatingDollar.gd
class_name FloatingDollar
extends Node2D

@export var color: Color = Color(1, 1, 1, 1)
@export var lifetime: float = 0.8
@export var rise_speed: float = 60.0
@export var font_size: int = 36

var _age: float = 0.0
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 50
	set_process(true)

func _process(delta: float) -> void:
	_age += delta
	position.y -= rise_speed * delta
	queue_redraw()
	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var alpha: float = clamp(1.0 - (_age / lifetime), 0.0, 1.0)
	var col := Color(color.r, color.g, color.b, alpha)
	draw_string(_font, Vector2(-5.0, 0.0), "$", HORIZONTAL_ALIGNMENT_LEFT, 64.0, font_size, col)
