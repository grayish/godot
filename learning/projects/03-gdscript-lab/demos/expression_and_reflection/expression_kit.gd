class_name ExpressionKit
extends RefCounted
## Expression 을 안전하게 파싱/실행하는 정적 도우미. 데모 5 와 selftest 가 함께 쓴다 (Log 오토로드를 쓰지 않는다).
## 엔진: core/math/expression.cpp — GDScript 와 별개의 작은 언어. parse() 가 토큰화+파싱, execute() 가 트리 순회 실행.


## 실패해도 콘솔에 ERROR 를 찍지 않고 {"ok", "value", "error"} 로 돌려준다.
## show_error=false 가 중요하다: true 면 Expression::execute 가 ERR_FAIL_COND_V_MSG 로 오류를 출력한다.
static func evaluate(text: String, names: PackedStringArray, values: Array, base: Object = null) -> Dictionary:
	var expression := Expression.new()
	var err: Error = expression.parse(text, names)
	if err != OK:
		return {"ok": false, "value": null, "error": "파싱 실패 (%s): %s" % [error_string(err), expression.get_error_text()]}
	var value: Variant = expression.execute(values, base, false)
	if expression.has_execute_failed():
		return {"ok": false, "value": null, "error": "실행 실패: " + expression.get_error_text()}
	return {"ok": true, "value": value, "error": ""}
