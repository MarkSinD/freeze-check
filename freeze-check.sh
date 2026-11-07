#!/usr/bin/env bash
# freeze-check — which hosting networks your connection can actually download from.
#
# Russian TSPU equipment "freezes" TCP connections to some hosting networks: the connection opens,
# a few packets pass (about 8 on mobile, about 25 on wired), then nothing, with no reset.
# This script downloads the first 256 KB of public test files from ~430 hosting points in ~200
# networks and shows which networks freeze. It also tests your own server and CDN sites.
#
# Usage:
#   freeze-check.sh scan [--quick]          all networks (2-4 min) or one point per network (~30 s)
#   freeze-check.sh url URL [URL...]        your own URLs, each tried 3 times
#   freeze-check.sh cdn                     ordinary sites on Cloudflare and other CDNs
#   freeze-check.sh owner IP|HOST           who owns the network and what we measured there
#   freeze-check.sh serve [PORT]            run ON YOUR SERVER: serve a 2 MB test file (needs python3)
#
# Options for scan, url, cdn:
#   --wait          start now, turn the VPN off afterwards: waits up to 10 min for a Russian address
#   --any-country   run even if the connection does not exit in Russia
#   --label TEXT    note saved in the results, e.g. "Beeline LTE, Moscow"
#   --out FILE      results file (default: results/<command>-<date>.tsv next to this script)
#   --tries N       attempts per URL for url and cdn (default 3)
#
# Needs: bash, curl. Works in Linux, macOS and Git Bash on Windows.
# Privacy: nothing is uploaded anywhere. Results hold no IP address; ipinfo.io is asked only for
# your country (to warn about a VPN left on) and, for `owner`, about the address you give.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TARGETS=${FREEZE_TARGETS:-$HERE/targets.tsv}
LIMIT=262144      # bytes to fetch per target
SLOW_MIN=65536    # a cut-off download above this is a slow link, not a freeze (freezes stop < 40 KB)
MAXT=${MAXT:-40}  # seconds per target
JOBS=${JOBS:-16}  # parallel downloads

CDN_URLS="https://www.cloudflare.com/
https://developers.cloudflare.com/
https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js
https://speed.cloudflare.com/__down?bytes=5000000
https://unpkg.com/react-dom@18.3.1/umd/react-dom.development.js
https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js
https://storage.googleapis.com/chrome-for-testing-public/157.0.8103.38/linux64/chrome-linux64.zip"

die() { echo "freeze-check: $*" >&2; exit 2; }

# One target line in -> one result line out: verdict bytes asn owner brand country url
# PASS: 256 KB arrived, or the whole (smaller) file did. SLOW: cut off by time above 64 KB.
# FROZEN: stopped after 1 B..64 KB. NONE: nothing arrived.
probe() {
  IFS=$'\t' read -r asn owner brand country url _ <<<"$1"
  local rcf; rcf=$(mktemp)
  got=$( { curl -sk -r 0-$((LIMIT - 1)) --connect-timeout 8 --speed-time 6 --speed-limit 1 -m "$MAXT" \
           "$url" 2>/dev/null; echo $? > "$rcf"; } | head -c "$LIMIT" | wc -c | tr -d ' ')
  local rc; rc=$(cat "$rcf" 2>/dev/null); rm -f "$rcf"
  if [ "$got" -ge "$LIMIT" ] || { [ "${rc:-1}" = 0 ] && [ "$got" -gt 0 ]; }; then v=PASS
  elif [ "$got" -ge "$SLOW_MIN" ]; then v=SLOW
  elif [ "$got" -gt 0 ]; then v=FROZEN
  else v=NONE; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$got" "$asn" "$owner" "$brand" "$country" "$url"
}
export -f probe
export LIMIT SLOW_MIN MAXT

country() { curl -s -m 8 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n '; }

targets() { grep -v '^#' "$TARGETS" | tail -n +2 | tr -d '\r'; }

# Shared options. Sets: WAIT ANY LABEL OUT TRIES QUICK ARGS
parse_opts() {
  WAIT=0 ANY=0 LABEL="" OUT="" TRIES=3 QUICK=0 ARGS=()
  while [ $# -gt 0 ]; do
    case $1 in
      --wait) WAIT=1 ;;
      --any-country) ANY=1 ;;
      --quick) QUICK=1 ;;
      --label) LABEL=${2:-}; shift ;;
      --out) OUT=${2:-}; shift ;;
      --tries) TRIES=${2:-3}; shift ;;
      --*) die "unknown option $1" ;;
      *) ARGS+=("$1") ;;
    esac
    shift
  done
}

# Make sure we measure from Russia. Sets C (country code).
need_russia() {
  C=$(country)
  if [ "$C" != "RU" ] && [ "$WAIT" = 1 ]; then
    echo "Connection exits in '${C:-unknown}'. Turn the VPN off now; waiting up to 10 minutes..."
    local i
    for i in $(seq 1 120); do
      sleep 5; C=$(country)
      [ "$C" = "RU" ] && { echo "Russian address seen, starting."; break; }
    done
  fi
  if [ "$C" != "RU" ] && [ "$ANY" = 0 ]; then
    echo "Your connection exits in '${C:-unknown}', not in Russia."
    echo "Turn the VPN off and run again, or add --wait and turn it off after starting. To run anyway: --any-country"
    exit 2
  fi
}

default_out() {
  [ -n "$OUT" ] && return
  mkdir -p "$HERE/results"
  OUT="$HERE/results/$1-$(date -u +%Y%m%d-%H%M).tsv"
}

cmd_scan() {
  parse_opts "$@"
  [ -f "$TARGETS" ] || die "no target list at $TARGETS"
  need_russia
  default_out "scan"
  local list; list=$(targets)
  [ "$QUICK" = 1 ] && list=$(printf '%s\n' "$list" | awk -F'\t' '!seen[$1]++')
  local n; n=$(printf '%s\n' "$list" | grep -c .)
  echo "Checking $n points from ${C:-?}, $JOBS at a time, up to ${MAXT}s each..."
  {
    echo "# freeze-check scan country=${C:-?} label=${LABEL:--} date=$(date -u +%FT%TZ)"
    printf 'verdict\tbytes\tasn\towner\tbrand\tcountry\turl\n'
    printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 -P "$JOBS" -n 1 bash -c 'probe "$1"' _
  } > "$OUT"
  summary "$OUT"
  echo
  echo "Results: $OUT (no IP address inside)."
  echo "You can turn the VPN back on."
}

# Per-network verdict: BLOCKED if every point is FROZEN/NONE, OK if none is, MIXED otherwise.
summary() {
  awk -F'\t' -v ref="$TARGETS" '
    BEGIN { while ((getline l < ref) > 0) { if (l ~ /^#|^asn\t/) continue; split(l, f, "\t"); home[f[5]] = f[6] } }
    /^#|^verdict\t/ { next }
    {
      bad = ($1 == "FROZEN" || $1 == "NONE")
      total[$3]++; if (bad) nbad[$3]++
      name[$3] = $4
      if (!index(brands[$3], $5)) brands[$3] = brands[$3] (brands[$3] ? ", " : "") $5
      cnt[$1]++; points++
      h = home[$7]
      if (h != "" && h != "-") {
        hb = (h == "FROZEN" || h == "NONE")
        if (hb != bad) diff[++nd] = sprintf("  %-6s here, %-6s in our test: %s (%s, %s)", $1, h, $5, $6, $4)
      }
    }
    END {
      printf "\n%d points: %d downloaded, %d slow but alive, %d frozen, %d got nothing.\n",
             points, cnt["PASS"], cnt["SLOW"], cnt["FROZEN"], cnt["NONE"]
      for (a in total) {
        line = sprintf("  %-9s %-34s %5s  %s", a, substr(name[a], 1, 34), nbad[a] "/" total[a], brands[a])
        if (nbad[a] == total[a]) { frozen[++nfz] = line; fk[nfz] = total[a] }
        else if (nbad[a] > 0) mixed[++nmx] = line
        else ok++
      }
      for (i = 2; i <= nfz; i++)   # most points first
        for (j = i; j > 1 && fk[j] > fk[j - 1]; j--) {
          t = frozen[j]; frozen[j] = frozen[j - 1]; frozen[j - 1] = t
          t = fk[j]; fk[j] = fk[j - 1]; fk[j - 1] = t
        }
      printf "\nBLOCKED networks (%d) - every point there failed:\n", nfz
      for (i = 1; i <= nfz; i++) print frozen[i]
      if (nmx) {
        printf "\nMIXED networks (%d) - some points failed; repeat before trusting:\n", nmx
        for (i = 1; i <= nmx; i++) print mixed[i]
      }
      printf "\nNetworks where everything downloaded: %d\n", ok
      if (nd) {
        printf "\nDifferent from our November 2026 home result (%d points):\n", nd
        for (i = 1; i <= nd && i <= 25; i++) print diff[i]
        if (nd > 25) printf "  ... and %d more\n", nd - 25
      }
      print "\nA network with one failed point may just have a dead test server: repeat, or check it from abroad."
      print "FROZEN = connection opened, then stopped after a few KB: the TSPU freeze."
      print "NONE   = nothing arrived: on mobile this is usually the same freeze (it hits before TLS ends)."
    }' "$1"
}

# Try each URL TRIES times (sequentially, so attempts do not disturb each other), save and explain.
check_urls() {
  local kind=$1; shift
  need_russia
  default_out "$kind"
  local u t r
  {
    echo "# freeze-check $kind country=${C:-?} label=${LABEL:--} date=$(date -u +%FT%TZ)"
    printf 'verdict\tbytes\ttry\turl\n'
  } > "$OUT"
  echo "Checking $# URL(s) from ${C:-?}, $TRIES attempt(s) each..."
  for u in "$@"; do
    for t in $(seq 1 "$TRIES"); do
      r=$(probe "$(printf '%s\t%s\t%s\t%s\t%s' - - - - "$u")")
      printf '%s\t%s\t%s\t%s\n' "$(echo "$r" | cut -f1)" "$(echo "$r" | cut -f2)" "$t" "$u" >> "$OUT"
    done
  done
  echo
  awk -F'\t' '
    /^#|^verdict\t/ { next }
    { n[$4]++; v[$4, $1]++; if (!($4 in order)) { order[$4] = ++k; urls[k] = $4 }
      if ($1 == "FROZEN" && (!($4 in fb) || $2 > fb[$4])) fb[$4] = $2 }
    END {
      for (i = 1; i <= k; i++) {
        u = urls[i]; p = v[u, "PASS"] + v[u, "SLOW"]; f = v[u, "FROZEN"]; z = v[u, "NONE"]
        if (p == n[u]) s = "OK      "
        else if (f + z == n[u]) s = (f ? "FROZEN  " : "NOTHING ")
        else s = "UNSTABLE"
        line = sprintf("%s %d/%d ok", s, p, n[u])
        if (f) line = line sprintf(", frozen at <= %d B", fb[u])
        if (z) line = line sprintf(", %d empty", z)
        printf "  %-40s %s\n", line, u
        if (s == "OK      ") ok++; else bad++
      }
      printf "\n%d OK, %d with problems.\n", ok, bad
      print "OK = downloaded. FROZEN = stopped after a few KB: the TSPU freeze."
      print "NOTHING = no data: the freeze (common on mobile) or the site is down; check the URL from abroad."
    }' "$OUT"
  echo
  echo "Results: $OUT (no IP address inside)."
  echo "You can turn the VPN back on."
}

cmd_url() {
  parse_opts "$@"
  [ ${#ARGS[@]} -ge 1 ] || die "usage: freeze-check.sh url URL [URL...]"
  check_urls "url" "${ARGS[@]}"
}

cmd_cdn() {
  parse_opts "$@"
  local list=()
  while IFS= read -r u; do list+=("$u"); done <<<"$CDN_URLS"
  check_urls "cdn" "${list[@]}"
}

cmd_owner() {
  [ $# -ge 1 ] || die "usage: freeze-check.sh owner IP|HOST"
  local ip=$1
  if ! echo "$ip" | grep -Eq '^[0-9.]+$|:'; then
    ip=$(curl -s -m 8 "https://dns.google/resolve?name=$1&type=A" | grep -Eo '"data": *"[0-9.]+"' | head -1 | grep -Eo '[0-9.]+')
    [ -n "$ip" ] || die "cannot resolve $1"
  fi
  local org; org=$(curl -s -m 8 "https://ipinfo.io/$ip/org")
  [ -n "$org" ] || die "ipinfo.io did not answer"
  echo "Network owner: $org"
  local asn=${org%% *}
  local line; line=$(targets | awk -F'\t' -v a="$asn" '$1 == a { n++; if ($6 == "FROZEN" || $6 == "NONE") h++; if ($7 == "FROZEN" || $7 == "NONE") m++ }
    END { if (n) printf "%d\t%d\t%d", n, h + 0, m + 0 }')
  if [ -z "$line" ]; then
    echo "Not in our list. Measure it: run 'freeze-check.sh serve' on the server and 'freeze-check.sh url ...' from Russia."
    return
  fi
  IFS=$'\t' read -r n h m <<<"$line"
  echo "Our November 2026 test, $n points in this network: frozen $h/$n on home wired, $m/$n on mobile."
  if [ "$h" -eq "$n" ]; then echo "This network was FROZEN. A server here will likely not work over TCP from Russia."
  elif [ "$h" -eq 0 ] && [ "$m" -eq 0 ]; then echo "This network was reachable. Still measure your own server: lists change."
  else echo "Mixed results: measure your own server."; fi
}

cmd_serve() {
  local port=${1:-8080}
  command -v python3 >/dev/null || die "python3 is needed for serve"
  [ "$port" = "80" ] && echo "Warning: some Russian ISPs intercept port 80; use another port."
  local tok; SERVE_DIR=$(mktemp -d); tok=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
  mkdir -p "$SERVE_DIR/$tok"
  head -c 2097152 /dev/urandom > "$SERVE_DIR/$tok/freeze-test.bin"
  local ip; ip=$(curl -s -m 8 https://ipinfo.io/ip)
  python3 -m http.server "$port" --bind 0.0.0.0 --directory "$SERVE_DIR" >/dev/null 2>&1 &
  SERVE_PID=$!
  trap 'kill $SERVE_PID 2>/dev/null; rm -rf "$SERVE_DIR"; echo; echo "Stopped, test file deleted."' EXIT
  trap 'exit 0' INT TERM
  local i
  for i in $(seq 1 20); do
    curl -s -o /dev/null -m 2 "http://127.0.0.1:$port/$tok/freeze-test.bin" && break
    kill -0 $SERVE_PID 2>/dev/null || die "could not start a server on port $port (busy?)"
    sleep 0.5
  done
  echo "Serving a 2 MB test file. Open TCP port $port in the firewall if needed. Ctrl+C stops and deletes it."
  echo
  echo "From Russia, with VPN off:"
  echo "  freeze-check.sh url http://${ip:-YOUR_SERVER_IP}:$port/$tok/freeze-test.bin"
  echo "or open that address in the phone browser and watch the download."
  echo "Check it from abroad too: if it downloads abroad and stops in Russia, it is the freeze."
  wait $SERVE_PID
}

case ${1:-} in
  scan) shift; cmd_scan "$@" ;;
  url) shift; cmd_url "$@" ;;
  cdn) shift; cmd_cdn "$@" ;;
  owner) shift; cmd_owner "$@" ;;
  serve) shift; cmd_serve "$@" ;;
  ""|-h|--help|help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command $1 (try --help)" ;;
esac
