# Hermes 一键安装器

通过纯前端 WebUI 填写 Telegram Bot Token、模型与 API 信息，生成一条可复制到 VPS 执行的安装命令。

## 在线使用

启用 GitHub Pages 后访问：`https://goldsonhwy.github.io/hermes-oneclick/`

1. 在浏览器填写配置。
2. 点击"生成安装命令"。
3. 复制命令到 Ubuntu/Debian/CentOS 等 Linux VPS，以目标用户身份执行。
4. 安装脚本会安装 Hermes、写入配置、安装并启动 Gateway 服务，并执行健康检查。

## 功能

- **多端点支持** — 主模型 + 多个附加端点，自动写入自定义 Provider
- **回退 Provider** — 设置备用 Provider，主模型不可用时自动切换
- **2026+ 常用模型列表** — 预置 deepseek-v4-flash、gpt-5.6-sol、claude-sonnet-4 等
- **表单持久化** — 刷新页面自动恢复填写内容

## 安全说明

- WebUI 是纯静态页面，数据只在浏览器本地处理，不会上传到服务器。
- 生成的命令包含 Base64 编码后的密钥；Base64 **不是加密**。
- 命令可能进入 VPS Shell 历史。安装后应执行 `history -d $(history 1 | awk '{print $1}')`，或临时使用 `set +o history`。
- 不要把生成后的命令、Bot Token 或 API Key 提交到 GitHub。

## 直接运行 WebUI

```bash
python3 -m http.server 8080
# 打开 http://127.0.0.1:8080
```

## 开发验证

```bash
bash -n install.sh
python3 tests/test_payload.py
```

## 版本

当前版本：**v1.4.0**

安装脚本固定地址（WebUI 生成的命令指向此地址）：
`https://raw.githubusercontent.com/goldsonhwy/hermes-oneclick/v1.4.0/install.sh`

### v1.4.0 变更（修复上游 Hermes 版本更新导致的失效问题）

- **修复（致命）**：移除失效的 `hermes config set telegram.require_mention` 调用（新版上游已无此顶层键，会导致脚本中途退出）。改为将 `TELEGRAM_REQUIRE_MENTION` 写入 `.env`，由 Telegram adapter 在运行时读取。
- **修复**：API Key 不再双写。移除 `hermes config set model.api_key`，统一由 `.env` 的 `OPENAI_API_KEY` 提供，避免与上游新的密钥引用机制冲突。
- **修复**：附加端点 `custom_providers` 每项补充 `models` 字段，使端点出现在可选模型列表、避免被静默忽略。
- WebUI 生成的安装命令改为指向 `v1.4.0` tag 的固定脚本地址，旧版 `v1.3.1` 不受影响。

## 上游

Hermes Agent 官方安装器：<https://hermes-agent.nousresearch.com/install.sh>
