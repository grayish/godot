extends Control

## 데모 7: AudioServer 버스/이펙트 + AudioStreamGenerator 로 사인파 합성.
## 엔진: servers/audio/audio_server.cpp add_bus(:677) add_bus_effect(:923) set_bus_volume_db(:821) _mix_step(:131)
##       servers/audio/audio_driver_dummy.h — 헤드리스에선 더미 드라이버가 스레드에서 믹스만 하고 버린다 (3.1.1 절)
##       scene/resources/audio/audio_stream_generator.cpp push_frame(:112) get_frames_available(:154) _mix_internal(:168)
## 드라이버 스레드가 _mix_internal 로 링버퍼를 읽고, 우리는 메인 스레드에서 push_frame 으로 채운다.
## 버스 이름은 StringName 이고 인덱스는 버스가 추가/삭제되면 바뀌므로 get_bus_index 로 다시 찾는다.

const BUS_NAME: StringName = &"LabReverb"
const GENERATOR_MIX_RATE: float = 22050.0

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback = null
var created_bus: bool = false
var frequency: float = 220.0
var amplitude: float = 0.25
var phase: float = 0.0
var frames_pushed: int = 0
var info_timer: float = 0.0
var info_label: Label


func _ready() -> void:
	var bus_index: int = AudioServer.get_bus_index(BUS_NAME)
	if bus_index == -1:
		bus_index = AudioServer.bus_count
		AudioServer.add_bus() # at_position=-1 → 맨 뒤
		AudioServer.set_bus_name(bus_index, String(BUS_NAME))
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.9
		reverb.wet = 0.4
		AudioServer.add_bus_effect(bus_index, reverb)
		AudioServer.set_bus_volume_db(bus_index, -6.0)
		created_bus = true
		# 버스 send 기본값은 "Master": LabReverb → (리버브) → Master → 출력 드라이버.
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = GENERATOR_MIX_RATE # AudioServer 믹스 레이트와 달라도 리샘플된다
	generator.buffer_length = 0.1 # 초 단위 링버퍼 크기 = 지연 시간과의 트레이드오프
	player = AudioStreamPlayer.new()
	player.stream = generator
	player.bus = BUS_NAME
	add_child(player)
	player.play()
	# 재생이 시작되어야 playback 객체가 생긴다.
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		Log.warn("AudioStreamGeneratorPlayback 을 얻지 못했습니다")
	else:
		_fill_buffer()
	_build_ui()
	Log.info("드라이버 %s, 믹스 레이트 %.0f Hz, 출력 지연 %.1f ms, 버스 %d개" % [
		AudioServer.get_driver_name(), AudioServer.get_mix_rate(), AudioServer.get_output_latency() * 1000.0, AudioServer.bus_count])
	if AudioServer.get_driver_name() == "Dummy":
		Log.warn("더미 오디오 드라이버: 소리는 나지 않지만 믹싱/버스/제너레이터 경로는 그대로 동작합니다.")


func _exit_tree() -> void:
	player.stop()
	if created_bus:
		var idx: int = AudioServer.get_bus_index(BUS_NAME)
		if idx != -1:
			AudioServer.remove_bus(idx)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(8, 8)
	add_child(box)
	_add_slider(box, "주파수 (Hz)", 110.0, 880.0, 1.0, frequency, func(v: float) -> void: frequency = v)
	_add_slider(box, "진폭", 0.0, 0.5, 0.01, amplitude, func(v: float) -> void: amplitude = v)
	_add_slider(box, "버스 볼륨 (dB)", -40.0, 0.0, 0.5, -6.0, func(v: float) -> void:
		var idx: int = AudioServer.get_bus_index(BUS_NAME)
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, v))
	var reverb_check := CheckBox.new()
	reverb_check.text = "리버브 이펙트 켜기 (set_bus_effect_enabled)"
	reverb_check.button_pressed = true
	reverb_check.toggled.connect(func(v: bool) -> void:
		var idx: int = AudioServer.get_bus_index(BUS_NAME)
		if idx != -1 and AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.set_bus_effect_enabled(idx, 0, v))
	box.add_child(reverb_check)
	info_label = Label.new()
	box.add_child(info_label)
	_update_info()


func _add_slider(parent: Control, label_text: String, min_v: float, max_v: float, step: float, initial: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(130, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(240, 0)
	slider.value_changed.connect(callback)
	row.add_child(slider)
	parent.add_child(row)


## 링버퍼의 빈 자리만큼 사인파 프레임을 채운다. 매 프레임 호출해도 get_frames_available 이 0 이면 아무것도 안 한다.
func _fill_buffer() -> void:
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	var increment: float = TAU * frequency / GENERATOR_MIX_RATE
	for i: int in available:
		var sample: float = sin(phase) * amplitude
		playback.push_frame(Vector2(sample, sample)) # (왼쪽, 오른쪽)
		phase = fmod(phase + increment, TAU)
	frames_pushed += available


func _process(delta: float) -> void:
	_fill_buffer()
	info_timer += delta
	if info_timer >= 0.5:
		info_timer = 0.0
		_update_info()


func _update_info() -> void:
	var names: PackedStringArray = PackedStringArray()
	for i: int in AudioServer.bus_count:
		names.append("%d:%s(%.1f dB)" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	var skips: int = playback.get_skips() if playback != null else 0
	info_label.text = "드라이버 %s | 믹스 레이트 %.0f Hz | 출력 지연 %.1f ms | 스피커 모드 %d\n버스: %s\n밀어 넣은 프레임 %d | 버퍼 부족(skips) %d | 마지막 믹스 후 %.1f ms" % [
		AudioServer.get_driver_name(), AudioServer.get_mix_rate(), AudioServer.get_output_latency() * 1000.0, AudioServer.get_speaker_mode(),
		", ".join(names), frames_pushed, skips, AudioServer.get_time_since_last_mix() * 1000.0,
	]
