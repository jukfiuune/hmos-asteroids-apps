#!/bin/bash
# asteroids: sign a HAP with our developer cert so it installs on this port (its root is in the device trust store;
# see common/signing/merge-trust.py). Runs on the build PC, where the private keystore lives.
#   sign-hap.sh <unsigned.hap> <out-signed.hap> [udid]
# Builds a debug provisioning profile from the HAP's own manifest: bundle name, and its requested permissions in
# allowed-acls (so ACL-gated ones like FLOAT_VIEW are granted). A device UDID (bm get --udid) scopes the debug profile.
# SYSTEM_APP=1 signs it as a system app (app-feature hos_system_app, APL system_basic), for apps Huawei ships as system
# apps whose services check isSystemApp.
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
HAP=$1; OUT=$2
if [ "$SYSTEM_APP" = 1 ]; then FEATURE=hos_system_app APL=system_basic; else FEATURE=hos_normal_app APL=normal; fi
D=$(cd "$(dirname "$0")" && pwd); S=$HB/tools/asteroids-signing
# The phone's UDID: the third argument, $ASTEROIDS_UDID, or the udid file next to the keys (gen-pki.sh notes how to read it).
UDID=${3:-${ASTEROIDS_UDID:-$(cat $S/udid 2>/dev/null)}}
[ -n "$UDID" ] || { echo "no UDID: put the phone's (./port sh 'chroot /hmos-root /system/bin/bm get --udid') in $S/udid" >&2; exit 1; }
DIST=$HB/tools/hapsigner/dist; J="java -jar $DIST/hap-sign-tool.jar"; P=123456
work=$(mktemp -d)
python3 - "$HAP" "$S/app-release.pem" "$DIST/UnsgnedDebugProfileTemplate.json" "$UDID" "$work/profile.json" \
    "$FEATURE" "$APL" <<'PY'
import json, re, sys, zipfile
hap, appcert, template, udid, out, feature, apl = sys.argv[1:8]
leaf = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", open(appcert).read(), re.S)[0] + "\n"
mj = json.loads(zipfile.ZipFile(hap).read("module.json"))
perms = [p["name"] for p in mj["module"].get("requestPermissions", [])]
t = json.load(open(template))
t["bundle-info"].update({"bundle-name": mj["app"]["bundleName"], "developer-id": "Asteroids",
    "development-certificate": leaf, "distribution-certificate": leaf, "apl": apl, "app-feature": feature})
t["debug-info"] = {"device-ids": [udid], "device-id-type": "udid"}
t["validity"] = {"not-before": 1700000000, "not-after": 2400000000}
t["acls"] = {"allowed-acls": perms}
t["permissions"] = {"restricted-permissions": []}
json.dump(t, open(out, "w"), indent=4)
PY
$J sign-profile -keyAlias a-prof -signAlg SHA256withECDSA -mode localSign -profileCertFile $S/profile-release.pem \
   -inFile $work/profile.json -keystoreFile $S/asteroids.p12 -outFile $work/profile.p7b -keyPwd $P -keystorePwd $P >/dev/null
$J sign-app -keyAlias a-app -signAlg SHA256withECDSA -mode localSign -appCertFile $S/app-release.pem \
   -profileFile $work/profile.p7b -inFile "$HAP" -keystoreFile $S/asteroids.p12 -outFile "$OUT" -keyPwd $P -keystorePwd $P >/dev/null
rm -rf $work
echo "signed -> $OUT"
