# Apps

## Third-party apps launch (2026-11-13)

Every non-system app stayed on SceneBoard's starting window while the app itself ran: render_service dropped its UI
commits (`IsCallingPidValid check failed: callingPid = 0`). Commits are one-way binder calls, Linux binder reports
sender pid 0 for those, and render_service checks a non-system app's commands against the caller's pid (Huawei's
HongMeng kernel gives the real pid). sheng hit the same. Fixed in the kernel: `common/kernel/binder-oneway-pid.py`
sets `t->from_pid` for one-way calls and reports it as sender_pid ([kernel.md](kernel.md)). Commits stay async.

## Installing apps

- Preload apps: Huawei's preload package for this build (`update_full_preload_HBN-AL10_all_cn_R3.zip`, 537 MB,
  SHA-256 cc715607...affe0 per the CDN's filelist.xml) unpacked into preload.img (EROFS, 612 MB), now preload_b in
  super. prep.sh mounts it at `/preload` and binds a baselayer.cfg with `/preload/HBN-AL10/all/cn` added. Eight apps
  (Ctrip, Kuaishou, Qunar, Toutiao, Vipshop, Weibo, Xiaohongshu, Youku).
- `asteroids_bundle` (uid system, INSTALL_BUNDLE; `common/boot/svc/bundle-install.sh`) runs bm install only on the directories
  listed in `/data/local/tmp/asteroids-install.list` and empties it, so apps the user removed stay removed. `aa start`
  and `bm` from a raw root shell fail with "caller invalid" (no token).
- Self-signed apps: our PKI (`common/signing/gen-pki.sh`: root CA → signing CA → app and profile leaves; private keystore
  only on the build PC in `~/harmony-build/tools/asteroids-signing/`, the public root cert in the repo) is merged into the donor's HAP
  trust config (`merge-trust.py`; prep.sh binds trusted_root_ca.json and trusted_apps_sources.json). `sign-hap.sh`
  makes a debug profile from the HAP's manifest (bundle name, its permissions as allowed-acls; device UDID scope).
  `patch-key-enable.py` no-ops EnableKeyInProfile's `/dev/code_sign` (our kernel lacks it).
- Store (AppGallery) apps: their code is encrypted and decrypted in Huawei's TEE; out of reach. AppGallery itself
  blocks its main thread ~3 s (Huawei services/account).
- Home screen: apps installed through bm fill free slots on page 2, not the last page.

## Our apps

- Keyboard (`common/keyboard`, built on the PC with hvigor 6.26 and the 6.1 SDK, `build.sh`): English QWERTY, Bulgarian
  phonetic, symbols, digits on long press, system colors and HM Symbol icons; keys follow raw touch events so
  overlapping presses keep order (2026-11-13). Enabled in Settings > System > Input methods. Celia Keyboard's English
  pack needs a Huawei app credential (the attestation wall below); its 英 key types English without it.
- Petrelgram (Telegram with forum topics, English UI): `common/apps/build-petrelgram.sh` builds v1.5.9's ArkTS side on the
  PC with Huawei's Command Line Tools 26.0.1.290 (PC `~/harmony-build/tools/hmos-cli-26`, API 26), takes TDLib, tgcalls and libentry.so
  from the release, packs the user's api_id/api_hash (on the PC only) and applies `common/apps/petrelgram-*.patch`:
  01 title hidden, 02 thumbnail LRU and paused pulse timers during flings, 03 two upstream diagnostics off, 04 flat
  rows as in Messages, 05 Messages' icons (`symbol-usage.py`), 06 forum views in system style, 07 instant tab switches.
  `sign-petrelgram.sh` (the earlier path: sign the upstream release) is superseded.
- Harlgram (`common/apps/build-harlgram.sh`, TDLib via Node-API, API lowered to 21): starts to its welcome screen, Chinese
  UI; superseded by Petrelgram.

## Walls

- Huawei device attestation: OUCS/TSMS app credentials need a key attestation from the device certificate in
  Huawei's TEE; our HUKS is software with no certificate. Hits Weather (401; TSMS also has no route for country BG),
  Petal Maps, Celia's language packs and DroiTong's image download.
- DroiTong / Android apps: Huawei runs Android apps in a container (the `anco_hmos` image, run by iSulad) with DroiTong
  as the front end. Normally DroiTong downloads that image, but the download needs Huawei device attestation we can't do
  (no TEE device cert), so it's a dead end.
  - Instead we install the image locally. `common/apps/build-anco-preset.sh` builds a preset package (the real 1.2 GB
    Android image + its signed config) from a genuine Huawei phone OTA. `common/apps/stage-anco.sh` (laptop) puts it in
    `/data/asteroids/anco` (preset/, anco_hmos.part, rvt.img; a wiped userdata needs it again), and
    `common/boot/prep.d/65-anco.sh` shows it where the container manager looks for a preinstalled image. No download,
    no attestation.
  - The container runs: Android 16 boots to `sys.boot_completed=1` (2026-11-16) on the Adreno GPU. The kernel needed
    IPC namespaces, POSIX mqueue and the devices cgroup, and `loop.max_part=0` (the guest's apexd numbers loop devices
    by index). The guest loads its GPU driver from the host's `/vendor/anco_spec/vendor` (Kirin's on Huawei phones);
    `common/apps/build-anco-adreno.sh` builds an Adreno/QTI-gralloc one from Nothing's vendor.
  - Boot steps: 65-anco.sh (a normal boot reason, the preset on /sys_prod, loop devices for anco_hmos and rvt, hwlog
    nodes from hwlog.ko, the container overrides: /proc/tty, binderfs nodes bound in, /sys/fs/cgroup read-write, a
    cgroup2 hierarchy for iSulad's lxc) and `platform/qcom/boot/prep.d/85-anco-adreno.sh` (the GPU overlay from
    asteroids.img's anco/ over /vendor/anco_spec/vendor, kgsl and the dma-buf heaps, the patched libgui). The overlay
    also undeclares Huawei's sensor HAL (it needs Kirin's sensor hub). It carries the guest's SELinux labels as xattrs
    (build-asteroids.sh): the guest's init won't start a service whose binary has no exec type.
  - Display bridge (2026-11-16): Android apps render in the guest (hwui frames, Adreno). Needed: Adreno's core shader
    compiler (libllvm-qgl, dlopened) and AOSP's libdmabufheap in place of the guest vendor's Huawei build, which
    passed ION flags as dma-buf heap_flags (EINVAL on Linux, so no buffers at all). Frames still don't reach the
    screen. The app's BLAST queue hands each buffer to the host through Huawei's surface delegator. The guest probes
    the broker's version with SetAlphaWithWindowId(-999, 115); our donor broker answers with an error (243), which
    the guest takes for a version with the newer "token" protocol (request 101, unknown to every libdelegator we
    have). `build-anco-adreno.sh` patches the guest's libgui to stay on the old protocol (85-anco-adreno.sh binds it
    into the guest). The host then gets the buffers but can't convert them: libdelegator dlopens a vendor
    `libgralloc_priv.z.so` for `convert_buffer_handle(native_handle *, BufferHandle **)` (Kirin's turns a Kirin
    private_handle_t into a HarmonyOS BufferHandle). Ours, for QTI handles, is `platform/qcom/display/gralloc_priv.cpp`
    (514228f). With it, the Android app store's Discover page shows on screen (2026-11-16).
  - Touch works (the user, 2026-11-16).
  - Google Play (2026-11-16): Play services, the Services Framework and the Play Store from MindTheGapps 16.0.0 arm64
    (20261023, sha256 6929...5810), built into bind trees by `common/apps/build-anco-gapps.sh` and staged on /data
    by `common/apps/stage-anco-gapps.sh` (277 MB; too big for asteroids_b). 65-anco.sh binds them over the guest's
    priv-app and configuration directories. They install as privileged system apps; Huawei's signature allowlist for
    those names (emui/china/xml/hwDiffSignature.xml, microG's) didn't get in the way. Sign-in works (the user).
    Not yet checked: Play Protect certification (the guest reports a Huawei fingerprint).
  - The Play Store's home-screen icon (2026-11-17): the guest's package converter (hwServices.jar,
    `com.android.server.pm.ancoproxy.converter.Converter.isHideDesktopIcon`) marks the Play Store's and Play services'
    icons hidden while `ro.pms.hide_anco_icon` is true (the default). HarmonyOS's BMS broker
    (libservicebroker_bms.z.so) then records the user in `hideDesktopIconUserIds` in its database
    (/data/service/el1/public/bundle_framework_broker), and it checks again only on an install. The gapps trees carry
    /product's build.prop with the property off, and 65-anco.sh clears the stored entry before the broker starts. The
    launcher then adds the icon, and it opens the Play Store.
  - Found on the way: the guest's hiview_anco spun a core reading /dev/hwlog_jank when it was a /dev/null node (hence
    hwlog.ko); the guest sleeps whenever the host screen goes off and its activities stop, so test with the screen on.
  - Container freeze (2026-11-17): with the screen off, the low-power manager pauses the container. iSulad's lxc
    freezes the cgroup, then fails on HongMeng's deep freeze (`/dev/frz/isulad/<id>/anco_deep_frozen`,
    `hm.freezer.pin_state`) and reports the pause failed (`runtime errno -205`) with the freeze left on. Everyone
    then treats the container as running, nobody resumes it, and every Android app hung on launch. 65-anco.sh's
    watcher (inotifyd on the cgroup's cgroup.events) undoes any freeze left on. Not at once (2026-11-19): lxc waits
    for `frozen 1` in cgroup.events before the deep freeze, and a thaw before it read that kept it waiting forever with
    the container's lock held, so iSulad answered every later query with "trylock timeout" and the brokers took the
    container for gone. The watcher now waits for `frozen 1` and gives lxc 2 s; the pause then fails at once (-205)
    and lxc undoes its own freeze (checked: no stuck pause threads, apps answer after a screen-off). Just before the pause, the guest's
    freezer (hwpged, Pged-Freezer) has also frozen every app's processes in /dev/frz groups, and it thaws them only on
    a resume. So the watcher also thaws the frozen groups that hold container processes; HarmonyOS's own app groups
    stay as they are. That is the state HarmonyOS believes in. Each thaw is logged to /data/local/tmp/anco-thaw.txt.
    Checked with a real screen-off pause: the Play Store and Viber open afterwards. The container is never
    paused, so the Android side gets no screen-off power saving beyond its own.
  - Keys (2026-11-17): the guest's keymaster (keymaster 3.0 with Huawei's keystore_anco module from the Kirin
    anco_spec) keeps keys in iTrustee through teecd, and this phone has no iTrustee. Every key failed with
    TEEC_ERROR_GENERIC (keystore2 `Error::Km(-65536)`), and Instagram's login ended in "An unexpected error occurred".
    build-anco-adreno.sh drops the module, and 65-anco.sh binds the host's keymaster.para with
    const.tee.hwkeymaster.enable off (the guest's ro.tee.anco.hwkeymaster.enbale comes from it). The keymaster
    then takes AOSP's software-only path: keys work, but none are hardware-backed and attestation can't pass.
  - Mobile data (2026-11-19): on mobile data the guest's network is a cellular data network from its own
    telephony, which reaches the modem through a virtual RIL (`libvirtual_ril.so`, socket
    `/data/virt_service/virt_comm/rgm_hmos/uds/virt_ril/virt_ril.sock`). Huawei's host end, `libril_msgtransfer.z.so`,
    normally sits in the RIL host in front of the Balong modem RIL. Here `anco_vrild` (common/anco/vril, an init
    service) loads it on its own, answers its parameters, and puts `libanco_vril.z.so` (Android's RIL_Init interface)
    behind it, answering from slot 1's state as `asteroids_atd` writes it to /data/asteroids/modem-state: SIM, LTE
    registration, operator, and the phone's data call, which anco_vrild activates once through msgtransfer's host
    side. The guest's data call is its cellular link: a veth pair the network broker (libservicebroker_netmanager)
    builds when the phone's default network is cellular, host `ancormnet_data0` at 172.17.0.1, guest `rmnet_data0` at
    172.17.0.2/24, routing table 2019 and NAT. (On Wi-Fi it is `ancowlan0`/`wlan0`, 172.17.1.x; `anco-wlan0`,
    172.17.11.x, exists only with the hotspot on.) Huawei's container engine couldn't build the cellular link from
    this phone's interface name (Kirin's is `rmnet0`): it took only letters and digits in veth names ("host Veth Name
    is invalid"), and its iptables chains (prefix + "_" + host veth name) passed iptables' 28 characters. 65-anco.sh
    binds a patched `librgm_engine_plugin_server.z.so` (any name accepted, shorter chain prefixes; the original bytes
    are checked first). Checked: the guest's MOBILE[LTE] network is VALIDATED and reaches the internet. SIM file reads
    (SIM_IO) and signal strength aren't answered. Container networking isn't set up again until the phone's default
    network changes, so a link that fails to build stays down until then.
  - Identity and Play Protect (2026-11-19): Android's init (Huawei's) takes part of its identity from HarmonyOS
    parameters over /dev/PropBridge (the host's /system/etc/param/param_to_prop.cfg) and the rest from Huawei's
    hw_product props, which made it a Huawei Pura 70 Pro (`HUAWEI/default/HWHBN:...:user/release-keys`) with this
    phone's model number. 65-anco.sh now gives it this phone's identity with a build of its own: the identity lines go
    from param_to_prop.cfg, and a layer over the /sys_prod preset carries hw_product's local.prop with brand and
    manufacturer Nothing, device Asteroids, model A059, name asteroids_anco and fingerprint
    `Nothing/asteroids_anco/Asteroids:16/BP2A.250605.031.A3/104.5.5.111DHSP3:user/release-keys` (not Nothing OS's).
    No Huawei service in the guest minded. Google certifies neither: every check-in that reaches Google comes back
    with `uncertified_status` 3 in Play services' gservices, and Play services then shows its UncertifiedDeviceActivity,
    turns its APIs off ("GoogleAuth.API is not available") and some of its modules crash on that. Sign-in had worked
    on 2026-11-16, before a check-in got through over mobile data. Play services lacks READ_PHONE_STATE, so the IMEI
    isn't part of the check-in. The device's GSF ID (unchanged by clearing Play services' data) is registered at
    google.com/android/uncertified; whether and when that lifts the block is open.
  - Open: a sensors bridge. 32-bit apps go through Huawei's exagear translator (this
    CPU has no AArch32) and are untested.
- Cangjie apps crashed in their runtime's stack walk (pointer authentication; fixed with `arm64.nopauth`): Petrelgram
  confirmed. Weibo crashed the same way before the fix and hasn't been retested (uninstalled).
