#!/bin/bash
# 默认不访问私有制品；--share-core 可显式校验或获取固定版本制品。
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev_environment.py" check "$@"
