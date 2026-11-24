#!/usr/bin/env bash
# Read-only disk survey for a WSL/Linux home. Deletes nothing.
# Stays on the root filesystem (-xdev), so /mnt/c, /mnt/d, ... are never read.
#
#   bash scan.sh            survey, folders >= 500M
#   bash scan.sh 2G         only folders >= 2G
#
# Columns: size, date of the newest file inside (not atime: relatime and
# package upgrades make atime useless), path.

set -o nounset
min="${1:-500M}"
min_bytes=$(numfmt --from=iec "${min}")

section() { printf '\n## %s\n' "$1"; }

survey() {  # survey DIR: children >= min with size and newest-file date
  local d s sz newest
  for d in "$1"/*/ "$1"/.[!.]*/; do
    [[ -d "${d}" && ! -L "${d%/}" ]] || continue
    s=$(du -xsb "${d}" 2>/dev/null | cut -f1)
    [ "${s:-0}" -ge "${min_bytes}" ] || continue
    sz=$(numfmt --to=iec "${s}")
    newest=$(find "${d}" -xdev -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    printf '%s\t%s\t%s\n' "${s}" "${sz}" "$(date -d "@${newest%.*}" +%F 2>/dev/null || echo '-')  ${d}"
  done | sort -rn | cut -f2-
}

section "Filesystem (df counts root-owned data that du below cannot read, e.g. /var/lib/docker)"
df -h / | tail -1

section "Home, folders >= ${min}"
survey "${HOME}"

for d in "${HOME}/.cache" "${HOME}/.local/share"; do
  section "${d}, folders >= ${min}"
  survey "${d}"
done

section "Single files >= 1G in home"
find "${HOME}" -xdev -type f -size +1G -printf '%s\t%TF\t%p\n' 2>/dev/null \
  | sort -rn | awk -F'\t' '{ printf "%.1fG\t%s\t%s\n", $1/2^30, $2, $3 }' | head -30

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  section "Docker (root dir: $(docker info --format '{{.DockerRootDir}}'))"
  docker system df
  echo
  echo "Images (same ID = tags of one image; 'in use' = has a container):"
  used=$(docker ps -a --format '{{.Image}}' | sort -u)
  docker images --format '{{.ID}}\t{{.Size}}\t{{.CreatedSince}}\t{{.Repository}}:{{.Tag}}' \
    | while IFS=$'\t' read -r id size age ref; do
        mark=""; grep -qxF "${ref}" <<<"${used}" && mark="  [in use]"
        printf '%s\t%s\t%s\t%s%s\n' "${id}" "${size}" "${age}" "${ref}" "${mark}"
      done
fi

section "Toolchains and environments"
command -v rustup >/dev/null 2>&1 && { echo "rustup:"; rustup toolchain list; }
command -v mise >/dev/null 2>&1 && { echo "mise (installed vs. requested):"; mise ls 2>/dev/null; }
for e in "${HOME}"/.local/share/mamba/envs/* "${HOME}"/miniconda3/envs/* "${HOME}"/.conda/envs/*; do
  [ -d "${e}" ] || continue
  printf 'conda env %s\t%s\tlast change %s\n' "$(du -sh "${e}" | cut -f1)" "${e}" \
    "$(stat -c %y "${e}/conda-meta/history" 2>/dev/null | cut -d' ' -f1)"
done

section "Largest apt packages (KB) and manually installed ones"
dpkg-query -Wf '${Installed-Size}\t${Package}\n' 2>/dev/null | sort -rn | head -25
echo
apt-mark showmanual 2>/dev/null | tr '\n' ' '
echo
command -v snap >/dev/null 2>&1 && snap list 2>&1 | head -5

section "Running user services (their data is in use)"
systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null
