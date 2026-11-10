## Market（港口行情表，纯逻辑）：真相源 res://data/goods.json + ports.json。
extends GutTest

const LISBON := 0
const NO_SUCH_PORT := 999


func before_each() -> void:
	Market._reset()


func test_port_lists_its_goods_with_buy_and_sell_prices() -> void:
	var rows := Market.goods(LISBON)
	assert_gt(rows.size(), 1)
	for row: Dictionary in rows:
		assert_ne(row["key"], "")
		assert_ne(row["label"], "", "%s 有显示名" % row["key"])
		assert_gt(row["buy"], 0)
		assert_eq(row["sell"], row["buy"] * 9 / 10, "卖价 = 买价九折（去尾）")
		assert_lt(row["sell"], row["buy"], "同港买进再卖出必亏")


func test_goods_without_a_listed_price_do_not_trade_at_the_port() -> void:
	var traded := Market.goods(LISBON).map(func(r: Dictionary) -> String: return r["key"])
	assert_does_not_have(traded, "pepper", "里斯本不产胡椒")
	assert_ne(Market.label("pepper"), "", "但胡椒在货物表里")


func test_label_looks_up_any_good() -> void:
	var first: Dictionary = Market.goods(LISBON)[0]
	assert_eq(Market.label(first["key"]), first["label"])
	assert_eq(Market.label("no_such_good"), "")


func test_port_name() -> void:
	assert_eq(Market.port_name(LISBON), "里斯本")


func test_unknown_port_has_no_market() -> void:
	assert_eq(Market.goods(NO_SUCH_PORT), [])
	assert_eq(Market.port_name(NO_SUCH_PORT), "")
