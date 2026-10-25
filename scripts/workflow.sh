#!/bin/bash
set -euo pipefail
trap 'echo "[FATAL] line $LINENO (exit $?)" >&2' ERR
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); cd "$ROOT"
: "${COMMIT:=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
: "${DEPLOY_BRANCH:=local}"
: "${CFG:=debug}"
: "${JOBS:=$(nproc 2>/dev/null || echo 4)}"
NDK_HOME="$ROOT/ndk-binaries"
ANDROID_HOME="$ROOT/android-sdk"
JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
ABI=armeabi-v7a
API=19
LIBPATH="$ROOT/libs/$ABI"
LOG="$ROOT/build-$CFG.log"
mkdir -p "$LIBPATH" "$HOME/.android" "$ROOT/bin"
export NDK_HOME ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME APP_ABI="$ABI"
export PATH="$NDK_HOME:$JAVA_HOME/bin:$PATH"
command -v ccache >/dev/null && export NDK_CCACHE=ccache
log(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die(){ printf '[FAIL] %s\n' "$*" >&2; exit 1; }
check_elf(){ file -b "$1" | grep -q 'ARM' || die "not ARM: $1"; echo "ok $(basename "$1")"; }
build(){
  local dir=$1 out=$2 start=$SECONDS
  [ -d "$dir" ] || { log "skip $dir"; return 0; }
  log "build $dir -> $out"
  ( cd "$dir" && make -j"$JOBS" NDK=1 NDK_PATH="$NDK_HOME" APP_ABI="$ABI" APP_PLATFORM="android-$API" APP_API_LEVEL="$API" CFG="$CFG" NDK_VERBOSE=1 ) 2>&1 | tail -40
  [ -f "$dir/$out" ] || { echo "[skip] $dir/$out"; return 1; }
  install -Dm644 "$dir/$out" "$LIBPATH/$out"
  check_elf "$LIBPATH/$out"
  log "ok ($(( SECONDS - start ))s)"
}
gen_res(){
  cat > res/values/build_info.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="last_commit">$COMMIT</string>
    <string name="deploy_branch">$DEPLOY_BRANCH</string>
</resources>
XML
  echo -n "$COMMIT" > "$ROOT/version"
}
cd srcsdk
build main                      libmain.so
build gl4es                     libRegal.so
build vinterface_wrapper/client libclient.so
build vinterface_wrapper/server libserver.so
cd "$ROOT"
build jni/src/tierhook libtierhook.so
gen_res
install -Dm600 "$ROOT/debug.keystore" "$HOME/.android/debug.keystore"
[ -f "$ANDROID_HOME/tools/ant/build.xml" ] || die "missing $ANDROID_HOME/tools/ant/build.xml"
cat > "$ROOT/local.properties" <<LP
sdk.dir=$ANDROID_HOME
LP
log "local.properties: sdk.dir=$ANDROID_HOME"
log "ant $CFG"
ant -Dsdk.dir="$ANDROID_HOME" "$CFG" 2>&1 | tee "$LOG"
APK=$(ls -1t "$ROOT"/bin/*-"$CFG".apk 2>/dev/null | head -n1 || true)
[ -z "$APK" ] && die "no apk"
log "APK: $APK"
ls -lh "$APK"
