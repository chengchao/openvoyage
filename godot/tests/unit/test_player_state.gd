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


func test_buy_spends_gold_and_fills_the_hold() -> void:
	var p := PlayerState.new(1000, 0)
	assert_true(p.buy("wine", 5, 40))
	assert_eq(p.gold, 800)
	assert_eq(p.cargo, {"wine": 5})
	assert_eq(p.cargo_used(), 5)
	assert_true(p.buy("wine", 2, 40))
	assert_eq(p.cargo, {"wine": 7}, "同种货物累加")


func test_buy_beyond_gold_or_hold_fails_unchanged() -> void:
	var p := PlayerState.new(1000, 0)
	assert_false(p.buy("wine", 26, 40), "钱不够")
	assert_false(p.buy("salt", p.hold + 1, 1), "船舱装不下")
	assert_false(p.buy("wine", 0, 40))
	assert_false(p.buy("wine", -3, 40))
	assert_eq(p.gold, 1000)
	assert_eq(p.cargo, {})


func test_hold_counts_all_goods_together() -> void:
	var p := PlayerState.new(100000, 0)
	assert_true(p.buy("wine", p.hold - 1, 1))
	assert_false(p.buy("salt", 2, 1), "两种货物共用一个船舱")
	assert_true(p.buy("salt", 1, 1))
	assert_eq(p.cargo_used(), p.hold)


func test_sell_earns_gold_and_drops_emptied_goods() -> void:
	var p := PlayerState.new(0, 0)
	p.cargo = {"wine": 5}
	assert_true(p.sell("wine", 2, 36))
	assert_eq(p.gold, 72)
	assert_eq(p.cargo, {"wine": 3})
	assert_true(p.sell("wine", 3, 36))
	assert_eq(p.cargo, {}, "卖光的货物不留 0 条目")


func test_sell_more_than_held_fails_unchanged() -> void:
	var p := PlayerState.new(0, 0)
	p.cargo = {"wine": 5}
	assert_false(p.sell("wine", 6, 36))
	assert_false(p.sell("salt", 1, 10), "没有的货")
	assert_false(p.sell("wine", 0, 36))
	assert_eq(p.gold, 0)
	assert_eq(p.cargo, {"wine": 5})
