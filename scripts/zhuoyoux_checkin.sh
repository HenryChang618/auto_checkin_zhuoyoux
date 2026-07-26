#!/usr/bin/env bash
set -Eeuo pipefail

# 爱桌游自动签到脚本
# 必填环境变量：
#   ZHUOYOUX_AUTHORIZATION  从浏览器请求头中复制的 Authorization 值
# 可选环境变量：
#   ZHUOYOUX_USER_AGENT     自定义 User-Agent
#   ZHUOYOUX_DRY_RUN        设置为 1 时只检查参数，不真正发起签到请求
#   ZHUOYOUX_PRINT_RESPONSE 设置为 1 时打印接口原始响应（公开仓库不建议开启）

SIGN_URL="https://www.zhuoyoux.com/lzy/user/sign"
AUTHORIZATION="${ZHUOYOUX_AUTHORIZATION:-}"
USER_AGENT="${ZHUOYOUX_USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36}"
DRY_RUN="${ZHUOYOUX_DRY_RUN:-0}"
PRINT_RESPONSE="${ZHUOYOUX_PRINT_RESPONSE:-0}"

if [[ -z "${AUTHORIZATION}" ]]; then
  echo "错误：缺少环境变量 ZHUOYOUX_AUTHORIZATION。" >&2
  echo "请在 GitHub 仓库 Settings -> Secrets and variables -> Actions 中添加同名 Repository secret。" >&2
  exit 2
fi

if [[ "${AUTHORIZATION}" == "XXXXXXXXXXXXXXXXXXXXXXXX" ]]; then
  echo "错误：ZHUOYOUX_AUTHORIZATION 仍是占位符，请替换为真实 Authorization。" >&2
  exit 2
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry run: 已检测到 Authorization，跳过真实签到请求。"
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
  else
    echo "结果：签到请求成功。"
  fi
  exit 0
fi

if [[ "${body}" == *"已经签到过"* ]]; then
  echo "结果：今日此前已经签到过。接口返回 ${http_code}，但业务含义为已完成，按成功处理。"
  exit 0
fi

echo "结果：签到失败。" >&2
echo "提示：为避免公开仓库 Actions 日志泄露账号信息，默认不打印接口原始响应。" >&2
echo "如需临时调试，可在仓库 Variables 中设置 ZHUOYOUX_PRINT_RESPONSE=1，调试后建议删除。" >&2
exit 1
