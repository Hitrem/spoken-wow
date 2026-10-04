#!/usr/bin/env bash
# Builds the last release of each retired CurseForge project, spoken-quests, spoken-zones and
# spoken-books: a zip holding only a tombstone under the folder name that project shipped.
#
#   ./scripts/spoken/package-retired.sh                 # dist/SpokenQuests-<version>.zip, and Zones', Books'
#   ALLOW_DIRTY=1 ./scripts/spoken/package-retired.sh   # build from an uncommitted tree
#
# WHY A RELEASE AT ALL. The modules ship inside Spoken's zip now, from Spoken_Quests,
# Spoken_Zones and Spoken_Books. A player who still has a retired project installed keeps its
# folder, the module's full old copy, which loads beside the renamed one and voices every line a
# second time. Updating the retired project to this file replaces that copy with a tombstone,
# a .toc that never loads (addons/SpokenQuests/SpokenQuests.toc explains it), and the old names
# are why the modules moved: whatever the CurseForge app does to a retired project's folders on
# update or removal, it now does to folders Spoken's zip does not ship.
#
# The tombstone goes under every .toc name the old folder had on Blizzard's clients, so no
# client finds a name the tombstone missed and loads the old Lua through it. Each copy carries
# the Interface line of the .toc the same client reads from the renamed module. The 1.12, 2.4.3
# and 3.3.5 names are not here: those clients never had CurseForge, and the quests addon's own
# legacy zips carry the tombstone for them (scripts/quests/package.sh).
#
# The version is Spoken's, and every template must say the same: the three projects retire with
# the release that moved the folders, and the release scripts read each project's version off
# its template (scripts/quests/release.sh's player target, scripts/zones/release.sh and
# scripts/books/release.sh), so a template that drifted would name a zip this did not build.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPOKEN_TOC="$REPO/addons/Spoken/Spoken.toc"
DIST="${DIST:-$REPO/dist}"
# shellcheck source=../lib/tombstone.sh
source "$REPO/scripts/lib/tombstone.sh"

# old folder -> the folder that replaced it, and the flavor suffixes the old folder's .toc names
# carried, from its history: `git log --format= --name-only -- 'addons/SpokenQuests/*.toc'` on a
# commit before the rename; "-" is the unsuffixed name. A case rather than an associative array:
# macOS still ships bash 3.2.
RETIRED=(SpokenQuests SpokenZones SpokenBooks)
renamed_to() { case "$1" in
  SpokenQuests) echo "Spoken_Quests";;
  SpokenZones)  echo "Spoken_Zones";;
  SpokenBooks)  echo "Spoken_Books";;
esac; }
old_suffixes() { case "$1" in
  SpokenQuests) echo "- _Mainline _TBC _Vanilla _Wrath";;
  SpokenZones)  echo "-";;
  SpokenBooks)  echo "-";;
esac; }

[ -f "$SPOKEN_TOC" ] || { echo "error: $SPOKEN_TOC not found" >&2; exit 1; }
version="$(sed -n 's/^## Version:[[:space:]]*//p' "$SPOKEN_TOC" | head -1 | tr -d '\r')"
[ -n "$version" ] || { echo "error: no '## Version:' line in $SPOKEN_TOC" >&2; exit 1; }

# A zip built from uncommitted edits cannot be traced back to a commit later.
if [ -z "${ALLOW_DIRTY:-}" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  paths=()
  for old in "${RETIRED[@]}"; do paths+=("addons/$old" "addons/$(renamed_to "$old")"); done
  if [ -n "$(git -C "$REPO" status --porcelain -- "${paths[@]}")" ]; then
    echo "error: a tombstone template or the module it reads from has uncommitted changes." >&2
    echo "       Commit them, or re-run with ALLOW_DIRTY=1 to package anyway." >&2
    exit 1
  fi
fi

mkdir -p "$DIST"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

for old in "${RETIRED[@]}"; do
  new="$(renamed_to "$old")"
  template="$REPO/addons/$old/$old.toc"
  [ -f "$template" ] || { echo "error: $template not found" >&2; exit 1; }
  template_version="$(sed -n 's/^## Version:[[:space:]]*//p' "$template" | head -1 | tr -d '\r')"
  [ "$template_version" = "$version" ] || { echo "error: $old.toc says $template_version, Spoken.toc says $version" >&2; exit 1; }

  mkdir -p "$staging/$old"
  for suffix in $(old_suffixes "$old"); do
    [ "$suffix" != "-" ] || suffix=""
    source_toc="$REPO/addons/$new/$new$suffix.toc"
    [ -f "$source_toc" ] || { echo "error: no $source_toc to take the ${old}$suffix.toc Interface line from" >&2; exit 1; }
    tombstone_toc "$template" "$source_toc" "$staging/$old/$old$suffix.toc"
  done

  zip_path="$DIST/$old-$version.zip"
  rm -f "$zip_path"
  (cd "$staging" && zip -r -q -X "$zip_path" "$old")
  echo "built $(basename "$zip_path")   tocs: $(unzip -Z1 "$zip_path" | grep -c '\.toc$')"
done
