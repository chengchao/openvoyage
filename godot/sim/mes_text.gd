## MES/MESSAGE 文本记录解析（纯逻辑）：一条记录字节流 → 结构化 token，供对话窗渲染。
## 格式见 docs/08 §8.2：[说话人名(0x8162…0x8163) 0x0A] 正文… 0x00 终止。
##
## 不负责字形映射（code→字模索引在渲染层/字库做）与 $ 变量取值（运行时由游戏代入）；
## 此处只把字节切成 token：换行 / ASCII 字符 / 双字节字形码 / $变量。
class_name MesText
extends RefCounted

const END := 0x00
const NEWLINE := 0x0A
const VAR := 0x24       # '$'
const LEAD_MIN := 0x81  # 双字节字形的首字节下限
const NAME_OPEN := 0x8162
const NAME_CLOSE := 0x8163


## 解析一条记录 → {"speaker": [token...], "body": [token...]}。
## token: {"type":"newline"} | {"type":"ascii","ch":String} | {"type":"glyph","code":int} | {"type":"var","arg":int}
static func parse(rec: PackedByteArray) -> Dictionary:
	var i := 0
	var speaker: Array = []
	# 首行说话人名：0x8162 … 0x8163，随后 0x0A
	if rec.size() >= 2 and (rec[0] << 8 | rec[1]) == NAME_OPEN:
		i = 2
		while i + 1 < rec.size() and (rec[i] << 8 | rec[i + 1]) != NAME_CLOSE:
			speaker.append({"type": "glyph", "code": rec[i] << 8 | rec[i + 1]})
			i += 2
		i += 2  # 跳过 0x8163
		if i < rec.size() and rec[i] == NEWLINE:
			i += 1
	var body := _parse_run(rec, i)
	return {"speaker": speaker, "body": body}


static func _parse_run(rec: PackedByteArray, i: int) -> Array:
	var out: Array = []
	while i < rec.size():
		var b := rec[i]
		if b == END:
			break
		if b == NEWLINE:
			out.append({"type": "newline"})
			i += 1
		elif b == VAR:
			var arg := rec[i + 1] if i + 1 < rec.size() else 0
			out.append({"type": "var", "arg": arg})
			i += 2
		elif b >= LEAD_MIN and i + 1 < rec.size():
			out.append({"type": "glyph", "code": b << 8 | rec[i + 1]})
			i += 2
		else:
			out.append({"type": "ascii", "ch": char(b)})
			i += 1
	return out
