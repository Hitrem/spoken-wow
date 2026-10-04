# Tombstones: a folder an older release installed, left holding nothing but .toc files that
# never load, so unzipping a release over the old folder leaves it nothing to run. Sourced by the
# packagers. Each template explains its own folder: addons/SpokenPlayer/SpokenPlayer.toc for
# Spoken's old name, addons/SpokenQuests, addons/SpokenZones and addons/SpokenBooks for the
# modules' folders before 3.0.0-beta.3 renamed them.

# Write <template .toc> to <output .toc>, with the Interface line of <interface .toc>, which is
# the .toc the same client reads from the folder that replaced the old one.
tombstone_toc() { # <template .toc> <interface .toc> <output .toc>
  local template="$1" interface
  [ -f "$template" ] || { echo "error: no tombstone template at $template" >&2; exit 1; }
  interface="$(grep -m1 '^## Interface:' "$2" | tr -d '\r')"
  [ -n "$interface" ] || { echo "error: no '## Interface:' line in $2" >&2; exit 1; }
  sed "s|^## Interface:.*|$interface|" "$template" > "$3"
}
