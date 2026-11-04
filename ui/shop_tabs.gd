class_name ShopTabs
extends HBoxContainer
## The mod menu (cheats) and buy menu (guns, servers) act as one shop (fun pack,
## D65): both show this tab strip, both are in GROUP, and opening one closes the
## other. Each menu implements `SHOP_TAB`, `open_menu()`, `close_menu()`.

const GROUP := "shop_menus"
const TABS := [["cheats", "CHEATS  [INSERT]"], ["guns", "GUNS & SERVERS  [B]"]]


## Strip for the menu whose tab is `current` (that one is shown pressed).
static func make(current: String) -> ShopTabs:
	var strip := ShopTabs.new()
	strip.add_theme_constant_override("separation", 6)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = t[0] == current
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(strip.open_tab.bind(t[0]))
		strip.add_child(b)
	return strip


## Opens the shop on `tab` (closing whichever shop menu is open).
func open_tab(tab: String) -> void:
	open_in(get_tree(), tab)


static func open_in(tree: SceneTree, tab: String) -> void:
	for m in tree.get_nodes_in_group(GROUP):
		if m.SHOP_TAB == tab:
			m.open_menu()
			return


## Called by a shop menu as it opens: closes every other shop menu first.
static func close_others(menu: Node) -> void:
	if not menu.is_inside_tree():
		return
	for m in menu.get_tree().get_nodes_in_group(GROUP):
		if m != menu and m.is_open():
			m.close_menu()
