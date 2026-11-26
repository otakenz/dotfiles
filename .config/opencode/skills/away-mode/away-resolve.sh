#!/usr/bin/env bash
# Guarded session helper for the `watcher` resolver agent: read a worker's
# state, or interrupt it only when the listener recorded stop=interrupt.
# Exit: 0 ok, 1 error, 2 usage, 3 refused.

set -o nounset
set -o pipefail

usage() {
  echo "usage: away-resolve.sh [--state-dir DIR] status|interrupt SES" >&2
  exit 2
}

STATE_DIR=/tmp/opencode/away-watch
if [[ "${1:-}" == --state-dir ]]; then
  [[ $# -ge 2 ]] || usage
  STATE_DIR="${2}"
  shift 2
fi
[[ $# -eq 2 ]] || usage
CMD="${1}"
WORKER="${2}"
[[ "${CMD}" == status || "${CMD}" == interrupt ]] || usage
[[ "${WORKER}" =~ ^ses_[A-Za-z0-9]+$ ]] || usage

NOW="${AWAY_WATCH_NOW:-$(date +%s)}"
STATE="${STATE_DIR}/${WORKER}.state"

# fetch: sets SES_JSON; returns 1 (with `error:` printed) on failure or an
# invalid response.
fetch() {
  local out
  if ! out="$(opencode api get "/api/session/${WORKER}" 2>&1)"; then
    echo "error: get failed: ${out:0:120}"
    return 1
  fi
  SES_JSON="${out}"
}

# summary: prints the status lines for SES_JSON, or fails on a bad response.
summary() {
  python3 -c '
import json, sys
now = int(sys.argv[2])
def num(v):
    return type(v) is int and v >= 0
try:
    d = json.loads(sys.argv[1])
    t = d.get("data", d)["time"]
    u, b = t["updated"], t["busy"]
    i = t.get("idle")
    if not (num(u) and num(b) and (i is None or num(i))):
        raise ValueError
except Exception:
    print("error: invalid response")
    sys.exit(1)
age = lambda v: max(0, now - v // 1000)
print("busy_age_s: %d" % age(b))
print("idle_age_s: %s" % ("none" if i is None else age(i)))
print("updated_age_s: %d" % age(u))
print("finished: %s" % ("yes" if i is not None and i > b else "no"))
' "${SES_JSON}" "${NOW}"
}

# is_finished: true when SES_JSON shows idle > busy.
is_finished() { [[ "$(summary | sed -n 's/^finished: //p')" == yes ]]; }

if [[ "${CMD}" == status ]]; then
  fetch || exit 1
  out="$(summary)" || {
    echo "${out}"
    exit 1
  }
  echo "${out}"
  exit 0
fi

refuse() {
  echo "refused: ${1}"
  exit 3
}
[[ -f "${STATE}" ]] || refuse "listener state is not a regular file"
SNAP="$(cat "${STATE}" 2>/dev/null)" || refuse "cannot read listener state"
[[ -n "${SNAP}" ]] || refuse "empty listener state"
state_key() { sed -n "s/^${1}=//p" <<<"${SNAP}" | tail -n 1; }
[[ -n "$(state_key resolver)" ]] || refuse "no resolver recorded"
[[ "$(state_key stop)" == interrupt ]] || refuse "stop is not interrupt"
! grep -q '^done\(=\|$\)' <<<"${SNAP}" || refuse "watch is done"

fetch || exit 1
summary >/dev/null || {
  echo "error: invalid response"
  exit 1
}
is_finished && refuse "worker finished"

if ! out="$(opencode api post "/api/session/${WORKER}/interrupt" 2>&1)"; then
  echo "error: interrupt failed: ${out:0:120}"
  exit 1
fi
if ! fetch; then
  echo "confirmed: no"
  exit 1
fi
if summary >/dev/null && is_finished; then
  echo "confirmed: yes"
else
  echo "confirmed: no"
fi
