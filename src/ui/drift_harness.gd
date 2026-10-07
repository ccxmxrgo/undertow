class_name DriftHarness
extends Control
## Real-audio drift logger (D-30 manual half, Pitfall 7 part b). Plays the 5-minute click chart
## through the real Conductor and logs once per second: song_time minus elapsed system time.
## Run it non-headless on a real device. Esc stops early. The CSV path is fixed (T-06-01).

const LOG_PATH := "user://drift_log.csv"
const DURATION_SEC := 300.0
const LEAD_IN_SEC := 2.0
const MENU_SCENE := "res://scenes/main_menu.tscn"

## CSV destination. Callers (tests) override this BEFORE add_child; default is LOG_PATH.
var log_path: String = LOG_PATH
var conductor: Conductor
var _file: FileAccess
var _start_ticks: int = 0
var _next_log_s: float = 0.0
var _label: Label
var _rows: Array[String] = []
var _finished: bool = false


func _ready() -> void:
	UiLayout.fill_rect(self)
	theme = Palette.load_theme()
	_label = Label.new()
	_label.position = Vector2(64.0, 64.0)
	_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	add_child(_label)
	var chart := TestCharts.five_minute_click_chart()
	conductor = Conductor.new()
	conductor.tempo_map = chart.tempo_map
	add_child(conductor)
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file != null:
		_file.store_line("elapsed_s,song_time_s,drift_ms")
	_start_ticks = Time.get_ticks_usec()
	conductor.begin(chart.audio_stream, LEAD_IN_SEC)
	_label.text = "Drift harness: starting..."


func _process(_delta: float) -> void:
	if _finished:
		return
	var elapsed := (Time.get_ticks_usec() - _start_ticks) / 1000000.0 - LEAD_IN_SEC
	if elapsed >= _next_log_s:
		var st := conductor.song_time()
		var drift_ms := (st - elapsed) * 1000.0
		var row := "%.1f,%.4f,%.2f" % [elapsed, st, drift_ms]
		if _file != null:
			_file.store_line(row)
			_file.flush()
		_rows.append("t=%5.0f s  song_time=%9.4f  drift=%+7.2f ms" % [elapsed, st, drift_ms])
		while _rows.size() > 20:
			_rows.pop_front()
		_label.text = "Drift harness (Esc to stop) - log: %s\n\n%s" % [
			ProjectSettings.globalize_path(log_path), "\n".join(_rows)]
		_next_log_s += 1.0
	if elapsed >= DURATION_SEC:
		_stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_stop()
		var target := MENU_SCENE if ResourceLoader.exists(MENU_SCENE) else ""
		if target != "":
			get_tree().change_scene_to_file(target)


func _stop() -> void:
	if _finished:
		return
	_finished = true
	conductor.stop()
	if _file != null:
		_file.close()
		_file = null
	_label.text += "\n\nDone. Log saved to %s" % ProjectSettings.globalize_path(log_path)
