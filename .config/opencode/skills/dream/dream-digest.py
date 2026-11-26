#!/usr/bin/env python3
"""Read-only digest of OpenCode sessions for /dream.

  dream-digest.py [--db PATH] (--days N | --since YYYY-MM-DD)   overview
  dream-digest.py --session ses_<id>                            one session

Opens the database only with mode=ro. Never writes, no network.
"""
import argparse
import collections
import datetime
import json
import os
import re
import sqlite3
import sys
import time
from urllib.parse import quote

DEFAULT_DB = "~/.local/share/opencode/opencode.db"
SESSION_RE = re.compile(r"^ses_[A-Za-z0-9]+$")
CUES = re.compile(r"\b(no|not|again|wrong|i said|instead|don'?t)\b", re.I)
SECRETS = [
    re.compile(r"-----BEGIN [A-Z ]*KEY-----(?:.*?-----END [A-Z ]*KEY-----)?", re.S),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{10,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{10,}"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{10,}"),
    re.compile(r"\bxox[bp]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\bAKIA[A-Z0-9]{12,}"),
]
SECRET_WORDS = r"password|passwd|token|secret|api[_-]?key"
KV_SECRET = re.compile(
    r"(?i)\b([A-Za-z0-9_]*(?:" + SECRET_WORDS + r"))([\\\"']{0,2}\s*[=:]\s*)"
    r"(\\?\"(?:[^\"\\]|\\.)*\\?\"|\\?'(?:[^'\\]|\\.)*\\?'|\S+)")
SECRET_KEY = re.compile(r"(?i)" + SECRET_WORDS)


def open_ro(path):
    # mode=ro: no stored data is ever changed. SQLite may still create its
    # WAL bookkeeping files (-wal/-shm) next to a WAL-mode database; that is allowed.
    path = os.path.abspath(os.path.expanduser(path))
    return sqlite3.connect("file:%s?mode=ro" % quote(path), uri=True)


def mask(text):
    text = str(text)
    for rx in SECRETS:
        text = rx.sub("[redacted]", text)
    return KV_SECRET.sub(lambda m: m.group(1) + m.group(2) + "[redacted]", text)


def mask_obj(obj):
    """Mask every string inside a structure before it is serialized."""
    if isinstance(obj, str):
        return mask(obj)
    if isinstance(obj, list):
        return [mask_obj(x) for x in obj]
    if isinstance(obj, dict):
        return {mask(k): "[redacted]" if SECRET_KEY.search(str(k)) else mask_obj(v)
                for k, v in obj.items()}
    return obj


def short(text, n):
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def clean(text, n):
    """Mask first, then truncate, so a cut can never expose part of a secret."""
    return short(mask(text), n)


def model_name(raw):
    if not raw:
        return "?"
    try:
        j = json.loads(raw)
        if isinstance(j, dict):
            return str(j.get("id") or j.get("modelID") or "?")
    except (ValueError, TypeError):
        pass
    return str(raw)


def table_names(conn):
    return {r[0] for r in conn.execute("select name from sqlite_master where type='table'")}


def load_sessions(conn, since_ms):
    tables = table_names(conn)
    present = [t for t in ("session", "session_v2") if t in tables]
    if not present:
        raise sqlite3.DatabaseError("no session or session_v2 table found")
    out = {}
    for table in present:
        rows = conn.execute(
            "select id,parent_id,agent,model,cost,tokens_input,tokens_output,"
            "tokens_cache_read,tokens_cache_write,title,directory,time_created,time_compacting "
            "from %s where time_created >= ?" % table, (since_ms,)).fetchall()
        for r in rows:
            gens = out[r[0]]["gens"] if r[0] in out else set()
            out[r[0]] = {
                "id": r[0], "parent": r[1], "agent": r[2] or "?", "model": model_name(r[3]),
                "cost": r[4] or 0.0, "tokens": (r[5] or 0, r[6] or 0, r[8] or 0),
                "cache_read": r[7] or 0, "title": r[9] or "", "directory": r[10] or "",
                "created": r[11] or 0, "compacting": bool(r[12]),
                "gens": gens | {table},
            }
    return sorted(out.values(), key=lambda s: s["created"])


def require_transcripts(conn, sessions):
    tables = table_names(conn)
    need = {"session": ("message", "part"), "session_v2": ("session_message",)}
    for gen in sorted({g for s in sessions for g in s["gens"]}):
        missing = [t for t in need[gen] if t not in tables]
        if missing:
            raise sqlite3.DatabaseError(
                "table %s has sessions but transcript table(s) missing: %s" % (gen, ", ".join(missing)))


def chunks(seq, n=400):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def jload(raw):
    j = json.loads(raw)
    if not isinstance(j, dict):
        raise ValueError("not an object")
    return j


def new_msg(role, text="", compactions=0):
    return {"role": role, "text": text, "tools": [], "compactions": compactions}


def tool_entry(name, state):
    """(name, status, input, error); None only when there is no state object."""
    if not isinstance(state, dict):
        return None
    status = str(state.get("status") or "pending")
    err = ""
    if status == "error":
        err = str(state.get("error") or state.get("message") or "")
    return (str(name or "?"), status, state.get("input"), err)


def rank(status):
    return {"error": 2, "completed": 1}.get(status, 0)


def merge_tool(old, new):
    base, other = (new, old) if rank(new[1]) > rank(old[1]) else (old, new)
    err = base[3]
    if base[1] == "error" and not err and other[1] == "error":
        err = other[3]
    return (base[0], base[1], base[2] if base[2] is not None else other[2], err)


def load_v2(conn, chunk, msgs, has_parts):
    skipped = 0
    q = ",".join("?" * len(chunk))
    by_id, calls = {}, {}
    rows = conn.execute(
        "select id,session_id,type,data from session_message where session_id in (%s) "
        "order by session_id,seq" % q, chunk).fetchall()
    for mid, sid, typ, raw in rows:
        if typ not in ("user", "assistant", "compaction"):
            continue
        try:
            d = jload(raw)
            if typ == "user":
                if not isinstance(d.get("text"), str):
                    raise ValueError("no text")
                m = new_msg("user", d["text"])
            elif typ == "assistant":
                content = d["content"]
                if not isinstance(content, list):
                    raise ValueError("no content")
                m = new_msg("assistant")
                text = []
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") == "text":
                        text.append(str(item.get("text") or ""))
                    elif item.get("type") == "tool":
                        t = tool_entry(item.get("name"), item.get("state"))
                        if t is None:
                            skipped += 1
                            continue
                        m["tools"].append(t)
                        if item.get("id"):
                            calls[(sid, str(item["id"]))] = (m, len(m["tools"]) - 1)
                m["text"] = " ".join(text)
            else:
                m = new_msg("compaction", compactions=1)
        except (ValueError, KeyError, TypeError):
            skipped += 1
            continue
        by_id[mid] = m
        msgs[sid].append(m)
    if not has_parts:
        return skipped
    prows = conn.execute(
        "select message_id,session_id,call_id,type,data from session_part where session_id in (%s) "
        "order by message_id,ordinal" % q, chunk).fetchall()
    for mid, sid, call_id, typ, raw in prows:
        if typ not in ("tool", "text"):
            continue
        try:
            d = jload(raw)
            m = by_id.get(mid)
            if typ == "tool":
                cid = str(d.get("id") or call_id or "")
                t = tool_entry(d.get("name"), d.get("state"))
                if t is None:
                    skipped += 1
                    continue
                if cid and (sid, cid) in calls:
                    om, oi = calls[(sid, cid)]
                    om["tools"][oi] = merge_tool(om["tools"][oi], t)
                    continue
                if m is None:
                    m = by_id[mid] = new_msg("assistant")
                    msgs[sid].append(m)
                m["tools"].append(t)
                if cid:
                    calls[(sid, cid)] = (m, len(m["tools"]) - 1)
            else:
                if m is None:
                    m = by_id[mid] = new_msg("assistant")
                    msgs[sid].append(m)
                m.setdefault("ptext", []).append(str(d.get("text") or ""))
        except (ValueError, TypeError):
            skipped += 1
    for m in by_id.values():
        frag = m.pop("ptext", None)
        if frag and not m["text"].strip():
            m["text"] = " ".join(frag)
    return skipped


def load_v1(conn, chunk, msgs):
    skipped = 0
    q = ",".join("?" * len(chunk))
    mrows = conn.execute(
        "select id,session_id,data from message where session_id in (%s) "
        "order by session_id,time_created,id" % q, chunk).fetchall()
    prows = conn.execute(
        "select message_id,data from part where session_id in (%s) "
        "order by time_created,id" % q, chunk).fetchall()
    by_id = {}
    for mid, sid, raw in mrows:
        try:
            role = jload(raw).get("role")
        except (ValueError, TypeError):
            skipped += 1
            continue
        by_id[mid] = new_msg(role or "?")
        msgs[sid].append(by_id[mid])
    for mid, raw in prows:
        m = by_id.get(mid)
        if m is None:
            continue
        try:
            d = jload(raw)
            typ = d.get("type")
            if typ == "text" and not d.get("synthetic"):
                m["text"] = (m["text"] + " " + str(d.get("text") or "")).strip()
            elif typ == "tool":
                t = tool_entry(d.get("tool"), d.get("state"))
                if t is None:
                    skipped += 1
                else:
                    m["tools"].append(t)
            elif typ == "compaction":
                m["compactions"] += 1
        except (ValueError, TypeError):
            skipped += 1
    return skipped


def v2_session_ids(conn, chunk, tables):
    q = ",".join("?" * len(chunk))
    have = set()
    for t in ("session_message", "session_part"):
        if t in tables:
            have |= {r[0] for r in conn.execute(
                "select distinct session_id from %s where session_id in (%s)" % (t, q), chunk)}
    return have


def load_messages(conn, session_ids):
    """-> ({sid: [msg]}, skipped). msg: role, text, tools, compactions.

    Per session the V2 transcript is authoritative when it has any rows; the
    V1 message/part tables are only a fallback for sessions without one.
    """
    msgs = {s: [] for s in session_ids}
    skipped = 0
    tables = table_names(conn)
    for chunk in chunks(list(session_ids)):
        have = set()
        if "session_message" in tables:
            have = v2_session_ids(conn, chunk, tables)
            skipped += load_v2(conn, chunk, msgs, "session_part" in tables)
        if {"message", "part"} <= tables:
            rest = [x for x in chunk if x not in have]
            if rest:
                skipped += load_v1(conn, rest, msgs)
    return msgs, skipped


def tool_status(status):
    return {"completed": "ok", "error": "error"}.get(status, "pending")


def date_of(ms):
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%d")


def project(s):
    return clean(os.path.basename(s["directory"].rstrip("/")) or "?", 30)


def norm_key(text):
    words = re.sub(r"[^\w\s]", " ", text.lower()).split()[:8]
    return " ".join(words) if len(words) >= 2 else ""


def capped(lines, limit):
    if len(lines) <= limit:
        return lines
    return lines[:limit] + ["…(%d more)" % (len(lines) - limit)]


SKILL_ROOTS = ("~/.config/opencode/skills", "~/.agents/skills", "~/.claude/skills",
               "~/wiki/ai-workflow/skills")


def installed_skills():
    found = set()
    scanned = []
    for base in SKILL_ROOTS:
        root = os.path.expanduser(base)
        if os.path.isdir(root):
            scanned.append(base)
        try:
            for name in os.listdir(root):
                if os.path.isfile(os.path.join(root, name, "SKILL.md")):
                    found.add(name)
        except OSError:
            pass
    return found, scanned


def section(title, lines, budget):
    """Heading plus lines within a byte budget; an omission marker replaces the tail."""
    head = ["## " + title, ""]
    size = lambda ls: sum(len(x.encode("utf-8")) + 1 for x in ls)
    used = size(head) + 1
    if used + size(lines) <= budget:
        return head + lines + [""]
    keep = []
    for ln in lines:
        if used + size([ln]) > budget - 24:
            break
        keep.append(ln)
        used += size([ln])
    return head + keep + ["…(%d more)" % (len(lines) - len(keep)), ""]


def overview(sessions, messages, skipped=0, window=""):
    by_id = {s["id"]: s for s in sessions}
    subs = [s for s in sessions if s["parent"]]
    total_cost = sum(s["cost"] for s in sessions)

    per_model = collections.defaultdict(lambda: [0, 0.0, 0, 0, 0, 0])
    per_agent = collections.defaultdict(lambda: [0, 0.0, 0, 0, 0, 0])
    for s in sessions:
        for acc in (per_model[s["model"]], per_agent[s["agent"]]):
            acc[0] += 1
            acc[1] += s["cost"]
            acc[2] += s["tokens"][0]
            acc[3] += s["tokens"][1]
            acc[4] += s["cache_read"]
            acc[5] += s["tokens"][2]
    totals = ["- sessions: %d (subagent sessions: %d), cost: $%.2f" % (len(sessions), len(subs), total_cost),
              "- skipped rows: %d" % skipped]
    for label, table in (("model", per_model), ("agent", per_agent)):
        rows = sorted(table.items(), key=lambda kv: -kv[1][1])
        totals += capped(["- %s `%s`: %d sess, $%.2f, in %d, out %d, cache-read %d, cache-write %d"
                          % ((label, clean(k, 30)) + tuple(v)) for k, v in rows], 5)

    top = []
    for s in sorted(sessions, key=lambda s: -s["cost"])[:10]:
        denom = s["tokens"][0] + s["cache_read"]
        ratio = "%d%%" % (100 * s["cache_read"] / denom) if denom else "-"
        top.append("- %s %s %s \"%s\" %s %s $%.2f cache %s" % (
            s["id"], date_of(s["created"]), project(s), clean(s["title"], 30), clean(s["agent"], 20),
            clean(s["model"], 20), s["cost"], ratio))

    sub = []
    agg = collections.defaultdict(lambda: [0, 0.0])
    child_cost = collections.defaultdict(float)
    for s in subs:
        agg[s["agent"]][0] += 1
        agg[s["agent"]][1] += s["cost"]
        if s["parent"] in by_id:
            child_cost[s["parent"]] += s["cost"]
    if agg:
        sub += capped(["- `%s`: %d dispatches, $%.2f" % (clean(k, 30), v[0], v[1])
                       for k, v in sorted(agg.items(), key=lambda kv: -kv[1][1])], 8)
        pc = sum(by_id[p]["cost"] for p in child_cost)
        sub.append("- child cost $%.2f vs parent cost $%.2f" % (sum(child_cost.values()), pc))
    else:
        sub.append("- none")

    user_counts, corr_counts, tool_err_sess, comp_counts = {}, {}, {}, {}
    corr_ex = []
    inferred = set()
    phrase_sessions = collections.defaultdict(set)
    phrase_text = {}
    skill_counts, cmd_counts = collections.Counter(), collections.Counter()
    tool_errs, err_msgs = collections.Counter(), collections.Counter()
    for sid, ms in messages.items():
        if sid not in by_id:
            continue
        u = c = e = k = 0
        human = not by_id[sid]["parent"]
        for m in ms:
            k += m["compactions"]
            if m["role"] == "user":
                u += 1
            if m["role"] == "user" and m["text"].strip():
                text = m["text"]
                if human and text.lstrip().startswith("/") and len(text.split()) <= 6:
                    cmd_counts[text.split()[0]] += 1
                if human and CUES.search(text):
                    c += 1
                    corr_ex.append((sid, text))
                key = norm_key(text) if human else ""
                if key:
                    phrase_sessions[key].add(sid)
                    phrase_text.setdefault(key, text)
            for name, status, inp, err in m["tools"]:
                if name == "skill" and isinstance(inp, dict):
                    nm = inp.get("id") or inp.get("name")
                    if nm:
                        skill_counts[str(nm)] += 1
                if status == "error":
                    e += 1
                    tool_errs[name] += 1
                    err_msgs[short(mask(err), 400)] += 1
        if k == 0 and by_id[sid]["compacting"]:
            k = 1
            inferred.add(sid)
        user_counts[sid], corr_counts[sid], tool_err_sess[sid], comp_counts[sid] = u, c, e, k

    corr = ["- user messages: %d across %d sessions" % (sum(user_counts.values()), len(user_counts))]
    per_sess = sorted(((v, k) for k, v in user_counts.items()), key=lambda x: (-x[0], x[1]))
    corr.append("- messages per session: " + (", ".join("%s %d" % (k, v) for v, k in per_sess[:8])
                                              + (", …(%d more)" % (len(per_sess) - 8) if len(per_sess) > 8 else "")
                                              if per_sess else "none"))
    repeats = sorted(((k, v) for k, v in phrase_sessions.items() if len(v) >= 2),
                     key=lambda kv: (-len(kv[1]), kv[0]))
    corr.append("- repeated phrasings:" if repeats else "- repeated phrasings: none")
    corr += capped(["  - \"%s\" — %s" % (clean(phrase_text[k], 150), ", ".join(sorted(v)[:4])) for k, v in repeats], 5)
    corr.append("- correction excerpts:" if corr_ex else "- correction excerpts: none")
    top_corr = sorted(corr_ex, key=lambda x: -corr_counts[x[0]])
    corr += ["  - %s: \"%s\"" % (sid, clean(ex, 150)) for sid, ex in top_corr[:6]]
    if len(top_corr) > 6:
        corr.append("  …(%d more)" % (len(top_corr) - 6))

    skills = []
    if skill_counts:
        skills += capped(["- skill `%s`: %d" % (clean(k, 40), v) for k, v in skill_counts.most_common()], 8)
    else:
        skills.append("- skills loaded: none")
    if cmd_counts:
        skills.append("- commands (inferred from /-prefixed messages): " + short(
            ", ".join("`%s` %d" % (clean(k, 30), v) for k, v in cmd_counts.most_common(5)), 200))
    installed, scanned = installed_skills()
    unused = sorted(installed - set(skill_counts))
    if unused:
        skills.append("- no recorded load (scanned: %s): %s" % (", ".join(scanned), short(
            ", ".join(clean(u, 40) for u in unused[:12]) +
            (" …(%d more)" % (len(unused) - 12) if len(unused) > 12 else ""), 300)))

    errs = []
    if tool_errs:
        errs += capped(["- `%s`: %d" % (clean(k, 30), v) for k, v in tool_errs.most_common()], 8)
        errs += ["- msg (%d×): %s" % (v, clean(k, 100) or "(empty)") for k, v in err_msgs.most_common(5)]
    else:
        errs.append("- none")

    comp = sorted(((v, k) for k, v in comp_counts.items() if v), key=lambda x: (-x[0], x[1]))
    comps = capped(["- %s: %d%s" % (k, v, " (inferred)" if k in inferred else "") for v, k in comp], 5) if comp else ["- none"]

    reasons = collections.defaultdict(list)

    def pick(ranking, fmt):
        for sid, val in ranking[:4]:
            if val > 0:
                reasons[sid].append(fmt % val)
    pick(sorted(corr_counts.items(), key=lambda kv: -kv[1]), "%d corrections")
    pick(sorted(((s["id"], s["cost"]) for s in sessions), key=lambda kv: -kv[1]), "high cost $%.2f")
    pick(sorted(tool_err_sess.items(), key=lambda kv: -kv[1]), "%d tool errors")
    pick(sorted(((k, len(v)) for k, v in messages.items() if k in by_id), key=lambda kv: -kv[1]),
         "long (%d messages)")
    ranked = sorted(reasons.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:15]
    worth = ["- %s (%s, %s): %s" % (sid, date_of(by_id[sid]["created"]), project(by_id[sid]), ", ".join(rs))
             for sid, rs in ranked] or ["- none"]

    out = ["# Session digest%s" % (" (%s)" % window if window else ""), ""]
    for title, lines, budget in (
            ("Totals", totals, 1000), ("Top sessions by cost", top, 1400), ("Subagents", sub, 600),
            ("Corrections and repeats", corr, 1300), ("Skills and commands", skills, 800),
            ("Tool errors", errs, 1000), ("Compactions", comps, 400),
            ("Worth a closer look", worth, 1500)):
        out += section(title, lines, budget)
    return "\n".join(out)


def dump(session, messages):
    L = ["# Session %s" % session["id"], "",
         "- %s, %s, agent %s, model %s, $%.2f" % (date_of(session["created"]), project(session),
                                                  clean(session["agent"], 30), clean(session["model"], 40),
                                                  session["cost"]),
         "- title: %s" % clean(session["title"], 120), ""]
    for m in messages:
        L += ["[compaction]"] * m["compactions"]
        if m["role"] == "user":
            L += ["USER:", mask(m["text"]), ""]
        elif m["role"] == "assistant":
            if m["text"].strip():
                L += ["ASSISTANT: " + clean(m["text"], 300)]
            for name, status, inp, err in m["tools"]:
                summary = ""
                if inp not in (None, "", {}):
                    try:
                        summary = json.dumps(mask_obj(inp), ensure_ascii=False)
                    except (TypeError, ValueError):
                        summary = mask(inp)
                line = "- %s — %s" % (clean(name, 40), tool_status(status))
                if summary:
                    line += ": " + short(summary, 100)
                L.append(line)
            L.append("")
    return "\n".join(L) + "\n"


class Parser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write("dream-digest: %s\n" % message)
        sys.exit(2)


def main(argv):
    p = Parser(prog="dream-digest.py", allow_abbrev=False)
    p.add_argument("--db")
    p.add_argument("--days", type=int)
    p.add_argument("--since")
    p.add_argument("--session")
    if any(x.startswith("--session") for x in argv):
        if len(argv) != 2 or argv[0] != "--session" or not SESSION_RE.fullmatch(argv[1]):
            p.error("usage: --session ses_<id> (and nothing else)")
    a = p.parse_args(argv)
    if a.db == "":
        p.error("--db needs a path")
    default = os.environ.get("DREAM_DB") or DEFAULT_DB

    if a.session is not None:
        try:
            conn = open_ro(default)
            found = [s for s in load_sessions(conn, 0) if s["id"] == a.session]
            if not found:
                sys.stderr.write("no such session\n")
                return 1
            require_transcripts(conn, found)
            msgs, _ = load_messages(conn, [a.session])
        except sqlite3.Error as e:
            sys.stderr.write("cannot read database: %s\n" % e)
            return 1
        sys.stdout.write(dump(found[0], msgs[a.session]))
        return 0

    if (a.days is None) == (a.since is None):
        p.error("give exactly one of --days or --since")
    if a.days is not None:
        if a.days < 1:
            p.error("--days must be positive")
        since_ms = int(time.time() * 1000) - a.days * 86400000
    else:
        try:
            d = datetime.datetime.strptime(a.since, "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            p.error("--since must be YYYY-MM-DD")
        since_ms = int(d.timestamp() * 1000)
    window = "%s .. %s" % (date_of(since_ms), date_of(time.time() * 1000))
    try:
        conn = open_ro(default if a.db is None else a.db)
        sessions = load_sessions(conn, since_ms)
        if not sessions:
            sys.stdout.write("No sessions in window (%s)\n" % window)
            return 0
        require_transcripts(conn, sessions)
        msgs, skipped = load_messages(conn, [s["id"] for s in sessions])
    except sqlite3.Error as e:
        sys.stderr.write("cannot read database: %s\n" % e)
        return 1
    sys.stdout.write(overview(sessions, msgs, skipped, window))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
