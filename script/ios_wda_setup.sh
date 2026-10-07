#!/bin/bash
# macOS/iOS 15 WDA PoC 部署；不启动 AnyDeck，不自动选择用户的签名身份。
set -euo pipefail
wda_revision=d17782422d55ff1e5e0ceb74eb1fd509cc0c35b6
if [[ "${1:-}" == "--help" || $# == 0 ]]; then
  echo '用法: bash script/ios_wda_setup.sh <UDID> <DeveloperTeamID>'
  echo '仅编译检查: bash script/ios_wda_setup.sh --build-unsigned'
  echo '源码固定版本；构建缓存位于 ~/Library/Caches/AnyDeck/ios-poc。'
  exit 0
fi
unsigned=false
if [[ "$1" == '--build-unsigned' ]]; then
  unsigned=true
  team_id=UNSIGNED00
else
  [[ $# == 2 && "$2" =~ ^[A-Za-z0-9]{10}$ && "$1" =~ ^[A-Fa-f0-9-]+$ ]] || {
    echo '必须指定 iPhone UDID 和 10 位 Developer Team ID。' >&2; exit 2;
  }
  phone_udid="$1"
  team_id="$2"
  command -v ios >/dev/null
  command -v iproxy >/dev/null || { echo '请先安装: brew install libusbmuxd' >&2; exit 2; }
fi
cache_dir="$HOME/Library/Caches/AnyDeck/ios-poc"
mkdir -p "$cache_dir"
work_dir="$(mktemp -d "$cache_dir/wda-source.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
curl --fail --location --retry 2 --connect-timeout 15 --max-time 120 \
  "https://codeload.github.com/appium/WebDriverAgent/tar.gz/$wda_revision" \
  -o "$work_dir/source.tar.gz"
mkdir "$work_dir/source"
tar -xzf "$work_dir/source.tar.gz" -C "$work_dir/source" --strip-components=1
# 仅在本次临时源码中替换 Runner Bundle ID，不修改第三方仓库或用户项目。
python3 - "$work_dir/source/WebDriverAgent.xcodeproj/project.pbxproj" "$team_id" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('com.facebook.WebDriverAgentRunner',
    'com.anydeck.WebDriverAgentRunner.' + sys.argv[2].lower()))
PY
derived_dir="$cache_dir/build-$wda_revision-$team_id"
build_args=(build-for-testing -project "$work_dir/source/WebDriverAgent.xcodeproj"
  -scheme WebDriverAgentRunner -configuration Debug -sdk iphoneos
  -derivedDataPath "$derived_dir" IPHONEOS_DEPLOYMENT_TARGET=15.0)
if $unsigned; then
  build_args+=(-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO)
else
  build_args+=(-destination "id=$phone_udid" -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration "DEVELOPMENT_TEAM=$team_id" CODE_SIGN_STYLE=Automatic)
fi
xcodebuild "${build_args[@]}"
runner_path="$derived_dir/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"
[[ -d "$runner_path" ]] || { echo '未找到 WDA Runner 构建产物。' >&2; exit 1; }
if $unsigned; then
  echo "未签名编译检查完成（不能安装到手机）: $runner_path"
else
  ios install "--path=$runner_path" "--udid=$phone_udid"
  echo 'Runner 已安装。请在手机上信任开发者证书，再点击 AnyDeck 的“启用控制”。'
fi
