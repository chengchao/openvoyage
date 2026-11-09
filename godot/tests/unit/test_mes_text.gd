## MesText 解析单元测试（纯逻辑）。
extends GutTest


func test_parses_speaker_and_body_tokens() -> void:
	# 0x8162 [字形 0x8841] 0x8163 0x0A   "5"  字形0x8941  0x0A  $n(0x24 0x6e)  0x00
	var rec := PackedByteArray([
		0x81, 0x62, 0x88, 0x41, 0x81, 0x63, 0x0A,
		0x35, 0x89, 0x41, 0x0A, 0x24, 0x6E, 0x00,
	])
	var r := MesText.parse(rec)
	assert_eq(r.speaker.size(), 1)
	assert_eq(r.speaker[0], {"type": "glyph", "code": 0x8841})
	var b: Array = r.body
	assert_eq(b[0], {"type": "ascii", "ch": "5"})
	assert_eq(b[1], {"type": "glyph", "code": 0x8941})
	assert_eq(b[2], {"type": "newline"})
	assert_eq(b[3], {"type": "var", "arg": 0x6E})


func test_no_speaker_when_no_bracket() -> void:
	var rec := PackedByteArray([0x35, 0x36, 0x00])  # "56"
	var r := MesText.parse(rec)
	assert_eq(r.speaker, [])
	assert_eq(r.body.size(), 2)
	assert_eq(r.body[0]["ch"], "5")


func test_stops_at_terminator() -> void:
	var rec := PackedByteArray([0x35, 0x00, 0x36])  # 0x00 后忽略
	var r := MesText.parse(rec)
	assert_eq(r.body.size(), 1)


func test_double_byte_glyph_grouping() -> void:
	var rec := PackedByteArray([0x94, 0x52, 0xAB, 0x36, 0x00])
	var r := MesText.parse(rec)
	assert_eq(r.body[0], {"type": "glyph", "code": 0x9452})
	assert_eq(r.body[1], {"type": "glyph", "code": 0xAB36})
