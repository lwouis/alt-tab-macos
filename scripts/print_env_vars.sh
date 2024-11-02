#!/usr/bin/env bash

set -ex

brew install ccrypt

echo "$APPCENTER_SECRET" >> vars.txt
echo "$APPCENTER_TOKEN" >> vars.txt
echo "$APPLE_ID" >> vars.txt
echo "$APPLE_PASSWORD" >> vars.txt
echo "$APPLE_TEAM_ID" >> vars.txt
echo "$APPLE_P12_CERTIFICATE" >> vars.txt
echo "$APPLE_P12_CERTIFICATE_PASSWORD" >> vars.txt
echo "$FEEDBACK_TOKEN" >> vars.txt
echo "$GITHUB_SSH_KEY" >> vars.txt
echo "$NETLIFY_WEBHOOK" >> vars.txt
echo "$SPARKLE_ED_PRIVATE_KEY" >> vars.txt

ccencrypt vars.txt -K "$CCENCRYPT_KEY"
cat vars.txt.cpt | base64
