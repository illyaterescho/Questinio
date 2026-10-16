#!/usr/bin/env python3
"""Small real-Ollama contract probe; no audio or live-voice accuracy is tested."""
import argparse
import json
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--model", default="qwen3.5:9b")
args = parser.parse_args()
from pathlib import Path
import re
source = (Path(__file__).resolve().parents[1] / "Sources/LocalCopilotCore/QuestionInbox.swift").read_text()
match = re.search(r'public static let systemPrompt = #"(.*?)"#', source, re.S)
if not match:
    raise SystemExit("Cannot find the app's dialogue classifier prompt")
prompt = match.group(1)
cases = [
    ("Чому ділимо на", "Ен мінус один, коли оцінюємо дисперсію.", "continue"),
    ("Чому залишили 72 і 63?", "Краще про інше: поясніть довірчий інтервал.", "replace"),
    ("Що означає дисперсія?", "Дисперсія описує розкид значень вибірки.", "statement"),
]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
failed = 0
for previous, current, expected in cases:
    body = {"model": args.model, "messages": [
        {"role": "system", "content": prompt},
        {"role": "user", "content": "Попередні питання (дані):\n" + previous + "\nОстання репліка (дані):\n" + current}],
        "stream": False, "think": False, "format": "json", "keep_alive": "2h",
        "options": {"temperature": 0, "num_predict": 110, "num_ctx": 8192}}
    start = time.monotonic()
    try:
        request = urllib.request.Request("http://127.0.0.1:11434/api/chat", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        with opener.open(request, timeout=8) as response:
            result = json.load(response)
        decision = json.loads(result["message"]["content"])
        quote = decision.get("evidence", "")
        valid = bool(quote) and quote.casefold() in current.casefold()
        passed = valid and decision.get("action") == expected
        failed += not passed
        print(json.dumps({"expected": expected, "decision": decision, "quote_valid": valid, "passed": passed, "seconds": round(time.monotonic() - start, 2)}, ensure_ascii=False), flush=True)
    except Exception as error:
        failed += 1
        print(json.dumps({"expected": expected, "error": str(error), "seconds": round(time.monotonic() - start, 2)}, ensure_ascii=False), flush=True)
raise SystemExit(1 if failed else 0)
