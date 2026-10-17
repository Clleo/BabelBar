#!/bin/bash
# Build a signed local copy, replace the running app, and launch the new build.
# Run from Terminal or double-click in Finder; no DMG or version bump is involved.
set -euo pipefail

cd "$(dirname "$0")"

app_dest="${BABELBAR_APP_DEST:-/Applications/BabelBar.app}"
expected_bundle="com.babelbar.app"
expected_team="QYX3YDV75G"
signing_name='Apple Development: clleoweb@gmail.com (TZ8TY6ZH56)'

if [[ "$app_dest" != /* || "$app_dest" != *.app ]]; then
  echo "Expected an absolute .app destination: $app_dest" >&2
  exit 1
fi

identity="$(security find-identity -v -p codesigning | awk -v name="$signing_name" 'index($0, name) { print $2; exit }')"
if [[ -z "$identity" ]]; then
  echo "Apple Development signing identity is unavailable. The running app was not changed." >&2
  exit 1
fi

if [[ -e "$app_dest" ]]; then
  installed_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dest/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$installed_bundle" != "$expected_bundle" ]]; then
    echo "Refusing to replace an app with bundle ID '$installed_bundle' at $app_dest" >&2
    exit 1
  fi
fi

build_tmp="$(mktemp -d /private/tmp/babelbar-dev-run.XXXXXX)"
stage=""
backup=""
installed=0

cleanup() {
  result=$?
  trap - EXIT
  if (( result != 0 )) && [[ -n "$backup" && -d "$backup" ]]; then
    echo "Restoring the previous BabelBar.app..." >&2
    if (( installed == 1 )); then
      while read -r pid; do
        [[ -n "$pid" ]] || continue
        executable="$(ps -p "$pid" -o comm= | sed 's/^[[:space:]]*//')"
        if [[ "$executable" == "$app_dest/Contents/MacOS/BabelBar" ]]; then
          kill -TERM "$pid" 2>/dev/null || true
        fi
      done < <(pgrep -x BabelBar || true)
    fi
    rm -rf -- "$app_dest"
    mv "$backup" "$app_dest"
    open -n "$app_dest" || true
  fi
  [[ -z "$stage" ]] || rm -rf -- "$stage"
  rm -rf -- "$build_tmp"
  exit "$result"
}
trap cleanup EXIT

echo "Building a signed BabelBar for local testing..."
xcodebuild \
  -project BabelBar.xcodeproj \
  -scheme BabelBar \
  -configuration Release \
  -derivedDataPath "$build_tmp" \
  DEVELOPMENT_TEAM="$expected_team" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -quiet build

built="$build_tmp/Build/Products/Release/BabelBar.app"
if [[ ! -d "$built" ]]; then
  echo "The build completed without BabelBar.app. The running app was not changed." >&2
  exit 1
fi

stage="$(mktemp -d "$(dirname "$app_dest")/.babelbar-stage.XXXXXX")"
candidate="$stage/BabelBar.app"
ditto "$built" "$candidate"
codesign --verify --deep --strict "$candidate"

bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")"
team="$(codesign -dv --verbose=2 "$candidate" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
if [[ "$bundle" != "$expected_bundle" || "$team" != "$expected_team" ]]; then
  echo "Signing verification failed (bundle=$bundle, team=$team). The running app was not changed." >&2
  exit 1
fi

# Match the executable path as well as the process name, so another process
# called BabelBar cannot be stopped by accident.
running_pids=()
while read -r pid; do
  [[ -n "$pid" ]] || continue
  executable="$(ps -p "$pid" -o comm= | sed 's/^[[:space:]]*//')"
  if [[ "$executable" == */BabelBar.app/Contents/MacOS/BabelBar ]]; then
    running_pids+=("$pid")
  fi
done < <(pgrep -x BabelBar || true)

if (( ${#running_pids[@]} > 0 )); then
  echo "Stopping the running BabelBar (${running_pids[*]})..."
  kill -TERM "${running_pids[@]}"
  for _ in {1..50}; do
    still_running=0
    for pid in "${running_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then still_running=1; fi
    done
    (( still_running == 0 )) && break
    sleep 0.1
  done
  if (( still_running != 0 )); then
    echo "BabelBar did not quit in five seconds; stopping it now..."
    kill -KILL "${running_pids[@]}" 2>/dev/null || true
  fi
fi

if [[ -d "$app_dest" ]]; then
  backup="$stage/previous.app"
  mv "$app_dest" "$backup"
fi
mv "$candidate" "$app_dest"
installed=1

echo "Starting $app_dest..."
open -n "$app_dest"

started=0
for _ in {1..50}; do
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    executable="$(ps -p "$pid" -o comm= | sed 's/^[[:space:]]*//')"
    if [[ "$executable" == "$app_dest/Contents/MacOS/BabelBar" ]]; then
      started=1
      break
    fi
  done < <(pgrep -x BabelBar || true)
  (( started == 1 )) && break
  sleep 0.1
done

if (( started == 0 )); then
  echo "The new BabelBar did not start; restoring the previous app." >&2
  exit 1
fi

echo "BabelBar is running from $app_dest"
