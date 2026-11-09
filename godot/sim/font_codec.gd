## 文本码值 → 字模图集索引（docs/07 §7.5：码值即 1.PAT/2.PAT 的字模索引）。
##
## ⚠ (hi,lo) → 字模索引 的精确公式尚未破解（doc 标「待考」：Shift-JIS 派生码 vs Big5 区位字库，
## 需一张映射）。当前占位返回未映射；对话窗对未映射字形画占位框。破解后只改本函数，UI 不动。
## 这正是「先建 UI 作验证台、再破码」的破解点：在对话窗渲染已知串，调本函数公式直到可读。
class_name FontCodec
extends RefCounted

const COLS := 64  # 字模图集每行字数（与 convert_font 一致）


## 码值 → {"atlas":"font1"|"font2", "col":int, "row":int}；未映射返回空字典。
static func glyph(code: int) -> Dictionary:
	return {}  # TODO(M5): 破解 (hi,lo)→字模索引 后在此实现


## 字模索引 → 图集格坐标（破解后渲染层用）。
static func atlas_cell(index: int) -> Dictionary:
	return {"col": index % COLS, "row": index / COLS}
