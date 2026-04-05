#!/usr/bin/env bash

set -exu

gh api repos/lwouis/alt-tab-website/dispatches -f event_type=update-website
