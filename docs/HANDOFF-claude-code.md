# HANDOFF → Claude Code (Godot remake): game text is fully decoded

This is a handoff from the Cowork-side RE work. **The game's Chinese text is now
fully decoded to Unicode**, offline, from the game files alone. Everything you need
to display dialog in the Godot remake is here. Read this, then integrate into the
converter at `~/code/my-koukai2`.

## TL;DR
- `tools/text_decode.py` + `tools/ocr_state/code_table.json` turn the game's custom
  2-byte text codes into Traditional Chinese (UTF-8).
- `dialog_text/*.txt` = the already-decoded corpus (6218 messages) for reference.
- The earlier doc claim "needs external Chinese system, can't decode from files" is
  **WRONG and retracted** — see docs 07 §7.5 / 08 §8.2.

## Where things are (paths on the Mac)
```
~/Documents/Claude/Projects/sea/koukai2-docs/
  tools/text_render.py        # MES code -> glyph bitmap (1.PAT/2.PAT); the font/index logic
  tools/text_decode.py        # MES code -> UTF-8 string (depends on code_table.json)
  tools/ocr_state/code_table.json   # AUTHORITATIVE 2-byte-code -> char map (2059 entries)
  tools/ocr_state/transcriptions.txt# raw OCR notes (code_table.json supersedes; has fixes)
  dialog_text/*.txt + README.md     # decoded corpus, format docs
  07-游戏内容与设计数据.md  (§7.5)   # full encoding write-up
  08-剧本对话与港口建筑.md  (§8.x)   # SNR script bytecode + dialog container
```
Game data dir (KOUKAI2): `~/Documents/Claude/Projects/sea/KOUKAI2/`

## The decode, in one screen
Text is a custom 2-byte code `(hi, lo)`, `hi ∈ 0x81..0xD8`.
1. **Glyph index** = routine reverse-engineered from `MAIN.EXE` image offset **0x4554**
   (implemented in `text_render.py::_glyph_index`). Per lead byte, `lo` falls in 4
   ranges (0x30-39 / 0x41-5A / 0x61-7A / 0x80-FD); each adds a base + `si=(hi-base)*0xBC`.
2. **Glyph bitmap** comes from the bundled fonts **1.PAT / 2.PAT**: 28-byte cells
   (16w×14h, 1bpp, MSB-first, big-endian rows), file is 512-byte sector aligned
   (18 glyphs ×28 = 504 + 8 pad per sector): `offset = (idx-1)*28 + ((idx-1)//18)*8`.
   Code→font: `0x8130..0xAF68`→1.PAT, `0xB030..0xD8C3`→2.PAT.
3. **Unicode** = OCR of those glyphs → `code_table.json`.

⚠️ **Bug lesson baked into the code (don't reintroduce):** the 2.PAT branch (hi≥0xB0)
MUST add `si` (disasm does `add ax,si`). An earlier version dropped it; every 2.PAT
glyph silently rendered the wrong character. Common chars are 1.PAT so it passed
eyeball checks — only *in-context* validation caught it. If you re-port the index
logic to another language, port `_glyph_index` verbatim and re-run the validation below.

## Container formats
| File(s) | Table | Records |
|---|---|---|
| `SNR0-6.MES` | BE32 offset table (size = first offset) | story lines |
| `MESSAGE.DAT`, `MENU.DAT` | BE16 offset table | system text / menus |
| `ITEM.MES` | NUL-separated | item descriptions |

Control codes in a record: `0x00` end, `0x0A` newline, `0x24 xx` variable
(`$n` player name, `$s` dynamic name, `$r..` port/region ref, `$d..` number).

## How to use it in the converter
`text_decode.py` is dependency-free (stdlib only) and loads the table relative to
itself. To integrate:
1. Copy `text_decode.py` and `ocr_state/code_table.json` into the converter package
   (keep the table next to it, or set the path). Add a thin wrapper that calls
   `decode(bytes)` / `dump_file(dir, name)`.
2. Emit Godot-friendly data: for each SNRn, write JSON `[{idx, text, lines:[...]}, …]`.
   Keep the `$n/$s/$r/$d` placeholders so Godot can substitute at runtime.
3. **Display options in Godot** (pick one):
   - *Modern font*: render the Unicode with any CJK font (easiest; loses pixel look).
   - *Pixel-faithful*: keep using the original bitmaps — reuse `text_render.py`'s
     `Font.glyph(hi,lo)` to bake a glyph atlas/`BitmapFont`, indexed by the 2-byte code.
     Then you don't even need Unicode at runtime, only for tooling/search.
4. Wire dialog to events: the SNR bytecode (`C0` open-window / `C8 nnnn` show MES line
   `nnnn` / `C7` wait, `CC nnnn` set portrait) is the playback layer — see doc 08 §8.1.
   The converter already has `snr.py` (census). Next step is an interpreter that walks
   the per-chapter event table and drives the dialog box.

## Validation (re-run after any change)
- Decode known plaintext (a port name, a menu pair, the shop greeting, a goods name) and compare with in-game screenshots.
- Render N random messages as **ground-truth bitmaps** with `text_render.py` and diff
  against `text_decode.py` output — they must agree char-for-char (this is how the
  2.PAT bug was found). Don't trust glyph-eyeballing alone; trust context + bitmap diff.

## Faithfulness notes (intentional)
The table maps each code to the glyph the game ACTUALLY shows, so a few 1994-port
quirks are preserved: e.g. `討閥` (the game's rendering of 討伐). Two special cases:
`A956` bundled glyph is a 餞-form but source word is 火焔 → mapped to **焰**;
`D8C6` has no bundled glyph (index past 2.PAT end) → **兒** (from 這兒/那兒 context).
