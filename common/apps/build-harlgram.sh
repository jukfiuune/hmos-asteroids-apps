#!/bin/bash
# Builds Harlgram (github.com/GaryChangCN/harlgram, a native HarmonyOS Telegram client: ArkUI + TDLib) on the build PC
# and signs it with our developer cert.
#
#   build-harlgram.sh            (output $HARMONY_BUILD/apps/harlgram-signed.hap)
#
# Expects in $HARMONY_BUILD:
#   apps/harlgram                    the checkout; entry/libs/arm64-v8a/libtdjson.so from its scripts/build-tdlib.sh
#                                    (run with OHOS_NATIVE=ohos/sdk/native, BUILD_JOBS=10 and tools/bin on PATH for the
#                                    locally built gperf and a shasum shim)
#   apps/harlgram/config/telegram.local.json   the user's own api_id/api_hash (git-ignored there, never in our repo)
#   tools/hmos-cli/command-line-tools          Huawei's Command Line Tools for HarmonyOS 6.0.1.251 (the HarmonyOS
#                                    SDK: Harlgram uses UIDesignKit, which the OpenHarmony SDK lacks)
# Harlgram declares HarmonyOS 6.1.1 (API 24) as its minimum; this SDK is 6.0.1 (API 21) and the phone runs API 26, so
# the minimum and target are set to 6.0.1(21), with harlgram-api21.patch for the two newer calls. HOME, ohpm's and hvigor's caches stay under $HARMONY_BUILD.
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
SIGN=$(cd "$(dirname "$0")/../signing" && pwd)/sign-hap.sh
B=$HB
C=$B/tools/hmos-cli/command-line-tools
A=$B/apps/harlgram
REAL_HOME=$HOME
export HOME=$B/tools/hmos-home DEVECO_SDK_HOME=$C/sdk NODE_HOME=$C/tool/node
export PATH=$C/bin:$C/tool/node/bin:$PATH
mkdir -p $HOME
cd $A
python3 - <<'EOF'
import re
s = open("build-profile.example.json5").read()
s = s.replace('"targetSdkVersion": "26.0.0"', '"targetSdkVersion": "6.0.1(21)"')
s = s.replace('"compatibleSdkVersion": "6.1.1(24)"', '"compatibleSdkVersion": "6.0.1(21)"')
# Huawei's BiSheng linker needs libxml2.so.2, which the build PC doesn't have; the SDK's standard LLVM builds the small
# Node-API bridge as well (TDLib is prebuilt).
s = s.replace('"nativeCompiler": "BiSheng",', "")
open("build-profile.json5", "w").write(s)
# Its hvigor/ohpm model is DevEco 26's; this toolchain (hvigor 6.21) reads 6.0.1.
for p in ("hvigor/hvigor-config.json5", "oh-package.json5"):
    t = open(p).read()
    open(p, "w").write(t.replace('"modelVersion": "26.0.0"', '"modelVersion": "6.0.1"'))
# app.json5's buildVersion is newer than the API 21 schema (metadata only).
p = "AppScope/app.json5"
t = re.sub(r'\n\s*"buildVersion": "[^"]*",', "", open(p).read())
open(p, "w").write(t)
EOF
# Two spots use APIs newer than 21 (the floating tab bar's material, fetchMetadataWithTimeout): harlgram-api21.patch.
git apply --reverse --check $B/m2/apps/harlgram-api21.patch 2>/dev/null || git apply $B/m2/apps/harlgram-api21.patch
HARLGRAM_ROOT=$A node scripts/configure-telegram.mjs release
ohpm install --all >/dev/null
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon
HAP=$(ls entry/build/default/outputs/default/*-unsigned.hap 2>/dev/null | head -1)
[ -n "$HAP" ] || HAP=$(ls entry/build/default/outputs/default/*.hap | head -1)
HOME=$REAL_HOME bash $SIGN "$HAP" $B/apps/harlgram-signed.hap
echo "HARLGRAM-OK $B/apps/harlgram-signed.hap"
