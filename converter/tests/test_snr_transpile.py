"""SNR 转译器的不变量 / 契约校验测试。

多数测试要求原版档（KOUKAI2_DIR），与仓库其它「原版档层」测试同样 skip-if-missing。运行：

    KOUKAI2_DIR=/path/to/KOUKAI2 uv run pytest tests/test_snr_transpile.py -q
"""
import json
import os
import tempfile

import pytest

from koukai2 import snr_transpile as T

KDIR = os.environ.get('KOUKAI2_DIR')
pytestmark = pytest.mark.skipif(not KDIR, reason='set KOUKAI2_DIR to run')

SCHEMA_DIR = os.path.join(os.path.dirname(__file__), '..', 'schema')


@pytest.fixture(scope='module')
def out():
    d = tempfile.mkdtemp()
    cov = T.transpile(KDIR, d)
    return d, cov


def _load(d, *p):
    return json.load(open(os.path.join(d, *p), encoding='utf-8'))


# --- container / structure -------------------------------------------------
def test_container_offsets_relative_to_tableb(out):
    """The lowest entry offset == TableB size == bytecode start (the invariant
    that pins the offset base)."""
    for fn in T.SCEN:
        path = os.path.join(KDIR, fn + '.DAT')
        if not os.path.exists(path):
            continue
        _, sections = T.parse_dat(path)
        for sec in sections:
            lowest = min(off for _, off in sec['entries'])
            assert sec['tb'] + lowest == sec['code']


# --- text store ------------------------------------------------------------
def test_say_text_ids_resolve(out):
    d, _ = out
    for n in range(7):
        ev = os.path.join(d, 'events', f'snr{n}.json')
        if not os.path.exists(ev):
            continue
        text = _load(d, 'text', f'snr{n}.json')
        events = json.load(open(ev, encoding='utf-8'))
        for ch in events['chapters']:
            for cmd in ch['script']:
                if cmd.get('op') == 'say':
                    assert cmd['text'] in text, f'missing text {cmd["text"]}'


# --- control flow integrity ------------------------------------------------
def test_branch_and_jump_targets_exist(out):
    d, _ = out
    for n in range(7):
        ev = os.path.join(d, 'events', f'snr{n}.json')
        if not os.path.exists(ev):
            continue
        events = json.load(open(ev, encoding='utf-8'))
        for ch in events['chapters']:
            labels = {c['label'] for c in ch['script'] if 'label' in c}
            for cmd in ch['script']:
                if cmd.get('to') and not cmd.get('unresolved'):
                    assert cmd['to'] in labels, f"snr{n} c{ch['index']}: dangling {cmd['to']}"


def test_entry_labels_exist(out):
    d, _ = out
    for n in range(7):
        ev = os.path.join(d, 'events', f'snr{n}.json')
        if not os.path.exists(ev):
            continue
        events = json.load(open(ev, encoding='utf-8'))
        for ch in events['chapters']:
            labels = {c['label'] for c in ch['script'] if 'label' in c}
            for e in ch['entries']:
                assert e['label'] in labels


# --- triggers --------------------------------------------------------------
def test_trigger_events_resolve(out):
    d, _ = out
    triggers = _load(d, 'triggers', 'index.json')
    # build label set per (scenario, chapter)
    idx = {}
    for n in range(7):
        ev = os.path.join(d, 'events', f'snr{n}.json')
        if not os.path.exists(ev):
            continue
        events = json.load(open(ev, encoding='utf-8'))
        for ch in events['chapters']:
            idx[(n, ch['index'])] = {c['label'] for c in ch['script'] if 'label' in c}
    for t in triggers:
        # event ref form: snr{n}/c{chapter}/{label}
        _, ck, lab = t['event'].split('/')
        n = t['scenario']; chap = int(ck[1:])
        assert lab in idx[(n, chap)], f'bad trigger ref {t["event"]}'


def test_facility_codes_in_range(out):
    d, _ = out
    triggers = _load(d, 'triggers', 'index.json')
    for t in triggers:
        if t['type'] == 'facility':
            assert (0 <= t['facility_code'] <= 0x0B) or t['facility_code'] in (0x15, 0xff)
            assert t['port'] is not None
        else:
            assert t['stage'] is not None and t['port'] is None


# --- coverage sanity -------------------------------------------------------
def test_main_story_decodes_majority(out):
    """The main-story scenarios should decode most of their bytecode to typed
    commands (the rest is undecoded演出 logic, shipped as raw)."""
    _, cov = out
    for fn in ('SNR1', 'SNR2', 'SNR6'):
        assert cov[fn]['pct_decoded'] >= 60.0, (fn, cov[fn])


# --- JSON Schema contract --------------------------------------------------
def test_emitted_json_matches_schema(out):
    """每套产物都必须满足 converter/schema/*.json 数据契约（draft-07）。"""
    jsonschema = pytest.importorskip('jsonschema')
    d, _ = out

    def schema(name):
        return json.load(open(os.path.join(SCHEMA_DIR, name), encoding='utf-8'))

    events_schema = schema('events.schema.json')
    text_schema = schema('text.schema.json')
    triggers_schema = schema('triggers.schema.json')

    jsonschema.validate(_load(d, 'triggers', 'index.json'), triggers_schema)
    for n in range(7):
        ev = os.path.join(d, 'events', f'snr{n}.json')
        if not os.path.exists(ev):
            continue
        jsonschema.validate(json.load(open(ev, encoding='utf-8')), events_schema)
        jsonschema.validate(_load(d, 'text', f'snr{n}.json'), text_schema)
