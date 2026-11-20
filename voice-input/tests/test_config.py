from voice_input.config import (
    apply_replacements,
    load_replacements,
    load_vocab,
)


def test_vocab_joins_terms_and_skips_comments(tmp_path):
    p = tmp_path / "vocab.txt"
    p.write_text("# terms\nOpenCode\n\nSOME/IP\n")
    assert load_vocab(p) == "OpenCode, SOME/IP."


def test_vocab_missing_file_is_empty(tmp_path):
    assert load_vocab(tmp_path / "nope.txt") == ""


def test_some_ip_variants_become_slash(tmp_path):
    p = tmp_path / "r.txt"
    p.write_text(r"\bSOME[\s,-]+IP\b => SOME/IP" + "\n")
    rules = load_replacements(p)
    for s in ["SOME IP", "SOME-IP", "SOME, IP"]:
        assert apply_replacements(f"the {s} proxy", rules) == (
            "the SOME/IP proxy"
        )


def test_bad_regex_line_is_skipped(tmp_path):
    p = tmp_path / "r.txt"
    p.write_text("([ => x\nfoo => bar\nno arrow here\n")
    rules = load_replacements(p)
    assert len(rules) == 1
    assert apply_replacements("  foo  baz ", rules) == "bar baz"


def test_bad_replacement_template_is_skipped(tmp_path):
    p = tmp_path / "r.txt"
    p.write_text(r"foo => \1" + "\n" + r"(?P<a>x) => \g<b>" + "\nbar => baz\n")
    rules = load_replacements(p)
    assert apply_replacements("foo x bar", rules) == "foo x baz"


def test_replacements_missing_file_is_empty(tmp_path):
    assert load_replacements(tmp_path / "nope.txt") == []
