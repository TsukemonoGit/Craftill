#!/bin/bash
# A-17: 商品画像ビルドの入口。詳細は scripts/build_images.py を参照。
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/build_images.py" "$@"
