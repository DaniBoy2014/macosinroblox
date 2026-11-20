"""Self-contained checks - no audio file and no model download needed.

    python tests/test_lyricsync.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lyricsync.align import align_reference, coverage
from lyricsync.audioutil import parse_sound_id
from lyricsync import luafmt, songs
from lyricsync.lines import LineOptions, group_words
from lyricsync.roblox import build_document, dumps
from lyricsync.transcribe import Word, _covered_seconds, _dedupe, _plausible, uncovered_spans


def words(spec):
    return [Word(start=s, end=e, text=t) for s, e, t in spec]


def test_parse_sound_id():
    assert parse_sound_id("6910191685") == 6910191685
    assert parse_sound_id("rbxassetid://6910191685") == 6910191685
    assert parse_sound_id("https://www.roblox.com/library/6910191685/Song") == 6910191685
    assert parse_sound_id("https://create.roblox.com/store/asset/6910191685") == 6910191685
    assert parse_sound_id(" 6910191685 ") == 6910191685
    assert parse_sound_id(6910191685) == 6910191685
    for bad in ("", "no digits here"):
        try:
            parse_sound_id(bad)
        except ValueError:
            continue
        raise AssertionError(f"{bad!r} should not parse")


def test_group_splits_on_silence():
    ws = words([
        (1.0, 1.4, "hold"), (1.4, 1.9, "the"), (1.9, 2.4, "line"),
        (6.0, 6.4, "until"), (6.4, 6.9, "the"), (6.9, 7.5, "morning"),
    ])
    lines = group_words(ws, LineOptions())
    assert len(lines) == 2, [l.text for l in lines]
    assert lines[0].text == "hold the line"
    assert lines[0].start == 1.0 and lines[1].end == 7.5


def test_group_respects_max_chars():
    ws = words([(i * 0.4, i * 0.4 + 0.35, "syllable") for i in range(12)])
    lines = group_words(ws, LineOptions(max_chars=30))
    assert len(lines) > 1
    assert all(len(l.text) <= 35 for l in lines), [len(l.text) for l in lines]


def test_document_shape_matches_roblox():
    lines = group_words(words([
        (1.067, 2.0, "first"), (2.0, 3.0, "line"),
        (5.397, 6.0, "second"), (6.0, 7.0, "line"),
    ]), LineOptions())
    doc = build_document(6910191685, lines, 59.488072562358279, written_by="EpicTitan100")

    assert doc["SoundId"] == 6910191685
    assert doc["Unsynced"] is False
    assert set(doc["Lyrics"][0]) == {"RightAligned", "Line", "Id", "TimeStart", "TimeEnd", "Adlibs"}
    assert [e["Id"] for e in doc["Lyrics"]] == ["L1", "L2", "CERTIFICATION"]
    assert all(e["Adlibs"] == [] for e in doc["Lyrics"])
    assert all(e["RightAligned"] is False for e in doc["Lyrics"])

    lyric_entries = doc["Lyrics"][:-1]
    for a, b in zip(lyric_entries, lyric_entries[1:]):
        assert a["TimeEnd"] == b["TimeStart"], "lines must be contiguous"

    cert = doc["Lyrics"][-1]
    assert cert["TimeStart"] == lyric_entries[-1]["TimeEnd"]
    assert cert["TimeEnd"] == 59.488072562358279, "certification ends at the raw track length"
    assert cert["Line"] == "Written By EpicTitan100\nSynced By @EpicTitan100"
    assert doc["Lyrics"][0]["TimeStart"] == 1.067


def test_certification_never_ends_before_it_starts():
    lines = group_words(words([(1.0, 1.5, "short"), (1.5, 2.0, "song")]), LineOptions())
    doc = build_document(1, lines, 1.0, written_by="Me")  # duration shorter than the lyrics
    cert = doc["Lyrics"][-1]
    assert cert["TimeEnd"] > cert["TimeStart"]


def test_alignment_uses_reference_text_and_audio_timing():
    ws = words([
        (1.0, 1.3, "rolling"), (1.3, 1.6, "throo"), (1.6, 2.0, "the"), (2.0, 2.6, "night"),
        (3.0, 3.4, "we"), (3.4, 3.8, "chase"), (3.8, 4.4, "shadows"),
    ])
    reference = ["Rolling through the night", "We chase shadows"]
    lines = align_reference(reference, ws, LineOptions())
    assert [l.text for l in lines] == reference          # spelling comes from the file
    assert abs(lines[0].start - 1.0) < 0.01              # timing comes from the audio
    assert abs(lines[1].end - 4.4) < 0.01
    assert coverage(reference, ws) > 0.7


def test_alignment_survives_a_line_whisper_missed():
    ws = words([(1.0, 1.4, "alpha"), (5.0, 5.4, "gamma")])
    lines = align_reference(["Alpha", "Beta unheard", "Gamma"], ws, LineOptions())
    assert len(lines) == 3
    assert lines[0].end <= lines[1].start <= lines[2].start


def test_json_is_compact_and_valid():
    lines = group_words(words([(0.5, 1.0, "hi"), (1.0, 1.5, "there")]), LineOptions())
    text = dumps(build_document(7, lines, 10.0, written_by="A"))
    assert ", " not in text and '": ' not in text, "should be compact like the in-game files"
    assert json.loads(text)["SoundId"] == 7


def test_offset_and_no_chain():
    lines = group_words(words([
        (1.0, 1.5, "one"), (1.5, 2.0, "two"),
        (4.0, 4.5, "three"), (4.5, 5.0, "four"),
    ]), LineOptions())
    shifted = build_document(1, lines, 30.0, written_by="A", offset=0.5)
    assert shifted["Lyrics"][0]["TimeStart"] == 1.5
    loose = build_document(1, lines, 30.0, written_by="A", chain=False)
    assert loose["Lyrics"][0]["TimeEnd"] == 2.0 < loose["Lyrics"][1]["TimeStart"]


def gapped_doc(threshold=6.0, **kw):
    lines = group_words(words([
        (1.0, 1.5, "alpha"), (1.5, 2.0, "one"),
        (3.0, 3.5, "alpha"), (3.5, 4.0, "two"),
        (40.0, 40.5, "beta"), (40.5, 41.0, "one"),
    ]), LineOptions())
    return build_document(1, lines, 60.0, written_by="Me", gap_threshold=threshold, **kw)


def test_gap_entries_are_numbered_by_position():
    ids = [e["Id"] for e in gapped_doc()["Lyrics"]]
    assert ids == ["L1", "L2", "GAP_3", "L3", "CERTIFICATION"], ids
    # the gap id carries its 1-based slot in the array, lyric numbering ignores it


def test_gap_entry_is_blank_and_covers_the_silence():
    entries = gapped_doc()["Lyrics"]
    gap = next(e for e in entries if e["Id"] == "GAP_3")
    assert gap["Line"] == ""
    assert gap["TimeStart"] == 4.0 and gap["TimeEnd"] == 40.0
    for a, b in zip(entries, entries[1:]):
        assert a["TimeEnd"] == b["TimeStart"], "gaps must not break the chain"


def test_gaps_can_be_disabled():
    ids = [e["Id"] for e in gapped_doc(threshold=0.0)["Lyrics"]]
    assert ids == ["L1", "L2", "L3", "CERTIFICATION"]


def test_short_breaks_do_not_become_gaps():
    assert not any(e["Id"].startswith("GAP_") for e in gapped_doc(threshold=45.0)["Lyrics"])


def test_lua_entry_matches_the_target_shape():
    doc = build_document(100847230469970, group_words(words([
        (0.695, 1.0, "first"), (1.0, 1.5, "line"),
    ]), LineOptions()), 219.51997916666667, written_by="HardestRaver", synced_by="You")
    text = luafmt.entry(doc)
    lines_out = text.splitlines()

    assert lines_out[0] == '	["100847230469970"] = {'
    assert lines_out[1] == "		SoundId = 100847230469970,"
    assert lines_out[2] == "		Unsynced = false,"
    assert lines_out[3] == "		Lyrics = {"
    assert lines_out[4] == '			{Line = "first line", TimeStart = 0.695, TimeEnd = 1.5, Id = "L1"},'
    assert lines_out[-2] == "		}"
    assert lines_out[-1] == "	},"
    assert "RightAligned" not in text and "Adlibs" not in text
    assert "219.51997916666667" in text, "the raw track length must survive"


def test_lua_escapes_the_certification_newline():
    doc = build_document(7, group_words(words([(0.5, 1.0, "hi"), (1.0, 1.5, "there")]), LineOptions()),
                         10.0, written_by="A", synced_by="B")
    rows = [l for l in luafmt.entry(doc).splitlines() if "CERTIFICATION" in l]
    assert len(rows) == 1, "the certification must stay on a single row"
    assert "\\n" in rows[0], "the newline must be written as a Lua escape"
    assert "Written By A" in rows[0] and "Synced By @B" in rows[0]


def test_lua_escapes_quotes_and_backslashes():
    assert luafmt.quote('say "hi"') == '"say \\"hi\\""'
    assert luafmt.quote("back\\slash") == '"back\\\\slash"'
    assert luafmt.quote("tab\there") == '"tab\\there"'


def test_lua_library_wraps_every_song():
    doc = build_document(5, group_words(words([(0.5, 1.0, "hi"), (1.0, 1.5, "there")]), LineOptions()),
                         10.0, written_by="A")
    text = luafmt.library([doc, doc])
    assert text.rstrip().endswith("}")
    assert text.count('["5"] = {') == 2
    assert "return {" in text
    assert luafmt.library([]).rstrip().endswith("return {}")


def test_slugify():
    assert songs.slugify("It's Raining! (Remix)") == "Its-Raining-Remix"
    assert songs.slugify("  my   song  ") == "my-song"
    assert songs.slugify("???") == "song"

def test_uncovered_spans_catches_a_dropped_ending():
    # words stop at 0:38 but the track runs to 1:10 - the exact failure we saw
    ws = words([(1.0, 1.5, "a"), (36.0, 38.0, "b")])
    spans = uncovered_spans(ws, 70.0, minimum=10.0)
    assert len(spans) == 2, spans
    hole, tail = spans
    assert hole == (1.5, 36.0)      # spans are the exact hole; padding is added when decoding
    assert tail == (38.0, 70.0)     # the dropped ending


def test_uncovered_spans_includes_a_late_start():
    assert uncovered_spans(words([(30.0, 31.0, "a")]), 40.0, minimum=10.0) == [(0.0, 30.0)]


def test_uncovered_spans_ignores_normal_breathing_room():
    ws = words([(1.0, 1.5, "a"), (4.0, 4.5, "b"), (7.0, 7.5, "c")])
    assert uncovered_spans(ws, 8.0, minimum=10.0) == []


def test_uncovered_spans_when_nothing_was_heard():
    assert uncovered_spans([], 60.0, minimum=10.0) == [(0.0, 60.0)]
    assert uncovered_spans([], 5.0, minimum=10.0) == []


def test_covered_seconds_merges_overlaps():
    assert abs(_covered_seconds(words([(0.0, 2.0, "a"), (1.0, 3.0, "b")])) - 3.0) < 1e-6
    assert abs(_covered_seconds(words([(0.0, 1.0, "a"), (5.0, 6.0, "b")])) - 2.0) < 1e-6


def test_dedupe_drops_a_word_heard_by_both_passes():
    ws = words([(10.0, 10.4, "tacos"), (10.05, 10.5, "Tacos"), (12.0, 12.4, "tacos")])
    kept = _dedupe(ws)
    assert len(kept) == 2, [w.text for w in kept]


class FakeSegment:
    def __init__(self, text, no_speech_prob=0.1, avg_logprob=-0.3):
        self.text = text
        self.no_speech_prob = no_speech_prob
        self.avg_logprob = avg_logprob


def test_rescue_rejects_whisper_filler():
    assert not _plausible(FakeSegment("Thanks for watching!"))
    assert not _plausible(FakeSegment(" you "))
    assert not _plausible(FakeSegment("..."))
    assert not _plausible(FakeSegment("real words", no_speech_prob=0.95))
    assert not _plausible(FakeSegment("real words", avg_logprob=-2.0))
    assert _plausible(FakeSegment("shell meat lettuce cheese"))


def simple_doc(sound_id=1, **kw):
    lines = group_words(words([(0.24, 1.0, "first"), (1.0, 2.12, "line")]), LineOptions())
    return build_document(sound_id, lines, 131.142857, written_by="Whisper", synced_by="Claude", **kw)


def test_lua_round_trips_through_the_parser():
    doc = simple_doc(9245470035)
    parsed = luafmt.parse(luafmt.entry(doc))
    assert len(parsed) == 1
    assert parsed[0] == doc, "a document must survive lua -> parse unchanged"


def test_lua_parses_a_whole_library_past_its_comments():
    a, b = simple_doc(1), simple_doc(2)
    parsed = luafmt.parse(luafmt.library([a, b]))
    assert [d["SoundId"] for d in parsed] == [1, 2]
    assert parsed[0] == a and parsed[1] == b


def test_lua_parse_restores_the_certification_newline():
    cert = luafmt.parse(luafmt.entry(simple_doc()))[0]["Lyrics"][-1]
    assert cert["Id"] == "CERTIFICATION"
    assert cert["Line"].count(chr(10)) == 1
    assert cert["Line"].startswith("Written By Whisper")


def test_lua_parse_survives_gaps_and_hand_edits():
    doc = simple_doc(7)
    text = luafmt.entry(doc).replace('Id = "L1"', 'Id = "L1", RightAligned = true')
    entry = luafmt.parse(text)[0]["Lyrics"][0]
    assert entry["RightAligned"] is True


def test_lua_parse_fills_in_missing_ids():
    text = '["5"] = { SoundId = 5, Lyrics = { {Line = "a", TimeStart = 0, TimeEnd = 1}, }}'
    assert luafmt.parse(text)[0]["Lyrics"][0]["Id"] == "L1"


def test_lua_parse_rejects_junk():
    for bad in ("", "return {}", "not lua at all"):
        try:
            luafmt.parse(bad)
        except ValueError:
            continue
        raise AssertionError(f"{bad!r} should not have parsed")


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failures = 0
    for test in tests:
        try:
            test()
            print(f"  PASS  {test.__name__}")
        except Exception as exc:
            failures += 1
            print(f"  FAIL  {test.__name__}: {exc.__class__.__name__}: {exc}")
    print(f"\n{len(tests) - failures}/{len(tests)} passed")
    sys.exit(1 if failures else 0)
