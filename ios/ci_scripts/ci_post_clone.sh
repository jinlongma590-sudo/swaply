#!/bin/sh
set -euo pipefail

# 进入仓库根目录（Xcode Cloud 会把路径放在这个变量里）
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "== Install Flutter =="
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version

echo "== Flutter iOS artifacts & deps =="
flutter precache --ios
flutter pub get

echo "== CocoaPods =="
# 有就用；没有就装。Homebrew 在 Xcode Cloud 里可用
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

echo "== Pod install =="
cd ios
pod install --repo-update
