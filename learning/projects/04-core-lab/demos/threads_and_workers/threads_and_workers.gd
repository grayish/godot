extends Control
## 데모 7: 스레드와 워커 — Thread, Mutex, Semaphore, WorkerThreadPool, 스레드에서 call_deferred.
## 엔진: core/os/thread.h (THREADS_ENABLED 없으면 no-op 스텁), core/os/mutex.h, core/os/semaphore.h,
##       core/object/worker_thread_pool.cpp (엔진 전역 작업 풀: 렌더/물리/셰이더 컴파일도 여기 태스크),
##       core/object/message_queue.cpp (call_deferred → 메인 스레드 flush).
## 규칙: 스레드에서는 씬 트리/Control 을 만지지 않는다 (Node 스레드 가드가 오류를 낸다). 결과는 call_deferred 로 넘긴다.

const INCREMENTS_PER_THREAD: int = 20_000
const QUEUE_ITEMS: int = 8
const POOL_ELEMENTS: int = 1_000_000
const POOL_CHUNKS: int = 8

var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _counter: int = 0
var _queue: Array[int] = []
var _consumed: Array[int] = []
var _pool_data: PackedInt32Array = PackedInt32Array()
var _pool_total: int = 0
var _background: Thread = null
var _status_label: Label


func _ready() -> void:
	_build_ui()
	Log.section("스레드와 워커")
	Log.info("OS.get_processor_count()=%d, 메인 스레드 id=%d, 지금 스레드 id=%d" % [
		OS.get_processor_count(), OS.get_main_thread_id(), OS.get_thread_caller_id()])
	_demo_thread_basics()
	_demo_mutex_counter()
	_demo_semaphore()
	_demo_worker_pool()
	_demo_deferred_from_thread()
	Log.info("스레드 안전 API 요약: 서버(RenderingServer/PhysicsServer)는 CommandQueueMT 로 안전, ResourceLoader.load 안전, "
		+ "씬 트리·Control·Array/Dictionary 는 안전하지 않음 → Mutex 또는 call_deferred (문서 'Thread-safe APIs')")


func _exit_tree() -> void:
	# 시작한 Thread 는 반드시 wait_to_finish 로 회수한다 (core/os/thread.cpp ~Thread 경고).
	if _background != null and _background.is_started():
		_background.wait_to_finish()
	_background = null


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "Thread / Mutex / Semaphore / WorkerThreadPool — 버튼으로 각 실험을 다시 실행"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	var items: Array = [
		["Thread 기본", _demo_thread_basics], ["Mutex 카운터", _demo_mutex_counter], ["Mutex 없이 (경합 관찰)", _demo_unsafe_counter],
		["Semaphore 생산/소비", _demo_semaphore], ["WorkerThreadPool", _demo_worker_pool], ["스레드→call_deferred", _demo_deferred_from_thread],
	]
	for item: Array in items:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		grid.add_child(button)
	_status_label = Label.new()
	_status_label.text = "백그라운드 작업 대기 중"
	box.add_child(_status_label)


func _demo_thread_basics() -> void:
	Log.section("Thread.start + wait_to_finish")
	var thread := Thread.new()
	# Callable.bind 로 인자를 묶는다. 우선순위는 Thread.PRIORITY_NORMAL 이 기본.
	var err := thread.start(_sum_range.bind(1, 1_000_000))
	Log.info("start → %s, is_started=%s, is_alive=%s (실행 중)" % [error_string(err), str(thread.is_started()), str(thread.is_alive())])
	var result: int = thread.wait_to_finish()
	Log.info("wait_to_finish → %d (Callable 의 반환값을 돌려준다; 호출한 쪽은 그동안 블록)" % result)
	Log.info("스레드 함수 안에서 Log 를 직접 부르지 않고 call_deferred 로 넘겼다 → 아래 줄은 MessageQueue flush 때 나온다")


func _sum_range(begin: int, end: int) -> int:
	# 여기서는 다른 스레드다. UI/Log 는 건드리지 않고 call_deferred 로만 메시지를 보낸다.
	Log.info.call_deferred("  (스레드 id=%d 에서 실행됨, 메인=%s)" % [OS.get_thread_caller_id(), str(Thread.is_main_thread())])
	var total: int = 0
	for i: int in range(begin, end + 1):
		total += i
	return total


func _demo_mutex_counter() -> void:
	Log.section("Mutex 로 보호한 공유 카운터")
	_counter = 0
	var t0 := Time.get_ticks_usec()
	var a := Thread.new()
	var b := Thread.new()
	a.start(_increment_locked.bind(INCREMENTS_PER_THREAD))
	b.start(_increment_locked.bind(INCREMENTS_PER_THREAD))
	a.wait_to_finish()
	b.wait_to_finish()
	Log.info("스레드 2개 × %d회 lock/+=1/unlock → %d (기대 %d), %dus" % [
		INCREMENTS_PER_THREAD, _counter, INCREMENTS_PER_THREAD * 2, Time.get_ticks_usec() - t0])
	Log.info("Mutex 는 재귀(같은 스레드가 다시 lock 가능), BinaryMutex 는 비재귀 (core/os/mutex.h). try_lock 은 즉시 반환")


func _increment_locked(count: int) -> void:
	for i: int in count:
		_mutex.lock()
		_counter += 1
		_mutex.unlock()


func _demo_unsafe_counter() -> void:
	Log.section("Mutex 없이 (데이터 경합 관찰용 — 결과가 기대보다 작을 수 있음)")
	_counter = 0
	var a := Thread.new()
	var b := Thread.new()
	a.start(_increment_unlocked.bind(INCREMENTS_PER_THREAD))
	b.start(_increment_unlocked.bind(INCREMENTS_PER_THREAD))
	a.wait_to_finish()
	b.wait_to_finish()
	Log.info("보호 없이 += → %d (기대 %d). 읽기-수정-쓰기가 끼어들면 갱신이 사라진다" % [_counter, INCREMENTS_PER_THREAD * 2])


func _increment_unlocked(count: int) -> void:
	for i: int in count:
		_counter += 1


func _demo_semaphore() -> void:
	Log.section("Semaphore 생산자/소비자")
	_queue.clear()
	_consumed.clear()
	var producer := Thread.new()
	var consumer := Thread.new()
	producer.start(_produce.bind(QUEUE_ITEMS))
	consumer.start(_consume.bind(QUEUE_ITEMS))
	producer.wait_to_finish()
	consumer.wait_to_finish()
	Log.info("생산 %d개 → 소비 순서 %s (post() 마다 wait() 하나가 깨어난다, core/os/semaphore.h)" % [QUEUE_ITEMS, str(_consumed)])
	Log.info("큐(Array) 자체는 스레드 안전하지 않으므로 Mutex 로 감쌌다. Semaphore 는 '개수', Mutex 는 '배타' 를 담당")


func _produce(count: int) -> void:
	for i: int in count:
		_mutex.lock()
		_queue.append(i * 10)
		_mutex.unlock()
		_semaphore.post()


func _consume(count: int) -> void:
	for i: int in count:
		_semaphore.wait()
		_mutex.lock()
		var value: int = _queue.pop_front()
		_mutex.unlock()
		_consumed.append(value)


func _demo_worker_pool() -> void:
	Log.section("WorkerThreadPool.add_group_task: 청크 합산")
	_pool_data.resize(POOL_ELEMENTS)
	for i: int in POOL_ELEMENTS:
		_pool_data[i] = i % 7
	var t0 := Time.get_ticks_usec()
	var serial: int = 0
	for value: int in _pool_data:
		serial += value
	var t1 := Time.get_ticks_usec()
	_pool_total = 0
	var group_id := WorkerThreadPool.add_group_task(_sum_chunk, POOL_CHUNKS, -1, false, "core_lab_sum")
	# 진행 상황 조회는 wait 전에만 유효하다 — wait_for_group_task_completion 이 그룹을 테이블에서 지운다 (Invalid Group ID).
	var processed_early: int = WorkerThreadPool.get_group_processed_element_count(group_id)
	var completed_early: bool = WorkerThreadPool.is_group_task_completed(group_id)
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	var t2 := Time.get_ticks_usec()
	Log.info("직렬 합=%d (%dus) / 그룹 %d청크 합=%d (%dus). wait 직전 스냅샷: 처리 요소 %d개, 완료=%s" % [
		serial, t1 - t0, POOL_CHUNKS, _pool_total, t2 - t1, processed_early, str(completed_early)])
	Log.info("GDScript 청크는 인터프리터 오버헤드가 커서 병렬이 늘 빠르진 않다 — 풀의 진짜 고객은 C++ 쪽(렌더 컬링, 물리, 셰이더 컴파일)")
	var task_id := WorkerThreadPool.add_task(_single_task, true, "core_lab_single")
	Log.info("add_task(high_priority) 하나 → wait_for_task_completion=%s" % error_string(WorkerThreadPool.wait_for_task_completion(task_id)))
	Log.info("풀 크기는 threading/worker_pool/max_threads 설정 (기본 CPU 수). 작은 작업은 스레드 생성보다 풀이 싸다")


func _sum_chunk(index: int) -> void:
	var chunk: int = ceili(float(POOL_ELEMENTS) / POOL_CHUNKS)
	var begin: int = index * chunk
	var end: int = mini(begin + chunk, POOL_ELEMENTS)
	var partial: int = 0
	for i: int in range(begin, end):
		partial += _pool_data[i]
	_mutex.lock()
	_pool_total += partial
	_mutex.unlock()


func _single_task() -> void:
	Log.info.call_deferred("  단일 태스크가 워커 스레드 id=%d 에서 실행됨" % OS.get_thread_caller_id())


func _demo_deferred_from_thread() -> void:
	Log.section("백그라운드 스레드 → call_deferred / set_deferred 로 UI 갱신")
	if _background != null and _background.is_started():
		Log.warn("이미 백그라운드 작업이 진행 중")
		return
	_background = Thread.new()
	_background.start(_background_work.bind(1_000_000))
	Log.info("스레드 시작. 결과는 _on_background_done 이 메인 스레드에서 받는다 (MessageQueue 는 뮤텍스로 보호된 큐)")


func _background_work(n: int) -> void:
	var total: int = 0
	for i: int in n:
		total += i & 3
	# Node 의 프로퍼티를 직접 바꾸면 스레드 가드 오류 → set_deferred / call_deferred 로 메인 스레드에 맡긴다.
	_status_label.set_deferred(&"text", "백그라운드 합=%d (set_deferred 로 갱신)" % total)
	call_deferred(&"_on_background_done", total)


func _on_background_done(total: int) -> void:
	if _background != null and _background.is_started():
		_background.wait_to_finish()
	Log.info("백그라운드 합=%d 도착, 스레드 회수 완료 (wait_to_finish)" % total)
