#!/usr/bin/env python3
"""SNR 事件转译器（大航海時代II → Godot 可直接消费的 JSON）。

读取原版 SNRn.DAT（剧本字节码）+ SNRn.MES（台词），产出三套**不依赖原版档**即可
载入的引擎原生数据（数据契约见 converter/schema/*.json、docs/koukai2-docs/09）：

  text/snr{n}.json      id -> 字符串          （台词；$n/$s/$r/$d 保留为占位符）
  events/snr{n}.json    chapters -> 带标签的命令表脚本（每章一段，多个入口标签）
  triggers/index.json   (scenario, chapter, port, facility) -> 事件标签

设计（见 OPCODES.md、docs/09）：
  * 每章一段脚本，含多个具名入口（每个触发器一个）。忠实做法：事件间共享代码、互相
    跳转，孤立每个事件会丢信息。
  * 置信、定长的操作码解码为有类型命令；不确定/变长的操作码经长度模型精确切分后原样
    保留为 {"op":"raw", ...}，绝不丢字节——日后逆向出语义再补，无需重新提取。

文本解码复用本包**已验证**的 text_decode（与逆向自带字库的码表一致，逐字校验 0 差异），
不再单独 vendor 一份 text_decode（见 docs/HANDOFF-claude-code.md）。

用法:
    python3 -m koukai2.snr_transpile /path/to/KOUKAI2 -o out/
    python3 -m koukai2.snr_transpile /path/to/KOUKAI2 -o out/ --preview
"""
import os, sys, json, struct, argparse

from . import text_decode  # 复用已验证的文本解码器（decode_file()）

# ---------------------------------------------------------------------------
# 剧本元数据（见 memory / doc 09）
# ---------------------------------------------------------------------------
SCEN = {  # file -> (scenario number, MES line count, home/anchor port id)
    'SNR0': (0, 192, None),   # 共通/序章  (scen field 0x0080)
    'SNR1': (1, 1176, 0),     # João  -> Lisbon (port 0)
    'SNR2': (2, 917, 1),
    'SNR3': (3, 532, 0x1d),
    'SNR4': (4, 234, 0x21),
    'SNR5': (5, 326, 8),
    'SNR6': (6, 926, 2),
}

FACILITY = {
    0: 'market', 1: 'tavern', 2: 'shipyard', 3: 'harbor', 4: 'inn',
    5: 'palace', 6: 'bank', 7: 'house', 8: 'item_shop', 9: 'guild',
    10: 'church', 11: 'fortune', 0x15: 'special_15', 0xff: 'default',
}

# ---------------------------------------------------------------------------
# Opcode length model — fully derived from the MAIN.EXE interpreter (see OPCODES.md).
# The VM dispatches by the opcode's top 2 bits into 4 groups; every group computes a
# fixed instruction length from the opcode bitfields (and, for group 3, a jump table).
# This makes decoding length-exact: no guessing, no resync.
#
#   group 0  0x00-0x3F  set/assign   len 3, or 4 when (BB!=2 & AA==0 & CC==3)
#   group 1  0x40-0x7F  arithmetic   len 3 always
#   group 2  0x80-0xBF  condition    len 4 if (BB==2 & CC!=2) else 5  (BB==3 invalid)
#   group 3  0xC0-0xFF  presentation per-opcode table below
#     where BB=(op>>4)&3, CC=(op>>2)&3, AA=op&3
# ---------------------------------------------------------------------------
# group-3 instruction lengths, index = op-0xC0 (traced from the 64-entry table @0x330E5)
GROUP3_LEN = [
    2,1,1,1,1,2,1,1,3,4,2,6,3,2,1,1,   # C0..CF
    5,2,1,1,3,1,1,1,1,1,1,1,5,1,1,1,   # D0..DF
    1,1,3,3,2,1,2,2,2,2,2,4,2,2,2,1,   # E0..EF
    1,1,1,1,2,1,1,1,1,3,4,2,3,1,3,1,   # F0..FF  (F4 sound=2; FE=jump, len 3)
]
# group-1 arithmetic op selected by (op & 0x23)
ARITH = {0x00: 'add', 0x01: 'sub', 0x02: 'mul', 0x03: 'div',
         0x20: 'or', 0x21: 'and', 0x22: 'shr', 0x23: 'shl'}


def instr_len(op, b, i):
    """Exact instruction byte length for the opcode at b[i]."""
    g = op >> 6
    if g == 0:
        BB, CC, AA = (op >> 4) & 3, (op >> 2) & 3, op & 3
        return 4 if (BB != 2 and AA == 0 and CC == 3) else 3
    if g == 1:
        return 3
    if g == 2:
        BB, CC = (op >> 4) & 3, (op >> 2) & 3
        if BB == 3:
            return 1          # invalid encoding -> engine skips 1
        return 4 if (BB == 2 and CC != 2) else 5
    return GROUP3_LEN[op - 0xC0]


def be16(b, o):
    return struct.unpack('>H', b[o:o + 2])[0]


def be32(b, o):
    return struct.unpack('>I', b[o:o + 4])[0]


# ---------------------------------------------------------------------------
# Container parse:  SNRn.DAT -> list of sections, each with TableA, TableB, code
# ---------------------------------------------------------------------------
def parse_dat(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'SNDT', 'bad magic'
    scen_field = be16(b, 4)
    secs, o = [], 0x10
    while True:
        v = be32(b, o); o += 4
        if v == 0xFFFFFFFF:
            break
        secs.append(v)
    ends = secs + [len(b)]
    out = []
    for i, s in enumerate(secs):
        seg = b[s:ends[i + 1]]
        p = 0
        tableA = []
        while be16(seg, p) != 0xFFFF:
            tableA.append(be16(seg, p)); p += 2
        p += 2
        tb = p                      # TableB start; ALL offsets are relative to here
        entries = []
        while be16(seg, p) != 0xFFFF:
            entries.append((be16(seg, p), be16(seg, p + 2))); p += 4
        p += 4
        out.append(dict(seg=seg, tableA=tableA, tb=tb, code=p, entries=entries))
    return scen_field, out


# ---------------------------------------------------------------------------
# Bytecode decode (length-exact model). Offsets in the stream are relative to `tb`.
# ---------------------------------------------------------------------------
def label(off):
    return f'L{off:04x}'


def decode_one(op, seg, i, ln, scen_n, mes_count):
    """Build a typed command for the opcode at seg[i] of byte length ln.
    Returns (command_dict, branch_target_rel_tb_or_None)."""
    g = op >> 6
    if g == 3:                                            # presentation
        if op == 0xC0:
            return {'op': 'window', 'arg': seg[i + 1]}, None
        if op == 0xC7:
            return {'op': 'wait'}, None
        if op == 0xC8:
            line = be16(seg, i + 1)
            if line >= mes_count:                          # out of range -> data/mis-decode
                return {'op': 'raw', 'code': '0xc8', 'bytes': list(seg[i:i + ln])}, None
            return {'op': 'say', 'text': f'snr{scen_n}/{line}'}, None
        if op == 0xCC:
            return {'op': 'portrait', 'kao': be16(seg, i + 1)}, None
        if op == 0xCD:                                     # portrait, face index from a var
            return {'op': 'portrait', 'from_var': seg[i + 1]}, None
        if op == 0xCA:                                     # play sound effect (id, gated by [0x3E4])
            return {'op': 'sound', 'id': seg[i + 1]}, None
        if op == 0xF4:                                     # play music (FMDRV overlay)
            return {'op': 'music', 'id': seg[i + 1]}, None
        if op in (0xDC, 0xD0):                             # dynamic game-data query -> var ($s/$r/$d)
            return {'op': 'query', 'code': f'0x{op:02x}',
                    'args': list(seg[i + 1:i + ln])}, None
        if op == 0xFE:
            return {'op': 'jump'}, be16(seg, i + 1)        # target filled by caller
        if op == 0xF2:
            return {'op': 'end'}, None                     # engine-verified terminal (returns 0)
        return {'op': 'raw', 'code': f'0x{op:02x}', 'bytes': list(seg[i:i + ln])}, None
    if g == 2:                                            # condition / branch
        BB, CC = (op >> 4) & 3, (op >> 2) & 3
        tgt = be16(seg, i + ln - 2)                        # target is always the last 2 bytes
        if BB == 2 and CC != 2:                            # single-flag AC/AD (engine-verified)
            return {'op': 'branch', 'if': 'set' if (op & 1) == 0 else 'clear',
                    'flag': seg[i + 1], 'to': None}, tgt
        # richer condition forms (two-flag / var compare) kept structured + raw operands
        return {'op': 'cond', 'code': f'0x{op:02x}',
                'args': list(seg[i + 1:i + ln - 2]), 'to': None}, tgt
    if g == 1:                                            # arithmetic
        return {'op': 'arith', 'fn': ARITH.get(op & 0x23, f'0x{op & 0x23:02x}'),
                'args': [seg[i + 1], seg[i + 2]]}, None
    # group 0: set / assign
    return {'op': 'set', 'code': f'0x{op:02x}', 'args': list(seg[i + 1:i + ln])}, None


def decode_section(sec, scen_n, mes_count):
    seg, tb, code, entries = sec['seg'], sec['tb'], sec['code'], sec['entries']
    n = len(seg)
    end_rel = n - tb
    entry_offsets = {off for _, off in entries}

    # ---- length-exact LINEAR decode + integrity split ----
    # The bytecode is laid out sequentially (scene after scene, each ending in F2 = end),
    # and the engine reaches later scenes by iterating the entry table — they're not all
    # jump targets — so a pure CFG walk under-covers. Linear decode with exact lengths
    # (F4 fixed) tiles the whole section; the rare data/padding spot between scenes can
    # desync a short run, so any jump/branch target that lands mid-instruction triggers an
    # integrity split, keeping every reference resolvable.
    instrs = []                # (offset_rel_tb, command_dict)
    targets = set()
    i = code
    while i < n:
        op = seg[i]
        ln = instr_len(op, seg, i)
        if i + ln > n:
            instrs.append((i - tb, {'op': 'raw', 'code': f'0x{op:02x}',
                                    'bytes': list(seg[i:n])}))
            break
        cmd, tgt = decode_one(op, seg, i, ln, scen_n, mes_count)
        if tgt is not None:
            cmd['to'] = label(tgt)
            if code - tb <= tgt < end_rel:
                targets.add(tgt)
            else:
                cmd['unresolved'] = True
        instrs.append((i - tb, cmd))
        i += ln

    referenced = set(targets) | entry_offsets
    start_set = {off for off, _ in instrs}
    bounds = [off for off, _ in instrs] + [end_rel]
    need_split = sorted(r for r in referenced
                        if r not in start_set and code - tb <= r < end_rel)
    if need_split:
        new = []
        for k, (off, cmd) in enumerate(instrs):
            nxt = bounds[k + 1]
            cuts = [r for r in need_split if off < r < nxt]
            if not cuts:
                new.append((off, cmd)); continue
            pts = [off] + cuts + [nxt]
            for a, b in zip(pts, pts[1:]):
                new.append((a, {'op': 'raw', 'code': f'0x{seg[tb + a]:02x}',
                                'bytes': list(seg[tb + a:tb + b])}))
        instrs = new
        start_set = {off for off, _ in instrs}
    referenced &= start_set

    # ---- build the script: inline label markers where referenced ----
    script = []
    ref_labels = {label(r) for r in referenced}
    for off, cmd in instrs:
        if off in referenced:
            script.append({'label': label(off)})
        if cmd.get('to') and not cmd.get('unresolved') and cmd['to'] not in ref_labels:
            cmd = dict(cmd); cmd['unresolved'] = True
        script.append(cmd)

    # ---- entries / triggers for this section ----
    entry_list = []
    for eid, off in entries:
        hi, lo = eid >> 8, eid & 0xff
        is_stage = hi >= 0xa0
        entry_list.append({
            'trigger_id': f'{eid:04x}',
            'label': label(off),
            'type': 'stage' if is_stage else 'facility',
            'port': None if is_stage else hi,
            'facility': FACILITY.get(lo, f'unknown_{lo:#04x}'),
            'facility_code': lo,
            'stage': hi if is_stage else None,
        })
    return script, entry_list


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def transpile(koukai2_dir, out_dir, preview=False, write_text=True):
    """转译全部剧本到 out_dir。write_text=False 时不写 text/（主管线已有列表式
    text/snr*.json，避免覆盖；say 的 id 'snrN/k' 以行下标解析即可）。返回覆盖率统计。"""
    os.makedirs(os.path.join(out_dir, 'events'), exist_ok=True)
    os.makedirs(os.path.join(out_dir, 'triggers'), exist_ok=True)
    if write_text:
        os.makedirs(os.path.join(out_dir, 'text'), exist_ok=True)

    triggers = []
    coverage = {}
    for fn, (scen_n, _scen_mes, home_port) in SCEN.items():
        dat = os.path.join(koukai2_dir, fn + '.DAT')
        mes = os.path.join(koukai2_dir, fn + '.MES')
        if not os.path.exists(dat) or not os.path.exists(mes):
            continue

        # ---- text store（复用已验证的 decode_file；行下标即 say 的 id 尾号）----
        lines = text_decode.decode_file(open(mes, 'rb').read(), fn + '.MES')
        mes_count = len(lines)
        if write_text:
            text = {f'snr{scen_n}/{k}': t for k, t in enumerate(lines)}
            json.dump(text, open(os.path.join(out_dir, 'text', f'snr{scen_n}.json'), 'w',
                                 encoding='utf-8'), ensure_ascii=False, indent=1)
        else:
            text = {f'snr{scen_n}/{k}': t for k, t in enumerate(lines)}  # preview 用

        # ---- events + triggers ----
        scen_field, sections = parse_dat(dat)
        chapters = []
        cov_total = cov_raw = 0
        preview_lines = []
        for si, sec in enumerate(sections):
            script, entries = decode_section(sec, scen_n, mes_count)
            chapters.append({'index': si, 'entries': entries, 'script': script})
            cov_total += len(sec['seg']) - sec['code']
            for c in script:
                if c.get('op') == 'raw':
                    cov_raw += len(c['bytes'])
            for e in entries:
                triggers.append({
                    'scenario': scen_n, 'chapter': si, 'home_port': home_port,
                    'type': e['type'], 'port': e['port'],
                    'facility': e['facility'], 'facility_code': e['facility_code'],
                    'stage': e['stage'],
                    'event': f'snr{scen_n}/c{si}/{e["label"]}',
                })
            if preview:
                preview_lines.append(f'==== chapter {si} ====')
                for cmd in script:
                    if 'label' in cmd:
                        preview_lines.append(f'{cmd["label"]}:')
                    elif cmd['op'] == 'say':
                        t = text.get(cmd['text'], '?').replace('\n', ' / ')
                        preview_lines.append(f'    say  «{t}»')
                    elif cmd['op'] == 'branch':
                        u = ' (extern)' if cmd.get('unresolved') else ''
                        preview_lines.append(f'    if flag#{cmd["flag"]} {cmd["if"]} -> {cmd["to"]}{u}')
                    elif cmd['op'] == 'cond':
                        u = ' (extern)' if cmd.get('unresolved') else ''
                        preview_lines.append(f'    cond {cmd["code"]} {cmd["args"]} -> {cmd["to"]}{u}')
                    elif cmd['op'] == 'jump':
                        u = ' (extern)' if cmd.get('unresolved') else ''
                        preview_lines.append(f'    jump -> {cmd["to"]}{u}')
                    elif cmd['op'] == 'sound':
                        preview_lines.append(f'    sound #{cmd["id"]}')
                    elif cmd['op'] == 'music':
                        preview_lines.append(f'    music #{cmd["id"]}')
                    elif cmd['op'] == 'query':
                        preview_lines.append(f'    query {cmd["code"]} {cmd["args"]}')
                    elif cmd['op'] == 'portrait' and 'from_var' in cmd:
                        preview_lines.append(f'    portrait <-var{cmd["from_var"]}')
                    elif cmd['op'] == 'arith':
                        preview_lines.append(f'    arith {cmd["fn"]} {cmd["args"]}')
                    elif cmd['op'] == 'set':
                        preview_lines.append(f'    set  {cmd["code"]} {cmd["args"]}')
                    elif cmd['op'] == 'raw':
                        preview_lines.append(f'    raw  {cmd["code"]} {" ".join(f"{x:02x}" for x in cmd["bytes"])}')
                    else:
                        preview_lines.append(f'    {cmd["op"]} {cmd.get("arg","") if "arg" in cmd else cmd.get("kao","")}')

        out = {'scenario': scen_n, 'scen_field': f'{scen_field:#06x}',
               'home_port': home_port, 'chapters': chapters}
        json.dump(out, open(os.path.join(out_dir, 'events', f'snr{scen_n}.json'), 'w',
                            encoding='utf-8'), ensure_ascii=False, indent=1)
        if preview:
            open(os.path.join(out_dir, 'events', f'snr{scen_n}.preview.txt'), 'w',
                 encoding='utf-8').write('\n'.join(preview_lines))

        coverage[fn] = dict(total_bytes=cov_total, raw_bytes=cov_raw,
                            decoded_bytes=cov_total - cov_raw,
                            pct_decoded=round(100 * (cov_total - cov_raw) / max(1, cov_total), 1))

    json.dump(triggers, open(os.path.join(out_dir, 'triggers', 'index.json'), 'w',
                             encoding='utf-8'), ensure_ascii=False, indent=1)
    return coverage


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('koukai2_dir')
    ap.add_argument('-o', '--out', default='out')
    ap.add_argument('--preview', action='store_true', help='also write human-readable *.preview.txt')
    a = ap.parse_args()
    cov = transpile(a.koukai2_dir, a.out, a.preview)
    print('decode coverage by bytecode bytes (decoded = dialogue+control; raw =演出/logic, shipped verbatim):')
    for fn, c in cov.items():
        print(f'  {fn}: {c["decoded_bytes"]:5d}/{c["total_bytes"]:5d} bytes decoded '
              f'({c["pct_decoded"]}%), {c["raw_bytes"]:5d} raw')
    print(f'-> wrote text/, events/, triggers/index.json to {a.out}/')


if __name__ == '__main__':
    main()
