from koukai2 import text_wip


def test_width_is_188():
    assert text_wip.WIDTH == 188


def test_punctuation_row():
    # lead 0x81 with lo 0x31/0x34/0x38/0x39 -> ，。？！
    for lo, ch in ((0x31, "，"), (0x34, "。"), (0x38, "？"), (0x39, "！")):
        toks = text_wip.parse(bytes([0x81, lo, 0x00]))
        assert toks == [("punct", ch)]


def test_controls():
    toks = text_wip.parse(bytes([0x0A, 0x24, 0x6E, 0x00]))
    assert toks[0] == ("nl",)
    assert toks[1] == ("var", 0x6E)


def test_glyph_token_shape():
    toks = text_wip.parse(bytes([0xA4, 0xD6, 0x00]))
    assert toks[0][0] == "glyph" and toks[0][1] == 0xA4 and toks[0][2] == 0xD6


def test_to_font_code_disasm_transform():
    # reverse-engineered MAIN.EXE 0x43A1 transform (regression pins)
    assert text_wip.to_font_code(0x97, 0xFA) == 20092
    assert text_wip.to_font_code(0x81, 0x31) == 0x2112
    # non-hanzi lead bytes rejected
    assert text_wip.to_font_code(0x40, 0x40) is None
    assert text_wip.to_font_code(0xF5, 0x40) is None
