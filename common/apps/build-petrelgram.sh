#!/bin/bash
# Builds Petrelgram (github.com/miramira8295/Petrelgram, ArkUI + TDLib) from source on the build PC, with our patches
# (petrelgram-*.patch here, in order), and signs it with our developer cert. Same bundle and signer as
# sign-petrelgram.sh's release, so it installs over it and keeps the app's data.
#
#   build-petrelgram.sh [version]     (default 1.5.9; output $HARMONY_BUILD/apps/petrelgram-signed.hap)
#
# Expects in $HARMONY_BUILD:
#   apps/petrelgram/Petrelgram-<version>-unsigned.app.hap   the upstream release (sign-petrelgram.sh fetches it); its
#                                    native libraries are used as they are (TDLib, tgcalls, libentry.so), so only the
#                                    ArkTS side is built here
#   apps/harlgram/config/telegram.local.json   the user's own api_id/api_hash (never in our repo)
#   tools/hmos-cli-26/command-line-tools       Huawei's Command Line Tools for HarmonyOS 26.0.1.290 (Linux x64, from the
#                                    Download Center; upstream builds with the HarmonyOS 26 SDK, and the API 21 one in
#                                    6.0.1 lacks ~30 of the APIs it uses)
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
SIGN=$(cd "$(dirname "$0")/../signing" && pwd)/sign-hap.sh
V=${1:-1.5.9}
B=$HB
C=$B/tools/hmos-cli-26/command-line-tools
A=$B/apps/petrelgram-src
REL=$B/apps/petrelgram/Petrelgram-$V-unsigned.app.hap
REAL_HOME=$HOME
export HOME=$B/tools/hmos-home DEVECO_SDK_HOME=$C/sdk NODE_HOME=$C/tool/node
export PATH=$C/bin:$C/tool/node/bin:$PATH
mkdir -p $HOME
[ -f $REL ] || { echo "$REL missing: run sign-petrelgram.sh $V first"; exit 1; }
[ -d $A ] || git clone -q https://github.com/miramira8295/Petrelgram $A
cd $A
git fetch -q --depth 50 origin tag v$V
git checkout -q -f v$V
# Files our patches added last time (git-ignored build inputs such as entry/libs stay).
git clean -q -fd
# Native libraries from the release (entry/libs is git-ignored upstream); libentry.so too, so CMake isn't run.
rm -rf entry/libs && mkdir -p entry/libs/arm64-v8a
unzip -q -o -j $REL entry-default.hap -d /tmp/petrelgram-$$
unzip -q -o -j /tmp/petrelgram-$$/entry-default.hap 'libs/arm64-v8a/libtdjson.so' 'libs/arm64-v8a/libtgcalls_ohos.so' \
    'libs/arm64-v8a/libentry.so' -d entry/libs/arm64-v8a
rm -rf /tmp/petrelgram-$$
# The ijkplayer HAR (the developer's fork, 2.0.13-pg.10 = ca83788) is no longer at its release URL, so
# fetch-ijkplayer.sh builds it from the fork; its DevEco paths point at the command-line tools.
IJK=$B/apps/ohos_ijkplayer
[ -d $IJK ] || git clone -q -b petrelgram https://gitcode.com/shaoewn/ohos_ijkplayer.git $IJK
git -C $IJK checkout -q -f ca83788
DEV=$B/tools/deveco-shim
mkdir -p $DEV/tools
ln -sfn $C/sdk $DEV/sdk
ln -sfn $C/tool/node $DEV/tools/node
ln -sfn $C/ohpm $DEV/tools/ohpm
ln -sfn $C/hvigor $DEV/tools/hvigor
DEVECO_HOME=$DEV IJKPLAYER_FORK_DIR=$IJK OHOS_NATIVE=$C/sdk/default/openharmony/native bash scripts/fetch-ijkplayer.sh
# The user's credentials, packed as upstream's gen-creds.mjs does.
T=entry/src/main/ets/tdkit
CREDS=$(node -e 'const c=require(process.argv[1]); console.log(c.apiId + " " + c.apiHash)' \
    $B/apps/harlgram/config/telegram.local.json)
node scripts/gen-creds.mjs $CREDS > /tmp/petrelgram-creds.$$
python3 - $T/ApiCredentials.template.ets $T/ApiCredentials.ets /tmp/petrelgram-creds.$$ <<'EOF'
import re, sys
src, out, creds = sys.argv[1:4]
s = open(src).read()
for name, value in re.findall(r"const (_[nrs])[^=]*= ([^;]+);", open(creds).read()):
    s = re.sub(r"const %s(: \w+)? = [^;]+;" % name, lambda m: "const %s%s = %s;" % (name, m.group(1) or "", value), s)
open(out, "w").write(s)
EOF
rm -f /tmp/petrelgram-creds.$$
# Upstream's signing config is the developer's own (unsigned here; sign-hap.sh signs below). No CMake: libentry.so
# comes from the release, so BiSheng (DevEco's native compiler) isn't needed either.
python3 - <<'EOF'
import re
p = "build-profile.json5"
s = open(p).read()
s = re.sub(r"signingConfigs: \[.*?\n    \],", "signingConfigs: [],", s, flags=re.S)
s = s.replace("signingConfig: 'default',", "")
s = s.replace("nativeCompiler: 'BiSheng',", "")
open(p, "w").write(s)
p = "entry/build-profile.json5"
s = open(p).read()
s = re.sub(r'"externalNativeOptions": \{.*?\n    \},?', "", s, flags=re.S)
open(p, "w").write(s)
EOF
for p in $(ls $B/m2/apps/petrelgram-*.patch 2>/dev/null); do
    git apply $p
done
ohpm install --all >/dev/null
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon
HAP=$(ls entry/build/default/outputs/default/*-unsigned.hap 2>/dev/null | head -1)
[ -n "$HAP" ] || HAP=$(ls entry/build/default/outputs/default/*.hap | head -1)
HOME=$REAL_HOME bash $SIGN "$HAP" $B/apps/petrelgram-signed.hap
echo "PETRELGRAM-OK $B/apps/petrelgram-signed.hap"
