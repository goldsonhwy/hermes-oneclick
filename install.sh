#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.4.1"
OFFICIAL_INSTALLER="https://hermes-agent.nousresearch.com/install.sh"

info() { printf '\033[1;34m[Hermes OneClick]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

PAYLOAD_B64="${1:-}"
[[ -n "$PAYLOAD_B64" ]] || fail "缺少配置参数，请从 WebUI 生成安装命令。"
command -v curl >/dev/null || fail "需要 curl，请先安装 curl。"
command -v base64 >/dev/null || fail "需要 base64（coreutils）。"

# 解码 Base64 载荷
TMP_PAYLOAD="$(mktemp)"
cleanup() { rm -f "$TMP_PAYLOAD"; unset PAYLOAD_B64; }
trap cleanup EXIT
printf '%s' "$PAYLOAD_B64" | base64 -d > "$TMP_PAYLOAD" 2>/dev/null || fail "配置参数不是有效 Base64。"
unset PAYLOAD_B64
chmod 600 "$TMP_PAYLOAD"

# 先校验 JSON 包含必要字段（使用 shell 工具，无需 python3）
grep -q '"telegram_token"' "$TMP_PAYLOAD" 2>/dev/null || fail "配置缺少 telegram_token"
grep -q '"model"' "$TMP_PAYLOAD" 2>/dev/null || fail "配置缺少 model"
grep -q '"provider"' "$TMP_PAYLOAD" 2>/dev/null || fail "配置缺少 provider"

# 确保 Python 3 存在（Hermes 官方安装器依赖 python3）
install_python3() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq python3 python3-pip
  elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 python3-pip
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 python3-pip
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3 py3-pip
  elif command -v pkg >/dev/null 2>&1; then
    pkg install -y python3
  else
    fail "无法自动安装 python3，请手动安装后重试。"
  fi
}
if ! command -v python3 >/dev/null; then
  info "系统未安装 python3，正在自动安装..."
  install_python3
  command -v python3 >/dev/null || fail "python3 安装失败，请手动安装。"
  ok "python3 已安装。"
fi

# ── 安装 Hermes 模型管理菜单所需的系统依赖：jq 与 PyYAML ──
# 官方安装器 --skip-setup 会跳过这些，导致管理菜单报
# "jq: command not found" 与 "No module named 'yaml'"，无法获取模型列表。
# 幂等：已就绪则跳过；在 PATH 刷新前后各调用一次，覆盖系统 python3 与 uv python3。

_ensure_pyyaml() {
  python3 -c 'import yaml' >/dev/null 2>&1 && return 0
  info "安装 PyYAML（当前 python3: $(command -v python3)）..."
  # 依次尝试：普通 pip → 允许系统环境 → uv → 系统包管理器
  python3 -m pip install --quiet pyyaml 2>/dev/null \
    || python3 -m pip install --quiet --break-system-packages pyyaml 2>/dev/null \
    || { command -v uv >/dev/null 2>&1 && uv pip install --system --quiet pyyaml 2>/dev/null; } \
    || { command -v apt-get >/dev/null 2>&1 && apt-get install -y -qq python3-yaml 2>/dev/null; } \
    || { command -v yum >/dev/null 2>&1 && yum install -y python3-pyyaml 2>/dev/null; } \
    || { command -v dnf >/dev/null 2>&1 && dnf install -y python3-pyyaml 2>/dev/null; } \
    || { command -v apk >/dev/null 2>&1 && apk add --no-cache py3-pyyaml 2>/dev/null; } \
    || true
}

install_menu_deps() {
  local need_jq=0
  command -v jq >/dev/null 2>&1 || need_jq=1
  if (( need_jq )); then
    info "安装 jq..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y -qq jq
    elif command -v yum >/dev/null 2>&1; then
      yum install -y jq
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y jq
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache jq
    else
      info "未识别包管理器，请手动安装 jq。"
    fi
  fi
  _ensure_pyyaml
  if command -v jq >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    ok "管理依赖 jq / PyYAML 已就绪。"
  else
    info "部分管理依赖未就绪，模型管理菜单可能受限，请按报错手动补装。"
  fi
}

install_menu_deps

info "安装 Hermes Agent（OneClick v${VERSION}）..."
curl -fsSL "$OFFICIAL_INSTALLER" | bash -s -- --skip-setup

# 刷新 PATH：官方安装器会把 hermes 和 uv 安装到 $HOME/.local/bin
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# 现在 python3 应该由 uv 提供（或系统已有）
command -v python3 >/dev/null || fail "安装后未找到 python3，请手动安装 Python 3.11+。"
command -v hermes >/dev/null || fail "Hermes 已安装但命令不在 PATH，请重新登录后再试。"

# PATH 刷新后 python3 可能已切换为 uv 版本，再补一次依赖以确保该 python 也有 PyYAML
install_menu_deps

# 用 python3 做完整校验
info "校验配置..."
python3 - "$TMP_PAYLOAD" <<'PY' || exit 1
import json, re, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
required=['telegram_token','model','provider']
missing=[k for k in required if not str(p.get(k,'')).strip()]
if missing: raise SystemExit('缺少必填变量: '+', '.join(missing))
t=str(p['telegram_token'])
if not re.fullmatch(r'\d+:[A-Za-z0-9_-]{30,}',t):
    raise SystemExit('Telegram Bot Token 格式无效')
if p.get('base_url') and not str(p['base_url']).startswith(('http://','https://')):
    raise SystemExit('API Base URL 必须以 http:// 或 https:// 开头')
print('配置校验通过')
PY

info "写入安全配置..."
python3 - "$TMP_PAYLOAD" <<'PY'
import json, os, pathlib, subprocess, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
home=pathlib.Path(os.environ.get('HERMES_HOME', pathlib.Path.home()/'.hermes'))
home.mkdir(parents=True, exist_ok=True)
env_path=home/'.env'
existing={}
if env_path.exists():
    for line in env_path.read_text(encoding='utf-8',errors='ignore').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1); existing[k]=v
updates={
 'TELEGRAM_BOT_TOKEN':p['telegram_token'],
 'TELEGRAM_ALLOWED_USERS':p.get('telegram_allowed_users',''),
 'TELEGRAM_HOME_CHANNEL':p.get('telegram_home_channel',''),
 'TELEGRAM_REQUIRE_MENTION':str(bool(p.get('require_mention',False))).lower(),
}
if p.get('api_key'): updates['OPENAI_API_KEY']=p['api_key']
if p.get('base_url'): updates['OPENAI_BASE_URL']=p['base_url'].rstrip('/')
existing.update({k:str(v) for k,v in updates.items() if str(v).strip()})
env_path.write_text('\n'.join(f'{k}={v}' for k,v in existing.items())+'\n',encoding='utf-8')
os.chmod(env_path,0o600)

def cfg(key,value):
    if value is None or value=='': return
    subprocess.run(['hermes','config','set',key,str(value)],check=True)

# 主模型
cfg('model.default',p.get('model') or p.get('primary_model',''))
cfg('model.provider',p.get('provider') or p.get('primary_provider','custom'))
if p.get('base_url'): cfg('model.base_url',p['base_url'].rstrip('/'))

# 附加端点 -> 写入 custom_providers
extras = p.get('extra_endpoints', [])
if isinstance(extras, list) and extras:
    custom = []
    for i, ep in enumerate(extras):
        if ep.get('name'):
            custom.append({
                'name': ep['name'],
                'base_url': ep.get('base_url','').rstrip('/'),
                'api_key': ep.get('api_key',''),
                'models': [p.get('model') or p.get('primary_model','')] if (p.get('model') or p.get('primary_model','')) else [],
            })
    if custom:
        cfg('custom_providers', json.dumps(custom, ensure_ascii=False))

print('配置已写入',home)
PY

info "安装并启动 Hermes Gateway..."
hermes gateway install
hermes gateway restart || hermes gateway start

info "执行健康检查..."
hermes doctor || true
hermes gateway status || true
ok "Hermes 安装完成。Telegram Bot Gateway 已启动。"
printf '\n常用命令：\n  hermes status --all\n  hermes gateway status\n  hermes gateway restart\n  hermes doctor\n'
