extends Node
## Walking-skeleton root: click chart + judge + highway wired end to end.

const BPM := 120.0
const BEATS := 64
const LEAD_IN_BEATS := 2

var chart: ChartData
var judge: InputJudge

@onready var conductor: Conductor = $Conductor
@onready var lane_input: LaneInput = $LaneInput
@onready var highway: Highway = $Highway


func _ready() -> void:
	chart = TestCharts.click_chart(BPM, BEATS)
	judge = InputJudge.new(chart, JudgeConfig.new())
	lane_input.setup(conductor, judge)
	highway.setup(chart, conductor)
	judge.judged.connect(highway.on_judged)
	judge.stray.connect(highway.on_stray)
	conductor.begin(chart.audio_stream, LEAD_IN_BEATS * 60.0 / BPM)


func _process(_delta: float) -> void:
	# Conductor runs first (process_priority), so song_time is fresh here.
	judge.tick(conductor.song_time())
