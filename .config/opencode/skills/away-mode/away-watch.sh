#!/usr/bin/env bash
# Model-free watcher for one delegated worker session. Run every few minutes
# by a shell automation; steers a quiet worker, starts a `watcher` child for
# real hangs, and tells the main session only when that fails.

set -o nounset
set -o pipefail

usage() {
  echo "usage: away-watch.sh --worker SES --main SES --checkpoint FILE [--stale MIN] [--interval MIN] [--watch GLOB]... [--repo DIR] [--stop interrupt|never] [--state-dir DIR]" >&2
  exit 2
}

WORKER="" MAIN="" CHECKPOINT="" REPO="" STOP=never
STALE=15 INTERVAL=10 STATE_DIR=/tmp/opencode/away-watch
WATCH=()
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "${1}" in
  --worker) WORKER="${2}" ;;
  --main) MAIN="${2}" ;;
  --checkpoint) CHECKPOINT="${2}" ;;
  --stale) STALE="${2}" ;;
  --interval) INTERVAL="${2}" ;;
  --watch) WATCH+=("${2}") ;;
  --repo) REPO="${2}" ;;
  --stop) STOP="${2}" ;;
  --state-dir) STATE_DIR="${2}" ;;
  *) usage ;;
  esac
  shift 2
done

[[ "${WORKER}" =~ ^ses_[A-Za-z0-9]+$ ]] || usage
[[ "${MAIN}" =~ ^ses_[A-Za-z0-9]+$ ]] || usage
[[ -n "${CHECKPOINT}" ]] || usage
[[ "${STALE}" =~ ^[0-9]+$ && "${INTERVAL}" =~ ^[0-9]+$ ]] || usage
[[ "${STOP}" == interrupt || "${STOP}" == never ]] || usage

NOW="${AWAY_WATCH_NOW:-$(date +%s)}"
GRACE=120
RESOLVER_LIMIT=1200
STATE="${STATE_DIR}/${WORKER}.state"
ERR="${STATE_DIR}/${WORKER}.err"
# Strip leading zeros and cap the length before any arithmetic (no octal, no wrap).
while [[ "${STALE}" == 0?* ]]; do STALE="${STALE#0}"; done
while [[ "${INTERVAL}" == 0?* ]]; do INTERVAL="${INTERVAL#0}"; done
[[ "${#STALE}" -le 5 && "${#INTERVAL}" -le 5 ]] || usage
[[ "${STALE}" -ge 1 && "${STALE}" -le 10080 && "${INTERVAL}" -ge 1 && "${INTERVAL}" -le 10080 ]] || usage
mkdir -p "${STATE_DIR}"

log_err() { echo "$(date +%FT%T) $*" >>"${ERR}"; }

# One tick per worker at a time. With flock (Linux): a kernel lock that dies
# with the process. Fallback (no flock, e.g. macOS): a mkdir lock holding the
# owner's PID. Its stale check and the rename that reclaims the lock are
# separate steps, so a tick that pauses after its check can later rename a
# live replacement lock. Fallback only; it needs a pause at exactly that spot
# plus two overlapping ticks, and one automation ticks 10 minutes apart.
if [[ -z "${AWAY_WATCH_NO_FLOCK:-}" ]] && command -v flock >/dev/null 2>&1; then
  exec 9>"${STATE_DIR}/${WORKER}.flock"
  flock -n 9 || exit 0
else
  LOCK="${STATE}.lock"
  lock_stale() {
    local pid
    pid="$(cat "${LOCK}/pid" 2>/dev/null)"
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
      ! kill -0 "${pid}" 2>/dev/null
    else
      [[ -n "$(find "${LOCK}" -maxdepth 0 -mmin +10 2>/dev/null)" ]]
    fi
  }
  if ! mkdir "${LOCK}" 2>/dev/null; then
    lock_stale || exit 0
    # Reclaim by rename: one mover wins, the loser backs off (see the race above).
    mv "${LOCK}" "${LOCK}.stale.$$" 2>/dev/null || exit 0
    rm -rf "${LOCK}.stale.$$"
    mkdir "${LOCK}" 2>/dev/null || exit 0
  fi
  if ! echo "$$" >"${LOCK}/pid" || [[ "$(cat "${LOCK}/pid" 2>/dev/null)" != "$$" ]]; then
    rm -rf "${LOCK}"
    log_err "cannot write lock pid"
    exit 0
  fi
  trap '[[ "$(cat "${LOCK}/pid" 2>/dev/null)" == "$$" ]] && rm -rf "${LOCK}"' EXIT
fi

get_key() { sed -n "s/^${1}=//p" "${STATE}" 2>/dev/null | tail -n 1; }
set_key() {
  del_key "${1}"
  echo "${1}=${2}" >>"${STATE}"
}
del_key() {
  [[ -f "${STATE}" ]] || return 0
  grep -v "^${1}=" "${STATE}" >"${STATE}.tmp" || true
  mv "${STATE}.tmp" "${STATE}"
}

hhmm() { date -d "@${NOW}" +%H:%M 2>/dev/null || date -r "${NOW}" +%H:%M; }
checkpoint() {
  mkdir -p "$(dirname "${CHECKPOINT}")"
  echo "- $(hhmm) ${1}" >>"${CHECKPOINT}"
}

# json_get JSON PATH: print a dotted path (under "data" when present), or nothing.
json_get() {
  python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
    d = d.get("data", d)
    for k in sys.argv[2].split("."):
        d = d[k]
    if d is not None:
        print(d)
except Exception:
    pass
' "${1}" "${2}"
}

# valid_session JSON: prints ok when time.updated and time.busy (and time.idle
# when present) are non-negative JSON integers.
valid_session() {
  python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
    t = d.get("data", d)["time"]
    def num(v):
        return type(v) is int and v >= 0
    if num(t["updated"]) and num(t["busy"]) and ("idle" not in t or t["idle"] is None or num(t["idle"])):
        print("ok")
except Exception:
    pass
' "${1}"
}

json_body() {
  python3 -c '
import json, sys
print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))
' "${@}"
}

# Newest mtime (epoch s) of the files given on stdin (NUL separated), or 0.
if stat -c %Y / >/dev/null 2>&1; then STAT_FMT=(-c %Y); else STAT_FMT=(-f %m); fi
newest() {
  xargs -0 stat "${STAT_FMT[@]}" 2>/dev/null | sort -n | tail -n 1
}

done_exit() {
  set_key "done" "${NOW}"
  exit 0
}

# blocker REASON [CHILD]: done is written first so a failed post is never
# resent (the API has no idempotency key).
blocker() {
  local reason="${1}" child="${2:-}" text out
  text="Watcher BLOCKER ${WORKER}: ${reason}"
  [[ -n "${child}" ]] && text="${text}"$'\n'"details: session ${child}"
  if ! set_key "done" "${NOW}" || [[ -z "$(get_key "done")" ]]; then
    log_err "cannot write done state; blocker not sent"
    exit 0
  fi
  if ! out="$(opencode api post "/api/session/${MAIN}/prompt" -d "$(json_body text "${text}" delivery queue)" 2>&1)"; then
    log_err "blocker post failed: ${out}"
  fi
  checkpoint "BLOCKER watcher ${WORKER}: ${reason}"
  exit 0
}

# session_state SES: sets SES_JSON; returns 0 ok, 1 gone (404), 2 failure or
# invalid response (logged).
session_state() {
  local out errout rc=0 errf="${STATE_DIR}/${WORKER}.stderr"
  out="$(opencode api get "/api/session/${1}" 2>"${errf}")" || rc=$?
  errout="$(cat "${errf}" 2>/dev/null)"
  rm -f "${errf}"
  if [[ "${rc}" -ne 0 ]]; then
    if [[ "${out}${errout}" == *404* ]]; then return 1; fi
    log_err "get ${1} failed: ${out} ${errout}"
    return 2
  fi
  if [[ "$(valid_session "${out}")" != ok ]]; then
    log_err "get ${1}: invalid response: ${out}"
    return 2
  fi
  SES_JSON="${out}"
}

# finished JSON: true when time.idle is newer than time.busy.
finished() {
  local busy idle
  busy="$(json_get "${1}" time.busy)"
  idle="$(json_get "${1}" time.idle)"
  [[ -n "${idle}" && "${idle}" -gt "${busy:-0}" ]]
}

[[ -n "$(get_key "done")" ]] && exit 0

STEERED="$(get_key steered)"
RESOLVER="$(get_key resolver)"
RSTARTED="$(get_key resolver_started)"
if [[ -n "${RESOLVER}" && ! "${RESOLVER}" =~ ^ses_[A-Za-z0-9]+$ ]]; then
  log_err "invalid resolver id in state: ${RESOLVER}"
  exit 0
fi

if [[ -z "${RESOLVER}" && -n "$(get_key resolver_pending)" ]]; then
  blocker "resolver create unconfirmed"
fi

session_state "${WORKER}"
case $? in
1) blocker "session gone" "${RESOLVER}" ;;
2) exit 0 ;;
esac
WJSON="${SES_JSON}"

finished "${WJSON}" && done_exit

# Activity in epoch seconds; ignore updates caused by our own messages.
activity=0
updated="$(json_get "${WJSON}" time.updated)"
if [[ -n "${updated}" ]]; then
  updated=$((updated / 1000))
  ignore=0
  for t in "${STEERED}" "${RSTARTED}"; do
    if [[ -n "${t}" && "${updated}" -ge "${t}" && "${updated}" -le $((t + GRACE)) ]]; then ignore=1; fi
  done
  [[ "${ignore}" -eq 0 ]] && activity="${updated}"
fi
if [[ "${#WATCH[@]}" -gt 0 ]]; then
  for g in "${WATCH[@]}"; do
    while IFS= read -r f; do
      [[ -e "${f}" ]] && printf '%s\0' "${f}"
    done < <(compgen -G "${g}")
  done >"${STATE_DIR}/${WORKER}.files"
  m="$(newest <"${STATE_DIR}/${WORKER}.files")"
  rm -f "${STATE_DIR}/${WORKER}.files"
  [[ -n "${m}" && "${m}" -gt "${activity}" ]] && activity="${m}"
fi
if [[ -n "${REPO}" && -d "${REPO}" ]]; then
  m="$(find "${REPO}" -name .git -prune -o -type f -print0 2>/dev/null | newest)"
  [[ -n "${m}" && "${m}" -gt "${activity}" ]] && activity="${m}"
fi

if [[ $((NOW - activity)) -lt $((STALE * 60)) ]]; then
  if [[ -n "${STEERED}" && "${activity}" -gt $((STEERED + GRACE)) ]]; then
    del_key steered
  fi
  exit 0
fi

if [[ "${activity}" -gt 0 ]]; then
  QUIET=$(((NOW - activity) / 60))
else
  QUIET="${STALE}"
fi

resolver_prompt() {
  local child="${1}" text out
  text="worker: ${WORKER}"$'\n'"main: ${MAIN}"$'\n'"checkpoint: ${CHECKPOINT}"$'\n'"stop: ${STOP}"$'\n'"quiet for: ${QUIET} min"
  [[ -n "${REPO}" ]] && text="${text}"$'\n'"repo: ${REPO}"
  [[ "${#WATCH[@]}" -gt 0 ]] && text="${text}"$'\n'"watch: ${WATCH[*]}"
  if ! out="$(opencode api post "/api/session/${child}/prompt" -d "$(json_body text "${text}")" 2>&1)"; then
    log_err "resolver prompt failed: ${out}"
    return 1
  fi
  set_key resolver_started "${NOW}"
  checkpoint "WATCH resolver ${child}"
}

if [[ -n "${RESOLVER}" ]]; then
  if [[ -z "${RSTARTED}" ]]; then
    resolver_prompt "${RESOLVER}"
    exit 0
  fi
  session_state "${RESOLVER}"
  rc=$?
  [[ "${rc}" -eq 2 ]] && exit 0
  if [[ "${rc}" -eq 1 ]] || finished "${SES_JSON}"; then
    ridle="$(get_key resolver_idle)"
    if [[ -z "${ridle}" ]]; then
      set_key resolver_idle "${NOW}"
      exit 0
    fi
    [[ $((NOW - ridle)) -ge $((INTERVAL * 60)) ]] && blocker "still stale after resolver" "${RESOLVER}"
  elif [[ $((NOW - RSTARTED)) -ge "${RESOLVER_LIMIT}" ]]; then
    blocker "resolver busy > 20 min" "${RESOLVER}"
  fi
  exit 0
fi

if [[ -z "${STEERED}" ]]; then
  text="Watcher: no activity for ${QUIET} min. Reply in 3 lines: what you are doing, last result, next step. If the same error repeats, stop and report BLOCKED per your brief."
  if ! out="$(opencode api post "/api/session/${WORKER}/prompt" -d "$(json_body text "${text}" delivery steer)" 2>&1)"; then
    log_err "steer failed: ${out}"
    exit 0
  fi
  set_key steered "${NOW}"
  checkpoint "WATCH steer ${WORKER}"
  exit 0
fi

if [[ $((NOW - STEERED)) -ge $((INTERVAL * 60)) ]]; then
  if ! set_key resolver_pending "${NOW}" || [[ -z "$(get_key resolver_pending)" ]]; then
    log_err "cannot write resolver_pending; resolver not created"
    exit 0
  fi
  if ! out="$(opencode api post /api/session -d "$(json_body parentID "${WORKER}" agent watcher title "watcher ${WORKER}")" 2>&1)"; then
    log_err "resolver create failed: ${out}"
    exit 0
  fi
  child="$(json_get "${out}" id)"
  if [[ ! "${child}" =~ ^ses_[A-Za-z0-9]+$ ]]; then
    log_err "resolver create: no session id in: ${out}"
    exit 0
  fi
  if ! set_key resolver "${child}" || [[ "$(get_key resolver)" != "${child}" ]]; then
    log_err "cannot record resolver ${child}"
    exit 0
  fi
  del_key resolver_pending
  resolver_prompt "${child}"
fi
exit 0
