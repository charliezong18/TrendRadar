#!/bin/bash
# TrendRadar 定时抓取（launchd 调用）
# API key 运行时从 CCR 配置读取，不在此文件留副本
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$HOME/TrendRadar" || exit 1

export DOCKER_CONTAINER=true          # 抑制跑完自动弹浏览器
# 不导出 NTFY_*：自带推送会分 3 批推明细。改由 publish.py 发单条简报+链接。

# 发布参数（ntfy topic / Pages URL）—— 仓库是公开 fork，值放仓库外
ENV_FILE="$HOME/.config/trendradar/env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$ENV_FILE"
else
  echo "警告: 缺少 $ENV_FILE，publish.py 将跳过发布" >&2
fi

export AI_API_KEY="$(python3 -c "
import json
cfg = json.load(open('$HOME/.claude-code-router/config.json'))
for p in cfg.get('Providers', []):
    if 'deepseek' in (p.get('name','') + p.get('api_base_url','')).lower() and p.get('api_key'):
        print(p['api_key']); break
")"

echo "=== $(date '+%F %T') start ==="
.venv/bin/python -m trendradar
RC=$?
echo "=== $(date '+%F %T') exit=$RC ==="

# 发布到 GitHub Pages + 推一条 AI 简报（带链接）
if [ $RC -eq 0 ]; then
  .venv/bin/python publish.py
fi

# 跑成功就把最新报告弹到默认浏览器，Charlie 看完自己关
# 优先线上 Pages：那边默认宽屏（本地 file:// 的窄版是邮件用的 600px 底样式），手机也能开
LOCAL_HTML="$HOME/TrendRadar/output/html/latest/current.html"
PAGES_HTML="${TRENDRADAR_PAGES_DIR:-$HOME/brief-pages}/index.html"
if [ $RC -eq 0 ]; then
  OPENED=""
  # 确认 publish.py 真写了新版；否则线上还是上一期，宁可开本地。
  # 不能用 [ -nt ]：bash 的 -nt 只比整秒（zsh 才是纳秒），而 publish.py 写
  # index.html 只比 current.html 晚零点几秒，同秒内恒判 false，线上分支永不执行。
  if [ -n "$TRENDRADAR_PAGE_URL" ] && [ -f "$PAGES_HTML" ] && awk \
      -v a="$(stat -f %Fm "$PAGES_HTML")" -v b="$(stat -f %Fm "$LOCAL_HTML")" \
      'BEGIN{exit !(a>b)}'; then
    # 等 Pages 部署完（通常 20~60s），不等的话打开的是上一期报告，还看不出来
    WANT=$(wc -c < "$PAGES_HTML" | tr -d ' ')
    for _ in $(seq 24); do
      if [ "$(curl -sfL "$TRENDRADAR_PAGE_URL" | wc -c | tr -d ' ')" = "$WANT" ]; then
        open "$TRENDRADAR_PAGE_URL"; OPENED=1; break
      fi
      sleep 5
    done
    [ -z "$OPENED" ] && echo "警告: Pages 120s 内未更新，退回本地文件" >&2
  else
    # 闸门不通过时必须出声：上一版就是在这里静默退回本地，查了半天才发现
    echo "警告: $PAGES_HTML 不比本地报告新（或 PAGE_URL 未配），跳过线上，开本地文件" >&2
  fi
  [ -z "$OPENED" ] && [ -f "$LOCAL_HTML" ] && open "$LOCAL_HTML"
fi

find output -type f -mtime +7 -delete 2>/dev/null
