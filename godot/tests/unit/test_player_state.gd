## PlayerState（玩家经济状态：现金/存款）纯逻辑测试。
extends GutTest


func test_init_sets_starting_funds() -> void:
	var p := PlayerState.new(2000, 500)
	assert_eq(p.gold, 2000)
	assert_eq(p.bank, 500)


func test_init_defaults_zero() -> void:
	var p := PlayerState.new()
	assert_eq(p.gold, 0)
	assert_eq(p.bank, 0)


func test_deposit_moves_gold_to_bank() -> void:
	var p := PlayerState.new(2000, 0)
	assert_true(p.deposit(1500))
	assert_eq(p.gold, 500)
	assert_eq(p.bank, 1500)


func test_deposit_over_gold_fails_unchanged() -> void:
	var p := PlayerState.new(1000, 0)
	assert_false(p.deposit(1001), "现金不足应失败")
	assert_eq(p.gold, 1000)
	assert_eq(p.bank, 0)


func test_deposit_non_positive_fails() -> void:
	var p := PlayerState.new(1000, 0)
	assert_false(p.deposit(0))
	assert_false(p.deposit(-100))
	assert_eq(p.gold, 1000)


func test_withdraw_moves_bank_to_gold() -> void:
	var p := PlayerState.new(0, 800)
	assert_true(p.withdraw(300))
	assert_eq(p.gold, 300)
	assert_eq(p.bank, 500)


func test_withdraw_over_bank_fails_unchanged() -> void:
	var p := PlayerState.new(0, 500)
	assert_false(p.withdraw(501), "存款不足应失败")
	assert_eq(p.gold, 0)
	assert_eq(p.bank, 500)


func test_total_conserved_across_ops() -> void:
	var p := PlayerState.new(2000, 1000)
	var total := p.gold + p.bank
	p.deposit(700)
	p.withdraw(300)
	p.deposit(123)
	assert_eq(p.gold + p.bank, total, "存取不应凭空增减总额")
