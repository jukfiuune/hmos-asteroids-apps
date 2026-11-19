#!/bin/bash
# asteroids: private developer signing PKI. root CA -> one signing CA -> app + profile leaf certs. A single signing CA
# issues both (the trust-source entry has one issuer-ca field, matching how the Huawei entries are structured). The
# public root goes into the device trust store; the private keys stay on the build PC for signing.
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
J="java -jar $HB/tools/hapsigner/dist/hap-sign-tool.jar"
KS=asteroids.p12; P=123456; O="C=CN,O=Asteroids,OU=Asteroids Port"
rm -f $KS *.cer *.pem
for a in a-root a-ca a-app a-prof; do
  $J generate-keypair -keyAlias "$a" -keyAlg ECC -keySize NIST-P-256 -keystoreFile $KS -keystorePwd $P -keyPwd $P >/dev/null
done
$J generate-ca -keyAlias a-root -subject "$O,CN=Asteroids Root CA" -validity 7300 -signAlg SHA256withECDSA \
   -keystoreFile $KS -keystorePwd $P -keyPwd $P -outFile rootCA.cer -keyAlg ECC -keySize NIST-P-256 >/dev/null
$J generate-ca -keyAlias a-ca -issuer "$O,CN=Asteroids Root CA" -issuerKeyAlias a-root -issuerKeyPwd $P \
   -subject "$O,CN=Asteroids Signing CA" -validity 7300 -signAlg SHA256withECDSA \
   -keystoreFile $KS -keystorePwd $P -keyPwd $P -outFile signCA.cer -keyAlg ECC -keySize NIST-P-256 >/dev/null
$J generate-app-cert -keyAlias a-app -issuer "$O,CN=Asteroids Signing CA" -issuerKeyAlias a-ca -issuerKeyPwd $P \
   -subject "$O,CN=Asteroids Application Release" -validity 7300 -signAlg SHA256withECDSA \
   -keystoreFile $KS -keystorePwd $P -keyPwd $P -subCaCertFile signCA.cer -rootCaCertFile rootCA.cer \
   -outForm certChain -outFile app-release.pem >/dev/null
$J generate-profile-cert -keyAlias a-prof -issuer "$O,CN=Asteroids Signing CA" -issuerKeyAlias a-ca -issuerKeyPwd $P \
   -subject "$O,CN=Asteroids Profile Release" -validity 7300 -signAlg SHA256withECDSA \
   -keystoreFile $KS -keystorePwd $P -keyPwd $P -subCaCertFile signCA.cer -rootCaCertFile rootCA.cer \
   -outForm certChain -outFile profile-release.pem >/dev/null
echo "== chains =="
for f in app-release.pem profile-release.pem; do echo "-- $f"; openssl crl2pkcs7 -nocrl -certfile $f | openssl pkcs7 -print_certs -noout 2>/dev/null | grep "subject="; done
