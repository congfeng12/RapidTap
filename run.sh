#!/bin/bash
#
# 编译（如未编译）并启动 RapidTap
#
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -x "RapidTap.app/Contents/MacOS/RapidTap" ]; then
    ./build.sh
fi

open "RapidTap.app"
