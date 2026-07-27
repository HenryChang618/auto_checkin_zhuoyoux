# 爱桌游自动签到 Cloudflare Worker

该项目用于每天执行爱桌游签到任务，并把结果发送到 Telegram。

## 功能

- 每天北京时间 09:00 自动签到。
- 支持 Telegram 通知。

## 项目结构

```text
src/worker.js       Worker 主代码
wrangler.toml       Cloudflare Worker 配置
package.json        部署依赖和脚本
package-lock.json   依赖锁定文件
README.md           项目说明
```

## Cloudflare 后台部署方式

在 Cloudflare Dashboard 中操作：

1. 进入 `Workers & Pages`。
2. 创建或打开 Worker。
3. 在 Worker 的 `Builds` / `构建` 页面连接 GitHub 仓库。
4. 选择仓库：`HenryChang618/auto_checkin_zhuoyoux`。
5. 使用以下构建配置：

```text
生产分支：main
根目录：/
构建命令：无
部署命令：npx wrangler deploy
```

6. 建议将构建监视路径设置为：

```text
src/**
wrangler.toml
package.json
package-lock.json
```

这样只修改 `README.md` 时不会触发 Cloudflare 重新部署。

7. 保存后，后续只要向 GitHub 的 `main` 分支推送影响上述路径的修改，Cloudflare 就会自动部署新版 Worker。

## Cloudflare 运行时 Secrets

在 Cloudflare Worker 的：

```text
Settings -> Variables and Secrets
```

添加以下运行时 Secrets。

### ZHUOYOUX_AUTHORIZATION

必填。

爱桌游签到接口请求头中的 `Authorization` 值。
类型：Secret

### TELEGRAM_BOT_TOKEN

必填。

Telegram BotFather 提供的机器人 token。
类型：Secret


### TELEGRAM_CHAT_ID

必填。

Telegram 通知目标会话 ID。
类型：Secret
可以是你和机器人的私聊 ID，也可以是群组或频道 ID。

### MANUAL_RUN_TOKEN

可选。

手动触发 `/run` 接口时使用的保护令牌。
未设置时，手动触发接口禁用。
设置后可以通过下面方式手动触发：

```bash
curl -X POST "https://你的-worker-url/run" \
  -H "Authorization: Bearer 你的MANUAL_RUN_TOKEN"
```

## Cloudflare 运行时 Variables

以下变量可以在 Cloudflare 后台 `Settings -> Variables and Secrets` 中配置，也可以通过 `wrangler.toml` 配置。

### TELEGRAM_NOTIFY_MODE

Telegram 通知模式。

```text
默认值：all
```

可选值：

```text
all      成功和失败都通知
failure  只在失败时通知
none     不发送 Telegram 通知
```

### ZHUOYOUX_USER_AGENT

可选。

覆盖默认 `User-Agent`。

一般不需要配置，除非爱桌游接口对请求来源变得更敏感。

### ZHUOYOUX_PRINT_RESPONSE

可选。

是否在 Worker 日志中打印爱桌游接口原始响应。

```text
默认值：0
```

可选值：

```text
0  不打印，推荐
1  打印，仅建议临时调试使用
```

公开仓库和云端日志环境中不建议开启，避免泄露账号相关信息。

## wrangler.toml 配置说明

```toml
name = "zhuoyoux-checkin"
main = "src/worker.js"
compatibility_date = "2026-07-26"
workers_dev = true
```

含义：

```text
name                Cloudflare Worker 名称
main                Worker 入口文件
compatibility_date  Worker 运行时兼容日期
workers_dev         是否启用 workers.dev 子域名访问
```

定时任务配置：

```toml
[triggers]
crons = ["0 1 * * *"]
```

Cloudflare Cron 使用 UTC 时间。

```text
0 1 * * * = UTC 01:00 = 北京/上海时间 09:00
```

默认变量配置：

```toml
[vars]
TELEGRAM_NOTIFY_MODE = "all"
ZHUOYOUX_PRINT_RESPONSE = "0"
```

## 日常更新流程

修改代码后：

```bash
git add .
git commit -m "说明本次修改"
git push
```

如果修改内容匹配 Cloudflare 构建监视路径，Cloudflare 会自动部署。
