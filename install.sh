#!/usr/bin/env bash
# Aladdin 预构建版安装器（aladdin.bz 下载分发用）。
# 有仓库读权限的开发者请继续用仓库内的 `make install`——那是带完整
# 事务与回滚的认证路径；本脚本只覆盖预构建 app 的快捷安装。
set -euo pipefail
umask 077

# 整个脚本包在 main() 里：curl | bash 场景下 bash 必须先解析完整文件
# 才开始执行，杜绝流式执行中 stdin 被消费或下载截断造成的解析损坏。
main() {

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "❌ 缺少下载地址参数。请到官网复制完整安装命令（curl … -o /tmp/aladdin-install.sh && bash /tmp/aladdin-install.sh <地址>）。" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
APP_DST="$HOME/Applications/Aladdin.app"
CONFIG_DIR="$HOME/.config/aladdin"
CONFIG="$CONFIG_DIR/config.json"
PLIST="$HOME/Library/LaunchAgents/com.internal.aladdin.plist"
LABEL="com.internal.aladdin"
DOMAIN="gui/$(id -u)"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "❌ 这份构建只支持 Apple Silicon (arm64)。" >&2
  exit 1
fi

echo "==> 下载 Aladdin.app（约 15 MB）"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$BASE_URL/downloads/Aladdin.app.zip" -o "$TMP/Aladdin.app.zip"
ditto -x -k "$TMP/Aladdin.app.zip" "$TMP/unpacked"
if [[ ! -d "$TMP/unpacked/Aladdin.app" ]]; then
  echo "❌ 压缩包内容异常，安装中止。" >&2
  exit 1
fi

echo "==> 停止旧实例（如在运行）"
/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/usr/bin/pkill -x Aladdin 2>/dev/null || true

echo "==> 安装到 ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
ditto "$TMP/unpacked/Aladdin.app" "$APP_DST"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

if [[ -f "$CONFIG" ]]; then
  echo "==> 已有配置 ${CONFIG}，保留不动"
else
  echo "==> 首次配置：需要团队网关地址和你的个人 token（问网关管理员要）"
  read -r -p "网关地址（如 https://gw.aladdin.bz）: " GATEWAY </dev/tty
  case "$GATEWAY" in
    https://*) ;;
    http://localhost*|http://127.0.0.1*|"http://[::1]"*) ;;
    *) echo "❌ 网关必须是 https://（或本机回环 http://）。" >&2; exit 1 ;;
  esac
  GATEWAY="${GATEWAY%/}"
  read -r -s -p "个人 token（输入不回显）: " TOKEN </dev/tty
  echo
  if [[ -z "$TOKEN" || ! "$TOKEN" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
    echo "❌ token 为空或含有异常字符。" >&2
    exit 1
  fi
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  OLD_UMASK="$(umask)"
  umask 177
  cat > "$CONFIG" <<EOF
{
  "gateway_url": "$GATEWAY",
  "token": "$TOKEN",
  "language": "auto",
  "dictionary": [],
  "allow_remote_personal_context_egress": false
}
EOF
  umask "$OLD_UMASK"
  unset TOKEN
fi

echo "==> 注册开机自启"
mkdir -p "$HOME/Library/LaunchAgents"
OLD_UMASK="$(umask)"
umask 177
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>KeepAlive</key>
	<false/>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$HOME/Applications/Aladdin.app/Contents/MacOS/Aladdin</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
umask "$OLD_UMASK"
/bin/launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || true
/usr/bin/open "$APP_DST"

cat <<'DONE'

✅ Aladdin 已安装并启动（菜单栏找星月夜图标）。

还差最后几步系统权限，只能你自己点（应用会引导，也可现在就设）：
  1. 系统设置 → 隐私与安全性 → 麦克风         → 打开 Aladdin
  2. 系统设置 → 隐私与安全性 → 辅助功能       → 打开 Aladdin
  3. 系统设置 → 隐私与安全性 → 输入监控       → 打开 Aladdin
  4. 系统设置 → 键盘 → 「按下 🌐 键时」        → 改成「无操作」
  5. 系统设置 → 键盘 → 听写                   → 关闭

之后：轻点 Fn 开始听写、再点提交；按住 Fn 说话、松开提交。
DONE

}

main "$@"
