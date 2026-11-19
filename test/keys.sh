#!/usr/bin/env bash
# Hermetic test for `./install --keys`: generated identities, file:// stores,
# throwaway HOME per simulated machine. Touches nothing outside a temp dir.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Short path: gpg-agent sockets live in GNUPGHOME and have a ~100 char limit.
ROOT="$(mktemp -d /tmp/keys.XXXXXX)"
FX="${ROOT}/fixture-gnupg"
PRISTINE="${ROOT}/backup-pristine"
HOMES=()
declare -A FPR FX_SIGN FX_ENCR

cleanup() {
  local h
  for h in "${HOMES[@]}" "${FX}"; do
    GNUPGHOME="${h}" gpgconf --kill all 2>/dev/null || true
  done
  if [ -n "${KEYS_KEEP:-}" ]; then
    echo "kept ${ROOT}"
  else
    rm -rf "${ROOT}"
  fi
}
trap cleanup EXIT

CURRENT=
fail() {
  printf "  \e[31mFAIL\e[0m %s: %s\n" "${CURRENT}" "${*}" >&2
  local log
  for log in "${ROOT}"/m*.log; do
    [ -f "${log}" ] && {
      printf -- "--- %s\n" "${log##*/}"
      tail -n 25 "${log}"
    } >&2
  done
  exit 1
}

set -o errtrace
trap 'fail "unexpected error: ${BASH_COMMAND} (line ${LINENO})"' ERR

PASSPHRASE="keys-test"

fx_gpg() {
  GNUPGHOME="${FX}" gpg --batch --quiet --pinentry-mode loopback --passphrase "${PASSPHRASE}" "${@}"
}

# Answers every agent prompt with the fixture passphrase, so the script runs
# through the same pinentry path it uses on a real machine.
write_fake_pinentry() {
  cat >"${ROOT}/pinentry" <<EOF
#!/bin/sh
echo "OK Pleased to meet you"
while read -r cmd _; do
  case "\${cmd}" in
  GETPIN) printf 'D %s\nOK\n' "${PASSPHRASE}" ;;
  BYE) echo OK; exit 0 ;;
  *) echo OK ;;
  esac
done
EOF
  chmod +x "${ROOT}/pinentry"
}

# Refuses every passphrase prompt, to prove a decrypt needed none.
write_failing_pinentry() {
  cat >"${ROOT}/pinentry-fail" <<'EOF'
#!/bin/sh
echo "OK Pleased to meet you"
while read -r cmd _; do
  case "${cmd}" in
  GETPIN) echo "ERR 83886179 Operation cancelled" ;;
  BYE) echo OK; exit 0 ;;
  *) echo OK ;;
  esac
done
EOF
  chmod +x "${ROOT}/pinentry-fail"
}

# -- fixture ------------------------------------------------------------------

make_identity() {
  local id="${1}" uid="${2}" fpr encr

  fx_gpg --quick-generate-key "${uid}" ed25519 cert 3y 2>/dev/null
  fpr="$(GNUPGHOME="${FX}" gpg --list-keys --with-colons "${uid}" | awk -F: '$1=="fpr"{print $10; exit}')"
  fx_gpg --quick-add-key "${fpr}" ed25519 sign 2y
  fx_gpg --quick-add-key "${fpr}" cv25519 encr 2y

  # The backup holds only what no machine can recreate: the primary and the
  # shared encryption subkey. Machine 1's signing secret stays on machine 1.
  encr="$(subkey_fprs "${FX}" "${fpr}" e | head -1)"
  fx_gpg --armor --export-secret-keys "${fpr}!" "${encr}!" >"${PRISTINE}/${id}-secret.asc"
  [ "$(GNUPGHOME="${FX}" gpg --show-keys --with-colons "${PRISTINE}/${id}-secret.asc" |
    awk -F: '$1=="ssb"{print $12}')" = "e" ] || fail "fixture ${id}-secret.asc is not primary + encryption"
  fx_gpg --armor --export-secret-keys "${fpr}!" >"${PRISTINE}/${id}-primary.asc"
  fx_gpg --armor --export "${fpr}" >"${PRISTINE}/${id}-public.asc"
  cp "${FX}/openpgp-revocs.d/${fpr}.rev" "${PRISTINE}/${id}-revocation.rev"

  # The work store names its recipient by email, as `gopass init` allows.
  if [ "${id}" = "work" ]; then
    seed_store "${id}" "w@example.com"
  else
    seed_store "${id}" "0x${fpr}"
  fi
  FPR[${id}]="${fpr}"
  FX_SIGN[${id}]="$(subkey_fprs "${FX}" "${fpr}" s | head -1)"
  FX_ENCR[${id}]="$(subkey_fprs "${FX}" "${fpr}" e | head -1)"
}

seed_store() {
  local id="${1}" fpr="${2}"
  local work="${ROOT}/seed-${id}"

  git init -q "${work}"
  printf "%s\n" "${fpr}" >"${work}/.gpg-id"
  mkdir -p "${work}/test"
  printf "secret-%s\n" "${id}" |
    GNUPGHOME="${FX}" gpg --batch --quiet --trust-model always -e -r "${fpr}" -o "${work}/test/entry.gpg"
  git -C "${work}" add -A
  git -C "${work}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false \
    commit -q -m seed
  git clone -q --bare "${work}" "${ROOT}/remote-${id}.git"
}

# -- keyring queries ----------------------------------------------------------

# Prints "<cap> <secret> <fpr>" per subkey; secret is "+" (usable) or "#" (stub).
subkeys() {
  local home="${1}" fpr="${2}"
  { GNUPGHOME="${home}" gpg -K --with-colons --with-subkey-fingerprint "${fpr}" 2>/dev/null || true; } |
    awk -F: '$1=="ssb"{cap=$12; sec=($15=="#")?"#":"+"; want=1; next}
             $1=="fpr" && want {print cap, sec, $10; want=0}'
}

subkey_fprs() {
  local home="${1}" fpr="${2}" cap="${3}"
  subkeys "${home}" "${fpr}" | awk -v c="${cap}" '$1 ~ c {print $3}'
}

primary_secret() {
  { GNUPGHOME="${1}" gpg -K --with-colons "${2}" 2>/dev/null || true; } |
    awk -F: '$1=="sec"{print ($15=="#")?"#":"+"; exit}'
}

unattended_fprs() {
  { GNUPGHOME="${ROOT}/${1}/.config/gnupg" gpg -K --with-colons 2>/dev/null || true; } |
    awk -F: '$1=="sec"{fpr=""; want=1; next}
             $1=="fpr" && want {fpr=$10; want=0; next}
             $1=="uid" && fpr!="" && index($10, " unattended (") {print fpr; fpr=""}'
}

public_subkey_count() {
  GNUPGHOME="${FX}" gpg --show-keys --with-colons "${1}" | grep -c '^sub:'
}

# -- simulated machine --------------------------------------------------------

# machine NAME IDENTITY_NAME IDENTITY_EMAIL: a fresh HOME as phase 1 leaves it.
machine() {
  local name="${1}" user_name="${2}" user_email="${3}"
  local home="${ROOT}/${name}" dots="${ROOT}/${name}/dotfiles"

  mkdir -p "${home}/.config/git" "${home}/.ssh" "${dots}/.config/git"
  cp "${REPO}/install" "${dots}/install"
  cp "${REPO}/.config/git/config" "${dots}/.config/git/config"
  git init -q "${dots}"
  git -C "${dots}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m init

  ln -s "${dots}/.config/git/config" "${home}/.config/git/config"
  cat >"${home}/.config/git/config.local" <<EOF
[user]
  name = ${user_name}
  email = ${user_email}
[core]
  sshCommand = "ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"
EOF

  mkdir -p "${home}/.config/gnupg"
  chmod 700 "${home}/.config/gnupg"
  printf "pinentry-program %s\n" "${ROOT}/pinentry" >"${home}/.config/gnupg/gpg-agent.conf"
  HOMES+=("${home}/.config/gnupg")
}

# run_keys NAME DIR [ARGS...]: phase 2 on that machine, no TTY.
run_keys() {
  local name="${1}" dir="${2}"
  shift 2
  local home="${ROOT}/${name}"

  env -i PATH="${PATH}" HOME="${home}" USER="${USER:-test}" LANG=C.UTF-8 \
    GNUPGHOME="${home}/.config/gnupg" DOTFILES_PATH="${home}/dotfiles" \
    GOPASS_PERSONAL_URL="${PERSONAL_URL-file://${ROOT}/remote-personal.git}" \
    GOPASS_WORK_URL="${WORK_URL-file://${ROOT}/remote-work.git}" \
    bash ${KEYS_TRACE:+-x} "${home}/dotfiles/install" --keys "${dir}" "${@}" </dev/null >"${home}.log" 2>&1
}

on() {
  local name="${1}"
  shift
  local home="${ROOT}/${name}"
  env -i PATH="${PATH}" HOME="${home}" USER="${USER:-test}" LANG=C.UTF-8 \
    GNUPGHOME="${home}/.config/gnupg" "${@}"
}

# -- assertions ---------------------------------------------------------------

assert_identity_restored() {
  local name="${1}" id="${2}"
  local gh="${ROOT}/${name}/.config/gnupg"
  local fpr="${FPR[${id}]}" fx_sign="${FX_SIGN[${id}]}" fx_encr="${FX_ENCR[${id}]}" signs

  [ "$(primary_secret "${gh}" "${fpr}")" = "#" ] || fail "${id}: primary secret still on disk"
  subkeys "${gh}" "${fpr}" | grep -q "^s # ${fx_sign}$" ||
    fail "${id}: imported signing subkey secret kept"
  subkeys "${gh}" "${fpr}" | grep -q "^e + ${fx_encr}$" ||
    fail "${id}: shared encryption subkey not usable"
  signs="$(subkeys "${gh}" "${fpr}" | awk '$1 ~ /s/ && $2=="+"' | wc -l)"
  [ "${signs}" -eq 1 ] || fail "${id}: expected exactly 1 usable signing subkey, got ${signs}"
}

own_sign() {
  subkeys "${ROOT}/${1}/.config/gnupg" "${FPR[${2}]}" | awk '$1 ~ /s/ && $2=="+" {print $3}'
}

# -- scenarios ----------------------------------------------------------------

t1_work_pc_fresh() {
  machine m2 "Test Work" "w@example.com"
  run_keys m2 "${DIR}" --work-pc || fail "install --keys exited non-zero (see m2.log)"

  assert_identity_restored m2 personal
  assert_identity_restored m2 work

  local cfg="${ROOT}/m2/.config/git"
  [ "$(git config --file "${cfg}/config.local" user.signingkey)" = "${FPR[work]}" ] ||
    fail "config.local signingkey is not the work fingerprint"
  [ "$(git config --file "${cfg}/config.local" commit.gpgsign)" = "true" ] ||
    fail "commit signing not enabled"
  [ "$(git config --file "${cfg}/config.local.personal" user.signingkey)" = "${FPR[personal]}" ] ||
    fail "config.local.personal signingkey is not the personal fingerprint"

  local scratch="${ROOT}/m2/scratch" key
  on m2 git init -q "${scratch}"
  on m2 git -C "${scratch}" commit -q --allow-empty -m signed || fail "signed commit failed"
  key="$(on m2 git -C "${scratch}" log -1 --format=%GK)"
  [[ "$(own_sign m2 work)" == *"${key}" ]] || fail "work commit not signed by the new subkey (${key})"

  on m2 git -C "${ROOT}/m2/dotfiles" commit -q --allow-empty -m signed ||
    fail "signed dotfiles commit failed"
  key="$(on m2 git -C "${ROOT}/m2/dotfiles" log -1 --format=%GK)"
  [[ "$(own_sign m2 personal)" == *"${key}" ]] ||
    fail "dotfiles commit not signed by the personal subkey (${key})"

  if grep -q "may not decrypt" "${ROOT}/m2.log"; then
    fail "false .gpg-id warning for a recipient named by email"
  fi

  local id
  for id in personal work; do
    grep -q -F "gh gpg-key delete ${FPR[${id}]: -16} --yes" "${ROOT}/m2.log" ||
      fail "no GitHub delete step for the ${id} key"
    grep -q -F "gh gpg-key add ${DIR}/${id}-public.asc --title" "${ROOT}/m2.log" ||
      fail "no GitHub add step for the ${id} key"
  done

  [ "$(on m2 gopass show -o test/entry 2>/dev/null)" = "secret-personal" ] ||
    fail "personal store entry unreadable"
  [ "$(on m2 gopass show -o work/test/entry 2>/dev/null)" = "secret-work" ] ||
    fail "work store entry unreadable"

  [ "$(public_subkey_count "${DIR}/personal-public.asc")" -eq 3 ] ||
    fail "personal-public.asc should hold 3 subkeys"
  [ "$(public_subkey_count "${DIR}/work-public.asc")" -eq 3 ] ||
    fail "work-public.asc should hold 3 subkeys"

  M2_SIGN_personal="$(own_sign m2 personal)"

  local ufpr e store="${ROOT}/m2/.local/share/gopass/stores/work-unattended"
  [ "$(unattended_fprs m2 | wc -l)" -eq 1 ] || fail "expected exactly 1 unattended key"
  ufpr="$(unattended_fprs m2)"
  [ -z "$(subkey_fprs "${ROOT}/m2/.config/gnupg" "${ufpr}" s)" ] || fail "unattended key can sign"
  [ -n "$(subkey_fprs "${ROOT}/m2/.config/gnupg" "${ufpr}" e)" ] || fail "unattended key cannot encrypt"
  # gopass records the long key ID; it must name this key and nothing else.
  [ "$(wc -l <"${store}/.gpg-id")" -eq 1 ] &&
    [[ "${ufpr}" == *"$(sed 's/^0x//' "${store}/.gpg-id")" ]] ||
    fail ".gpg-id does not name the unattended key"
  [ ! -e "${store}/.git" ] || fail "unattended store has git"
  on m2 gopass mounts | grep -q work-unattended || fail "work-unattended not mounted"
  for e in jira-pat confluence-pat llmi-api-token; do
    grep -q -F "gopass insert work-unattended/${e}" "${ROOT}/m2.log" || fail "no insert step for ${e}"
  done
  grep -q -F "uvx mcp-atlassian==0.24.6 --version" "${ROOT}/m2.log" || fail "no uvx pre-warm step"

  printf 'tok-123\n' | on m2 gopass insert -f work-unattended/jira-pat >/dev/null 2>&1 ||
    fail "insert into the unattended store failed"
  printf "pinentry-program %s\n" "${ROOT}/pinentry-fail" >"${ROOT}/m2/.config/gnupg/gpg-agent.conf"
  on m2 gpgconf --kill gpg-agent
  [ "$(on m2 gopass show -o work-unattended/jira-pat 2>/dev/null)" = "tok-123" ] ||
    fail "unattended entry needs a passphrase"
  if on m2 gopass show -o work/test/entry >/dev/null 2>&1; then
    fail "work store decrypted without a passphrase (test is not meaningful)"
  fi
  printf "pinentry-program %s\n" "${ROOT}/pinentry" >"${ROOT}/m2/.config/gnupg/gpg-agent.conf"
  on m2 gpgconf --kill gpg-agent
}

t2_third_machine() {
  machine m3 "Test Work" "w@example.com"
  run_keys m3 "${DIR}" --work-pc || fail "install --keys exited non-zero (see m3.log)"

  assert_identity_restored m3 personal
  local m3_sign
  m3_sign="$(own_sign m3 personal)"
  [ "${m3_sign}" != "${M2_SIGN_personal}" ] || fail "m3 reused m2's signing subkey"

  GNUPGHOME="${FX}" gpg --show-keys --with-colons --with-subkey-fingerprint \
    "${DIR}/personal-public.asc" | grep -q "^fpr:.*:${M2_SIGN_personal}:" ||
    fail "m3's export dropped m2's signing subkey"
  [ "$(public_subkey_count "${DIR}/personal-public.asc")" -eq 4 ] ||
    fail "personal-public.asc should hold 4 subkeys"
}

t3_rerun_noop() {
  local before after
  before="$(cksum <"${DIR}/personal-public.asc")"
  run_keys m2 "${DIR}" --work-pc || fail "re-run exited non-zero (see m2.log)"
  after="$(cksum <"${DIR}/personal-public.asc")"

  [ "${before}" = "${after}" ] || fail "re-run republished the key"
  [ "$(unattended_fprs m2 | wc -l)" -eq 1 ] || fail "re-run created a second unattended key"
  assert_identity_restored m2 personal
  assert_identity_restored m2 work
}

t4_rollback() {
  local dir="${ROOT}/backup-t4"
  cp -R "${PRISTINE}" "${dir}"
  printf "not a key\n" >"${dir}/work-public.asc"

  machine m4 "Test Work" "w@example.com"
  if run_keys m4 "${dir}" --work-pc; then fail "expected non-zero exit"; fi

  local gh="${ROOT}/m4/.config/gnupg"
  if GNUPGHOME="${gh}" gpg --list-keys "${FPR[work]}" >/dev/null 2>&1; then
    fail "work key left in the keyring after rollback"
  fi
  assert_identity_restored m4 personal
  [ -z "$(find "${ROOT}/m4" -name '*.asc' -path '*tmp*' 2>/dev/null)" ] ||
    fail "temporary secret export left behind"
}

t5_personal_only() {
  local dir="${ROOT}/backup-t5"
  cp -R "${PRISTINE}" "${dir}"

  machine m5 "Test Personal" "p@example.com"
  WORK_URL="" run_keys m5 "${dir}" || fail "install --keys exited non-zero (see m5.log)"

  assert_identity_restored m5 personal
  if GNUPGHOME="${ROOT}/m5/.config/gnupg" gpg --list-keys "${FPR[work]}" >/dev/null 2>&1; then
    fail "work key imported on a personal machine"
  fi
  [ "$(git config --file "${ROOT}/m5/.config/git/config.local" user.signingkey)" = "${FPR[personal]}" ] ||
    fail "config.local signingkey is not the personal fingerprint"
  [ ! -e "${ROOT}/m5/.config/git/config.local.personal" ] || fail "config.local.personal written"
  [ ! -e "${ROOT}/m5/.local/share/gopass/stores/work" ] || fail "work store cloned"
  [ -z "$(unattended_fprs m5)" ] || fail "unattended key on a personal machine"
  [ ! -e "${ROOT}/m5/.local/share/gopass/stores/work-unattended" ] ||
    fail "unattended store on a personal machine"
}

t6_existing_primary() {
  local dir="${ROOT}/backup-t6"
  cp -R "${PRISTINE}" "${dir}"

  machine m6 "Test Personal" "p@example.com"
  on m6 gpg --batch --quiet --pinentry-mode loopback --passphrase "${PASSPHRASE}" \
    --import "${PRISTINE}/personal-secret.asc" 2>/dev/null
  printf "not a key\n" >"${dir}/personal-public.asc"

  if run_keys m6 "${dir}"; then fail "expected a refusal on a machine holding the primary"; fi
  [ "$(primary_secret "${ROOT}/m6/.config/gnupg" "${FPR[personal]}")" = "+" ] ||
    fail "a primary that was already on this machine was deleted or stripped"
  grep -q "already holds the primary" "${ROOT}/m6.log" || fail "no explanation printed"
}

t7_double_interrupt() {
  command -v setsid >/dev/null 2>&1 || {
    echo "  (skipped: no setsid)"
    return 0
  }
  local dir="${ROOT}/backup-t7" bin="${ROOT}/m7-bin" real
  cp -R "${PRISTINE}" "${dir}"
  printf "not a key\n" >"${dir}/personal-public.asc"
  real="$(command -v gpg)"

  # Ctrl-C again while the rollback deletes the key: the whole foreground
  # process group gets SIGINT, as a terminal would send it.
  mkdir -p "${bin}"
  cat >"${bin}/gpg" <<EOF
#!/usr/bin/env bash
if [[ " \${*} " == *" --delete-secret-and-public-key "* ]] && [ ! -e "${bin}/fired" ]; then
  touch "${bin}/fired"
  kill -INT -- "-\$(ps -o pgid= -p \$\$ | tr -d ' ')"
  sleep 1
fi
exec "${real}" "\${@}"
EOF
  chmod +x "${bin}/gpg"

  machine m7 "Test Personal" "p@example.com"
  PATH="${bin}:${PATH}" setsid bash -c "$(declare -f run_keys); ROOT='${ROOT}' run_keys m7 '${dir}'" || true

  [ -e "${bin}/fired" ] || fail "the rollback never ran"
  [ -z "$(primary_secret "${ROOT}/m7/.config/gnupg" "${FPR[personal]}")" ] ||
    fail "primary left on disk after a second Ctrl-C during rollback"
}

t8_expired_encryption() {
  local fx="${ROOT}/fx8" dir="${ROOT}/backup-t8" fpr
  mkdir -p "${fx}" "${dir}"
  chmod 700 "${fx}"
  HOMES+=("${fx}")
  g8() { GNUPGHOME="${fx}" gpg --batch --quiet --pinentry-mode loopback --passphrase "${PASSPHRASE}" "${@}"; }

  g8 --quick-generate-key "Test Expired <x@example.com>" ed25519 cert 3y 2>/dev/null
  fpr="$(GNUPGHOME="${fx}" gpg --list-keys --with-colons | awk -F: '$1=="fpr"{print $10; exit}')"
  g8 --quick-add-key "${fpr}" ed25519 sign 2y
  g8 --quick-add-key "${fpr}" cv25519 encr seconds=2
  sleep 3
  g8 --armor --export-secret-keys "${fpr}" >"${dir}/personal-secret.asc"
  g8 --armor --export "${fpr}" >"${dir}/personal-public.asc"
  GNUPGHOME="${fx}" gpg --export-ownertrust >"${dir}/ownertrust.txt"

  machine m8 "Test Expired" "x@example.com"
  if run_keys m8 "${dir}"; then fail "expected a refusal for an expired encryption subkey"; fi
  grep -q "encryption subkey expired" "${ROOT}/m8.log" || fail "no 'renew it first' explanation"
  if GNUPGHOME="${ROOT}/m8/.config/gnupg" gpg --list-keys "${fpr}" >/dev/null 2>&1; then
    fail "key imported although it cannot be used"
  fi
}

# After a renewal only *-public.asc carries the new expiry; *-secret.asc keeps
# the old one, which may already have passed.
t10_renewed_in_public() {
  local fx="${ROOT}/fx10" dir="${ROOT}/backup-t10" fpr encr expiry
  mkdir -p "${fx}" "${dir}"
  chmod 700 "${fx}"
  HOMES+=("${fx}")
  g10() { GNUPGHOME="${fx}" gpg --batch --quiet --pinentry-mode loopback --passphrase "${PASSPHRASE}" "${@}"; }

  g10 --quick-generate-key "Test Renewed <r@example.com>" ed25519 cert 3y 2>/dev/null
  fpr="$(GNUPGHOME="${fx}" gpg --list-keys --with-colons | awk -F: '$1=="fpr"{print $10; exit}')"
  g10 --quick-add-key "${fpr}" ed25519 sign 2y
  g10 --quick-add-key "${fpr}" cv25519 encr seconds=4
  encr="$(subkey_fprs "${fx}" "${fpr}" e | head -1)"
  # An older backup layout that still carries machine 1's signing secret.
  g10 --armor --export-secret-keys "${fpr}" >"${dir}/personal-secret.asc"
  sleep 2
  g10 --quick-set-expire "${fpr}" 2y "${encr}"
  g10 --armor --export "${fpr}" >"${dir}/personal-public.asc"
  GNUPGHOME="${fx}" gpg --export-ownertrust >"${dir}/ownertrust.txt"
  sleep 3

  machine m10 "Test Renewed" "r@example.com"
  run_keys m10 "${dir}" || fail "renewed encryption subkey refused (see m10.log)"

  expiry="$(GNUPGHOME="${ROOT}/m10/.config/gnupg" gpg -K --with-colons "${fpr}" |
    awk -F: '$1=="ssb" && $12 ~ /s/ && $15 != "#" {print $7; exit}')"
  [ -n "${expiry}" ] && [ "${expiry}" -gt "$(($(date +%s) + 365 * 86400))" ] ||
    fail "new signing subkey did not take the renewed expiry (${expiry:-none})"
  [ "$(subkeys "${ROOT}/m10/.config/gnupg" "${fpr}" | awk '$1 ~ /s/ && $2=="+"' | wc -l)" = 1 ] ||
    fail "machine 1's signing secret from an older backup was kept"
}

# Stands in for ssh: requires -i to name an existing file (so a path split on
# a space fails), logs it, and runs the remote git command locally.
write_fake_ssh() {
  mkdir -p "${ROOT}/fakessh"
  cat >"${ROOT}/fakessh/ssh" <<EOF
#!/usr/bin/env bash
key=
while [ "\${#}" -gt 0 ]; do
  case "\${1}" in
  -i) key="\${2}"; shift 2 ;;
  -o | -p) shift 2 ;;
  -*) shift ;;
  *) break ;;
  esac
done
[ -f "\${key}" ] || { echo "fake ssh: -i '\${key}' is not a file" >&2; exit 255; }
printf "%s\n" "\${key}" >>"${ROOT}/fakessh.log"
shift
exec sh -c "\${*}"
EOF
  chmod +x "${ROOT}/fakessh/ssh"
}

t9_awkward_paths() {
  local name="m9 dir" home="${ROOT}/m9 dir" cmd
  write_fake_ssh

  machine "${name}" "Test Personal" "p@example.com"
  cp -R "${PRISTINE}" "${home}/key backup"
  : >"${home}/.ssh/id_ed25519"

  if run_keys "${name}" "~nosuchuser/key backup"; then fail "~user path accepted"; fi
  grep -q "full path" "${home}.log" || fail "~user path not explained"

  # shellcheck disable=SC2088 # the script must expand the literal tilde itself
  PATH="${ROOT}/fakessh:${PATH}" PERSONAL_URL="ssh://fakehost${ROOT}/remote-personal.git" \
    run_keys "${name}" "~/key backup/" || fail "install --keys exited non-zero (see '${name}.log')"

  assert_identity_restored "${name}" personal
  grep -q -x "${home}/.ssh/id_ed25519" "${ROOT}/fakessh.log" || fail "ssh was not given the key path intact"
  [ "$(on "${name}" gopass show -o test/entry 2>/dev/null)" = "secret-personal" ] ||
    fail "personal store entry unreadable"

  cmd="$(grep -E '^ +.*rm -r' "${home}.log" | tail -n 1)"
  [ -n "${cmd}" ] || fail "no clean-up command printed"
  bash -c "${cmd}" || fail "printed clean-up command failed: ${cmd}"
  [ ! -e "${home}/key backup" ] || fail "printed clean-up command left the folder"

  # GitHub steps: host taken from the store URL, path quoted for copy-paste.
  grep -q -F "GH_HOST=fakehost gh gpg-key add $(printf %q "${home}/key backup/personal-public.asc")" \
    "${home}.log" || fail "GitHub add step lacks the store's host or a pasteable path"
}

t11_unattended_expired() {
  local dir="${ROOT}/backup-t11" uid fpr encr line
  cp -R "${PRISTINE}" "${dir}"
  machine m11 "Test Work" "w@example.com"
  uid="${USER:-test} unattended (x)"
  on m11 gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "${uid}" ed25519 cert 2y 2>/dev/null
  fpr="$(unattended_fprs m11)"
  on m11 gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-add-key "${fpr}" cv25519 encr 2y
  encr="$(subkey_fprs "${ROOT}/m11/.config/gnupg" "${fpr}" e)"
  on m11 gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-set-expire "${fpr}" seconds=2
  on m11 gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-set-expire "${fpr}" seconds=2 "${encr}"
  sleep 3

  run_keys m11 "${dir}" --work-pc || fail "install --keys exited non-zero (see m11.log)"
  grep -q -F "quick-set-expire ${fpr}" "${ROOT}/m11.log" || fail "no renewal command printed"
  [ "$(unattended_fprs m11 | wc -l)" -eq 1 ] || fail "a second unattended key was created"
  [ ! -e "${ROOT}/m11/.local/share/gopass/stores/work-unattended" ] ||
    fail "store created for an expired key"

  # The printed repair must actually work.
  while read -r line; do
    on m11 bash -c "${line}" 2>/dev/null || fail "printed repair failed: ${line}"
  done < <(grep -E '^ +gpg --quick-set-expire ' "${ROOT}/m11.log")
  run_keys m11 "${dir}" --work-pc || fail "re-run after repair exited non-zero (see m11.log)"
  [ -f "${ROOT}/m11/.local/share/gopass/stores/work-unattended/.gpg-id" ] ||
    fail "store not created after the printed repair"
  printf 'tok-11\n' | on m11 gopass insert -f work-unattended/jira-pat >/dev/null 2>&1 ||
    fail "insert after repair failed"
  [ "$(on m11 gopass show -o work-unattended/jira-pat 2>/dev/null)" = "tok-11" ] ||
    fail "entry unreadable after repair"
}

t12_unattended_key_missing() {
  local dir="${ROOT}/backup-t12"
  cp -R "${PRISTINE}" "${dir}"
  machine m12 "Test Work" "w@example.com"
  run_keys m12 "${dir}" --work-pc || fail "install --keys exited non-zero (see m12.log)"
  on m12 gpg --batch --yes --delete-secret-and-public-key "$(unattended_fprs m12)" 2>/dev/null

  run_keys m12 "${dir}" --work-pc || fail "re-run exited non-zero (see m12.log)"
  grep -q -F "gopass mounts remove work-unattended" "${ROOT}/m12.log" || fail "no fix printed"
  [ -z "$(unattended_fprs m12)" ] || fail "a new unattended key was created for the old store"
}

# -- main ---------------------------------------------------------------------

mkdir -p "${FX}" "${PRISTINE}"
chmod 700 "${FX}"
write_fake_pinentry
write_failing_pinentry

if gpg --version | grep -q 'libgcrypt 1\.12\.0$'; then
  echo "NOTE: libgcrypt 1.12.0 randomly rejects imported cv25519 keys (Ubuntu LP #2174038);"
  echo "      an import failing with 'Bad secret key' here is that bug, not this script."
fi
make_identity personal "Test Personal <p@example.com>"
make_identity work "Test Work <w@example.com>"
GNUPGHOME="${FX}" gpg --export-ownertrust >"${PRISTINE}/ownertrust.txt"

DIR="${ROOT}/backup"
cp -R "${PRISTINE}" "${DIR}"

ALL_TESTS="t1_work_pc_fresh t2_third_machine t3_rerun_noop t4_rollback t5_personal_only
  t6_existing_primary t7_double_interrupt t8_expired_encryption t9_awkward_paths
  t10_renewed_in_public t11_unattended_expired t12_unattended_key_missing"
# KEYS_TESTS="t7_double_interrupt" bash test/keys.sh runs a subset.
# shellcheck disable=SC2086
for CURRENT in ${KEYS_TESTS:-${ALL_TESTS}}; do
  "${CURRENT}"
  printf "  \e[32mPASS\e[0m %s\n" "${CURRENT}"
done
