#!/bin/bash
#
# 2way 自签代码签名证书 —— 幂等脚本
#
# 为什么需要它（TECH_PLAN §9）：
#   ad-hoc 签名（codesign -s -）的 designated requirement 就是二进制的 cdhash，
#   每次重新构建都会变。macOS 把 Keychain ACL 信任与 TCC 授权记录在 DR 上，
#   所以 ad-hoc 下每次重建后，读取已存密钥都会弹系统密码框、摄像头授权也会重置。
#   用一张固定的自签证书签名，DR 变成
#     identifier "com.kimi.2way" and certificate root = H"<证书哈希>"
#   证书不变则 DR 永远不变，重建多少次权限都不掉。
#
# 前置：已安装 openssl（Homebrew 或系统自带均可）
# 用法：bash scripts/create-signing-cert.sh
# 幂等：已有同身份证书时直接退出，不会重复创建
#
set -euo pipefail

CN="${SIGNING_CN:-2way Local Signing}"
BACKUP_DIR="$HOME/Library/Application Support/2way/signing"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
VALID_DAYS="${SIGNING_DAYS:-3650}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }

bold "==> [1/6] 检查是否已存在身份「$CN」"
# 注意：必须去掉 -v。自签根不受系统信任，会报 CSSMERR_TP_NOT_TRUSTED，
# 带 -v 时被隐藏，看起来像"没有证书"。
if security find-identity -p codesigning 2>/dev/null | grep -qF "$CN"; then
  bold "  已存在，无需重复创建："
  security find-identity -p codesigning 2>/dev/null | grep -F "$CN" | sed 's/^/    /'
  echo
  bold "==> 验证当前 DR 形态（应含 identifier + certificate root，不含 cdhash）"
  echo "  用一个临时二进制验证："
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf 'int main(void){return 0;}' > "$WORK/t.c"
  if cc -o "$WORK/t" "$WORK/t.c" 2>/dev/null; then
    codesign --force --sign "$CN" "$WORK/t" 2>/dev/null || true
    codesign -d -r- "$WORK/t" 2>&1 | grep -i designated | sed 's/^/    /' || true
  fi
  exit 0
fi
note "未找到，开始创建"

bold "==> [2/6] 生成自签证书（含 codeSigning EKU）"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
P12PW="${SIGNING_P12_PASSWORD:-$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)}"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days "$VALID_DAYS" \
  -subj "/CN=$CN/O=2way Local/C=CN" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  2>/dev/null
note "证书已生成：$(openssl x509 -in "$WORK/cert.pem" -noout -subject 2>/dev/null)"

bold "==> [3/6] 导出 p12"
# 关键坑：OpenSSL 3.x 默认用 AES-256 导出 p12，macOS 的 security import 读不了，
# 会报 "MAC verification failed during PKCS12 import"。必须加 -legacy。
if ! openssl pkcs12 -export -legacy -out "$WORK/id.p12" \
      -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
      -name "$CN" -passout "pass:$P12PW" 2>/dev/null; then
  bold "  -legacy 不可用，改用显式 PBE 参数重试"
  openssl pkcs12 -export -out "$WORK/id.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -name "$CN" -passout "pass:$P12PW" 2>/dev/null
fi
note "p12 已生成"

bold "==> [4/6] 导入登录钥匙串（信任 codesign 使用该私钥）"
security import "$WORK/id.p12" -k "$LOGIN_KC" -P "$P12PW" -T /usr/bin/codesign 2>&1 | sed 's/^/  /'

bold "==> [5/6] 备份私钥材料"
# 这里只备份 p12（有密码保护）与证书公钥，不落明文私钥
mkdir -p "$BACKUP_DIR"
cp "$WORK/id.p12" "$BACKUP_DIR/2way-signing.p12"
cp "$WORK/cert.pem" "$BACKUP_DIR/2way-signing-cert.pem"
chmod 600 "$BACKUP_DIR/2way-signing.p12"
note "备份目录：$BACKUP_DIR"

bold "==> [6/6] 结果"
security find-identity -p codesigning 2>/dev/null | grep -F "$CN" | sed 's/^/  /' || true
echo
bold "身份已安装。验证码库中的密钥从此与该证书绑定 —— 请务必保留备份。"
echo
note "p12 备份密码（请立即保存到密码管理器）：$P12PW"
echo
bold "可选：让 codesign 首次使用私钥时不弹窗"
note "下面这条需要你的登录密码，可选执行："
note "  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <登录密码> \"$LOGIN_KC\""
note "不执行的话，首次 codesign 会弹一次「允许/始终允许」，点「始终允许」即可。"
