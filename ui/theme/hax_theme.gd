class_name HaxTheme
extends RefCounted
## Shared "sketchy injected cheat" look for the mod menu (and later menu skins):
## monospace font, dark panel with a neon border, neon toggles and buttons.
## Colours come from data/palette.json through DataRegistry; only sizes live here.

const FONT_NAMES := ["DejaVu Sans Mono", "Consolas", "Courier New", "Liberation Mono", "monospace"]
const FONT_SIZE := 15
const BORDER_PX := 2
const CORNER_PX := 2


## Builds a fresh Theme. Cheap enough to call once per menu instance.
static func build() -> Theme:
	var neon := DataRegistry.color("neon")
	var accent := DataRegistry.color("accent")
	var bg := DataRegistry.color("ui_bg")
	var text := DataRegistry.color("ui_text")

	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	theme.default_font = font
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", _box(Color(bg, 0.94), neon, BORDER_PX))
	theme.set_stylebox("panel", "Panel", _box(Color(bg, 0.94), neon, BORDER_PX))
	theme.set_color("font_color", "Label", text)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := Color(bg.lightened(0.08), 1.0)
		var border := neon
		match state:
			"hover":
				fill = Color(neon, 0.18)
			"pressed":
				fill = Color(neon, 0.35)
			"disabled":
				border = Color(text, 0.25)
			"focus":
				fill = Color(0, 0, 0, 0)
		var box := _box(fill, border, 1)
		box.content_margin_left = 8
		box.content_margin_right = 8
		theme.set_stylebox(state, "Button", box)
	theme.set_color("font_color", "Button", neon)
	theme.set_color("font_hover_color", "Button", text)
	theme.set_color("font_pressed_color", "Button", text)
	theme.set_color("font_disabled_color", "Button", Color(text, 0.35))

	# Tabs: neon underline on the selected tab.
	var tab_sel := _box(Color(neon, 0.2), neon, 0)
	tab_sel.border_width_bottom = BORDER_PX
	theme.set_stylebox("tab_selected", "TabBar", tab_sel)
	theme.set_stylebox("tab_unselected", "TabBar", _box(Color(0, 0, 0, 0), neon, 0))
	theme.set_stylebox("tab_hovered", "TabBar", _box(Color(neon, 0.1), neon, 0))
	theme.set_color("font_selected_color", "TabBar", neon)
	theme.set_color("font_unselected_color", "TabBar", Color(text, 0.6))
	theme.set_color("font_hovered_color", "TabBar", text)

	# Toggle switches (CheckButton): neon when on, muted when off.
	theme.set_color("font_color", "CheckButton", text)
	theme.set_color("font_pressed_color", "CheckButton", neon)
	theme.set_color("font_hover_pressed_color", "CheckButton", neon)
	theme.set_color("font_disabled_color", "CheckButton", Color(text, 0.3))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())

	var bar_bg := _box(Color(0, 0, 0, 0.6), neon, 1)
	var bar_fill := _box(accent, accent, 0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", text)
	return theme


static func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(CORNER_PX)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box
