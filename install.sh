#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
OFFICIAL_INSTALLER="https://hermes-agent.nousresearch.com/install.sh"

info() { printf '\033[1;34m[Hermes OneClick]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

PAYLOAD_B64="${1:-}"
[[ -n "$PAYLOAD_B64" ]] || fail "缺少配置参数，请从 WebUI 生成安装命令。"
command -v curl >/dev/null || fail "需要 curl，请先安装 curl。"
command -v base64 >/dev/null || fail "需要 base64（coreutils）。"

TMP_PAYLOAD="$(mktemp)"
cleanup() { rm -f "$TMP_PAYLOAD"; unset PAYLOAD_B64; }
trap cleanup EXIT
printf '%s' "$PAYLOAD_B64" | base64 -d > "$TMP_PAYLOAD" 2>/dev/null || fail "配置参数不是有效 Base64。"
unset PAYLOAD_B64
chmod 600 "$TMP_PAYLOAD"

# Validate before changing the system. Python 3 is required by Hermes itself.
command -v python3 >/dev/null || fail "需要 Python 3.11+。请先安装 python3，或使用官方安装器支持的系统。"
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

info "安装 Hermes Agent（OneClick v${VERSION}）..."
curl -fsSL "$OFFICIAL_INSTALLER" | bash -s -- --skip-setup

# The official installer may update PATH in shell startup files.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
command -v hermes >/dev/null || fail "Hermes 已安装但命令不在 PATH，请重新登录后再试。"

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
}
if p.get('api_key'): updates['OPENAI_API_KEY']=p['api_key']
if p.get('base_url'): updates['OPENAI_BASE_URL']=p['base_url'].rstrip('/')
existing.update({k:str(v) for k,v in updates.items() if str(v).strip()})
env_path.write_text('\n'.join(f'{k}={v}' for k,v in existing.items())+'\n',encoding='utf-8')
os.chmod(env_path,0o600)

def cfg(key,value):
    if value is None or value=='': return
    subprocess.run(['hermes','config','set',key,str(value)],check=True)
cfg('model.default',p['model'])
cfg('model.provider',p['provider'])
if p.get('base_url'): cfg('model.base_url',p['base_url'].rstrip('/'))
if p.get('api_key'): cfg('model.api_key',p['api_key'])
cfg('telegram.require_mention',str(bool(p.get('require_mention',False))).lower())
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
