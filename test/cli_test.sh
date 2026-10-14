#!/usr/bin/env bash
# Plain-bash tests for bin/readout. Offline: dry run and a fake curl.
set -u

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/readout"
FIX="$ROOT/test/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  NO  %s\n' "$1"; [ $# -lt 2 ] || printf '      %s\n' "$2"; }

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2] got [$3]"; fi
}
# has <name> <needle> <haystack>
has() {
  case $3 in *"$2"*) ok "$1" ;; *) no "$1" "[$2] not in [$3]" ;; esac
}

# run <args...>: sets OUT, ERR, RC. Runs the CLI with a clean token environment.
run() {
  OUT=$(env -u READOUT_TOKEN -u READOUT_URL -u READOUT_DRY_RUN -u READOUT_CURL \
    "$@" 2>"$TMP/err")
  RC=$?
  ERR=$(cat "$TMP/err")
}
dry() { run env READOUT_DRY_RUN=1 "$CLI" "$@"; }

# ---------------------------------------------------------------- A2: dry run
echo "dry run: manifests"

dry "$FIX/single/report.html"
check "single file exits 0" 0 "$RC"
check "single file: one entry" 1 "$(jq '.manifest.files | length' <<<"$OUT")"
check "single file: path is the basename" report.html "$(jq -r '.manifest.files[0].path' <<<"$OUT")"
check "single file: field f0" f0 "$(jq -r '.manifest.files[0].field' <<<"$OUT")"
check "single file: no entry key" false "$(jq '.manifest | has("entry")' <<<"$OUT")"
check "single file: abs is absolute" "$FIX/single/report.html" "$(jq -r '.files[0].abs' <<<"$OUT")"
check "default url" https://readout.hillig.dev/api/v1/pages "$(jq -r '.url' <<<"$OUT")"

run env READOUT_DRY_RUN=1 READOUT_URL=http://localhost:8787/ "$CLI" publish "$FIX/single/report.html"
check "READOUT_URL override, trailing slash trimmed" http://localhost:8787/api/v1/pages "$(jq -r '.url' <<<"$OUT")"

dry "$FIX/site"
check "folder: sorted relative paths" "assets/app.js assets/mermaid.min.js index.html" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
check "folder: fields f0..f2" "f0 f1 f2" "$(jq -r '[.manifest.files[].field] | join(" ")' <<<"$OUT")"
check "folder: manifest entries carry no abs" false "$(jq '.manifest.files[0] | has("abs")' <<<"$OUT")"
check "folder: files carry abs" "$FIX/site/assets/app.js" "$(jq -r '.files[0].abs' <<<"$OUT")"

SKIP="$TMP/skip"
mkdir -p "$SKIP/.git" "$SKIP/node_modules/pkg" "$SKIP/sub/.hidden-dir"
: >"$SKIP/page.html"; : >"$SKIP/.DS_Store"; : >"$SKIP/.env"; : >"$SKIP/.git/config"
: >"$SKIP/node_modules/pkg/i.js"; : >"$SKIP/sub/keep.md"; : >"$SKIP/sub/.secret"
: >"$SKIP/sub/.hidden-dir/x.md"
dry "$SKIP"
check "skips .git, node_modules, dotfiles, dot dirs" "page.html sub/keep.md" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"

EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
dry "$EMPTY"
check "empty folder exits 2" 2 "$RC"
check "empty folder message" "readout: nothing to publish in $EMPTY" "$ERR"

DOTS="$TMP/dots"; mkdir -p "$DOTS/.git"; : >"$DOTS/.env"; : >"$DOTS/.git/HEAD"
dry "$DOTS"
check "dotfile-only folder exits 2" 2 "$RC"
check "dotfile-only folder message" "readout: nothing to publish in $DOTS" "$ERR"

dry "$FIX/spaces"
check "space in filename accepted" "Design Notes.md" "$(jq -r '.manifest.files[0].path' <<<"$OUT")"

UML="$TMP/uml"; mkdir -p "$UML"; printf '# x\n' >"$UML/Übersicht.md"
dry "$UML"
check "non-ASCII filename exits 2" 2 "$RC"
has "non-ASCII error names the path" "Übersicht.md" "$ERR"
has "non-ASCII error names the charset" "only A-Z a-z 0-9 . _ @ + - space are allowed" "$ERR"

SYM="$TMP/sym"; mkdir -p "$SYM"; : >"$SYM/ok.md"; ln -s "$FIX/single/report.html" "$SYM/escape.html"
dry "$SYM"
check "symlink pointing outside exits 2" 2 "$RC"
has "symlink error names the path" "escape.html" "$ERR"

SYM2="$TMP/sym2"; mkdir -p "$SYM2"; printf 'x\n' >"$SYM2/real.md"; ln -s real.md "$SYM2/alias.md"
dry "$SYM2"
check "symlink inside the folder accepted" "alias.md real.md" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"

dry "$FIX/symlink"
check "committed symlink fixture rejected" 2 "$RC"

dry "$TMP/does-not-exist"
check "missing path exits 2" 2 "$RC"

echo "dry run: flags"

dry "$FIX/single/report.html" --title T --entry a.html --name k --ttl 7d
check "title" T "$(jq -r '.manifest.title' <<<"$OUT")"
check "entry" a.html "$(jq -r '.manifest.entry' <<<"$OUT")"
check "name" k "$(jq -r '.manifest.name' <<<"$OUT")"
check "ttl 7d" 604800 "$(jq '.manifest.ttl' <<<"$OUT")"
check "no keep key when ttl" false "$(jq '.manifest | has("keep")' <<<"$OUT")"
dry "$FIX/single/report.html" --ttl 1h
check "ttl 1h" 3600 "$(jq '.manifest.ttl' <<<"$OUT")"
dry "$FIX/single/report.html" --ttl 90m
check "ttl 90m" 5400 "$(jq '.manifest.ttl' <<<"$OUT")"
dry "$FIX/single/report.html" --ttl abc
check "ttl abc exits 2" 2 "$RC"
dry "$FIX/single/report.html" --ttl
check "ttl without value exits 2" 2 "$RC"
dry "$FIX/single/report.html" --keep
check "keep true" true "$(jq '.manifest.keep' <<<"$OUT")"
check "keep has no ttl" false "$(jq '.manifest | has("ttl")' <<<"$OUT")"
dry "$FIX/single/report.html" --keep --ttl 7d
check "keep with ttl exits 2" 2 "$RC"
dry --title T "$FIX/single/report.html"
check "flags may precede the path" T "$(jq -r '.manifest.title' <<<"$OUT")"
dry "$FIX/single/report.html" --title 'A "quoted"; title'
check "title is JSON-escaped" 'A "quoted"; title' "$(jq -r '.manifest.title' <<<"$OUT")"

dry "$FIX/single/report.html" --bogus
check "unknown flag exits 2" 2 "$RC"
has "unknown flag prints usage" "Usage:" "$ERR"
dry
check "no path exits 2" 2 "$RC"
run env READOUT_DRY_RUN=1 "$CLI" publish
check "publish without path exits 2" 2 "$RC"
dry "$FIX/single/report.html" "$FIX/site"
check "two paths exit 2" 2 "$RC"

dry publish "$FIX/single/report.html"
check "explicit publish" report.html "$(jq -r '.manifest.files[0].path' <<<"$OUT")"
check "default subcommand equals publish" "$OUT" "$(env READOUT_DRY_RUN=1 "$CLI" "$FIX/single/report.html")"

run "$CLI" "$FIX/single/report.html"
check "missing token exits 3" 3 "$RC"
check "missing token message" "readout: READOUT_TOKEN is not set" "$ERR"

echo "dry run: local references of a single html file"

ASSETS="$TMP/assets"
mkdir -p "$ASSETS/sub" "$ASSETS/.hidden"
cat >"$ASSETS/review.html" <<'HTML'
<!doctype html>
<title>Review</title>
<link rel="stylesheet" href="style.css">
<script src="marked.min.js"></script>
<script SRC='mermaid.min.js'></script>
<script src="./marked.min.js"></script>
<img src="sub/pic.png?v=1#top">
<a href="page2.html#part">Part two</a>
<a href="#overview">Overview</a>
<a href="https://example.com/x.js">external</a>
<script src="//cdn.example.com/x.js"></script>
<img src="data:image/png;base64,AAAA">
<a href="mailto:me@example.com">mail</a>
<script src="/root.js"></script>
<a href="../outside.html">up</a>
<script src="../outside.js"></script>
<script src=".hidden/x.js"></script>
<img src="missing.png">
<a href="review.html">self</a>
<a href="sub">a folder</a>
HTML
for f in style.css marked.min.js mermaid.min.js page2.html sub/pic.png .hidden/x.js root.js unreferenced.js; do
  : >"$ASSETS/$f"
done
: >"$TMP/outside.html"; : >"$TMP/outside.js"
ASSETS_C=$(cd -P "$ASSETS" && pwd -P)
dry "$ASSETS/review.html"
check "html: exits 0" 0 "$RC"
check "html: the page plus its local asset references, sorted" \
  "review.html marked.min.js mermaid.min.js style.css sub/pic.png" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
check "html: entry is the page" review.html "$(jq -r '.manifest.entry' <<<"$OUT")"
check "html: references carry abs" "$ASSETS_C/sub/pic.png" "$(jq -r '.files[4].abs' <<<"$OUT")"
dry "$ASSETS/review.html" --entry style.css
check "html: --entry wins" style.css "$(jq -r '.manifest.entry' <<<"$OUT")"

# Only src/href attributes of asset tags count, and only for asset file types: text that merely
# looks like an attribute, links to other documents and non-asset files are never uploaded.
TXT="$TMP/txt"; mkdir -p "$TXT/config"
cat >"$TXT/page.html" <<'HTML'
<!doctype html>
<p>set href="config/app.js" in prose</p>
<pre>src="config/app.css"</pre>
<script>var s = 'href="config/app.js"';</script>
<img src="config/master.key">
<img data-src="config/lazy.png">
<a href="other.html">another report</a>
<link rel="stylesheet" href="config/app.css">
<script src="ok.js"></script>
HTML
for f in config/app.js config/app.css config/master.key config/lazy.png other.html ok.js; do : >"$TXT/$f"; done
dry "$TXT/page.html"
check "html: only asset tags and asset types" "page.html config/app.css ok.js" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"

ESC="$TMP/esc"; mkdir -p "$ESC"
printf '<script src="leak.js"></script>\n<script src="ok.js"></script>\n' >"$ESC/page.html"
ln -s "$FIX/single/report.html" "$ESC/leak.js"; : >"$ESC/ok.js"
dry "$ESC/page.html"
check "html: symlinked reference outside the folder is skipped" 0 "$RC"
check "html: the rest is still published" "page.html ok.js" "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
has "html: skip warning names the reference" "readout: skipped leak.js" "$ERR"

HID="$TMP/hid"; mkdir -p "$HID/.secret"
printf '<script src="envlink.js"></script>\n<script src="dirlink/x.js"></script>\n' >"$HID/page.html"
: >"$HID/.env"; : >"$HID/.secret/x.js"; ln -s .env "$HID/envlink.js"; ln -s .secret "$HID/dirlink"
dry "$HID/page.html"
check "html: references resolving to hidden files are skipped" page.html \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
has "html: hidden skip warning" "readout: skipped envlink.js" "$ERR"

ODD="$TMP/odd"; mkdir -p "$ODD/a"
printf '<link rel="stylesheet" href="a//b.css">\n<img src="photo(1).png">\n<script src="ok.js"></script>\n' >"$ODD/page.html"
: >"$ODD/a/b.css"; : >"$ODD/photo(1).png"; : >"$ODD/ok.js"
dry "$ODD/page.html"
check "html: invalid reference paths do not stop the publish" 0 "$RC"
check "html: invalid reference paths are skipped" "page.html ok.js" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
has "html: invalid path warning" "readout: skipped photo(1).png" "$ERR"

INS="$TMP/ins"; mkdir -p "$INS"
printf '<script src="alias.js"></script>\n' >"$INS/page.html"
printf 'x\n' >"$INS/real.js"; ln -s real.js "$INS/alias.js"
INS_C=$(cd -P "$INS" && pwd -P)
dry "$INS/page.html"
check "html: symlinked reference inside the folder accepted" "page.html alias.js" \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"
check "html: a symlinked reference uploads the checked target" "$INS_C/real.js" "$(jq -r '.files[1].abs' <<<"$OUT")"

FHID="$TMP/fhid"; mkdir -p "$FHID"
: >"$FHID/page.html"; : >"$FHID/.env"; ln -s .env "$FHID/alias.md"
dry "$FHID"
check "folder: symlinks to hidden files are skipped" page.html \
  "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"

MD="$TMP/md"; mkdir -p "$MD"
printf '# Notes\n\n<img src="pic.png">\n' >"$MD/notes.md"; : >"$MD/pic.png"
dry "$MD/notes.md"
check "markdown: references are not collected" notes.md "$(jq -r '[.manifest.files[].path] | join(" ")' <<<"$OUT")"

echo "dry run: default name"

sha16() { # first 16 hex chars of sha256(<text>)
  local h
  h=$(printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; })
  printf '%s' "${h:0:16}"
}
HOST=$(uname -n)
SINGLE_C="$(cd -P "$FIX/single" && pwd -P)/report.html"
dry "$FIX/single/report.html"
check "default name: path: plus the hashed host and canonical path" \
  "path:$(sha16 "$HOST:$SINGLE_C")" "$(jq -r '.manifest.name' <<<"$OUT")"
FILE_NAME=$(jq -r '.manifest.name' <<<"$OUT")
ln -s "$FIX/single/report.html" "$TMP/link.html"
dry "$TMP/link.html"
check "default name: a symlink names the file it points to" "$FILE_NAME" "$(jq -r '.manifest.name' <<<"$OUT")"
SITE_C=$(cd -P "$FIX/site" && pwd -P)
dry "$FIX/site"
check "default name: a folder hashes its canonical path" \
  "path:$(sha16 "$HOST:$SITE_C")" "$(jq -r '.manifest.name' <<<"$OUT")"
check "default name: different paths, different names" yes \
  "$([ "$FILE_NAME" != "$(jq -r '.manifest.name' <<<"$OUT")" ] && echo yes || echo no)"
dry "$FIX/single/report.html" --new
check "--new sends no name" false "$(jq '.manifest | has("name")' <<<"$OUT")"
dry "$FIX/single/report.html" --new --name k
check "--new with --name exits 2" 2 "$RC"

# ------------------------------------------------------------- https only
echo "READOUT_URL scheme"
for u in https://example.com http://localhost http://localhost:8787 http://localhost:8787/ \
  http://127.0.0.1 http://127.0.0.1:3000/x 'http://[::1]' 'http://[::1]:80/'; do
  run env READOUT_DRY_RUN=1 READOUT_URL="$u" "$CLI" publish "$FIX/single/report.html"
  check "accepts $u" 0 "$RC"
done
for u in http://example.com http://localhost.evil.com http://localhost@evil.com http://127.0.0.1.evil.com \
  ftp://example.com example.com localhost:8787 HTTP://example.com; do
  run env READOUT_DRY_RUN=1 READOUT_URL="$u" "$CLI" publish "$FIX/single/report.html"
  check "rejects $u: exit 2" 2 "$RC"
  check "rejects $u: message" "readout: READOUT_URL must use https (got $u)" "$ERR"
done
run env READOUT_TOKEN=x READOUT_URL=http://example.com "$CLI" whoami
check "whoami rejects http" 2 "$RC"

# ------------------------------------------------------- A3: network commands
echo "network commands (fake curl)"

FAKE="$ROOT/test/fake-curl"
export FAKE_CURL_LOG="$TMP/curl.log"
export FAKE_CURL_RAW_LOG="$TMP/curl.raw.log"
net() { # net <status> <body> <cli args...>
  export FAKE_CURL_STATUS=$1 FAKE_CURL_BODY=$2
  shift 2
  : >"$FAKE_CURL_LOG"
  : >"$FAKE_CURL_RAW_LOG"
  run env READOUT_TOKEN=tok123 READOUT_CURL="$FAKE" FAKE_CURL_STATUS="$FAKE_CURL_STATUS" \
    FAKE_CURL_BODY="$FAKE_CURL_BODY" FAKE_CURL_LOG="$FAKE_CURL_LOG" \
    FAKE_CURL_RAW_LOG="$FAKE_CURL_RAW_LOG" "$CLI" "$@"
}

BODY='{"id":"abc","url":"https://readout.hillig.dev/p/abc","title":"Report","expiresAt":"2026-11-13T00:00:00.000Z","files":1,"bytes":10,"replaced":false}'
net 201 "$BODY" "$FIX/single/report.html"
check "publish exits 0" 0 "$RC"
check "publish prints the url only" https://readout.hillig.dev/p/abc "$OUT"
check "a new page prints nothing on stderr" "" "$ERR"
net 200 "${BODY/\"replaced\":false/\"replaced\":true}" "$FIX/single/report.html"
check "replace prints the url only" https://readout.hillig.dev/p/abc "$OUT"
check "replace says so on stderr" "readout: replaced existing page abc" "$ERR"
net 201 "$BODY" "$FIX/single/report.html" --json
check "publish --json prints the body" "$BODY" "$OUT"

LOG=$(cat "$FAKE_CURL_LOG")
has "sends the bearer token" "Authorization: Bearer tok123" "$LOG"
RAW=$(cat "$FAKE_CURL_RAW_LOG")
case $RAW in *tok123*) no "token is not in curl argv" ;; *) ok "token is not in curl argv" ;; esac
case $RAW in *$'\n@'* | @*) ok "auth header is passed as a header file" ;; *) no "auth header is passed as a header file" ;; esac
case $LOG in *"Transfer-Encoding"*) no "no chunked transfer encoding" ;; *) ok "no chunked transfer encoding" ;; esac
has "sends the client header" "X-Readout-Client: cli/0.2.0" "$LOG"
has "posts to /api/v1/pages" "https://readout.hillig.dev/api/v1/pages" "$LOG"
has "manifest part typed as json" '";type=application/json'  "$LOG"
has "manifest part is named" "manifest=" "$LOG"
has "file part uses the absolute path" "f0=@$FIX/single/report.html" "$LOG"
has "reads the status with -w" '%{http_code}' "$LOG"
case $LOG in *--fail*) no "does not use --fail" ;; *) ok "does not use --fail" ;; esac

# -q must be curl's first argument so ~/.curlrc never applies to a request carrying the token.
net 201 "$BODY" "$FIX/single/report.html"
check "publish: -q is curl's first argument" -q "$(head -n 1 "$FAKE_CURL_RAW_LOG")"
net 200 '{"pages":[]}' ls
check "ls: -q is curl's first argument" -q "$(head -n 1 "$FAKE_CURL_RAW_LOG")"
net 204 '' rm abc
check "rm: -q is curl's first argument" -q "$(head -n 1 "$FAKE_CURL_RAW_LOG")"
net 200 '{"email":"a@b.c"}' whoami
check "whoami: -q is curl's first argument" -q "$(head -n 1 "$FAKE_CURL_RAW_LOG")"
net 201 "$BODY" "$FIX/single/report.html"

net 201 "$BODY" "$FIX/site" --name k
check "folder: three file parts" 3 "$(grep -c '^f[0-9]*=@' "$FAKE_CURL_LOG")"
has "folder: f2 part" "f2=@$FIX/site/index.html" "$(cat "$FAKE_CURL_LOG")"
MAN=$(grep '^manifest=' "$FAKE_CURL_LOG" | sed -e 's/^manifest="//' -e 's/";type=application\/json$//' -e 's/\\"/"/g' -e 's/\\\\/\\/g')
check "manifest argument is the manifest JSON" k "$(jq -r '.name' <<<"$MAN")"
check "manifest argument lists relative paths" "assets/app.js" "$(jq -r '.files[0].path' <<<"$MAN")"

net 400 '{"error":{"code":"invalid_path","message":"bad"}}' "$FIX/single/report.html"
check "400 exits 1" 1 "$RC"
check "400 message" "readout: bad (invalid_path)" "$ERR"
check "400 prints nothing on stdout" "" "$OUT"
net 426 '{"error":{"code":"client_outdated","message":"Upgrade readout: git pull"}}' "$FIX/single/report.html"
check "426 exits 1" 1 "$RC"
has "426 shows the server message" "Upgrade readout: git pull" "$ERR"
net 502 '<html>bad gateway</html>' "$FIX/single/report.html"
check "non-JSON 502 exits 1" 1 "$RC"
check "non-JSON 502 message" "readout: HTTP 502" "$ERR"

LS='{"pages":[{"id":"aaa","title":"One","expiresAt":"2026-11-13T00:00:00.000Z"},{"id":"bbb","title":"Two words","expiresAt":null}]}'
net 200 "$LS" ls
check "ls exits 0" 0 "$RC"
check "ls table" "aaa  2026-11-13T00:00:00.000Z  One
bbb  keep  Two words" "$OUT"
has "ls uses GET /api/v1/pages" "https://readout.hillig.dev/api/v1/pages" "$(cat "$FAKE_CURL_LOG")"
net 200 "$LS" ls --json
check "ls --json passes the body through" "$LS" "$OUT"
net 200 '{"pages":[]}' ls
check "ls with no pages prints nothing" "" "$OUT"

net 204 "" rm abc
check "rm exits 0" 0 "$RC"
check "rm is silent" "" "$OUT$ERR"
LOG=$(cat "$FAKE_CURL_LOG")
has "rm sends DELETE" "DELETE" "$LOG"
has "rm targets the page" "https://readout.hillig.dev/api/v1/pages/abc" "$LOG"
net 404 '{"error":{"code":"not_found","message":"No such page"}}' rm abc
check "rm 404 exits 1" 1 "$RC"
check "rm 404 message" "readout: No such page (not_found)" "$ERR"
net 204 "" rm
check "rm without id exits 2" 2 "$RC"
net 204 "" rm '../x'
check "rm with a bad id exits 2" 2 "$RC"

net 200 '{"email":"me@example.com","name":"Me"}' whoami
check "whoami prints the email" me@example.com "$OUT"
has "whoami uses GET /api/v1/me" "https://readout.hillig.dev/api/v1/me" "$(cat "$FAKE_CURL_LOG")"
net 401 '{"error":{"code":"unauthorized","message":"Invalid API key"}}' whoami
check "whoami 401 exits 1" 1 "$RC"
check "whoami 401 message" "readout: Invalid API key (unauthorized)" "$ERR"

net 200 "" ls
check "ls with an empty body exits 1" 1 "$RC"

run "$CLI" version
check "version output" "readout 0.2.0" "$OUT"
check "version exits 0" 0 "$RC"
run "$CLI" ls
check "ls without a token exits 3" 3 "$RC"
run "$CLI" bogus
check "unknown subcommand is a path and exits 2" 2 "$RC"

# curl failure
export FAKE_CURL_EXIT=7
net 200 "" whoami
check "curl failure exits 1" 1 "$RC"
has "curl failure message" "readout: request failed" "$ERR"
unset FAKE_CURL_EXIT

# missing tools: a PATH without the tool
TOOLS="$TMP/tools"
mkdir -p "$TOOLS"
for t in env cat sed find sort dirname basename realpath readlink printf tr mktemp rm uname; do
  p=$(command -v "$t" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$TOOLS/$t"
done
BASH_BIN=$(command -v bash)
JQ_BIN=$(command -v jq)
CURL_BIN=$(command -v curl)
ln -sf "$CURL_BIN" "$TOOLS/curl"
run env PATH="$TOOLS" READOUT_TOKEN=x "$BASH_BIN" "$CLI" whoami
check "jq missing exits 3" 3 "$RC"
has "jq missing names the tool" "jq" "$ERR"
rm -f "$TOOLS/curl"; ln -sf "$JQ_BIN" "$TOOLS/jq"
run env PATH="$TOOLS" READOUT_TOKEN=x "$BASH_BIN" "$CLI" whoami
check "curl missing exits 3" 3 "$RC"
has "curl missing names the tool" "curl" "$ERR"
run env PATH="$TOOLS" READOUT_TOKEN=x READOUT_CURL=/nonexistent/curl "$BASH_BIN" "$CLI" whoami
check "READOUT_CURL missing exits 3" 3 "$RC"
# TOOLS has no sha256sum, shasum or openssl. These runs execute jq, so link one that works on a
# bare PATH; a version-manager shim may only work on the full one.
ln -sf "$CURL_BIN" "$TOOLS/curl"
for j in $(type -aP jq); do
  if env PATH="$TOOLS" "$j" -n 1 >/dev/null 2>&1; then ln -sf "$j" "$TOOLS/jq"; break; fi
done
run env PATH="$TOOLS" READOUT_DRY_RUN=1 "$BASH_BIN" "$CLI" "$FIX/spaces"
check "no sha256 tool exits 3" 3 "$RC"
has "no sha256 tool names the tools" "sha256sum, shasum or openssl" "$ERR"
run env PATH="$TOOLS" READOUT_DRY_RUN=1 "$BASH_BIN" "$CLI" "$FIX/spaces" --new
check "no sha256 tool: --new still publishes" 0 "$RC"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
