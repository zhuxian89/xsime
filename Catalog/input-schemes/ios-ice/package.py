#!/usr/bin/env python3
"""Reproducible source-only Ice dictionary package for the existing iOS importer."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[3]
REVISION = "da1fbe602e38f26db846fa10120ee64c2b0324c0"
FILES = {
    "LICENSE": "f288702d2fa16d3cdf0035b15a9fcbc552cd88e7",
    "cn_dicts/8105.dict.yaml": "b2e80ec5231c972898e573b412f0378320b08adb",
    "cn_dicts/base.dict.yaml": "f1e253ea14ad035198f66b449c83217131184775",
    "cn_dicts/ext.dict.yaml": "77f2373efaed7fb6866db0f790288657036d5ec9",
    "cn_dicts/others.dict.yaml": "e300d40b1ccf91fc410be6ac8d008b9fc8f1ec9e",
}
NAME = "XSIME-Ice-Pinyin-9Key-20261028.zip"
SCHEMA = "xsime_ice"
DIGITS = str.maketrans("abcdefghijklmnopqrstuvwxyz", "22233344455566677778889999")


def schema(nine):
    sid = SCHEMA + ("_t9" if nine else "")
    alphabet = "abcdefghijklmnopqrstuvwxyz" + ("23456789" if nine else "")
    algebra = [r"derive/^(.*)$/\U$1/", "xlit/ABCDEFGHIJKLMNOPQRSTUVWXYZ/22233344455566677778889999/"] if nine else ["abbrev/^([a-z]).+$/$1/"]
    return f"""# XSIME mobile adaptation; upstream dictionary bodies and weights unchanged.
schema:
  schema_id: {sid}
  name: 雾凇拼音 · {'九宫格' if nine else '全拼'}
  version: '2026.10.28'
  dependencies: {json.dumps([] if nine else [SCHEMA + '_t9'])}
switches:
  - name: ascii_mode
    reset: 0
    states: [中文, English]
engine:
  processors: [ascii_composer, speller, punctuator, selector, navigator, express_editor]
  segmentors: [ascii_segmentor, abc_segmentor, punct_segmentor, fallback_segmentor]
  translators: [punct_translator, script_translator]
speller:
  alphabet: {alphabet}
  initials: {alphabet}
  delimiter: " '"
  algebra: {json.dumps(algebra)}
translator:
  dictionary: {SCHEMA}
  user_dict: {SCHEMA}
  prism: {sid}
  enable_user_dict: true
  enable_sentence: true
  enable_completion: true
  spelling_hints: {99 if nine else 0}
  always_show_comments: {'true' if nine else 'false'}
  preedit_format: []
menu:
  page_size: 9
punctuator:
  half_shape:
    ',': '，'
    '.': '。'
    '?': '？'
    '!': '！'
    ':': '：'
    ';': '；'
"""


def build(output, cache):
    output.mkdir(parents=True, exist_ok=True)
    contents, counts, sources = {}, {}, {}
    for name, expected in FILES.items():
        local = cache / name
        if not local.exists():
            local.parent.mkdir(parents=True, exist_ok=True)
            url = f"https://raw.githubusercontent.com/iDvel/rime-ice/{REVISION}/{name}"
            with urllib.request.urlopen(url, timeout=90) as response:
                data = response.read()
        else:
            data = local.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != expected:
            raise ValueError(f"Upstream checksum mismatch: {name}")
        local.write_bytes(data)
        sources[name] = {"gitBlob": actual, "sha256": hashlib.sha256(data).hexdigest()}
        if name == "LICENSE":
            contents["LICENSE.txt"] = data
        else:
            # Flatten names for compatibility with older importers too. Preserve
            # every dictionary entry, weight, attribution comment and source URL.
            short = Path(name).name.removesuffix(".dict.yaml")
            text = re.sub(r"(?m)^name: .+$", "name: ice_" + short, data.decode(), count=1)
            contents["ice_" + short + ".dict.yaml"] = text.encode()
            body = text.split("\n...", 1)[1]
            counts[short] = sum(bool(line.strip()) and not line.startswith("#") for line in body.splitlines())
    contents[SCHEMA + ".dict.yaml"] = ("---\nname: " + SCHEMA + "\nversion: '2026.10.28'\nsort: by_weight\nuse_preset_vocabulary: false\nimport_tables: [ice_8105, ice_base, ice_ext, ice_others]\n...\n").encode()
    for nine in (False, True):
        contents[SCHEMA + ("_t9" if nine else "") + ".schema.yaml"] = schema(nine).encode()
    contents["default.yaml"] = b"config_version: '1'\nmenu:\n  page_size: 9\n"
    contents["README.txt"] = ("XSIME 雾凇词库：全拼 / 九宫格\n\n"
        "来源：https://github.com/iDvel/rime-ice/tree/" + REVISION + "\n"
        "使用 8105 字表、base、ext、others；保留原始词条、词频与来源说明。\n"
        "适配：独立移动方案与九宫格编码；未包含上游完整 Lua、英语、腾讯大词库或语言模型。\n"
        "授权见 LICENSE.txt，字典内保留各数据来源说明。包内包含完整可编辑源数据。\n\n"
        "导入：XSIME → Rime 方案包与导入 → 添加方案或文本词库 → 选择整个 ZIP（不用解压）。\n"
        "部署并启用“雾凇拼音 · 九宫格”；保持 App 在前台直到部署完成，再切回键盘。\n"
        "也可启用全拼后，在键盘“键位布局”中选择“9 键 · 全拼”。\n"
        "仅添加文件不会切换方案；停用后可恢复内置。两个布局共用此方案的学习库。\n"
        "这是独立方案，不合并或删除原内置方案的学习词。此包是固定快照，不会自动更新热词。\n"
        "词条覆盖增加不保证每个词都为首选；iOS 17 真机的内存、速度与候选体验仍需实际确认。\n").encode()
    metadata = {"upstream": "iDvel/rime-ice", "revision": REVISION, "entriesByTable": counts,
                "totalEntries": sum(counts.values()), "sources": sources}
    contents["SOURCE.txt"] = (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode()
    archive = output / NAME
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo(name, (2026, 10, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, data)
    metadata["archiveSHA256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
    metadata["archiveBytes"] = archive.stat().st_size
    (output / "source.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    (output / (NAME + ".sha256")).write_text(metadata["archiveSHA256"] + "  " + NAME + "\n")
    (output / "导入说明.txt").write_bytes(contents["README.txt"])
    print(json.dumps(metadata, ensure_ascii=False), flush=True)
    return archive


def verify(output):
    # CI only: exercise the unmodified Swift importer and the actual iOS engine
    # host slice, not a replacement implementation of either component.
    sys.path.insert(0, str(ROOT / "scripts/input-schemes"))
    import scheme_build as checks
    work = output / "checks"
    work.mkdir(exist_ok=True)
    source = checks.importer_source(None)
    harness = checks.importer_harness(work, source)
    probe = checks.host_probe(work)
    cases = [("nihao", "你好"), ("weixin", "微信"), ("douyin", "抖音"),
             ("xiaohongshu", "小红书"), ("dazi", "搭子"), ("wanan", "晚安")]
    probes = [{"schema": SCHEMA + ("_t9" if nine else ""),
               "keys": keys.translate(DIGITS) if nine else keys, "expect": word}
              for nine in (False, True) for keys, word in cases]
    # verify_one expects an archive below packages/. Keep the delivered archive
    # separate from mutable deployment outputs.
    (work / "packages").mkdir(exist_ok=True)
    (work / "packages" / NAME).write_bytes((output / NAME).read_bytes())
    report = checks.verify_one({"archive": NAME, "recommended": [SCHEMA, SCHEMA + "_t9"]},
                              {"probes": probes}, harness, probe, work, 900)
    report["importerSHA256"] = hashlib.sha256(source).hexdigest()
    report["archiveSHA256"] = hashlib.sha256((output / NAME).read_bytes()).hexdigest()
    report["scope"] = "CI host importer and iOS engine; not iOS 17 physical-device acceptance"
    (output / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False), flush=True)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    build(args.output.resolve(), args.cache.resolve())
    if args.verify:
        verify(args.output.resolve())
