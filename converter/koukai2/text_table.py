"""通用大端偏移表文本容器解析（MESSAGE.DAT / MENU.DAT / SNRn.MES 共用）。

格式（自主逆向并对原档验证，见 docs/koukai2-docs/08 §8.2、05 §5.1）：
  表头：count 个 width 字节大端绝对偏移（自文件头起算，升序）；
        count = 第一个偏移 ÷ width（表本身占据 [0, 第一个偏移)）。
  正文：各条记录依偏移表切分，每条以 0x00 终止。
  width=2：MESSAGE.DAT(1022 条)、MENU.DAT(61 组)；width=4：SNRn.MES。

要点：MENU 的每条是「菜单组」，组内还含多个 0x00 分隔的标签，因此**必须按偏移表
切分记录、不能按 0x00 扫描**，否则会把一个菜单组拆成多条。本解析器只做结构化切分，
不解码自定义双字节字模编码（码表是 M5 的工作）。

flag 位说明：docs/05 提到部分大端偏移表（EVENT*/SNR*.DAT）最高字节带属性标志
（0x90/0xC0 等）。纯文本表（MESSAGE/MENU/*.MES）实测无此标志，故此处不做掩码；
带标志的事件表另行处理。
"""
from __future__ import annotations


class TextTableError(ValueError):
    pass


def parse_records(data: bytes, width: int = 2) -> list[bytes]:
    """按大端偏移表切分为各条记录的原始字节（剥除单个 0x00 终止符）。"""
    if width not in (2, 4):
        raise TextTableError(f"unsupported offset width {width}")
    if len(data) < width:
        raise TextTableError("file smaller than one offset entry")
    first = int.from_bytes(data[:width], "big")
    if first == 0 or first % width != 0:
        raise TextTableError(f"invalid table: first offset {first} not a positive multiple of {width}")
    if first > len(data):
        raise TextTableError("offset table extends past end of file")
    count = first // width
    offsets = [int.from_bytes(data[i * width : (i + 1) * width], "big") for i in range(count)]

    records: list[bytes] = []
    for i in range(count):
        start = offsets[i]
        end = offsets[i + 1] if i + 1 < count else len(data)
        if not (first <= start <= end <= len(data)):
            raise TextTableError(
                f"record {i}: offsets not monotonic/in range (start={start}, end={end}, len={len(data)})"
            )
        rec = data[start:end]
        if rec.endswith(b"\x00"):  # 剥除单个终止符；组内分隔符予以保留
            rec = rec[:-1]
        records.append(rec)
    return records


def to_json_obj(records: list[bytes]) -> list[str]:
    """转为 JSON 可序列化结构：每条记录的十六进制字符串（编码未解，保真不丢字节）。"""
    return [rec.hex() for rec in records]
