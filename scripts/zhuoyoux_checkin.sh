#!/usr/bin/env bash
set -Eeuo pipefail

# 爱桌游自动签到脚本
# 必填环境变量：
#   ZHUOYOUX_AUTHORIZATION  从浏览器请求头中复制的 Authorization 值
# 可选环境变量：
#   ZHUOYOUX_USER_AGENT     自定义 User-Agent
#   ZHUOYOUX_DRY_RUN        设置为 1 时只检查参数，不真正发起签到请求

SIGN_URL="https://www.zhuoyoux.com/lzy/user/sign"
AUTHORIZATION="${ZHUOYOUX_AUTHORIZATION:-}"
USER_AGENT="${ZHUOYOUX_USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36}"
DRY_RUN="${ZHUOYOUX_DRY_RUN:-0}"

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

# 使用临时文件保存响应，避免 curl 失败时丢失错误信息。
response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

http_code="$({
  curl --silent --show-error --location --fail-with-body \
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
  if [[ -s "${response_file}" ]]; then
    echo "响应内容：" >&2
    cat "${response_file}" >&2
    echo >&2
  fi
  exit "${status}"
}

echo "签到请求完成，HTTP 状态码：${http_code}"
echo "响应内容："
cat "${response_file}"
echo
