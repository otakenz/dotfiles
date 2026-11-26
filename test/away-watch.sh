#!/usr/bin/env bash
# Hermetic test for away-watch.sh: fake `opencode` on PATH, temp dirs, fixed
# clock via AWAY_WATCH_NOW. Never touches the real service or state dir.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/.config/opencode/skills/away-mode/away-watch.sh"
ROOT="$(mktemp -d /tmp/away-watch-test.XXXXXX)"
trap 'rm -rf "${ROOT}"' EXIT

NOW=1800000000
# The mkdir-lock tests exercise the fallback; the flock case unsets this.
export AWAY_WATCH_NO_FLOCK=1
failures=0

ok() { echo "ok   ${1}"; }
fail() {
  echo "FAIL ${1}"
  failures=$((failures + 1))
}

check() {
  local name="${1}"
  shift
  if "${@}"; then ok "${name}"; else fail "${name}"; fi
}

mkdir -p "${ROOT}/bin"
cat >"${ROOT}/bin/opencode" <<'FAKE'
#!/usr/bin/env bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
method="${2}"
path="${3}"
body=""
if [[ "${4:-}" == "-d" ]]; then body="${5}"; fi
marker=""
if compgen -G "${root}"/*/state/*.state >/dev/null && grep -qs '^done=' "${root}"/*/state/*.state; then marker=" [done-set]"; fi
if compgen -G "${root}"/*/state/*.state >/dev/null && grep -qs '^resolver_pending=' "${root}"/*/state/*.state; then marker="${marker} [pending-set]"; fi
echo "${method} ${path} ${body}${marker}" >>"${root}/calls.log"
if [[ -f "${root}/failpath" && "${path}" == "$(cat "${root}/failpath")" ]]; then
  echo "boom" >&2
  exit 1
fi
if [[ -e "${root}/warn" ]]; then echo "warning: something" >&2; fi
if [[ -e "${root}/down" ]]; then
  echo "connection refused" >&2
  exit 1
fi
if [[ "${method}" == "get" ]]; then
  f="${root}/sess-${path##*/}.json"
  if [[ -f "${f}" ]]; then
    cat "${f}"
  else
    echo "HTTP 404 Not Found"
    exit 1
  fi
elif [[ "${path}" == "/api/session" ]]; then
  echo '{"data":{"id":"ses_child1"}}'
else
  echo '{"data":{}}'
fi
FAKE
chmod +x "${ROOT}/bin/opencode"

# sess ID UPDATED_S BUSY_S [IDLE_S]
sess() {
  local idle=""
  if [[ -n "${4:-}" ]]; then idle=", \"idle\": $((${4} * 1000))"; fi
  echo "{\"data\":{\"id\":\"${1}\",\"time\":{\"updated\":$((${2} * 1000)),\"busy\":$((${3} * 1000))${idle}}}}" \
    >"${ROOT}/sess-${1}.json"
}

# settime FILE EPOCH: portable mtime setter (touch -d is GNU-only).
settime() { python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "${1}" "${2}"; }
# ran: the tick finished cleanly and read the worker session.
ran() { [[ "${RC}" -eq 0 ]] && grep -q '^get /api/session/ses_w' "${ROOT}/calls.log"; }

# Fresh sandbox per case.
CASE=""
newcase() {
  CASE="${1}"
  rm -rf "${ROOT:?}/${CASE}"
  mkdir -p "${ROOT}/${CASE}"
  rm -f "${ROOT}"/sess-*.json "${ROOT}/calls.log" "${ROOT}/down" "${ROOT}/warn" "${ROOT}/failpath"
  SD="${ROOT}/${CASE}/state"
  CP="${ROOT}/${CASE}/cp/checkpoint.md"
  mkdir -p "${SD}"
}

# run_at TIME ARGS...: run the listener; exit code in RC.
RC=0
run_at() {
  local t="${1}"
  shift
  RC=0
  PATH="${ROOT}/bin:${PATH}" AWAY_WATCH_NOW="${t}" bash "${SCRIPT}" \
    --checkpoint "${CP}" --state-dir "${SD}" "${@}" >/dev/null 2>&1 || RC=$?
}

W=(--worker ses_w --main ses_m)
posts() { grep -c '^post' "${ROOT}/calls.log" 2>/dev/null || true; }
calls_have() { grep -qE -- "${1}" "${ROOT}/calls.log" 2>/dev/null; }
state_have() { grep -qE -- "${1}" "${SD}/${2:-ses_w}.state" 2>/dev/null; }
cp_have() { grep -qE -- "${1}" "${CP}" 2>/dev/null; }
# A call line must match all patterns.
call_with() {
  local l
  l="$(grep -E -- "${1}" "${ROOT}/calls.log" 2>/dev/null)" || return 1
  shift
  for p in "${@}"; do
    grep -qE -- "${p}" <<<"${l}" || return 1
  done
}

newcase fresh
sess ses_w $((NOW - 60)) $((NOW - 600))
run_at "${NOW}" "${W[@]}"
check fresh [ "$(posts)" -eq 0 ]
check fresh_ran ran

newcase stale_steers
sess ses_w $((NOW - 1200)) $((NOW - 3000))
run_at "${NOW}" "${W[@]}"
check stale_steers_one_post [ "$(posts)" -eq 1 ]
check stale_steers_body call_with '^post /api/session/ses_w/prompt' '"delivery": ?"steer"' 'no activity for 20 min'
check stale_steers_state state_have "^steered=${NOW}\$"
check stale_steers_checkpoint cp_have 'WATCH steer ses_w'
check checkpoint_dir_created [ -f "${CP}" ]
check stale_steers_rc [ "${RC}" -eq 0 ]

run_at $((NOW + 300)) "${W[@]}"
check steer_once [ "$(posts)" -eq 1 ]

newcase steer_bump_ignored
sess ses_w $((NOW - 630)) $((NOW - 3000))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check steer_bump_resolver_post [ "$(posts)" -eq 2 ]
check steer_bump_session call_with '^post /api/session ' '"parentID": ?"ses_w"' '"agent": ?"watcher"'
check steer_bump_prompt call_with '^post /api/session/ses_child1/prompt' 'worker: ses_w' 'main: ses_m' 'stop: never'
check steer_bump_state state_have '^resolver=ses_child1$'
check steer_bump_checkpoint cp_have 'WATCH resolver ses_child1'

newcase reply_clears_steer
sess ses_w $((NOW - 60)) $((NOW - 3000))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check reply_clears_steer_nopost [ "$(posts)" -eq 0 ]
check reply_clears_steer_ran ran
check reply_clears_steer_state bash -c "! grep -q steered '${SD}/ses_w.state'"

newcase one_resolver
sess ses_w $((NOW - 3000)) $((NOW - 3500))
sess ses_child1 $((NOW - 100)) $((NOW - 300))
printf 'steered=%s\nresolver=ses_child1\nresolver_started=%s\n' $((NOW - 900)) $((NOW - 300)) >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check one_resolver [ "$(posts)" -eq 0 ]
check one_resolver_ran ran

newcase resolver_failed
sess ses_w $((NOW - 3000)) $((NOW - 3500))
sess ses_child1 $((NOW - 700)) $((NOW - 1000)) $((NOW - 700))
printf 'steered=%s\nresolver=ses_child1\nresolver_started=%s\nresolver_idle=%s\n' $((NOW - 1500)) $((NOW - 1000)) $((NOW - 700)) >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check resolver_failed_one_post [ "$(posts)" -eq 1 ]
check resolver_failed_body call_with '^post /api/session/ses_m/prompt' '"delivery": ?"queue"' 'Watcher BLOCKER ses_w: still stale after resolver' 'details: session ses_child1'
check resolver_failed_state state_have '^done='
check resolver_failed_checkpoint cp_have 'BLOCKER watcher ses_w'

newcase resolver_slow
sess ses_w $((NOW - 3000)) $((NOW - 3500))
sess ses_child1 $((NOW - 100)) $((NOW - 1300))
printf 'steered=%s\nresolver=ses_child1\nresolver_started=%s\n' $((NOW - 1900)) $((NOW - 1300)) >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check resolver_slow call_with '^post /api/session/ses_m/prompt' 'resolver busy > 20 min' 'details: session ses_child1'

newcase finished
sess ses_w $((NOW - 100)) $((NOW - 500)) $((NOW - 100))
run_at "${NOW}" "${W[@]}"
check finished_nopost [ "$(posts)" -eq 0 ]
check finished_done state_have '^done='
before="$(cat "${ROOT}/calls.log")"
run_at $((NOW + 600)) "${W[@]}"
check finished_next_silent [ "$(cat "${ROOT}/calls.log")" = "${before}" ]

newcase finished_after_steer
sess ses_w $((NOW - 3000)) $((NOW - 3500)) $((NOW - 100))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check finished_after_steer_done state_have '^done='
check finished_after_steer_nopost [ "$(posts)" -eq 0 ]

newcase gone
run_at "${NOW}" "${W[@]}"
check gone_blocker call_with '^post /api/session/ses_m/prompt' 'Watcher BLOCKER ses_w: session gone'
check gone_done state_have '^done='

newcase gone_with_resolver
echo "resolver=ses_child1" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check gone_resolver_details call_with '^post /api/session/ses_m/prompt' 'session gone' 'details: session ses_child1'

newcase blocker_done_first
sess ses_w $((NOW - 3000)) $((NOW - 3500))
sess ses_child1 $((NOW - 100)) $((NOW - 1300))
printf 'steered=%s\nresolver=ses_child1\nresolver_started=%s\n' $((NOW - 1900)) $((NOW - 1300)) >"${SD}/ses_w.state"
echo /api/session/ses_m/prompt >"${ROOT}/failpath"
run_at "${NOW}" "${W[@]}"
check blocker_done_before_post call_with '^post /api/session/ses_m/prompt' '\[done-set\]'
check blocker_post_fail_err [ -s "${SD}/ses_w.err" ]
check blocker_post_fail_checkpoint cp_have 'BLOCKER watcher ses_w'
run_at $((NOW + 600)) "${W[@]}"
check blocker_not_resent [ "$(posts)" -eq 1 ]

newcase lock_held
sess ses_w $((NOW - 1200)) $((NOW - 3000))
mkdir "${SD}/ses_w.state.lock"
run_at "${NOW}" "${W[@]}"
check lock_held_quiet [ "${RC}" -eq 0 ]
check lock_held_nocalls [ ! -e "${ROOT}/calls.log" ]

newcase lock_live_pid_old
sess ses_w $((NOW - 1200)) $((NOW - 3000))
mkdir "${SD}/ses_w.state.lock"
echo "$$" >"${SD}/ses_w.state.lock/pid"
settime "${SD}/ses_w.state.lock" 1000
run_at "${NOW}" "${W[@]}"
check lock_live_pid_nocalls [ ! -e "${ROOT}/calls.log" ]
check lock_live_pid_kept [ "$(cat "${SD}/ses_w.state.lock/pid")" = "$$" ]

newcase lock_dead_pid
sess ses_w $((NOW - 1200)) $((NOW - 3000))
mkdir "${SD}/ses_w.state.lock"
sleep 0 &
deadpid=$!
wait "${deadpid}"
echo "${deadpid}" >"${SD}/ses_w.state.lock/pid"
run_at "${NOW}" "${W[@]}"
check lock_dead_pid_taken_over call_with '^post /api/session/ses_w/prompt' 'steer'
check lock_dead_pid_released [ ! -d "${SD}/ses_w.state.lock" ]

newcase pending_marker_first
sess ses_w $((NOW - 630)) $((NOW - 3000))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check pending_before_create call_with '^post /api/session ' '\[pending-set\]'
check pending_cleared bash -c "! grep -q resolver_pending '${SD}/ses_w.state'"

newcase pending_unconfirmed
sess ses_w $((NOW - 630)) $((NOW - 3000))
printf 'steered=%s\nresolver_pending=%s\n' $((NOW - 660)) $((NOW - 60)) >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check pending_no_second_create [ "$(grep -c '^post /api/session ' "${ROOT}/calls.log")" -eq 0 ]
check pending_blocker call_with '^post /api/session/ses_m/prompt' 'resolver create unconfirmed'

newcase string_time
echo '{"data":{"id":"ses_w","time":{"updated":"08","busy":5}}}' >"${ROOT}/sess-ses_w.json"
run_at "${NOW}" "${W[@]}"
check string_time_nopost [ "$(posts)" -eq 0 ]
check string_time_err [ -s "${SD}/ses_w.err" ]
check string_time_rc [ "${RC}" -eq 0 ]

newcase pending_fresh_worker
sess ses_w $((NOW - 60)) $((NOW - 3000))
printf 'steered=%s\nresolver_pending=%s\n' $((NOW - 660)) $((NOW - 60)) >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check pending_fresh_blocker call_with '^post /api/session/ses_m/prompt' 'resolver create unconfirmed'
check pending_fresh_done state_have '^done='
check pending_fresh_one_post [ "$(posts)" -eq 1 ]

newcase idle_null
echo "{\"data\":{\"id\":\"ses_w\",\"time\":{\"updated\":$(((NOW - 1200) * 1000)),\"busy\":5000,\"idle\":null}}}" >"${ROOT}/sess-ses_w.json"
run_at "${NOW}" "${W[@]}"
check idle_null_not_finished bash -c "! grep -q '^done=' '${SD}/ses_w.state'"
check idle_null_steers call_with '^post /api/session/ses_w/prompt' 'steer'

newcase huge_decimal
run_at "${NOW}" "${W[@]}" --stale 18446744073709551617
check huge_stale_decimal_rc [ "${RC}" -eq 2 ]
run_at "${NOW}" "${W[@]}" --interval 99999999
check huge_interval_decimal_rc [ "${RC}" -eq 2 ]

newcase huge_stale
run_at "${NOW}" "${W[@]}" --stale 10081
check huge_stale_rc [ "${RC}" -eq 2 ]

if command -v flock >/dev/null 2>&1; then
  newcase flock_held
  sess ses_w $((NOW - 1200)) $((NOW - 3000))
  exec 8>"${SD}/ses_w.flock"
  flock -n 8
  RC=0
  env -u AWAY_WATCH_NO_FLOCK PATH="${ROOT}/bin:${PATH}" AWAY_WATCH_NOW="${NOW}" bash "${SCRIPT}" \
    --checkpoint "${CP}" --state-dir "${SD}" "${W[@]}" >/dev/null 2>&1 || RC=$?
  check flock_held_rc [ "${RC}" -eq 0 ]
  check flock_held_nocalls [ ! -e "${ROOT}/calls.log" ]
  exec 8>&-
  RC=0
  env -u AWAY_WATCH_NO_FLOCK PATH="${ROOT}/bin:${PATH}" AWAY_WATCH_NOW="${NOW}" bash "${SCRIPT}" \
    --checkpoint "${CP}" --state-dir "${SD}" "${W[@]}" >/dev/null 2>&1 || RC=$?
  check flock_free_runs call_with '^post /api/session/ses_w/prompt' 'steer'
else
  echo "skip flock_held (no flock)"
fi

newcase lock_released
sess ses_w $((NOW - 1200)) $((NOW - 3000))
run_at "${NOW}" "${W[@]}"
check lock_released [ ! -d "${SD}/ses_w.state.lock" ]

newcase resolver_prompt_retry
sess ses_w $((NOW - 630)) $((NOW - 3000))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
echo /api/session/ses_child1/prompt >"${ROOT}/failpath"
run_at "${NOW}" "${W[@]}"
check retry_child_saved state_have '^resolver=ses_child1$'
check retry_not_started bash -c "! grep -q resolver_started '${SD}/ses_w.state'"
check retry_err [ -s "${SD}/ses_w.err" ]
rm -f "${ROOT}/failpath"
run_at $((NOW + 60)) "${W[@]}"
check retry_one_child [ "$(grep -c '^post /api/session ' "${ROOT}/calls.log")" -eq 1 ]
check retry_prompt_sent [ "$(grep -c '^post /api/session/ses_child1/prompt' "${ROOT}/calls.log")" -eq 2 ]
check retry_started state_have '^resolver_started='
check retry_checkpoint cp_have 'WATCH resolver ses_child1'

newcase stderr_warning
sess ses_w $((NOW - 60)) $((NOW - 3000))
touch "${ROOT}/warn"
run_at "${NOW}" "${W[@]}"
check stderr_warning_ok ran
check stderr_warning_quiet [ "$(posts)" -eq 0 ]
sess ses_w $((NOW - 1200)) $((NOW - 3000))
run_at "${NOW}" "${W[@]}"
check stderr_warning_steers call_with '^post /api/session/ses_w/prompt' 'steer'

newcase malformed_json
echo 'not json' >"${ROOT}/sess-ses_w.json"
run_at "${NOW}" "${W[@]}"
check malformed_nopost [ "$(posts)" -eq 0 ]
check malformed_err [ -s "${SD}/ses_w.err" ]
check malformed_rc [ "${RC}" -eq 0 ]

newcase missing_fields
echo '{"data":{"id":"ses_w","time":{}}}' >"${ROOT}/sess-ses_w.json"
run_at "${NOW}" "${W[@]}"
check missing_fields_nopost [ "$(posts)" -eq 0 ]
check missing_fields_err [ -s "${SD}/ses_w.err" ]

newcase watch_space
sess ses_w $((NOW - 3000)) $((NOW - 3500))
mkdir -p "${ROOT}/${CASE}/my logs"
touch "${ROOT}/${CASE}/my logs/a.log"
settime "${ROOT}/${CASE}/my logs/a.log" "${NOW}"
run_at "${NOW}" "${W[@]}" --watch "${ROOT}/${CASE}/my logs/*.log"
check watch_space [ "$(posts)" -eq 0 ]
check watch_space_ran ran

newcase octal_stale
sess ses_w $((NOW - 1200)) $((NOW - 3000))
run_at "${NOW}" "${W[@]}" --stale 08 --interval 09
check octal_stale_ok [ "${RC}" -eq 0 ]
check octal_stale_steers call_with '^post /api/session/ses_w/prompt' 'steer'

newcase zero_stale
run_at "${NOW}" "${W[@]}" --stale 0
check zero_stale_rc [ "${RC}" -eq 2 ]

newcase bad_state_resolver
sess ses_w $((NOW - 3000)) $((NOW - 3500))
echo 'resolver=ses_x/../y' >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}"
check bad_state_resolver_nocalls [ ! -e "${ROOT}/calls.log" ]
check bad_state_resolver_err [ -s "${SD}/ses_w.err" ]
check bad_state_resolver_rc [ "${RC}" -eq 0 ]

newcase api_down
touch "${ROOT}/down"
run_at "${NOW}" "${W[@]}"
check api_down_ran grep -q "^get /api/session/ses_w" "${ROOT}/calls.log"
check api_down_nopost [ "$(posts)" -eq 0 ]
check api_down_err [ -s "${SD}/ses_w.err" ]
check api_down_rc [ "${RC}" -eq 0 ]

newcase watch_fresh
sess ses_w $((NOW - 3000)) $((NOW - 3500))
mkdir -p "${ROOT}/${CASE}/logs"
touch "${ROOT}/${CASE}/logs/a.log" && settime "${ROOT}/${CASE}/logs/a.log" "${NOW}"
run_at "${NOW}" "${W[@]}" --watch "${ROOT}/${CASE}/logs/*.log"
check watch_fresh [ "$(posts)" -eq 0 ]
check watch_fresh_ran ran

newcase repo_fresh
sess ses_w $((NOW - 3000)) $((NOW - 3500))
mkdir -p "${ROOT}/${CASE}/repo"
touch "${ROOT}/${CASE}/repo/f.c" && settime "${ROOT}/${CASE}/repo/f.c" "${NOW}"
run_at "${NOW}" "${W[@]}" --repo "${ROOT}/${CASE}/repo"
check repo_fresh [ "$(posts)" -eq 0 ]
check repo_fresh_ran ran

newcase repo_git_ignored
sess ses_w $((NOW - 3000)) $((NOW - 3500))
mkdir -p "${ROOT}/${CASE}/repo/.git/objects"
touch "${ROOT}/${CASE}/repo/.git/objects/x" && settime "${ROOT}/${CASE}/repo/.git/objects/x" "${NOW}"
run_at "${NOW}" "${W[@]}" --repo "${ROOT}/${CASE}/repo"
check repo_git_ignored call_with '^post /api/session/ses_w/prompt' 'steer'

newcase bad_id
run_at "${NOW}" --worker 'ses_x/../y' --main ses_m
check bad_id_rc [ "${RC}" -eq 2 ]
check bad_id_nocalls [ ! -e "${ROOT}/calls.log" ]

newcase two_workers
sess ses_a $((NOW - 3000)) $((NOW - 3500))
sess ses_b $((NOW - 60)) $((NOW - 3500))
run_at "${NOW}" --worker ses_a --main ses_m
run_at "${NOW}" --worker ses_b --main ses_m
check two_workers_a state_have '^steered=' ses_a
check two_workers_b_ran grep -q '^get /api/session/ses_b' "${ROOT}/calls.log"
check two_workers_b bash -c "[ ! -e '${SD}/ses_b.state' ] || ! grep -q steered '${SD}/ses_b.state'"

newcase stop_passed
sess ses_w $((NOW - 630)) $((NOW - 3000))
echo "steered=$((NOW - 660))" >"${SD}/ses_w.state"
run_at "${NOW}" "${W[@]}" --stop interrupt --repo "${ROOT}/${CASE}" --watch '/x/*.log'
check stop_passed call_with '^post /api/session/ses_child1/prompt' 'stop: interrupt' 'repo: ' 'watch: /x/\*\.log'

if [[ "${failures}" -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
echo "all passed"
