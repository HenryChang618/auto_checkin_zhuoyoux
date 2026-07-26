const SIGN_URL = 'https://www.zhuoyoux.com/lzy/user/sign';
const DEFAULT_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36';

export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(
      runCheckin(env, {
        trigger: 'cron',
        cron: controller?.cron,
        scheduledTime: controller?.scheduledTime,
      }),
    );
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/' || url.pathname === '/health') {
      return jsonResponse({
        ok: true,
        service: 'zhuoyoux-checkin-worker',
        time: nowShanghai(),
        manualRun: Boolean(env.MANUAL_RUN_TOKEN),
      });
    }

    if (url.pathname === '/run') {
      if (request.method !== 'POST') {
        return jsonResponse({ ok: false, error: 'Method Not Allowed' }, 405);
      }

      if (!env.MANUAL_RUN_TOKEN) {
        return jsonResponse({ ok: false, error: 'Manual run is disabled. Set MANUAL_RUN_TOKEN to enable it.' }, 403);
      }

      const authHeader = request.headers.get('Authorization') || '';
      const expected = `Bearer ${env.MANUAL_RUN_TOKEN}`;
      if (authHeader !== expected) {
        return jsonResponse({ ok: false, error: 'Forbidden' }, 403);
      }

      try {
        const result = await runCheckin(env, { trigger: 'manual' });
        return jsonResponse({ ok: true, ...result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error.message }, 500);
      }
    }

    return jsonResponse({ ok: false, error: 'Not Found' }, 404);
  },
};

async function runCheckin(env, context = {}) {
  try {
    validateEnv(env);
  } catch (error) {
    console.error(error.message);
    await notifyTelegram(env, 'failure', '爱桌游签到失败', `原因：${safeErrorMessage(error)}`, context);
    throw error;
  }

  let httpCode = 0;
  let body = '';

  try {
    const response = await fetch(SIGN_URL, {
      method: 'GET',
      headers: {
        Accept: 'application/json, text/plain, */*',
        Authorization: env.ZHUOYOUX_AUTHORIZATION,
        Referer: 'https://www.zhuoyoux.com/',
        'User-Agent': env.ZHUOYOUX_USER_AGENT || DEFAULT_USER_AGENT,
        ywj: 'ywj',
      },
    });

    httpCode = response.status;
    body = await response.text();
  } catch (error) {
    console.error('签到请求网络失败：', error);
    await notifyTelegram(env, 'failure', '爱桌游签到失败', `原因：签到请求网络失败。\n错误：${safeErrorMessage(error)}`, context);
    throw error;
  }

  console.log(`签到请求完成，HTTP 状态码：${httpCode}`);

  if (isTruthy(env.ZHUOYOUX_PRINT_RESPONSE)) {
    console.log(`响应内容：${body}`);
  }

  if (httpCode >= 200 && httpCode < 300) {
    if (body.includes('已经签到过')) {
      const result = { status: 'success', title: '爱桌游已签到', detail: `结果：今日此前已经签到过，按成功处理。\nHTTP：${httpCode}`, httpCode };
      await notifyTelegram(env, result.status, result.title, result.detail, context);
      return result;
    }

    const result = { status: 'success', title: '爱桌游签到成功', detail: `结果：签到请求成功。\nHTTP：${httpCode}`, httpCode };
    await notifyTelegram(env, result.status, result.title, result.detail, context);
    return result;
  }

  if (body.includes('已经签到过')) {
    const result = { status: 'success', title: '爱桌游已签到', detail: `结果：今日此前已经签到过，按成功处理。\nHTTP：${httpCode}`, httpCode };
    await notifyTelegram(env, result.status, result.title, result.detail, context);
    return result;
  }

  console.error('签到失败。为避免公开日志泄露账号信息，默认不打印接口原始响应。');
  const detail = `原因：签到接口返回异常。\nHTTP：${httpCode}`;
  await notifyTelegram(env, 'failure', '爱桌游签到失败', detail, context);
  throw new Error(`Zhuoyoux check-in failed with HTTP ${httpCode}`);
}

function validateEnv(env) {
  if (!env.ZHUOYOUX_AUTHORIZATION) {
    throw new Error('Missing required secret ZHUOYOUX_AUTHORIZATION');
  }

  if (env.ZHUOYOUX_AUTHORIZATION === 'XXXXXXXXXXXXXXXXXXXXXXXX') {
    throw new Error('ZHUOYOUX_AUTHORIZATION is still a placeholder');
  }
}

async function notifyTelegram(env, status, title, detail, context = {}) {
  if (!shouldNotify(status, env.TELEGRAM_NOTIFY_MODE || 'all')) {
    console.log(`Telegram 通知：当前模式 ${env.TELEGRAM_NOTIFY_MODE || 'all'}，跳过 ${status} 通知。`);
    return;
  }

  if (!env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_CHAT_ID) {
    console.warn('Telegram 通知：未配置 TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID，跳过发送。');
    return;
  }

  const icon = status === 'failure' ? '❌' : '✅';
  const message = [
    `${icon} ${title}`,
    '',
    detail,
    `时间：${nowShanghai()}`,
    `触发：${context.trigger || 'unknown'}${context.cron ? ` (${context.cron})` : ''}`,
  ].join('\n');

  try {
    const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      },
      body: new URLSearchParams({
        chat_id: env.TELEGRAM_CHAT_ID,
        text: message,
      }),
    });

    if (!response.ok) {
      console.error(`Telegram 通知：接口返回 HTTP ${response.status}，请检查 Bot Token 和 Chat ID。`);
      return;
    }

    console.log(`Telegram 通知：已发送 ${status} 通知。`);
  } catch (error) {
    console.error('Telegram 通知：发送失败。', error);
  }
}

function shouldNotify(status, mode) {
  switch (String(mode || 'all').toLowerCase()) {
    case 'all':
    case 'always':
    case 'success_and_failure':
      return true;
    case 'failure':
    case 'fail':
    case 'failed':
    case 'failures_only':
      return status === 'failure';
    case 'success':
    case 'success_only':
      return status === 'success';
    case 'none':
    case 'off':
    case 'disabled':
    case 'disable':
    case '0':
    case 'false':
      return false;
    default:
      console.warn(`未知 TELEGRAM_NOTIFY_MODE=${mode}，按 all 处理。`);
      return true;
  }
}

function nowShanghai() {
  const parts = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  })
    .formatToParts(new Date())
    .reduce((acc, part) => {
      acc[part.type] = part.value;
      return acc;
    }, {});

  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second} Asia/Shanghai`;
}

function isTruthy(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').toLowerCase());
}

function safeErrorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      'Content-Type': 'application/json;charset=UTF-8',
    },
  });
}
