#!/usr/bin/env bash

set -exu

certificateFile="codesign"
certificatePassword=$(openssl rand -base64 12)

# certificate request (see https://apple.stackexchange.com/q/359997)
cat >$certificateFile.conf <<EOL
  [ req ]
  distinguished_name = req_name
  prompt = no
  [ req_name ]
  CN = Local Self-Signed
  [ extensions ]
  basicConstraints=critical,CA:false
  keyUsage=critical,digitalSignature
  extendedKeyUsage=critical,1.3.6.1.5.5.7.3.3
  1.2.840.113635.100.6.1.14=critical,DER:0500
EOL

# generate key
openssl genrsa -out $certificateFile.key 2048
# generate self-signed certificate
openssl req -x509 -new -config $certificateFile.conf -nodes -key $certificateFile.key -extensions extensions -sha256 -out $certificateFile.crt
# wrap key and certificate into PKCS12
openssl pkcs12 -export -inkey $certificateFile.key -in $certificateFile.crt -out $certificateFile.p12 -passout pass:$certificatePassword
# import p12 into Keychain
security import $certificateFile.p12 -P $certificatePassword -T /usr/bin/codesign
# in Keychain, set Trust > Code Signing > "Always Trust"
security add-trusted-cert -d -r trustRoot -p codeSign $certificateFile.crt
