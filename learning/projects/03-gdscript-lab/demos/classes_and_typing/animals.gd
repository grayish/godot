class_name Animal
extends RefCounted
## 데모 4 의 클래스 계층. 같은 파일 안의 내부 클래스(Dog, Cat, Bird)가 바깥 클래스 Animal 을 상속한다.
## 엔진: modules/gdscript/gdscript.h — GDScript 리소스 하나가 base(부모 스크립트)와 subclasses(내부 클래스 맵)를 가진다.
##       인스턴스의 get_class() 는 네이티브 베이스("RefCounted")를 돌려주고, 스크립트 이름은 get_script().get_global_name() 이다.
##       static var 는 인스턴스가 아니라 GDScript 객체의 static_variables 에 산다 (gdscript.cpp).

enum Mood { HAPPY, HUNGRY, SLEEPY }

## 클래스(스크립트)당 하나. 인스턴스가 늘 때마다 _init 이 올린다.
static var population: int = 0

var display_name: String
var mood: Mood = Mood.HAPPY
## setter/getter 가 있는 프로퍼티. 본문 안에서 legs 를 읽고 쓰면 백킹 필드에 직접 접근한다 (무한 재귀 없음).
var legs: int = 4:
	set(value):
		legs = clampi(value, 0, 8)
	get:
		return legs


func _init(p_name: String, p_legs: int = 4) -> void:
	display_name = p_name
	legs = p_legs
	population += 1


func kind() -> String:
	return "Animal"


func speak() -> String:
	return "..."


func describe() -> String:
	return "%s (%s, 다리 %d, 기분 %s)" % [display_name, kind(), legs, Mood.keys()[mood]]


static func reset_population() -> void:
	population = 0


## 문자열로 종류를 골라 만드는 팩토리. 모르는 종류면 null.
static func create(species: String, p_name: String) -> Animal:
	match species:
		"dog":
			return Dog.new(p_name)
		"cat":
			return Cat.new(p_name)
		"bird":
			return Bird.new(p_name)
		_:
			return null


class Dog extends Animal:
	func _init(p_name: String) -> void:
		super(p_name, 4) # 부모 _init 호출 — 안 하면 부모 _init 이 기본 인자로 자동 호출되지 않고 오류다

	func kind() -> String:
		return "Dog"

	func speak() -> String:
		return super() + " 멍!" # super() 는 같은 이름의 부모 메서드


class Cat extends Animal:
	func _init(p_name: String) -> void:
		super(p_name, 4)
		mood = Mood.SLEEPY

	func kind() -> String:
		return "Cat"

	func speak() -> String:
		return "야옹"


class Bird extends Animal:
	func _init(p_name: String) -> void:
		super(p_name, 2)
		mood = Mood.HUNGRY

	func kind() -> String:
		return "Bird"

	func speak() -> String:
		return "짹"

	## 다른 동물에는 없는 메서드 — 덕 타이핑(has_method) 예시용.
	func fly() -> String:
		return display_name + " 가 난다"


## Animal 계층 밖이지만 speak() 가 있다 — "오리처럼 운다면 오리" 예시용.
class Robot extends RefCounted:
	func kind() -> String:
		return "Robot"

	func speak() -> String:
		return "삐빅"
