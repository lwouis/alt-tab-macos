#!/usr/bin/env bash

set -ex

# certificate request (see https://apple.stackexchange.com/q/359997)
cat >codesign.conf <<EOL
  [ req ]
  distinguished_name = req_name
  prompt = no
  [ req_name ]
  CN = alt-tab-macos
  [ extensions ]
  basicConstraints=critical,CA:false
  keyUsage=critical,digitalSignature
  extendedKeyUsage=critical,1.3.6.1.5.5.7.3.3
  1.2.840.113635.100.6.1.14=critical,DER:0500
EOL

password=$(openssl rand -base64 12)

# generate key
openssl genrsa -out codesign.key 2048
# generate self-signed certificate
openssl req -x509 -new -config codesign.conf -nodes -key codesign.key -extensions extensions -sha256 -out codesign.crt
# wrap key and certificate into PKCS12
openssl pkcs12 -export -inkey codesign.key -in codesign.crt -out codesign.p12 -passout pass:$password
# import p12 into Keychain
security import codesign.p12 -P $password -T /usr/bin/codesign
# in Keychain, set Trust > Code Signing > "Always Trust"
security add-trusted-cert -d -r trustRoot -p codeSign codesign.crt
