#!/usr/bin/env bash
set -Eeuo pipefail

# 爱桌游自动签到脚本
# 必填环境变量：
#   ZHUOYOUX_AUTHORIZATION  从浏览器请求头中复制的 Authorization 值
# 可选环境变量：
#   ZHUOYOUX_USER_AGENT     自定义 User-Agent
#   ZHUOYOUX_DRY_RUN        设置为 1 时只检查参数，不真正发起签到请求
#   ZHUOYOUX_PRINT_RESPONSE 设置为 1 时打印接口原始响应（公开仓库不建议开启）
# Telegram 通知环境变量：
#   TELEGRAM_BOT_TOKEN      Telegram BotFather 提供的 bot token，建议放入 GitHub Secret
#   TELEGRAM_CHAT_ID        通知目标 chat_id，建议放入 GitHub Secret
#   TELEGRAM_NOTIFY_MODE    all/failure/none，默认 all；后续只想失败通知时设为 failure

SIGN_URL="https://www.zhuoyoux.com/lzy/user/sign"
AUTHORIZATION="${ZHUOYOUX_AUTHORIZATION:-}"
USER_AGENT="${ZHUOYOUX_USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36}"
DRY_RUN="${ZHUOYOUX_DRY_RUN:-0}"
PRINT_RESPONSE="${ZHUOYOUX_PRINT_RESPONSE:-0}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_NOTIFY_MODE="${TELEGRAM_NOTIFY_MODE:-all}"

now_shanghai() {
  TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z'
}

run_url() {
  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
    printf '%s/%s/actions/runs/%s' "${GITHUB_SERVER_URL}" "${GITHUB_REPOSITORY}" "${GITHUB_RUN_ID}"
  fi
}

should_notify() {
  local status="$1"
  local mode="${TELEGRAM_NOTIFY_MODE,,}"
  case "${mode}" in
    all|always|success_and_failure)
      return 0
      ;;
    failure|fail|failed|failures_only)
      if [[ "${status}" == "failure" ]]; then
        return 0
      fi
      return 1
      ;;
    success|success_only)
      if [[ "${status}" == "success" ]]; then
        return 0
      fi
      return 1
      ;;
    none|off|disabled|disable|0|false)
      return 1
      ;;
    *)
      echo "警告：未知 TELEGRAM_NOTIFY_MODE=${TELEGRAM_NOTIFY_MODE}，按 all 处理。" >&2
      return 0
      ;;
  esac
}

notify_telegram() {
  local status="$1"
  local title="$2"
  local detail="$3"

  if ! should_notify "${status}"; then
    echo "Telegram 通知：当前模式 ${TELEGRAM_NOTIFY_MODE}，跳过 ${status} 通知。"
    return 0
  fi

  if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" ]]; then
    echo "Telegram 通知：未配置 TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID，跳过发送。" >&2
    return 0
  fi

  local icon="✅"
  if [[ "${status}" == "failure" ]]; then
    icon="❌"
  fi

  local message="${icon} ${title}

${detail}
时间：$(now_shanghai)"

  local url
  url="$(run_url)"
  if [[ -n "${url}" ]]; then
    message+="
Actions：${url}"
  fi

  # 通知失败不应影响签到结果，所以这里吞掉 Telegram API 错误，仅在日志中提示。
  local notify_response
  if ! notify_response="$({
    curl --silent --show-error --location \
      --request POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${message}" \
      --write-out "\n%{http_code}"
  } 2>&1)"; then
    echo "Telegram 通知：发送失败。${notify_response}" >&2
    return 0
  fi

  local notify_http_code
  notify_http_code="$(printf '%s' "${notify_response}" | tail -n 1)"
  if [[ ! "${notify_http_code}" =~ ^2[0-9][0-9]$ ]]; then
    echo "Telegram 通知：接口返回 HTTP ${notify_http_code}，请检查 Bot Token 和 Chat ID。" >&2
    return 0
  fi

  echo "Telegram 通知：已发送 ${status} 通知。"
}

if [[ -z "${AUTHORIZATION}" ]]; then
  message="错误：缺少环境变量 ZHUOYOUX_AUTHORIZATION。请在 GitHub 仓库 Actions Secrets 中添加同名 Repository secret。"
  echo "${message}" >&2
  notify_telegram "failure" "爱桌游签到失败" "原因：缺少 ZHUOYOUX_AUTHORIZATION。"
  exit 2
fi

if [[ "${AUTHORIZATION}" == "XXXXXXXXXXXXXXXXXXXXXXXX" ]]; then
  message="错误：ZHUOYOUX_AUTHORIZATION 仍是占位符，请替换为真实 Authorization。"
  echo "${message}" >&2
  notify_telegram "failure" "爱桌游签到失败" "原因：ZHUOYOUX_AUTHORIZATION 仍是占位符。"
  exit 2
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry run: 已检测到 Authorization，跳过真实签到请求和 Telegram 通知。"
  exit 0
fi

# 使用临时文件保存响应。
# 不使用 curl --fail/--fail-with-body：爱桌游在“今日已签到”时会返回 HTTP 403，
# 但业务含义不是失败，需要根据响应内容单独判断。
response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

http_code="$({
  curl --silent --show-error --location \
    --request GET "${SIGN_URL}" \
    --header "Accept: application/json, text/plain, */*" \
    --header "Authorization: ${AUTHORIZATION}" \
    --header "Referer: https://www.zhuoyoux.com/" \
    --header "User-Agent: ${USER_AGENT}" \
    --header "ywj: ywj" \
    --output "${response_file}" \
    --write-out "%{http_code}"
} 2>&1)" || {
  status=$?
  echo "签到请求失败，curl 退出码：${status}" >&2
  echo "HTTP/错误信息：${http_code}" >&2
  notify_telegram "failure" "爱桌游签到失败" "原因：签到请求网络或 curl 执行失败。\ncurl 退出码：${status}"
  exit "${status}"
}

body="$(cat "${response_file}")"

echo "签到请求完成，HTTP 状态码：${http_code}"

if [[ "${PRINT_RESPONSE}" == "1" ]]; then
  echo "响应内容："
  cat "${response_file}"
  echo
fi

if [[ "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
  if [[ "${body}" == *"已经签到过"* ]]; then
    echo "结果：今日此前已经签到过，按成功处理。"
    notify_telegram "success" "爱桌游已签到" "结果：今日此前已经签到过，按成功处理。\nHTTP：${http_code}"
  else
    echo "结果：签到请求成功。"
    notify_telegram "success" "爱桌游签到成功" "结果：签到请求成功。\nHTTP：${http_code}"
  fi
  exit 0
fi

if [[ "${body}" == *"已经签到过"* ]]; then
  echo "结果：今日此前已经签到过。接口返回 ${http_code}，但业务含义为已完成，按成功处理。"
  notify_telegram "success" "爱桌游已签到" "结果：今日此前已经签到过，按成功处理。\nHTTP：${http_code}"
  exit 0
fi

echo "结果：签到失败。" >&2
echo "提示：为避免公开仓库 Actions 日志泄露账号信息，默认不打印接口原始响应。" >&2
echo "如需临时调试，可在仓库 Variables 中设置 ZHUOYOUX_PRINT_RESPONSE=1，调试后建议删除。" >&2
notify_telegram "failure" "爱桌游签到失败" "原因：签到接口返回异常。\nHTTP：${http_code}"
exit 1
