## Market（港口行情表，纯逻辑）：真相源 res://data/goods.json + ports.json。
extends GutTest

const LISBON := 0
const SEVILLE := 1
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


func test_pepper_trades_in_seville() -> void:
	var traded := Market.goods(SEVILLE).map(func(r: Dictionary) -> String: return r["key"])
	assert_has(traded, "pepper")


func test_label_looks_up_any_good() -> void:
	var first: Dictionary = Market.goods(LISBON)[0]
	assert_eq(Market.label(first["key"]), first["label"])
	assert_eq(Market.label("no_such_good"), "")


func test_port_name() -> void:
	assert_eq(Market.port_name(LISBON), "里斯本")


func test_unknown_port_has_no_market() -> void:
	assert_eq(Market.goods(NO_SUCH_PORT), [])
	assert_eq(Market.port_name(NO_SUCH_PORT), "")


func test_port_scene_comes_from_the_ports_table() -> void:
	assert_eq(Market.port_scene(0), "res://game/port3d/ports/lisbon.tscn")
	assert_true(ResourceLoader.exists(Market.port_scene(0)))
	assert_eq(Market.port_scene(999), "", "未知港")


func test_every_port_has_a_scene_that_exists() -> void:
	for id in [LISBON, SEVILLE]:
		assert_true(ResourceLoader.exists(Market.port_scene(id)), "港 %d 的场景" % id)
	assert_eq(Market.port_name(SEVILLE), "塞維利亞")


func test_routes_list_destination_name_and_days() -> void:
	assert_eq(Market.routes(LISBON), [{"to": SEVILLE, "name": "塞維利亞", "days": 4}])
	assert_eq(Market.routes(SEVILLE), [{"to": LISBON, "name": "里斯本", "days": 4}])
	assert_eq(Market.routes(NO_SUCH_PORT), [])


## 在 from 买、到 to 卖能赚钱的货物（卖价已含九折）。
func _profitable(from: int, to: int) -> Array:
	var sell := {}
	for g: Dictionary in Market.goods(to):
		sell[g["key"]] = g["sell"]
	return Market.goods(from).filter(func(g: Dictionary) -> bool: return sell.get(g["key"], 0) > g["buy"])


func test_trade_is_profitable_in_both_directions() -> void:
	assert_gte(_profitable(LISBON, SEVILLE).size(), 2, "里斯本 → 塞維利亞 至少两种货有赚头")
	assert_gte(_profitable(SEVILLE, LISBON).size(), 2, "塞維利亞 → 里斯本 至少两种货有赚头")


func test_nothing_bought_can_be_stranded() -> void:
	for pair in [[LISBON, SEVILLE], [SEVILLE, LISBON]]:
		var taken := Market.goods(pair[1]).map(func(g: Dictionary) -> String: return g["key"])
		for g: Dictionary in Market.goods(pair[0]):
			assert_has(taken, g["key"], "港 %d 卖的%s，港 %d 得收" % [pair[0], g["label"], pair[1]])
