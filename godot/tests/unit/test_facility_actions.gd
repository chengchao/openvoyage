## FacilityActions（设施行为表解释器，纯逻辑）单元测试。
## 校验 (设施 key, 菜单项序号) → 行为原语名 的表驱动解析（真相源 res://data/facility_actions.json）。
extends GutTest


func before_each() -> void:
	FacilityActions._reset()  # 清静态缓存，避免跨用例串扰


func test_bank_items_resolve_to_money_actions() -> void:
	assert_eq(FacilityActions.action_of(&"bank", 0), &"deposit", "银行项0→deposit")
	assert_eq(FacilityActions.action_of(&"bank", 1), &"withdraw", "银行项1→withdraw")


func test_other_facilities_resolve_to_their_actions() -> void:
	assert_eq(FacilityActions.action_of(&"market", 0), &"buy_goods", "交易所项0→buy_goods")
	assert_eq(FacilityActions.action_of(&"tavern", 0), &"hire_sailor", "酒馆项0=水手僱用→hire_sailor")


func test_unknown_facility_or_item_returns_empty() -> void:
	assert_eq(FacilityActions.action_of(&"bank", 99), &"", "越界项→空")
	assert_eq(FacilityActions.action_of(&"no_such_facility", 0), &"", "未知设施→空")


func test_resolve_carries_catalog_contract() -> void:
	var info := FacilityActions.resolve(&"bank", 0)
	assert_eq(info.get("action"), &"deposit")
	assert_true((info.get("needs", []) as Array).has("amount"), "deposit 需要 amount 输入")
	assert_eq(info.get("kind"), &"money")


func test_resolve_unknown_returns_empty_dict() -> void:
	assert_eq(FacilityActions.resolve(&"bank", 99), {})
