#!/bin/bash
# Builds the keyboard HAP on the build PC with OpenHarmony's hvigor and the 6.1 ArkTS SDK, then signs it with our
# developer cert (common/signing/sign-hap.sh).
#
#   build.sh            (from $COMMON/keyboard; output asteroids-keyboard-signed.hap)
#
# hvigor comes from Huawei's public npm registry into ./node_modules, with npm (tools/npm) and every cache kept
# under $HARMONY_BUILD. The SDK is ohos/sdk-full/23 (ets, js, toolchains from the 6.1 SDK tarball).
set -e
. "$(dirname "$0")/../../build/env.sh"
HB=${HARMONY_BUILD:-$HOME/harmony-build}
cd "$(dirname "$0")"
B=$HB
HV=6.26.20
export npm_config_cache=$B/tools/npm-cache HVIGOR_USER_HOME=$B/tools/hvigor-home HOME_HVIGOR=$B/tools/hvigor-home
NPM="node $B/tools/npm/package/bin/npm-cli.js"
echo "sdk.dir=$B/ohos/sdk-full" > local.properties
if [ ! -d node_modules/@ohos/hvigor-ohos-plugin ]; then
    $NPM install --no-save --no-audit --no-fund --registry=https://repo.harmonyos.com/npm/ \
        @ohos/hvigor@$HV @ohos/hvigor-ohos-plugin@$HV >/dev/null
fi
node node_modules/@ohos/hvigor/bin/hvigor.js --mode module -p product=default -p buildMode=release assembleHap \
    --no-daemon
HAP=$(ls entry/build/default/outputs/default/*.hap | head -1)
bash ../signing/sign-hap.sh "$HAP" asteroids-keyboard-signed.hap
echo "KEYBOARD-OK $(pwd)/asteroids-keyboard-signed.hap"
