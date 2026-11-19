#!/bin/bash
# Fetches a Petrelgram release (github.com/miramira8295/Petrelgram, a HarmonyOS Telegram client: ArkUI + TDLib, with
# forum topics and an English UI) on the build PC, checks it against the release's SHA256SUMS, hides the "Petrel"
# title over the chat list and signs it with our developer cert. No build: the project publishes an unsigned .app whose
# only module is entry-default.hap, and its source needs a newer HarmonyOS SDK (API 26) than ours.
#
#   sign-petrelgram.sh [version]     (default 1.5.9; output $HARMONY_BUILD/apps/petrelgram-signed.hap)
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
SIGN=$(cd "$(dirname "$0")/../signing" && pwd)/sign-hap.sh
V=${1:-1.5.9}
B=$HB
D=$B/apps/petrelgram
U=https://github.com/miramira8295/Petrelgram/releases/download/v$V
mkdir -p $D
cd $D
curl -sSfLo Petrelgram-$V-unsigned.app.hap $U/Petrelgram-$V-unsigned.app.hap
curl -sSfLo SHA256SUMS.txt $U/SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
unzip -o -q Petrelgram-$V-unsigned.app.hap entry-default.hap
# The title is ChatListPage.homeTopBarContent's Text($r('app.string.app_name')).fontSize(25). app_name is also the
# app's system name, so the resource stays; the bytecode's fontSize argument becomes 0 instead. The instruction run is
# ldobjbyname <ic 0x1f> "fontSize"; sta v3; ldai 25; sta v4, unique in 1.5.9's modules.abc. Then the file's adler32
# checksum (offset 8, over the bytes after it) is redone. A release where the run isn't found once stops here.
python3 - <<'EOF'
import re, struct, zipfile, zlib
zin = zipfile.ZipFile("entry-default.hap")
abc = bytearray(zin.read("ets/modules.abc"))
hits = [m.start() for m in re.finditer(rb"\x42\x1f..\x61\x03\x62\x19\x00\x00\x00\x61\x04", abc, re.S)]
if len(hits) != 1:
    raise SystemExit("title fontSize instruction found %d times, expected 1" % len(hits))
abc[hits[0] + 7] = 0
struct.pack_into("<I", abc, 8, zlib.adler32(bytes(abc[12:])))
with zipfile.ZipFile("entry-notitle.hap", "w") as zout:
    for info in zin.infolist():
        data = bytes(abc) if info.filename == "ets/modules.abc" else zin.read(info.filename)
        out = zipfile.ZipInfo(info.filename, info.date_time)
        out.compress_type = info.compress_type
        out.external_attr = info.external_attr
        zout.writestr(out, data)
EOF
bash $SIGN entry-notitle.hap $B/apps/petrelgram-signed.hap
