#!/bin/bash
# Entrypoint of the All the Mods 11 server container.
#
# 1. asks CurseForge for the newest server pack and installs it when it differs from /data
# 2. installs the NeoForge version that the pack asks for
# 3. applies the settings given as environment variables
# 4. starts the server
set -euo pipefail

readonly MOD_ID=1148445
readonly API=https://api.curseforge.com/v1
readonly DATA=/data
readonly STAMP="$DATA/.installed_server_version"

cd "$DATA"

log() { printf '[atm11] %s\n' "$*"; }
die() { local code=$1; shift; log "ERROR: $*" >&2; exit "$code"; }

cf_get() { curl -fsS -H "x-api-key: ${CURSEFORGE_API_KEY}" -H 'Accept: application/json' "$1"; }

# ---------------------------------------------------------------- preconditions
case "${EULA:-}" in
  [Tt][Rr][Uu][Ee]) echo 'eula=true' > eula.txt ;;
  *) die 99 'Set EULA=true to accept the Minecraft EULA (https://aka.ms/MinecraftEULA).' ;;
esac
[[ -n "${CURSEFORGE_API_KEY:-}" ]] || die 98 'CURSEFORGE_API_KEY is not set. Create a free key at https://console.curseforge.com.'

# ---------------------------------------------------------------- newest server pack
find_server_pack() {
  local files pack_id
  files=$(cf_get "$API/mods/$MOD_ID/files?pageSize=50") || return 1
  # Server packs are flagged as such or named ServerFiles-<version>.zip; the newest one wins.
  jq -c '[.data[] | select(.isServerPack == true or (.fileName | test("^server-?files-.*[.]zip$"; "i")))]
         | sort_by(.fileDate) | last // empty' <<<"$files" | grep . && return 0
  # Otherwise follow the pointer from the newest regular file to its server pack.
  pack_id=$(jq -r '[.data[] | select(.serverPackFileId != null)] | sort_by(.fileDate) | last | .serverPackFileId // empty' <<<"$files")
  [[ -n "$pack_id" ]] || return 1
  cf_get "$API/mods/$MOD_ID/files/$pack_id" | jq -c '.data'
}

log 'Asking CurseForge for the newest server pack ...'
pack=$(find_server_pack) || die 96 'No server pack found on CurseForge (is the API key valid?).'
version=$(jq -r '.fileName' <<<"$pack" | sed -E 's/^[Ss]erver-?[Ff]iles-//; s/[.]zip$//')
url=$(jq -r '.downloadUrl // empty' <<<"$pack")
log "Newest server pack: $version"

installed=$(cat "$STAMP" 2>/dev/null || true)
neoforge_dir=libraries/net/neoforged/neoforge

# ---------------------------------------------------------------- install / update
if [[ "$installed" != "$version" || ! -d "$neoforge_dir" ]]; then
  [[ -n "$url" ]] || die 95 'CurseForge gave no download link for this server pack.'
  log "Installing '$version' (was: '${installed:-nothing}') ..."
  rm -rf mods libraries defaultconfigs kubejs packmenu

  zip="ServerFiles-$version.zip"
  curl -fL -H "x-api-key: ${CURSEFORGE_API_KEY}" -o "$zip" "$url" || die 9 'Download of the server pack failed.'
  unzip -q -o "$zip"
  rm -f "$zip"

  # Some packs unpack into a single ServerFiles-<version> folder: move its content up.
  for sub in ServerFiles-*/; do
    [[ -d "$sub" ]] || continue
    cp -a "$sub". "$DATA"/
    rm -rf "$sub"
  done

  # The pack names the NeoForge version it needs in startserver.sh; older packs ship a run.sh or the installer jar.
  nf=""
  [[ -f startserver.sh ]] && nf=$(sed -nE 's/^NEOFORGE_VERSION=([0-9][0-9A-Za-z.+-]*).*/\1/p' startserver.sh | head -n1 || true)
  [[ -z "$nf" && -f run.sh ]] && nf=$(grep -oE 'neoforge/[0-9][0-9A-Za-z.+-]*' run.sh | head -n1 | cut -d/ -f2 || true)
  if [[ -z "$nf" ]]; then
    installer=$(ls neoforge-*-installer.jar 2>/dev/null | head -n1 || true)
    nf=${installer#neoforge-}; nf=${nf%-installer.jar}
  fi
  nf=${NEOFORGE_VERSION:-$nf}
  [[ -n "$nf" ]] || die 8 'Could not tell which NeoForge version the pack needs (set NEOFORGE_VERSION).'

  installer="neoforge-$nf-installer.jar"
  if [[ ! -f "$installer" ]]; then
    log "Downloading NeoForge $nf ..."
    curl -fL -o "$installer" "https://maven.neoforged.net/releases/net/neoforged/neoforge/$nf/$installer" \
      || die 7 "Could not download the NeoForge installer $nf."
  fi
  log "Installing NeoForge $nf (this takes a while) ..."
  java -jar "$installer" --installServer
  rm -f "$installer" "$installer.log"

  echo "$version" > "$STAMP"
else
  log "Version $version is already installed."
fi

# ---------------------------------------------------------------- settings
if [[ -n "${JVM_OPTS:-}" ]]; then
  touch user_jvm_args.txt
  { grep -vE '^-Xm[sx]' user_jvm_args.txt || true; printf '%s\n' $JVM_OPTS; } > user_jvm_args.tmp
  mv user_jvm_args.tmp user_jvm_args.txt
fi

# The pack ships no server.properties; start with the basics and let Minecraft add the rest.
[[ -f server.properties ]] || printf 'motd=A Minecraft Server\nwhite-list=false\nallow-flight=true\nmax-players=5\nonline-mode=true\nserver-port=25565\n' > server.properties

# set_prop KEY VALUE: replace the value of KEY, or add the line. Values are never interpreted.
set_prop() {
  local tmp; tmp=$(mktemp -p "$DATA")
  if grep -q "^$1=" server.properties; then
    K=$1 V=$2 awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] } index($0, k "=") == 1 { print k "=" v; next } { print }' server.properties > "$tmp"
  else
    { cat server.properties; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
  fi
  mv "$tmp" server.properties
}

[[ -n "${MOTD:-}" ]]             && set_prop motd "$MOTD"
[[ -n "${ENABLE_WHITELIST:-}" ]] && set_prop white-list "$ENABLE_WHITELIST"
[[ -n "${ALLOW_FLIGHT:-}" ]]     && set_prop allow-flight "$ALLOW_FLIGHT"
[[ -n "${MAX_PLAYERS:-}" ]]      && set_prop max-players "$MAX_PLAYERS"
[[ -n "${ONLINE_MODE:-}" ]]      && set_prop online-mode "$ONLINE_MODE"
set_prop server-port 25565   # the container always listens on 25565; map the port outside

# add_players FILE "NAME1, NAME2" EXTRA_JSON: add each Minecraft account (looked up by name) to a JSON list.
add_players() {
  local file=$1 names=$2 extra=$3 name uuid
  [[ -f "$file" ]] || echo '[]' > "$file"
  local -a list
  IFS=',' read -ra list <<< "$names"
  for name in "${list[@]}"; do
    name=${name//[[:space:]]/}
    [[ -n "$name" ]] || continue
    if [[ ! "$name" =~ ^[A-Za-z0-9_]{3,16}$ ]]; then log "$file: skipping invalid name '$name'"; continue; fi
    uuid=$(curl -fsS "https://playerdb.co/api/player/minecraft/$name" | jq -r '.data.player.id // empty' || true)
    if [[ -z "$uuid" ]]; then log "$file: could not look up '$name'"; continue; fi
    if jq -e --arg u "$uuid" 'any(.[]; .uuid == $u)' "$file" > /dev/null; then log "$file: $name already listed"; continue; fi
    jq --arg u "$uuid" --arg n "$name" --argjson x "$extra" '. + [{uuid: $u, name: $n} + $x]' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    log "$file: added $name"
  done
}

add_players whitelist.json "${WHITELIST_USERS:-}" '{}'
add_players ops.json "${OP_USERS:-}" '{"level": 4, "bypassesPlayerLimit": false}'

# ---------------------------------------------------------------- start
touch user_jvm_args.txt
nf=$(ls -1 "$neoforge_dir" 2>/dev/null | sort -V | tail -n1 || true)
log "Starting the server (NeoForge ${nf:-unknown}) ..."
# exec: java becomes PID 1 and receives docker stop, so the world is saved before the container ends.
if [[ -n "$nf" && -f "$neoforge_dir/$nf/unix_args.txt" ]]; then
  exec java @user_jvm_args.txt "@$neoforge_dir/$nf/unix_args.txt" nogui
fi
chmod +x run.sh
exec ./run.sh nogui