# Hermes 一键安装器

通过纯前端 WebUI 填写 Telegram Bot Token、模型与 API 信息，生成一条可复制到 VPS 执行的安装命令。

## 在线使用

启用 GitHub Pages 后访问：`https://goldsonhwy.github.io/hermes-oneclick/`

1. 在浏览器填写配置。
2. 点击“生成安装命令”。
3. 复制命令到 Ubuntu/Debian/CentOS 等 Linux VPS，以目标用户身份执行。
4. 安装脚本会安装 Hermes、写入配置、安装并启动 Gateway 服务，并执行健康检查。

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

当前版本：**v1.0.1**

## 上游

Hermes Agent 官方安装器：<https://hermes-agent.nousresearch.com/install.sh>
