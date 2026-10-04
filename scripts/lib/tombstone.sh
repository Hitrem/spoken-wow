# The SpokenPlayer tombstone (addons/SpokenPlayer/SpokenPlayer.toc explains it), sourced by the
# packagers that ship Spoken.

# Write the tombstone to <output .toc>, with the Interface line of <Spoken .toc>, which is the
# .toc the same client reads from Spoken.
tombstone_toc() { # <Spoken .toc> <output .toc>
  local template="$REPO/addons/SpokenPlayer/SpokenPlayer.toc" interface
  interface="$(grep -m1 '^## Interface:' "$1" | tr -d '\r')"
  [ -n "$interface" ] || { echo "error: no '## Interface:' line in $1" >&2; exit 1; }
  sed "s|^## Interface:.*|$interface|" "$template" > "$2"
}
