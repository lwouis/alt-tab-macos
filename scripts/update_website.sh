#!/usr/bin/env bash

set -exu

curl -X POST -d {} $NETLIFY_WEBHOOK
