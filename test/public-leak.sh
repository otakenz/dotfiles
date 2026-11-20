#!/usr/bin/env bash
# Blocks company identifiers from reaching this public repo. Scans the lines
# ADDED by the selected commits (merge results included, via combined diff),
# plus their commit messages, against case-insensitive extended regexes from
# a private pattern file. Lines already in the base are never checked.
#
#   test/public-leak.sh REV-LIST-ARGS...    e.g. BASE..HEAD, or SHA --not --remotes
#
# Env: PUBLIC_LEAK_PATTERNS (default ~/wiki/ai-workflow/public-leak-patterns.txt):
# one ERE per line, blank lines and '#' comments ignored. A missing file warns
# and passes. Exit 1 on a hit, 2 on an error (bad pattern, git failure).
# Bypass a push with `git push --no-verify`.

set -o nounset
set -o pipefail

if [ "$#" -eq 0 ]; then
  printf "usage: %s REV-LIST-ARGS...\n" "$0" >&2
  exit 2
fi

patterns="${PUBLIC_LEAK_PATTERNS:-${HOME}/wiki/ai-workflow/public-leak-patterns.txt}"
if [ ! -f "${patterns}" ]; then
  printf "WARN: no pattern file at %s; public-leak check skipped\n" "${patterns}" >&2
  exit 0
fi

work="$(mktemp -d)" || {
  printf "ERROR: cannot create a temp dir\n" >&2
  exit 2
}
trap 'rm -rf "${work}"' EXIT
active="${work}/patterns"
records="${work}/records"
content="${work}/content"

: >"${active}" || {
  printf "ERROR: cannot write %s\n" "${active}" >&2
  exit 2
}
grep -v -E '^[[:space:]]*(#|$)' "${patterns}" >"${active}"
rc=$?
if [ "${rc}" -ge 2 ]; then
  printf "ERROR: cannot read patterns from %s\n" "${patterns}" >&2
  exit 2
fi
if [ "${rc}" -eq 1 ]; then
  printf "WARN: no patterns in %s; public-leak check skipped\n" "${patterns}" >&2
  exit 0
fi

while IFS= read -r p; do
  grep -E -e "${p}" </dev/null >/dev/null 2>&1
  if [ "$?" -ge 2 ]; then
    printf "ERROR: invalid pattern in %s: %s\n" "${patterns}" "${p}" >&2
    exit 2
  fi
done <"${active}"

revs="${work}/revs"
git rev-list "$@" >"${revs}" || {
  printf "ERROR: git rev-list failed for: %s\n" "$*" >&2
  exit 2
}
[ -s "${revs}" ] || exit 0

# Added lines: records = "file:line: text", content = text alone (same line count).
git log -p --cc -U0 --text --no-textconv --no-ext-diff --no-color \
  --format='%x01commit' "$@" |
  tr '\0' ' ' |
  RECORDS="${records}" CONTENT="${content}" awk '
    BEGIN { rec = ENVIRON["RECORDS"]; con = ENVIRON["CONTENT"]; printf "" >rec; printf "" >con }
    /^\001commit/ { inhunk = 0; file = ""; next }
    !inhunk && /^diff / { file = ""; next }
    !inhunk && /^\+\+\+ / {
      file = substr($0, 5)
      if (file == "/dev/null") file = ""; else sub(/^b\//, "", file)
      next
    }
    !inhunk && /^(---|index|new |deleted |old |similarity |rename |copy |Binary )/ { next }
    /^@@/ {
      inhunk = 1
      match($0, /^@+/)
      ncols = RLENGTH - 1
      np = 0
      for (i = 2; i <= NF && $i !~ /^@/; i++) {
        c = substr($i, 1, 1)
        n = split(substr($i, 2), a, ",")
        cnt = (n > 1) ? a[2] + 0 : 1
        if (c == "-") { np++; rem_old[np] = cnt }
        else if (c == "+") { line = a[1] + 0; rem_new = cnt }
      }
      next
    }
    inhunk {
      if (substr($0, 1, 1) == "\\") next
      prefix = substr($0, 1, ncols)
      if (index(prefix, "-") == 0) {
        if (index(prefix, "+") > 0 && file != "") {
          text = substr($0, ncols + 1)
          printf "%s:%d: %s\n", file, line, text >>rec
          print text >>con
        }
        line++
        rem_new--
      }
      for (i = 1; i <= ncols; i++) if (substr(prefix, i, 1) != "+") rem_old[i]--
      done = (rem_new <= 0)
      for (i = 1; i <= ncols && done; i++) if (rem_old[i] > 0) done = 0
      if (done) inhunk = 0
    }
    !inhunk && /^\\/ { next }
  ' || {
  printf "ERROR: reading the diff failed\n" >&2
  exit 2
}

hits=""
if [ -s "${content}" ]; then
  matched="$(grep -a -n -i -E -f "${active}" "${content}")"
  rc=$?
  if [ "${rc}" -ge 2 ]; then
    printf "ERROR: pattern matching failed\n" >&2
    exit 2
  fi
  if [ "${rc}" -eq 0 ]; then
    hits="$(printf '%s\n' "${matched}" | cut -d: -f1 |
      awk 'NR == FNR { want[$1] = 1; next } FNR in want' - "${records}")"
  fi
fi

msgs=""
while read -r sha; do
  msg="$(git log -1 --format=%B "${sha}")" || {
    printf "ERROR: cannot read commit %s\n" "${sha}" >&2
    exit 2
  }
  m="$(printf '%s\n' "${msg}" | grep -a -i -E -f "${active}")"
  rc=$?
  if [ "${rc}" -ge 2 ]; then
    printf "ERROR: pattern matching failed\n" >&2
    exit 2
  fi
  [ "${rc}" -eq 0 ] && msgs+="$(printf '%s\n' "${m}" | sed "s/^/commit ${sha:0:12} message: /")"$'\n'
done <"${revs}"

if [ -z "${hits}" ] && [ -z "${msgs}" ]; then
  exit 0
fi

printf "Public-leak check: company identifiers in the pushed commits:\n" >&2
[ -n "${hits}" ] && printf "%s\n" "${hits}" >&2
[ -n "${msgs}" ] && printf "%s" "${msgs}" >&2
printf "Fix them, or push anyway with: git push --no-verify\n" >&2
exit 1
