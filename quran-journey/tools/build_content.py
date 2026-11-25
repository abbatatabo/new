#!/usr/bin/env python3
"""
The Quran Journey - content pipeline.

Builds the read-only, bundled offline database `app/assets/db/quran.db`
from verbatim, attributed source files in `content/sources/`.

Nothing in this script generates, rewrites or "corrects" Quran text,
translations or morphology. It only parses the source files, validates
their integrity and copies their content into SQLite tables. Every check
that fails aborts the build.

Usage:  python3 -I tools/build_content.py        (from quran-journey/)
"""
import hashlib
import json
import os
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "content", "sources")
OUT_DIR = os.path.join(ROOT, "app", "assets", "db")
OUT = os.path.join(OUT_DIR, "quran.db")
REPORT = os.path.join(ROOT, "content", "integrity-report.json")

EXPECTED_SURAHS = 114
EXPECTED_VERSES = 6236
# Canonical verse counts (Hafs 'an 'Asim, Kufan count) used as an independent
# cross-check against both Tanzil's text file and Tanzil's metadata file.
CANONICAL_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
    111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
    54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
    49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52,
    44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19,
    26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3,
    6, 3, 5, 4, 5, 6,
]

# Extended Buckwalter transliteration as used by the Quranic Arabic Corpus
# (http://corpus.quran.com/java/buckwalter.jsp). Used ONLY to display the
# corpus' roots and lemmas in Arabic script; it is a 1:1 character encoding.
BUCKWALTER = {
    "'": "ء", ">": "أ", "&": "ؤ", "<": "إ", "}": "ئ",
    "A": "ا", "b": "ب", "p": "ة", "t": "ت", "v": "ث",
    "j": "ج", "H": "ح", "x": "خ", "d": "د", "*": "ذ",
    "r": "ر", "z": "ز", "s": "س", "$": "ش", "S": "ص",
    "D": "ض", "T": "ط", "Z": "ظ", "E": "ع", "g": "غ",
    "_": "ـ", "f": "ف", "q": "ق", "k": "ك", "l": "ل",
    "m": "م", "n": "ن", "h": "ه", "w": "و", "Y": "ى",
    "y": "ي", "F": "ً", "N": "ٌ", "K": "ٍ", "a": "َ",
    "u": "ُ", "i": "ِ", "~": "ّ", "o": "ْ", "^": "ٓ",
    "#": "ٔ", "`": "ٰ", "{": "ٱ", ":": "ۜ", "@": "۟",
    '"': "۠", "[": "ۢ", ";": "ۣ", ",": "ۥ", ".": "ۦ",
    "!": "ۨ", "-": "۪", "+": "۫", "%": "۬", "]": "ۭ",
    " ": " ",  # one corpus form (37:130 <ilo yaAsiyna) contains a space
}

ARABIC_DIACRITICS = re.compile(
    "[ؐ-ًؚ-ٰٟۖ-ۭـ]"
)


def bw_to_ar(s):
    # The corpus suffixes homograph lemmas with a digit (e.g. maE2); that is a
    # disambiguation index, not part of the Arabic word.
    s = re.sub(r"\d+$", "", s)
    out = []
    for ch in s:
        if ch not in BUCKWALTER:
            raise ValueError(f"Unknown Buckwalter character {ch!r} in {s!r}")
        out.append(BUCKWALTER[ch])
    return "".join(out)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg):
    print("INTEGRITY FAILURE:", msg, file=sys.stderr)
    sys.exit(1)


def is_pause_mark_token(tok):
    """Tanzil's Uthmani text places waqf (pause) marks and the rub/sajdah
    signs as separate space-delimited tokens. They are not words."""
    return all(
        ("ۖ" <= c <= "ۭ") or c in "۞۩" for c in tok
    )


def search_normalise(text):
    """Search index only (never displayed): remove diacritics, unify alef
    and yaa forms so users can type plain Arabic."""
    t = ARABIC_DIACRITICS.sub("", text)
    t = t.replace("ٱ", "ا").replace("أ", "ا")
    t = t.replace("إ", "ا").replace("آ", "ا")
    t = t.replace("ى", "ي")
    return re.sub(r"\s+", " ", t).strip()


def main():
    report = {"generated_at": datetime.now(timezone.utc).isoformat(), "checks": []}

    def check(name, ok, detail=""):
        report["checks"].append({"check": name, "passed": bool(ok), "detail": detail})
        print(("PASS " if ok else "FAIL ") + name + (f" - {detail}" if detail else ""))
        if not ok:
            with open(REPORT, "w", encoding="utf-8") as f:
                json.dump(report, f, ensure_ascii=False, indent=2)
            fail(name + " " + detail)

    files = {
        "tanzil_uthmani": "quran-uthmani.xml",
        "tanzil_metadata": "quran-data.xml",
        "pickthall": "en.pickthall.xml",
        "yusufali": "en.yusufali.xml",
        "transliteration": "en.transliteration.xml",
        "qac_morphology": "qac-morphology-0.4.txt",
        "tanzil_simple_clean": "quran-simple-clean.xml",
    }
    hashes = {k: sha256(os.path.join(SRC, v)) for k, v in files.items()}
    report["source_sha256"] = hashes

    # ---------- Quran text ----------
    raw = open(os.path.join(SRC, files["tanzil_uthmani"]), encoding="utf-8").read()
    check("Tanzil copyright block present", "Tanzil Quran Text" in raw and "CHANGING IT IS NOT ALLOWED" in raw)
    m = re.search(r"Tanzil Quran Text \(([^)]*)\)", raw)
    tanzil_version = m.group(1) if m else "unknown"
    tanzil_header = raw[raw.index("<!--") + 4: raw.index("-->")].strip("\n")
    qroot = ET.fromstring(raw.encode("utf-8"))
    suras = qroot.findall("sura")
    check("114 surahs in Tanzil text", len(suras) == EXPECTED_SURAHS, str(len(suras)))

    verses = []  # (surah, ayah, text, bismillah)
    for s in suras:
        si = int(s.get("index"))
        ayas = s.findall("aya")
        for idx, a in enumerate(ayas, start=1):
            if int(a.get("index")) != idx:
                fail(f"Non-sequential aya numbering in surah {si} at {idx}")
            verses.append((si, idx, a.get("text"), a.get("bismillah")))
    check("6236 verses in Tanzil text", len(verses) == EXPECTED_VERSES, str(len(verses)))
    counts = [len(s.findall("aya")) for s in suras]
    check("Per-surah verse counts match canonical Hafs (Kufan) counts", counts == CANONICAL_COUNTS)
    check("Surah indexes are 1..114 in order", [int(s.get("index")) for s in suras] == list(range(1, 115)))
    check("No empty verse text", all(v[2] and v[2].strip() for v in verses))
    bism = [v[0] for v in verses if v[3]]
    check(
        "Bismillah attribute on verse 1 of every surah except 1 and 9",
        bism == [i for i in range(2, 115) if i != 9],
        f"{len(bism)} surahs",
    )

    # ---------- Simple-clean text (search index only, never displayed) ----------
    sc_raw = open(os.path.join(SRC, files["tanzil_simple_clean"]), encoding="utf-8").read()
    sc_root = ET.fromstring(sc_raw.encode("utf-8"))
    simple = [
        (int(su.get("index")), int(a.get("index")), a.get("text"))
        for su in sc_root.findall("sura") for a in su.findall("aya")
    ]
    check("Simple-clean text: 6236 verses aligned with Uthmani keys",
          [(x[0], x[1]) for x in simple] == [(v[0], v[1]) for v in verses])

    # ---------- Metadata ----------
    meta = ET.parse(os.path.join(SRC, files["tanzil_metadata"])).getroot()
    msuras = meta.find("suras").findall("sura")
    check("Metadata has 114 surahs", len(msuras) == 114)
    check("Metadata verse counts match text", [int(s.get("ayas")) for s in msuras] == counts)
    starts = [int(s.get("start")) for s in msuras]
    check("Metadata start offsets are cumulative", starts == [sum(counts[:i]) for i in range(114)])

    gidx = {}
    for i, (s, a, _, _) in enumerate(verses, start=1):
        gidx[(s, a)] = i

    def marks(tag):
        out = {}
        for el in meta.find(tag).findall(tag[:-1]):
            out[gidx[(int(el.get("sura")), int(el.get("aya")))]] = int(el.get("index"))
        return out

    juz_start = marks("juzs")
    page_start = marks("pages")
    check("30 juz markers", len(juz_start) == 30)
    check("604 page markers (Madinah mushaf)", len(page_start) == 604)
    sajdas = {}
    for el in meta.find("sajdas").findall("sajda"):
        sajdas[gidx[(int(el.get("sura")), int(el.get("aya")))]] = el.get("type")
    check("15 sajdah verses", len(sajdas) == 15)

    # ---------- Translations ----------
    def load_trans(key):
        txt = open(os.path.join(SRC, files[key]), encoding="utf-8").read()
        header = txt[txt.index("<!--") + 4: txt.index("-->")]
        # Tanzil translation headers contain "--" inside an XML comment, which
        # strict parsers reject; parse the body after the comment.
        r = ET.fromstring(txt[txt.index("-->") + 3:].encode("utf-8"))
        rows = []
        for s in r.findall("sura"):
            for a in s.findall("aya"):
                rows.append((int(s.get("index")), int(a.get("index")), a.get("text")))
        return header, rows

    translations = {}
    for key in ("pickthall", "yusufali", "transliteration"):
        header, rows = load_trans(key)
        check(f"{key}: 6236 verses", len(rows) == EXPECTED_VERSES, str(len(rows)))
        check(f"{key}: verse keys align with Quran text", [(r[0], r[1]) for r in rows] == [(v[0], v[1]) for v in verses])
        check(f"{key}: no empty verses", all(r[2] and r[2].strip() for r in rows))
        translations[key] = (header, rows)

    # ---------- Morphology (Quranic Arabic Corpus 0.4) ----------
    words = {}  # (s,a,w) -> list of segments
    qac_lines = 0
    with open(os.path.join(SRC, files["qac_morphology"]), encoding="utf-8") as f:
        qac_head = []
        for line in f:
            if line.startswith("#"):
                qac_head.append(line.rstrip("\n"))
                continue
            if not line.startswith("("):
                continue
            qac_lines += 1
            loc, form, tag, feats = line.rstrip("\n").split("\t")
            s, a, w, g = map(int, loc.strip("()").split(":"))
            words.setdefault((s, a, w), []).append((g, form, tag, feats))
    check("QAC copyright block present", any("Quranic Arabic Corpus" in h for h in qac_head))
    check("QAC has 128,219 segments (v0.4)", qac_lines == 128219, str(qac_lines))
    check("QAC has 77,429 words", len(words) == 77429, str(len(words)))

    # Align corpus words to Tanzil Uthmani word tokens.
    aligned_ok = 0
    misaligned = []
    word_rows = []
    for vid, (s, a, text, _) in enumerate(verses, start=1):
        toks = [t for t in text.split(" ") if t and not is_pause_mark_token(t)]
        n = 0
        while (s, a, n + 1) in words:
            n += 1
        if n != len(toks):
            misaligned.append(f"{s}:{a} corpus={n} tanzil={len(toks)}")
            toks = [None] * n
        else:
            aligned_ok += 1
        for w in range(1, n + 1):
            segs = sorted(words[(s, a, w)])
            root = lemma = None
            stem_pos = None
            for g, form, tag, feats in segs:
                parts = feats.split("|")
                if "STEM" in parts:
                    stem_pos = tag
                for p in parts:
                    if p.startswith("ROOT:"):
                        root = p[5:]
                    elif p.startswith("LEM:"):
                        lemma = p[4:]
            # Compact verbatim corpus rows, one segment per line: FORM<TAB>TAG<TAB>FEATURES
            seg_text = "\n".join(f"{form}\t{tag}\t{feats}" for g, form, tag, feats in segs)
            word_rows.append((
                vid, w, toks[w - 1],
                root, " ".join(bw_to_ar(c) for c in root) if root else None,
                lemma, bw_to_ar(lemma) if lemma else None,
                stem_pos, seg_text,
            ))
    report["word_alignment"] = {"aligned_verses": aligned_ok, "misaligned": misaligned}
    check(
        "Corpus word segmentation aligns with Tanzil tokens for >= 99% of verses",
        aligned_ok >= 0.99 * EXPECTED_VERSES,
        f"{aligned_ok}/{EXPECTED_VERSES} aligned; misaligned: {len(misaligned)}",
    )

    # ---------- Write database ----------
    os.makedirs(OUT_DIR, exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript(open(os.path.join(ROOT, "content", "schema", "quran_bundle.sql"), encoding="utf-8").read())

    content_version = datetime.now(timezone.utc).strftime("%Y%m%d")
    db.executemany("INSERT INTO meta(key,value) VALUES (?,?)", [
        ("schema_version", "1"),
        ("content_version", content_version),
        ("tanzil_version", tanzil_version),
        ("tanzil_copyright", tanzil_header),
        ("qac_copyright", "\n".join(qac_head)),
        ("verse_count", str(EXPECTED_VERSES)),
        ("source_sha256", json.dumps(hashes)),
    ])

    for i, s in enumerate(msuras):
        db.execute(
            "INSERT INTO surahs VALUES (?,?,?,?,?,?,?,?,?)",
            (int(s.get("index")), s.get("name"), s.get("tname"), s.get("ename"),
             s.get("type"), int(s.get("order")), int(s.get("ayas")),
             int(s.get("start")) + 1, int(s.get("rukus"))),
        )

    juz = page = 0
    for vid, (s, a, text, b) in enumerate(verses, start=1):
        juz = juz_start.get(vid, juz)
        page = page_start.get(vid, page)
        db.execute(
            "INSERT INTO verses VALUES (?,?,?,?,?,?,?,?,?)",
            # Index both the Uthmani and the standard (imla'i) spelling so
            # users can search with everyday Arabic spelling.
            (vid, s, a, text, b, juz, page, sajdas.get(vid),
             search_normalise(text) + "\n" + search_normalise(simple[vid - 1][2])),
        )

    sources = [
        ("tanzil-uthmani", "quran_text", "Tanzil Quran Text (Uthmani)", "Tanzil Project",
         tanzil_version, "https://tanzil.net/download/",
         "CC BY 3.0 with Tanzil terms: verbatim copies only, attribute Tanzil, link to tanzil.net",
         "source_verified", hashes["tanzil_uthmani"]),
        ("tanzil-simple-clean", "search_index", "Tanzil Quran Text (Simple Clean)", "Tanzil Project",
         "1.1", "https://tanzil.net/download/",
         "CC BY 3.0 with Tanzil terms. Used only to build the search index; never displayed.",
         "source_verified", hashes["tanzil_simple_clean"]),
        ("tanzil-metadata", "metadata", "Tanzil Quran Metadata", "Tanzil Project", "1.0",
         "https://tanzil.net/docs/Quran_Metadata", "CC BY 3.0", "source_verified", hashes["tanzil_metadata"]),
        ("en.pickthall", "translation", "The Meaning of the Glorious Koran",
         "Mohammed Marmaduke William Pickthall (1875-1936)", "1930 translation; Tanzil digital edition updated 2010-09-04",
         "https://tanzil.net/trans/en.pickthall",
         "Translation first published 1930; translator died 1936 - public domain in life+70 and US jurisdictions. Digital text from Tanzil.",
         "source_verified", hashes["pickthall"]),
        ("en.yusufali", "translation", "The Holy Qur'an: Text, Translation and Commentary",
         "Abdullah Yusuf Ali (1872-1953)", "1934-1938 original edition; Tanzil digital edition updated 2013-05-10",
         "https://tanzil.net/trans/en.yusufali",
         "Original 1934-38 translation; translator died 1953 - public domain in life+70 jurisdictions since 2024. Later revised editions (e.g. 1985+) are NOT this text. Digital text from Tanzil.",
         "source_verified", hashes["yusufali"]),
        ("en.transliteration", "transliteration", "English Transliteration", "Tanzil Project (contributors)",
         "Tanzil digital edition updated 2010-09-06", "https://tanzil.net/trans/en.transliteration",
         "Distributed by Tanzil for use with attribution", "source_verified", hashes["transliteration"]),
        ("qac-morphology", "morphology", "Quranic Arabic Corpus - Morphology", "Kais Dukes, University of Leeds",
         "0.4", "https://corpus.quran.com/",
         "GNU GPL with corpus terms: verbatim copies, attribute and link to corpus.quran.com. Obtained as a verbatim mirror (github.com/cltk/arabic_morphology_quranic-corpus); SHA-256 recorded.",
         "source_verified", hashes["qac_morphology"]),
    ]
    db.executemany("INSERT INTO sources VALUES (?,?,?,?,?,?,?,?,?)", sources)

    for tid, (key, code, name, translator, lang) in enumerate([
        ("pickthall", "en.pickthall", "Pickthall", "Mohammed Marmaduke William Pickthall", "en"),
        ("yusufali", "en.yusufali", "Yusuf Ali", "Abdullah Yusuf Ali", "en"),
        ("transliteration", "en.transliteration", "Transliteration", "Tanzil Project", "en-Latn"),
    ], start=1):
        kind = "transliteration" if key == "transliteration" else "translation"
        db.execute("INSERT INTO translations VALUES (?,?,?,?,?,?,?)", (tid, code, kind, name, translator, lang, code))
        db.executemany(
            "INSERT INTO translation_text VALUES (?,?,?)",
            [(tid, i, r[2]) for i, r in enumerate(translations[key][1], start=1)],
        )

    db.executemany("INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?)", word_rows)
    db.commit()

    # Round-trip verification: the stored Arabic must be byte-identical to source.
    stored = [r[0] for r in db.execute("SELECT text_uthmani FROM verses ORDER BY id")]
    check("Stored Arabic text is byte-identical to Tanzil source", stored == [v[2] for v in verses])
    digest = hashlib.sha256("\n".join(stored).encode("utf-8")).hexdigest()
    db.execute("INSERT INTO meta(key,value) VALUES ('arabic_text_sha256', ?)", (digest,))
    db.commit()
    db.execute("VACUUM")
    db.close()

    report["arabic_text_sha256"] = digest
    report["database"] = {"path": os.path.relpath(OUT, ROOT), "bytes": os.path.getsize(OUT)}
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"Wrote {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB); Arabic text sha256 {digest}")


if __name__ == "__main__":
    main()
