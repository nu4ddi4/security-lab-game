class_name InvestigationTheme
extends RefCounted

# One visual language for every 2D surface: HUD, tablet, terminal, dialogue,
# settings, touch controls, loading screen and in-world monitors.
const BACKDROP = Color(.02,.04,.055)
const SURFACE = Color(.035,.065,.085,.96)
const RAISED = Color(.075,.125,.15,.96)
const INSET = Color(.015,.032,.045,.94)
const BORDER = Color(.2,.32,.37)
const BORDER_STRONG = Color(.4,.56,.61)
const ACCENT = Color(.25,.90,.86)
const ACCENT_FILL = Color(.06,.2,.22,.92)
const ACCENT_HOVER = Color(.1,.28,.3,.95)
const TEXT = Color(.88,.93,.95)
const TEXT_DIM = Color(.62,.74,.78)
const TEXT_FAINT = Color(.44,.6,.65)
const TERMINAL_TEXT = Color(.65,.92,.78)
const WARNING = Color(.95,.68,.28)
const DANGER = Color(.98,.42,.45)
const DANGER_FILL = Color(.2,.065,.085,.9)

const FONT_PATH = "res://assets/fonts/NotoSansKR.ttf"
const REGULAR_WEIGHT = 450
const BOLD_WEIGHT = 650

static var _fonts = {}

class Mark extends Control:
	func _draw():
		draw_polyline(PackedVector2Array([Vector2(22,4),Vector2(38,10),Vector2(35,30),Vector2(22,42),Vector2(9,30),Vector2(6,10),Vector2(22,4)]),ACCENT,2.5,true)
		draw_polyline(PackedVector2Array([Vector2(28,15),Vector2(18,15),Vector2(16,21),Vector2(27,27),Vector2(25,32),Vector2(16,32)]),ACCENT,3,true)

static func font(weight = REGULAR_WEIGHT) -> FontVariation:
	if not _fonts.has(weight):
		var variation = FontVariation.new()
		variation.base_font = load(FONT_PATH)
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):weight}
		_fonts[weight] = variation
	return _fonts[weight]

static func box(fill: Color, border = BORDER, radius = 10, margin = 14, border_width = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

static func brand_mark() -> Control:
	var mark = Mark.new()
	mark.custom_minimum_size = Vector2(48,48)
	return mark

static func _button(theme: Theme, type: String, fill: Color, border: Color, hover_fill: Color, color: Color):
	var normal = box(fill,border,9,12)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover = normal.duplicate()
	hover.bg_color = hover_fill
	hover.border_color = ACCENT
	var pressed = hover.duplicate()
	pressed.bg_color = ACCENT_FILL.lightened(.1)
	var disabled = normal.duplicate()
	disabled.bg_color = Color(fill.r,fill.g,fill.b,fill.a*.45)
	disabled.border_color = Color(border.r,border.g,border.b,.35)
	var focus = box(Color(0,0,0,0),ACCENT,9,0,2)
	theme.set_stylebox("normal",type,normal)
	theme.set_stylebox("hover",type,hover)
	theme.set_stylebox("pressed",type,pressed)
	theme.set_stylebox("hover_pressed",type,pressed)
	theme.set_stylebox("disabled",type,disabled)
	theme.set_stylebox("focus",type,focus)
	for name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		theme.set_color(name,type,color)
	theme.set_color("font_disabled_color",type,TEXT_FAINT)

static func _variation(theme: Theme, name: String, base: String, style: StyleBox):
	theme.set_type_variation(name,base)
	theme.set_stylebox("panel",name,style)

static func build(mobile: bool) -> Theme:
	var theme = Theme.new()
	theme.default_font = font()
	theme.default_font_size = 22 if mobile else 18

	theme.set_color("font_color","Label",TEXT)
	theme.set_color("font_shadow_color","Label",Color(0,0,0,.45))
	for entry in [["Heading",22,BOLD_WEIGHT,TEXT],["Title",26,BOLD_WEIGHT,TEXT],["Section",18,BOLD_WEIGHT,ACCENT],["Caption",14,REGULAR_WEIGHT,TEXT_DIM],["Eyebrow",12,BOLD_WEIGHT,TEXT_FAINT]]:
		theme.set_type_variation(entry[0]+"Label","Label")
		theme.set_font("font",entry[0]+"Label",font(entry[2]))
		theme.set_font_size("font_size",entry[0]+"Label",entry[1])
		theme.set_color("font_color",entry[0]+"Label",entry[3])

	_button(theme,"Button",RAISED,BORDER,ACCENT_HOVER,TEXT)
	theme.set_type_variation("PrimaryButton","Button")
	_button(theme,"PrimaryButton",ACCENT_FILL,ACCENT,ACCENT_HOVER,ACCENT)
	theme.set_type_variation("DangerButton","Button")
	_button(theme,"DangerButton",DANGER_FILL,DANGER,Color(.3,.09,.11,.95),DANGER)
	theme.set_type_variation("TileButton","Button")
	_button(theme,"TileButton",INSET,BORDER,ACCENT_HOVER,TEXT)
	theme.set_stylebox("normal","TileButton",box(INSET,BORDER,9,12))
	theme.set_constant("h_separation","Button",8)
	_button(theme,"OptionButton",RAISED,BORDER,ACCENT_HOVER,TEXT)
	_button(theme,"CheckButton",Color(0,0,0,0),Color(0,0,0,0),Color(1,1,1,.04),TEXT)
	theme.set_color("font_color","CheckButton",TEXT)

	theme.set_stylebox("panel","PanelContainer",box(RAISED))
	_variation(theme,"ModalPanel","PanelContainer",box(SURFACE,BORDER_STRONG,14,22))
	_variation(theme,"CardPanel","PanelContainer",box(Color(.035,.065,.085,.74),BORDER,10,14))
	_variation(theme,"InsetPanel","PanelContainer",box(INSET,BORDER,8,10))
	_variation(theme,"HudPanel","PanelContainer",box(Color(.02,.04,.055,.82),BORDER,10,14))
	_variation(theme,"BubblePanel","PanelContainer",box(RAISED,BORDER,10,12))
	_variation(theme,"OutgoingBubblePanel","PanelContainer",box(ACCENT_FILL,ACCENT.darkened(.35),10,12))
	_variation(theme,"WarningPanel","PanelContainer",box(DANGER_FILL,DANGER.darkened(.3),10,14))
	_variation(theme,"KeyCapPanel","PanelContainer",box(Color(.02,.09,.12,.92),ACCENT.darkened(.35),8,8))

	var tab_selected = box(RAISED,ACCENT,8,14,1)
	tab_selected.border_width_bottom = 3
	tab_selected.corner_radius_bottom_left = 0
	tab_selected.corner_radius_bottom_right = 0
	var tab_idle = box(Color(0,0,0,0),Color(0,0,0,0),8,14)
	var tab_hover = box(Color(1,1,1,.05),Color(0,0,0,0),8,14)
	theme.set_stylebox("tab_selected","TabContainer",tab_selected)
	theme.set_stylebox("tab_unselected","TabContainer",tab_idle)
	theme.set_stylebox("tab_hovered","TabContainer",tab_hover)
	theme.set_stylebox("tab_focus","TabContainer",box(Color(0,0,0,0),Color(0,0,0,0),0,0,0))
	theme.set_stylebox("panel","TabContainer",box(Color(0,0,0,0),Color(0,0,0,0),0,8,0))
	theme.set_color("font_selected_color","TabContainer",ACCENT)
	theme.set_color("font_unselected_color","TabContainer",TEXT_DIM)
	theme.set_color("font_hovered_color","TabContainer",TEXT)
	theme.set_constant("side_margin","TabContainer",0)

	var field = box(INSET,BORDER,8,10)
	var field_focus = box(INSET,ACCENT,8,10)
	var field_readonly = box(INSET.darkened(.2),BORDER,8,10)
	for type in ["LineEdit","TextEdit"]:
		theme.set_stylebox("normal",type,field)
		theme.set_stylebox("focus",type,field_focus)
		theme.set_stylebox("read_only",type,field_readonly)
		theme.set_color("font_color",type,TEXT)
		theme.set_color("font_placeholder_color",type,TEXT_FAINT)
		theme.set_color("caret_color",type,ACCENT)
		theme.set_color("selection_color",type,Color(ACCENT.r,ACCENT.g,ACCENT.b,.28))
	theme.set_color("default_color","RichTextLabel",TEXT)
	theme.set_color("selection_color","RichTextLabel",Color(ACCENT.r,ACCENT.g,ACCENT.b,.28))
	theme.set_font("bold_font","RichTextLabel",font(BOLD_WEIGHT))

	var popup = box(Color(.035,.065,.085,.99),BORDER_STRONG,10,6)
	theme.set_stylebox("panel","PopupMenu",popup)
	theme.set_stylebox("hover","PopupMenu",box(ACCENT_FILL,Color(0,0,0,0),6,6))
	theme.set_color("font_color","PopupMenu",TEXT)
	theme.set_color("font_hover_color","PopupMenu",ACCENT)
	var dialog = box(Color(.035,.065,.085,.99),BORDER_STRONG,12,18,1)
	for type in ["Window","AcceptDialog","ConfirmationDialog","FileDialog"]:
		theme.set_stylebox("embedded_border",type,dialog)
		theme.set_stylebox("embedded_unfocused_border",type,dialog)
		theme.set_color("title_color",type,TEXT)
		theme.set_constant("title_height",type,36)
		theme.set_constant("title_outline_size",type,0)
	theme.set_stylebox("panel","AcceptDialog",dialog)

	var track = box(Color(1,1,1,.06),Color(0,0,0,0),4,0,0)
	var grabber = box(BORDER_STRONG,Color(0,0,0,0),4,0,0)
	var grabber_hover = box(ACCENT,Color(0,0,0,0),4,0,0)
	for type in ["VScrollBar","HScrollBar"]:
		theme.set_stylebox("scroll",type,track)
		theme.set_stylebox("grabber",type,grabber)
		theme.set_stylebox("grabber_highlight",type,grabber_hover)
		theme.set_stylebox("grabber_pressed",type,grabber_hover)
	theme.set_stylebox("slider","HSlider",box(Color(1,1,1,.1),Color(0,0,0,0),3,0,0))
	theme.set_stylebox("grabber_area","HSlider",box(ACCENT.darkened(.3),Color(0,0,0,0),3,0,0))
	theme.set_stylebox("grabber_area_highlight","HSlider",box(ACCENT,Color(0,0,0,0),3,0,0))
	theme.set_stylebox("background","ProgressBar",box(Color(1,1,1,.08),Color(0,0,0,0),6,0,0))
	theme.set_stylebox("fill","ProgressBar",box(ACCENT,Color(0,0,0,0),6,0,0))
	theme.set_stylebox("separator","HSeparator",box(BORDER,Color(0,0,0,0),0,0,0))
	theme.set_constant("separation","VSeparator",12)
	return theme
