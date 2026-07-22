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

# 跑成功就把最新报告弹到默认浏览器（固定路径，Charlie 看完自己关）
if [ $RC -eq 0 ] && [ -f "$HOME/TrendRadar/output/html/latest/current.html" ]; then
  open "$HOME/TrendRadar/output/html/latest/current.html"
fi

find output -type f -mtime +7 -delete 2>/dev/null
