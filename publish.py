#!/usr/bin/env python3
"""把最新报告发布到 GitHub Pages，并推送一条 AI 简报 + 链接到 ntfy。

替代 TrendRadar 自带的 ntfy 推送（那个会分 3 批推明细）。
"""
import html as htmllib
import json
import os
import re
import subprocess
import sys
import urllib.request

REPORT = os.path.expanduser("~/TrendRadar/output/html/latest/current.html")
NTFY_BASE = "https://ntfy.sh"

# 发布参数走环境变量，不硬编码在仓库里（这是个公开 fork）。
# ntfy topic 无鉴权：泄露 = 任何人可订阅简报 + 向手机推假通知；
# Pages URL 的随机后缀就是它的全部防护。
# 值放 ~/.config/trendradar/env，由 run-local.sh 载入。
PAGES_DIR = os.path.expanduser(os.environ.get("TRENDRADAR_PAGES_DIR", "~/brief-pages"))
PAGE_URL = os.environ.get("TRENDRADAR_PAGE_URL", "")
TOPIC = os.environ.get("TRENDRADAR_NTFY_TOPIC", "")

NOINDEX = '<meta name="robots" content="noindex,nofollow">'


def publish(raw: str) -> bool:
    """写入 pages 仓库并 push。返回是否有实际变更。"""
    page = raw if NOINDEX in raw else raw.replace("<head>", "<head>" + NOINDEX, 1)
    dest = os.path.join(PAGES_DIR, "index.html")
    if os.path.exists(dest) and open(dest, encoding="utf-8").read() == page:
        return False
    with open(dest, "w", encoding="utf-8") as f:
        f.write(page)
    subprocess.run(["git", "add", "-A"], cwd=PAGES_DIR, check=True)
    r = subprocess.run(["git", "commit", "-q", "-m", "report: auto-update"],
                       cwd=PAGES_DIR, capture_output=True, text=True)
    if r.returncode != 0 and "nothing to commit" not in (r.stdout + r.stderr):
        print(f"[publish] commit 失败: {r.stdout}{r.stderr}", file=sys.stderr)
        return False
    p = subprocess.run(["git", "push", "-q", "origin", "main"],
                       cwd=PAGES_DIR, capture_output=True, text=True)
    if p.returncode != 0:
        print(f"[publish] push 失败: {p.stderr}", file=sys.stderr)
        return False
    return True


def extract_ai(raw: str) -> str:
    """从报告 HTML 里抽出 AI 分析各区块，转成 ntfy 用的 markdown。"""
    blocks = re.findall(
        r'<div class="ai-block-title">(.*?)</div>\s*<div class="ai-block-content">(.*?)</div>',
        raw, re.S)
    out = []
    for title, body in blocks:
        body = re.sub(r"<br\s*/?>", "\n", body)
        body = re.sub(r"<[^>]+>", "", body)
        body = htmllib.unescape(body).strip()
        out.append(f"**{htmllib.unescape(title).strip()}**\n{body}")
    return "\n\n".join(out)


def hot_topics(raw: str) -> str:
    m = re.search(r"最热话题[：:]\s*([^<\n]+)", raw)
    return m.group(1).strip() if m else ""


def main():
    missing = [n for n, v in (("TRENDRADAR_NTFY_TOPIC", TOPIC),
                              ("TRENDRADAR_PAGE_URL", PAGE_URL)) if not v]
    if missing:
        print(f"[publish] 缺少环境变量 {', '.join(missing)}，"
              f"请检查 ~/.config/trendradar/env", file=sys.stderr)
        return 1

    if not os.path.exists(REPORT):
        print("[publish] 找不到报告，跳过", file=sys.stderr)
        return 1
    raw = open(REPORT, encoding="utf-8").read()

    publish(raw)

    ai = extract_ai(raw)
    if not ai:
        print("[publish] 未提取到 AI 分析，跳过推送", file=sys.stderr)
        return 1

    topics = hot_topics(raw)
    header = f"🔥 {topics}\n\n" if topics else ""
    footer = f"\n\n———\n📄 [点开完整报告]({PAGE_URL})"

    # ntfy 单条上限 4096 字节；中文 1 字 3 字节，超了就截断（明细在网页上）
    budget = 4000 - len((header + footer).encode("utf-8"))
    trimmed = ai.encode("utf-8")[:budget].decode("utf-8", "ignore")
    if len(trimmed) < len(ai):
        trimmed = trimmed.rstrip() + "…"
    body = header + trimmed + footer

    payload = json.dumps({
        "topic": TOPIC,
        "title": "每日简报",
        "message": body,
        "click": PAGE_URL,
        "markdown": True,
        "tags": ["chart_with_upwards_trend"],
    }).encode("utf-8")

    req = urllib.request.Request(
        NTFY_BASE, data=payload,
        headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=20)
        print(f"[publish] 已推送 1 条简报（{len(body.encode('utf-8'))} 字节）→ {PAGE_URL}")
    except Exception as e:
        print(f"[publish] ntfy 推送失败: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
