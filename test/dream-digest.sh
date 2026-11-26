#!/usr/bin/env bash
# Hermetic test for dream-digest.py: builds a fixture opencode.db (rollback
# journal) in a temp dir and checks the overview and session dump output.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/.config/opencode/skills/dream/dream-digest.py"
ROOT="$(mktemp -d /tmp/dream-digest.XXXXXX)"
trap 'chmod -R u+w "${ROOT}" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT

FIX="${ROOT}/fix"
BIG="${ROOT}/big"
mkdir -p "${FIX}" "${BIG}"
failures=0

ok() { echo "ok   ${1}"; }
fail() {
  echo "FAIL ${1}"
  failures=$((failures + 1))
}

# check NAME CONDITION-COMMAND...: ok when the command succeeds.
check() {
  local name="${1}"
  shift
  if "${@}"; then ok "${name}"; else fail "${name}"; fi
}

cat >"${ROOT}/build.py" <<'PY'
import json
import sqlite3
import sys
import time

path, big = sys.argv[1], len(sys.argv) > 2
now = int(time.time() * 1000)
DAY = 86400000
c = sqlite3.connect(path)
c.executescript("""
create table session_v2 (id text primary key, project_id text not null default 'p',
 workspace_id text, parent_id text, fork_session_id text, fork_boundary text,
 slug text not null default 's', directory text not null, path text, title text,
 version text not null default '1', share_url text, summary_additions integer,
 summary_deletions integer, summary_files integer, summary_diffs text, metadata text,
 cost real not null default 0, tokens_input integer not null default 0,
 tokens_output integer not null default 0, tokens_reasoning integer not null default 0,
 tokens_cache_read integer not null default 0, tokens_cache_write integer not null default 0,
 revert text, permission text, agent text, model text,
 time_created integer not null, time_updated integer not null, time_compacting integer,
 time_archived integer, time_suspended integer, resume_attempts integer not null default 0,
 time_idle integer, time_viewed integer, idle_outcome text, time_busy integer);
create table session_message (id text primary key, session_id text not null,
 type text not null, seq integer not null, time_created integer not null,
 time_updated integer not null, data text not null);
create table session_part (message_id text, session_id text, ordinal integer, type text,
 call_id text, time_created integer, time_updated integer, data text);
create table session (id text primary key, project_id text not null default 'p',
 parent_id text, slug text not null default 's', directory text not null,
 title text not null default '', version text not null default '1', share_url text,
 summary_additions integer, summary_deletions integer, summary_files integer,
 summary_diffs text, revert text, permission text, time_created integer not null,
 time_updated integer not null, time_compacting integer, time_archived integer,
 workspace_id text, path text, agent text, model text, cost real not null default 0,
 tokens_input integer not null default 0, tokens_output integer not null default 0,
 tokens_reasoning integer not null default 0, tokens_cache_read integer not null default 0,
 tokens_cache_write integer not null default 0, metadata text);
create table message (id text primary key, session_id text not null,
 time_created integer not null, time_updated integer not null, data text not null);
create table part (id text primary key, message_id text not null, session_id text not null,
 time_created integer not null, time_updated integer not null, data text not null);
""")

MODEL = json.dumps({"id": "claude-opus-5-5", "providerID": "x"})
_n = [0]


def nid():
    _n[0] += 1
    return "id%06d" % _n[0]


def v2(sid, parent, agent, cost, directory, created, title="t"):
    c.execute("insert into session_v2 (id,parent_id,agent,model,cost,tokens_input,"
              "tokens_output,tokens_cache_read,tokens_cache_write,title,directory,"
              "time_created,time_updated) values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
              (sid, parent, agent, MODEL, cost, 1000, 500, 4000, 100, title, directory,
               created, created))


def msg(sid, seq, typ, data, raw=None):
    c.execute("insert into session_message values (?,?,?,?,?,?,?)",
              (nid(), sid, typ, seq, now, now, raw if raw is not None else json.dumps(data)))


v2("ses_A", None, "build", 12.5, "/x/proj-a", now - DAY, "Main work")
msg("ses_A", 1, "user", {"text": "please render the report"})
msg("ses_A", 2, "assistant", {"content": [
    {"type": "text", "text": "ok"},
    {"type": "tool", "name": "skill", "state": {"status": "completed", "input": {"id": "html-report"}}},
    {"type": "tool", "name": "bash", "state": {"status": "error", "input": {"command": "x"},
                                               "error": "command exited 1"}},
    {"type": "tool", "name": "read", "state": {"status": "completed", "input": {}}},
]})
msg("ses_A", 3, "user", {"text": "no, I said use the template"})
msg("ses_A", 4, "synthetic", {"text": "no no no injected memory"})
msg("ses_A", 5, "compaction", {})
msg("ses_A", 6, "user", {"text": "wrong again, check the file"})
msg("ses_A", 7, "assistant", {"content": [
    {"type": "tool", "name": "bash", "state": {"status": "completed", "input": {"command": "ls"}}}]})
msg("ses_A", 8, "user", {}, raw="not json")
msg("ses_A", 9, "assistant", {"content": [
    {"type": "tool", "name": "glob", "state": {"status": "running"}},
    {"type": "tool", "name": "bash", "state": {"status": "completed", "input": {"command": "ls /tmp"}}}]})

v2("ses_B", "ses_A", "build-runner", 0.3, "/x/proj-a", now - DAY + 1000)
c.execute("update session_v2 set time_compacting=? where id='ses_B'", (now,))
msg("ses_B", 1, "user", {"text": "run the tests"})
msg("ses_B", 2, "user", {"text": "wrong again"})
msg("ses_B", 3, "user", {"text": "no"})

v2("ses_D", None, "build", 1.0, "/x/proj-d", now - DAY + 5000)
msg("ses_D", 1, "user", {"text": "look at the part rows"})
msg("ses_D", 2, "assistant", {"content": []})
msg("ses_D", 21, "user", {"text": ""})
msg("ses_D", 3, "assistant", {"content": [
    {"type": "tool", "id": "c2", "name": "edit", "state": {"status": "completed", "input": {"f": "a"}}},
    {"type": "tool", "id": "c4", "name": "write", "state": {"status": "running"}},
    {"type": "tool", "id": "c5", "name": "fetch", "state": {"status": "error", "input": {}, "error": "boom embedded"}},
    {"type": "tool", "id": "c6", "name": "store", "state": {"status": "completed", "input": {}}}]})
v2("ses_E", None, "scout", 0.1, "/x/proj-e", now - DAY + 6000)
msg("ses_E", 1, "assistant", {"content": [{"type": "text", "text": "only the assistant spoke"}]})
d_msgs = [r[0] for r in c.execute("select id from session_message where session_id='ses_D' "
                                  "and type='assistant' order by seq")]


def part(mid, ordinal, typ, cid, data):
    c.execute("insert into session_part values (?,?,?,?,?,?,?,?)",
              (mid, "ses_D", ordinal, typ, cid, now, now, json.dumps(data)))


part(d_msgs[0], 0, "text", None, {"type": "text", "text": "from parts"})
part(d_msgs[0], 1, "tool", "c1", {"type": "tool", "id": "c1", "name": "grep",
                                  "state": {"status": "completed", "input": {"pattern": "x"}}})
part(d_msgs[0], 2, "tool", "c3", {"type": "tool", "id": "c3", "name": "webfetch",
                                  "state": {"status": "error", "input": {}, "error": "timed out"}})
part(d_msgs[0], 4, "text", None, {"type": "text", "text": "second fragment"})
part(d_msgs[1], 1, "tool", "c4", {"type": "tool", "id": "c4", "name": "write",
                                  "state": {"status": "error", "input": {"f": "b"}, "error": "disk full"}})
part(d_msgs[1], 2, "tool", "c5", {"type": "tool", "id": "c5", "name": "fetch",
                                  "state": {"status": "completed", "input": {}}})
part(d_msgs[1], 3, "tool", "c6", {"type": "tool", "id": "c6", "name": "store",
                                  "state": {"status": "error", "input": {}, "error": "late part error"}})
part(d_msgs[1], 4, "tool", "c7", {"type": "tool", "id": "c7", "name": "probe", "state": {
    "status": "error", "input": {}, "error": "A" * 60 + ' password="leak1 leak2 ' + "B" * 400 + '"'}})
part(d_msgs[1], 5, "tool", "c8", {"type": "tool", "id": "c8", "name": "probe", "state": {
    "status": "error", "input": {}, "error": "A" * 60 + ' password="leak1 leak2 ' + "B" * 400 + '"'}})
part(d_msgs[0], 3, "reasoning", None, {"type": "reasoning", "text": "thinking"})
part(d_msgs[1], 0, "tool", "c2", {"type": "tool", "id": "c2", "name": "edit",
                                  "state": {"status": "completed", "input": {"f": "a"}}})

v2("ses_F", None, "plan", 0.2, "/x/proj-f", now - DAY + 7000)
msg("ses_F", 1, "user", {"text": "wrong again"})
for g in ("ses_G", "ses_H"):
    v2(g, "ses_A", "scout", 0.1, "/x/proj-a", now - DAY + 8000)
    msg(g, 1, "user", {"text": "delegated no brief about the module again"})

# Shared ids: present in both generations. V2 transcript wins; V1 is a fallback.
v2("ses_S", None, "plan", 0.4, "/x/proj-s", now - DAY + 9000)
v2("ses_T", None, "plan", 0.4, "/x/proj-t", now - DAY + 9500)
msg("ses_S", 1, "user", {"text": "no, dupturn only once"})
msg("ses_S", 2, "assistant", {"content": [
    {"type": "tool", "name": "dupool", "state": {"status": "error", "input": {}, "error": "dup err"}}]})
msg("ses_S", 3, "compaction", {})
SHARED = {"ses_S": ("no, dupturn only once", 1), "ses_T": ("fallback turn from v1", 0)}

v2("ses_OLD", None, "build", 99.0, "/x/old", now - 400 * DAY)
msg("ses_OLD", 1, "user", {"text": "no, I said old stuff"})

t = now - 2 * DAY
c.execute("insert into session (id,directory,title,time_created,time_updated,agent,model,cost,"
          "tokens_input,tokens_output,tokens_cache_read,tokens_cache_write) "
          "values ('ses_C','/x/proj-c','V1 ghp_abcdefghijklmnopqrstuvwxyz0123456789 work',?,?,'plan',?,2.0,10,10,10,10)", (t, t, MODEL))
for i, (role, parts) in enumerate([
    ("user", [{"type": "text", "text": "no, I said use the template"}]),
    ("user", [{"type": "text", "text": "my token is ghp_abcdefghijklmnopqrstuvwxyz0123456789 ok"}]),
    ("user", [{"type": "text", "text": "no, password=\"hunter2 is long \\\"esc\\\" tailword\" again"}]),
    ("user", [{"type": "text", "text": "wrong again"}]),
    ("user", [{"type": "text", "text": "no"}]),
    ("assistant", [{"type": "tool", "tool": "bash", "state": {"status": "completed", "input": {
        "command": "echo ghp_abcdefghijklmnopqrstuvwxyz0123456789; deploy password=\"multi word cmdsecret \\\"q\\\" cmdtail\" end", "password": "hunter2 is long"}}},
        {"type": "compaction"}, {"type": "compaction"}]),
    ("assistant", [{"type": "tool", "tool": "kv", "state": {"status": "completed", "input": {
        "ghp_abcdefghijklmnopqrstuvwxyz0123456789_key": 1, "api_token": ["listsecret1", {"n": "listsecret2"}],
        "secrets": {"a": "objsecret"}}}}]),
]):
    mid = nid()
    c.execute("insert into message values (?,?,?,?,?)",
              (mid, "ses_C", t + i, t + i, json.dumps({"role": role})))
    for p in parts:
        c.execute("insert into part values (?,?,?,?,?,?)",
                  (nid(), mid, "ses_C", t + i, t + i, json.dumps(p)))

for sid in ("ses_S", "ses_T"):
    c.execute("insert into session (id,directory,title,time_created,time_updated,agent,model,cost) "
              "values (?,?,?,?,?,'plan',?,0.4)", (sid, "/x/proj-" + sid[-1].lower(), "t", t, t, MODEL))
    mid = nid()
    c.execute("insert into message values (?,?,?,?,?)", (mid, sid, t, t, json.dumps({"role": "user"})))
    c.execute("insert into part values (?,?,?,?,?,?)", (nid(), mid, sid, t, t,
              json.dumps({"type": "text", "text": SHARED[sid][0]})))
    mid = nid()
    c.execute("insert into message values (?,?,?,?,?)", (mid, sid, t + 1, t + 1, json.dumps({"role": "assistant"})))
    for p in [{"type": "tool", "tool": "dupool", "state": {"status": "error", "input": {}, "error": "dup err"}},
              {"type": "compaction"}]:
        c.execute("insert into part values (?,?,?,?,?,?)", (nid(), mid, sid, t + 1, t + 1, json.dumps(p)))

if big:
    for i in range(500):
        sid = "ses_big%d" % i
        v2(sid, "ses_A" if i % 3 == 0 else None, "agent-number-%d" % (i % 40),
           i / 10, "/x/some-long-project-name-%d" % i, now - DAY, "a long title " * 10)
        msg(sid, 1, "user", {"text": "no, wrong again, repeat phrase number %d here" % (i % 50)})
        msg(sid, 2, "assistant", {"content": [
            {"type": "tool", "name": "tool%d" % (i % 30),
             "state": {"status": "error", "input": {}, "error": "boom %d " % i * 30}},
            {"type": "tool", "name": "skill", "state": {"status": "completed", "input": {"id": "skill-%d" % i}}}]})
        msg(sid, 3, "compaction", {})
c.commit()
PY

python3 "${ROOT}/build.py" "${FIX}/fixture.db"
python3 "${ROOT}/build.py" "${BIG}/fixture.db" big

digest() { DREAM_DB="${FIX}/fixture.db" python3 "${SCRIPT}" "${@}"; }

OUT="${ROOT}/overview.txt"
rc=0
digest --days 14 >"${OUT}" 2>"${ROOT}/err.txt" || rc=$?

test_overview_sections() {
  local h
  for h in "## Totals" "## Top sessions by cost" "## Subagents" "## Corrections and repeats" \
    "## Skills and commands" "## Tool errors" "## Compactions" "## Worth a closer look"; do
    grep -qF "${h}" "${OUT}" || return 1
  done
  local top a c
  top="$(sed -n '/## Top sessions by cost/,/^## Subagents/p' "${OUT}")"
  a="$(grep -n 'ses_A' <<<"${top}" | head -1 | cut -d: -f1)"
  c="$(grep -n 'ses_C' <<<"${top}" | head -1 | cut -d: -f1)"
  [ -n "${a}" ] && [ -n "${c}" ] && [ "${a}" -lt "${c}" ] || return 1
  sed -n '/## Subagents/,/^## Corrections/p' "${OUT}" | grep -q 'build-runner' || return 1
  sed -n '/## Skills and commands/,/^## Tool errors/p' "${OUT}" | grep -q 'html-report' || return 1
  ! grep -q 'ses_OLD' "${OUT}"
}
check overview_sections test_overview_sections

test_repeat_detected() {
  sed -n '/## Corrections and repeats/,/^## Skills/p' "${OUT}" |
    grep 'no, I said use the template' | grep 'ses_A' | grep -q 'ses_C'
}
check repeat_detected test_repeat_detected

assert_no_secret() {
  local text="${1}" w
  grep -qF '[redacted]' <<<"${text}" || return 1
  for w in listsecret1 listsecret2 objsecret leak1 leak2 ghp_abc hunter2 'is long' tailword cmdsecret cmdtail; do
    if grep -qF "${w}" <<<"${text}"; then
      echo "     leaked: ${w}"
      return 1
    fi
  done
}

test_secret_masked_overview() { assert_no_secret "$(digest --days 14)"; }
check secret_masked_overview test_secret_masked_overview

test_secret_masked_dump() {
  local out
  out="$(digest --session ses_C)"
  assert_no_secret "${out}" && grep -qF '"api_token": "[redacted]"' <<<"${out}" &&
    grep -qF '"[redacted]_key": 1' <<<"${out}" && grep -qF '"secrets": "[redacted]"' <<<"${out}"
}
check secret_masked_dump test_secret_masked_dump

test_secret_skill_dirs() {
  local home="${ROOT}/home" out
  mkdir -p "${home}/.config/opencode/skills/ghp_abcdefghijklmnopqrstuvwxyz0123456789"
  : >"${home}/.config/opencode/skills/ghp_abcdefghijklmnopqrstuvwxyz0123456789/SKILL.md"
  out="$(HOME="${home}" digest --days 14)" || return 1
  grep -qF 'no recorded load (scanned:' <<<"${out}" && grep -qF '[redacted]' <<<"${out}" &&
    ! grep -qF 'ghp_abc' <<<"${out}"
}
check secret_skill_dirs test_secret_skill_dirs

test_malformed_rows() {
  [ "${rc}" -eq 0 ] && grep -qF 'skipped rows: 1' "${OUT}"
}
check malformed_rows test_malformed_rows

test_empty_window() {
  local out
  out="$(digest --since 2099-01-01)" || return 1
  grep -qF 'No sessions in window' <<<"${out}"
}
check empty_window test_empty_window

test_size_cap() {
  local out n h
  out="$(DREAM_DB="${BIG}/fixture.db" python3 "${SCRIPT}" --days 14)" || return 1
  n="$(printf '%s\n' "${out}" | wc -c)"
  [ "${n}" -le 8192 ] && [ "${n}" -gt 500 ] || {
    echo "     (500 sessions: ${n} bytes)"
    return 1
  }
  for h in "## Totals" "## Top sessions by cost" "## Subagents" "## Corrections and repeats" \
    "## Skills and commands" "## Tool errors" "## Compactions" "## Worth a closer look"; do
    grep -qF "${h}" <<<"${out}" || return 1
  done
  [ "$(grep -c '^…([0-9]* more)$' <<<"${out}")" -ge 3 ] || return 1
  sed -n '/## Worth a closer look/,$p' <<<"${out}" | grep -q '^- ses_'
}
check size_cap test_size_cap

snapshot() {
  (cd "${FIX}" && find . -printf '%p %s %T@ %m\n' | sort && find . -type f -exec sha256sum {} + | sort) | sha256sum
}

test_readonly_untouched() {
  local before after
  before="$(snapshot)"
  digest --days 14 >/dev/null || return 1
  digest --session ses_A >/dev/null || return 1
  after="$(snapshot)"
  [ "${before}" = "${after}" ] || return 1
  chmod a-w "${FIX}" "${FIX}/fixture.db"
  local r=0
  digest --days 14 >/dev/null 2>&1 || r=$?
  chmod u+w "${FIX}" "${FIX}/fixture.db"
  [ "${r}" -eq 0 ] && [ "$(snapshot)" = "${before}" ]
}
check readonly_untouched test_readonly_untouched

test_session_dump() {
  local out
  out="$(digest --session ses_A)" || return 1
  grep -qF 'no, I said use the template' <<<"${out}" &&
    grep -qF 'wrong again, check the file' <<<"${out}" &&
    grep -qF 'bash — error: {"command": "x"}' <<<"${out}" &&
    grep -qF 'bash — ok: {"command": "ls"}' <<<"${out}" &&
    grep -qF 'bash — ok: {"command": "ls /tmp"}' <<<"${out}" &&
    grep -qF 'skill — ok: {"id": "html-report"}' <<<"${out}" &&
    grep -qF 'glob — pending' <<<"${out}" &&
    ! grep -qF 'glob — ok' <<<"${out}" &&
    ! grep -qF 'injected memory' <<<"${out}" &&
    [ "$(grep -c '^- [a-z]* — ' <<<"${out}")" -eq 6 ] &&
    [ "$(grep -c '^\[compaction\]$' <<<"${out}")" -eq 1 ]
}
check session_dump test_session_dump

# shellcheck disable=SC2016
# shellcheck disable=SC2016
test_v2_parts() {
  local out o
  out="$(digest --session ses_D)" || return 1
  [ "$(grep -c '^- [a-z]* — ' <<<"${out}")" -eq 8 ] &&
    grep -qF 'fetch — error' <<<"${out}" && grep -qF 'store — error' <<<"${out}" &&
    ! grep -qF 'fetch — ok' <<<"${out}" && ! grep -qF 'store — ok' <<<"${out}" &&
    grep -qF 'grep — ok: {"pattern": "x"}' <<<"${out}" &&
    grep -qF 'webfetch — error' <<<"${out}" &&
    grep -qF 'write — error: {"f": "b"}' <<<"${out}" &&
    ! grep -qF 'write — pending' <<<"${out}" &&
    [ "$(grep -c 'edit — ok' <<<"${out}")" -eq 1 ] &&
    grep -qF 'ASSISTANT: from parts second fragment' <<<"${out}" || return 1
  o="$(sed -n '/## Tool errors/,/^## Compactions/p' "${OUT}")"
  grep -qF '`webfetch`: 1' <<<"${o}" && grep -qF 'timed out' <<<"${o}" &&
    grep -qF '`write`: 1' <<<"${o}" && grep -qF 'disk full' <<<"${o}" &&
    grep -qF '`fetch`: 1' <<<"${o}" && grep -qF '`store`: 1' <<<"${o}" &&
    assert_no_secret "${o}"
}
check v2_parts test_v2_parts

# shellcheck disable=SC2016
test_overview_values() {
  grep -qF 'agent `build`: 2 sess, $13.50, in 2000, out 1000, cache-read 8000, cache-write 200' "${OUT}" || return 1
  local m c
  m="$(grep 'messages per session' "${OUT}")"
  grep -qF 'ses_A 3' <<<"${m}" && grep -qF 'ses_C 5' <<<"${m}" &&
    grep -qF 'ses_B 3' <<<"${m}" && grep -qF 'ses_D 2' <<<"${m}" &&
    grep -qF 'user messages: 18 across 10 sessions' "${OUT}" || return 1
  c="$(sed -n '/## Compactions/,/^## Worth/p' "${OUT}")"
  grep -qF 'ses_A: 1' <<<"${c}" && ! grep -qF 'ses_A: 1 (inferred)' <<<"${c}" && grep -qF 'ses_B: 1 (inferred)' <<<"${c}" && grep -qF 'ses_C: 2' <<<"${c}"
}
check overview_values test_overview_values

test_short_repeat() {
  local r
  r="$(sed -n '/## Corrections and repeats/,/^## Skills/p' "${OUT}")"
  grep '"wrong again" —' <<<"${r}" | grep 'ses_F' | grep -q 'ses_C' || return 1
  ! grep '"wrong again" —' <<<"${r}" | grep -q 'ses_B' || return 1
  ! grep -qF '"no" —' <<<"${r}"
}
check short_repeat test_short_repeat

# Delegation prompts in child sessions are not human corrections or repeats.
test_child_not_human() {
  local r
  r="$(sed -n '/## Corrections and repeats/,/^## Skills/p' "${OUT}")"
  ! grep -qF 'delegated no brief' <<<"${r}" || return 1
  ! grep -E 'ses_(B|G|H)' <<<"$(grep 'correction excerpts' -A99 <<<"${r}")" | grep -q . || return 1
  grep -qF 'user messages:' <<<"${r}" && grep -qF 'ses_G 1' <<<"${r}"
}
check child_not_human test_child_not_human

# Shared ids: each turn is counted and dumped once; V1 is only a fallback.
# shellcheck disable=SC2016
test_shared_ids() {
  local r d p
  r="$(sed -n '/## Corrections and repeats/,/^## Skills/p' "${OUT}")"
  grep -qF 'user messages: 18 across' <<<"${r}" || return 1
  [ "$(sed -n '/## Worth/,$p' "${OUT}" | grep -c 'ses_S .*1 corrections')" -eq 1 ] || return 1
  ! sed -n '/## Worth/,$p' "${OUT}" | grep 'ses_S' | grep -q '2 corrections' || return 1
  [ "$(sed -n '/## Tool errors/,/^## Compactions/p' "${OUT}" | grep -c '`dupool`: 2')" -eq 1 ] || return 1
  p="$(sed -n '/## Compactions/,/^## Worth/p' "${OUT}")"
  grep -qF 'ses_S: 1' <<<"${p}" && ! grep -qF 'ses_S: 2' <<<"${p}" || return 1
  d="$(digest --session ses_S)"
  [ "$(grep -c 'dupturn only once' <<<"${d}")" -eq 1 ] && [ "$(grep -c 'dupool' <<<"${d}")" -eq 1 ] &&
    [ "$(grep -c '^\[compaction\]$' <<<"${d}")" -eq 1 ] || return 1
  d="$(digest --session ses_T)"
  grep -qF 'fallback turn from v1' <<<"${d}" && [ "$(grep -c 'dupool' <<<"${d}")" -eq 1 ]
}
check shared_ids test_shared_ids

# Prefixed credential names are masked in both output modes.
test_prefixed_secrets() {
  python3 - "${ROOT}/pre.db" <<'PY'
import json, sqlite3, sys, time
now = int(time.time() * 1000)
c = sqlite3.connect(sys.argv[1])
c.executescript("""
create table session_v2 (id text, parent_id text, agent text, model text, cost real,
 tokens_input int, tokens_output int, tokens_cache_read int, tokens_cache_write int,
 title text, directory text, time_created int, time_compacting int);
create table session_message (id text, session_id text, type text, seq int, data text);""")
c.execute("insert into session_v2 values ('ses_P',null,'a','x',1,1,1,1,1,'t','/x/p',?,null)", (now,))
text = 'no, SERVICE_TOKEN=prefsecret1 and MY_API_KEY: prefsecret2 and DB_PASSWORD="pref secret3 x" again'
c.execute("insert into session_message values ('m1','ses_P','user',1,?)", (json.dumps({"text": text}),))
c.execute("insert into session_message values ('m2','ses_P','assistant',2,?)", (json.dumps({"content": [
    {"type": "tool", "name": "bash", "state": {"status": "error", "input": {"command": "SERVICE_TOKEN=prefsecret1 run"},
     "error": "MY_API_KEY: prefsecret2 DB_PASSWORD=\"pref secret3 x\""}}]}),))
c.commit()
PY
  local out w
  for out in "$(DREAM_DB="${ROOT}/pre.db" python3 "${SCRIPT}" --days 3)" \
    "$(DREAM_DB="${ROOT}/pre.db" python3 "${SCRIPT}" --session ses_P)"; do
    grep -qF '[redacted]' <<<"${out}" || return 1
    for w in prefsecret1 prefsecret2 'pref secret3'; do
      if grep -qF "${w}" <<<"${out}"; then
        echo "     leaked: ${w}"
        return 1
      fi
    done
  done
}
check prefixed_secrets test_prefixed_secrets

# WAL: a live writer holds committed but uncheckpointed rows. The digest sees
# them and changes no stored data (WAL -wal/-shm sidecars are allowed).
test_wal_readonly() {
  python3 - "${ROOT}/wal.db" "${SCRIPT}" <<'PY'
import hashlib, os, subprocess, sqlite3, sys, time
path, script = sys.argv[1:3]
now = int(time.time() * 1000)
w = sqlite3.connect(path)
w.execute("pragma journal_mode=wal")
w.execute("pragma wal_autocheckpoint=0")
w.executescript("""
create table session_v2 (id text, parent_id text, agent text, model text, cost real,
 tokens_input int, tokens_output int, tokens_cache_read int, tokens_cache_write int,
 title text, directory text, time_created int, time_compacting int);
create table session_message (id text, session_id text, type text, seq int, data text);""")
w.commit()
w.execute("pragma wal_checkpoint(truncate)")
w.execute("insert into session_v2 values ('ses_W',null,'a','x',1,1,1,1,1,'t','/x/w',?,null)", (now,))
w.execute("insert into session_message values ('m1','ses_W','user',1,'{\"text\": \"no, walrow\"}')")
w.commit()
assert os.path.getsize(path + "-wal") > 0

def content():
    r = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    h = hashlib.sha256("\n".join(r.iterdump()).encode()).hexdigest()
    r.close()
    return h

before = content()
env = dict(os.environ, DREAM_DB=path)
out = subprocess.run([sys.executable, script, "--days", "3"], env=env, capture_output=True, text=True)
assert out.returncode == 0 and "ses_W" in out.stdout and "walrow" in out.stdout, out
dump = subprocess.run([sys.executable, script, "--session", "ses_W"], env=env, capture_output=True, text=True)
assert "walrow" in dump.stdout, dump
assert content() == before
n = w.execute("select count(*) from session_v2").fetchone()[0]
assert n == 1
PY
}
check wal_readonly_data_unchanged test_wal_readonly

test_read_failures() {
  local r=0
  python3 -c "import sqlite3; sqlite3.connect('${ROOT}/empty.db').execute('create table t(x)')"
  DREAM_DB="${ROOT}/empty.db" python3 "${SCRIPT}" --days 3 >/dev/null 2>"${ROOT}/e.txt" || r=$?
  [ "${r}" -eq 1 ] && grep -qF 'no session' "${ROOT}/e.txt" || return 1
  python3 -c "
import sqlite3
c = sqlite3.connect('${ROOT}/bad.db')
c.execute('create table session_v2 (id text)')
c.execute('create table session_message (id text)')"
  r=0
  DREAM_DB="${ROOT}/bad.db" python3 "${SCRIPT}" --days 3 >/dev/null 2>"${ROOT}/e.txt" || r=$?
  [ "${r}" -eq 1 ] && grep -qF 'cannot read database' "${ROOT}/e.txt"
}
check read_failures test_read_failures

# A session row exists but the transcript tables of its generation are missing.
test_incomplete_schema() {
  python3 - "${ROOT}" <<'PY'
import sqlite3
import sys
import time

cols = ("(id text, parent_id text, agent text, model text, cost real, tokens_input int, "
        "tokens_output int, tokens_cache_read int, tokens_cache_write int, title text, "
        "directory text, time_created int, time_compacting int)")
row = ("('ses_X', null, 'a', null, 1, 1, 1, 1, 1, 't', '/x', %d, null)" % (time.time() * 1000))
root = sys.argv[1]
c = sqlite3.connect(root + "/v1only.db")
c.execute("create table session " + cols)
c.execute("insert into session values " + row)
c.commit()
c = sqlite3.connect(root + "/v2only.db")
c.execute("create table session_v2 " + cols)
c.execute("insert into session_v2 values " + row)
c.commit()
c = sqlite3.connect(root + "/v2nopart.db")
c.execute("create table session_v2 " + cols)
c.execute("insert into session_v2 values " + row)
c.execute("create table session_message (id text, session_id text, type text, seq int, data text)")
c.commit()
PY
  local db r mode
  for db in v1only v2only; do
    for mode in "--days 3" "--session ses_X"; do
      r=0
      # shellcheck disable=SC2086
      DREAM_DB="${ROOT}/${db}.db" python3 "${SCRIPT}" ${mode} >/dev/null 2>"${ROOT}/e.txt" || r=$?
      if [ "${r}" -ne 1 ] || ! grep -qF 'transcript table(s) missing' "${ROOT}/e.txt"; then
        echo "     ${db} ${mode}: exit ${r}"
        return 1
      fi
    done
  done
  # session_part is optional
  DREAM_DB="${ROOT}/v2nopart.db" python3 "${SCRIPT}" --days 3 >/dev/null
}
check incomplete_schema test_incomplete_schema

test_session_args_strict() {
  local r a
  for a in "--session ses_A --db x" "--session ses_A;rm" "--session foo" "--session ses_A --days 3" \
    "--session ses_A --session ses_A" "--sess ses_A" "--session=ses_A" "--session" \
    "--db  --days 3" "--since  "; do
    r=0
    # shellcheck disable=SC2086
    digest ${a} >/dev/null 2>&1 || r=$?
    [ "${r}" -eq 2 ] || {
      echo "     exit ${r} for: ${a}"
      return 1
    }
  done
  r=0
  digest --session $'ses_A\n' >/dev/null 2>&1 || r=$?
  [ "${r}" -eq 2 ] || return 1
  r=0
  digest --session ses_A '' >/dev/null 2>&1 || r=$?
  [ "${r}" -eq 2 ] || return 1
  r=0
  digest --days 3 --db '' >/dev/null 2>&1 || r=$?
  [ "${r}" -eq 2 ] || return 1
  r=0
  digest --session ses_ZZZ >"${ROOT}/zzz.txt" 2>&1 || r=$?
  [ "${r}" -eq 1 ] && grep -qF 'no such session' "${ROOT}/zzz.txt"
}
check session_args_strict test_session_args_strict

test_wiki_gate() {
  local g="${REPO}/.config/opencode/skills/dream/wiki-gate.sh" w="${ROOT}/wiki" rc
  rm -rf "${w}" "${ROOT}/wiki-remote.git"
  git init -q --bare "${ROOT}/wiki-remote.git" && git init -q "${w}" &&
    git -C "${w}" remote add origin "${ROOT}/wiki-remote.git" || return 1
  git -C "${w}" config user.email t@t
  git -C "${w}" config user.name t
  git -C "${w}" config push.autoSetupRemote true
  echo ok >"${w}/a.md"
  WIKI_DIR="${w}" bash "${g}" m a.md >/dev/null 2>&1 || return 1
  git -C "${w}" log --oneline | grep -q . || return 1
  printf 'SERVICE_TOKEN=abc\n' >"${w}/b.md"
  rc=0
  WIKI_DIR="${w}" bash "${g}" m2 b.md >"${ROOT}/gate.txt" 2>&1 || rc=$?
  [ "${rc}" -ne 0 ] && ! grep -q abc "${ROOT}/gate.txt" && grep -q 'b.md' "${ROOT}/gate.txt" &&
    [ -z "$(git -C "${w}" diff --cached --name-only)" ] && [ "$(git -C "${w}" rev-list --count HEAD)" = 1 ] || return 1
  rc=0
  WIKI_DIR="${ROOT}/nonexistent" bash "${g}" m3 b.md >/dev/null 2>&1 || rc=$?
  [ "${rc}" -ne 0 ]
}
check wiki_gate test_wiki_gate

test_wiki_gate_edges() {
  local g="${REPO}/.config/opencode/skills/dream/wiki-gate.sh" w="${ROOT}/wiki2" r="${ROOT}/wiki2-remote.git" rc before
  rm -rf "${w}" "${r}" "${ROOT}/fakebin"
  git init -q --bare "${r}" && git init -q "${w}" && git -C "${w}" remote add origin "${r}" || return 1
  git -C "${w}" config user.email t@t
  git -C "${w}" config user.name t
  git -C "${w}" config push.autoSetupRemote true
  echo base >"${w}/base.md"
  WIKI_DIR="${w}" bash "${g}" base base.md >/dev/null 2>&1 || return 1
  echo other >"${w}/other.md"
  git -C "${w}" add other.md
  echo page >"${w}/p.md"
  WIKI_DIR="${w}" bash "${g}" page p.md >/dev/null 2>&1 || return 1
  [ "$(git -C "${w}" show --name-only --format= HEAD)" = p.md ] &&
    [ "$(git -C "${w}" diff --cached --name-only)" = other.md ] || return 1
  git -C "${w}" reset -q other.md
  printf 'x\0\nSERVICE_TOKEN=x\n' >"${w}/bin.md"
  rc=0
  WIKI_DIR="${w}" bash "${g}" bin bin.md >/dev/null 2>&1 || rc=$?
  [ "${rc}" -ne 0 ] && [ -z "$(git -C "${w}" diff --cached --name-only)" ] || return 1
  before="$(git -C "${w}" rev-parse HEAD)"
  mkdir "${ROOT}/fakebin"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = diff ] && exit 1; done\nexec %s "$@"\n' "$(command -v git)" >"${ROOT}/fakebin/git"
  chmod +x "${ROOT}/fakebin/git"
  echo more >"${w}/m.md"
  rc=0
  PATH="${ROOT}/fakebin:${PATH}" WIKI_DIR="${w}" bash "${g}" m m.md >/dev/null 2>&1 || rc=$?
  [ "${rc}" -ne 0 ] && [ "$(git -C "${w}" rev-parse HEAD)" = "${before}" ] &&
    [ "$(git --git-dir="${r}" rev-parse HEAD)" = "${before}" ] &&
    [ -z "$(git -C "${w}" diff --cached --name-only)" ]
}
check wiki_gate_edges test_wiki_gate_edges

if [ "${failures}" -ne 0 ]; then
  echo "${failures} failure(s)"
  exit 1
fi
echo "all passed"
