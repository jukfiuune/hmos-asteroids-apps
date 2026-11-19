# Apps for HarmonyOS NEXT on the Nothing Phone (3a)

Apps built for the hmos-asteroids port, signed with your own developer certificate:

- `common/keyboard/`: the on-screen keyboard (ArkTS). Build: `common/keyboard/build.sh`.
- `common/apps/build-petrelgram.sh`, `sign-petrelgram.sh`, `petrelgram-*.patch`: Petrelgram
  (github.com/miramira8295/Petrelgram), a Telegram client, with our patches.
- `common/apps/build-harlgram.sh`, `harlgram-api21.patch`: Harlgram, built for API 21.

You need, on the build machine (`$HARMONY_BUILD`, default `~/harmony-build`):

- The signing keys: `common/signing/gen-pki.sh` in `$HARMONY_BUILD/tools/asteroids-signing`, and the phone's UDID in
  its `udid` file. The port repository's build adds the root certificate to the phone's trust store.
- hap-sign-tool (`$HARMONY_BUILD/tools/hapsigner`, fetched by the port's `build/fetch-sources.sh tools`).
- Huawei's Command Line Tools for HarmonyOS (from Huawei's developer download center; the versions are in each
  script's header) and the OpenHarmony SDK (`fetch-sources.sh ohos`).
- For the Telegram clients, your own api_id and api_hash from my.telegram.org in
  `$HARMONY_BUILD/apps/harlgram/config/telegram.local.json`. Never commit them.

Licence: Apache-2.0 ([LICENSE](LICENSE)); the patches follow each app's own licence ([THIRD-PARTY.md](THIRD-PARTY.md)).
