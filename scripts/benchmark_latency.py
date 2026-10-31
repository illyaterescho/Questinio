#!/usr/bin/env python3
"""Measure a local Ollama chat's first visible token and completion time."""

import json
import sys
import time
import urllib.request


def chat(model, messages, context_tokens=8192):
    body = {
        "model": model,
        "messages": messages,
        "stream": True,
        "keep_alive": "10m",
        "think": False,
        "options": {"temperature": 0.2, "num_predict": -1, "num_ctx": context_tokens},
    }
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    start = time.monotonic()
    first = None
    output = []
    with urllib.request.urlopen(request, timeout=90) as response:
        for line in response:
            packet = json.loads(line)
            content = packet.get("message", {}).get("content", "")
            if content and first is None:
                first = time.monotonic() - start
            output.append(content)
            if packet.get("done"):
                break
    return round(first or 0, 3), round(time.monotonic() - start, 3), "".join(output)


SYSTEM = "Відповідай українською як розробник колезі. Одразу по суті, стисло й точно. Не вигадуй код."
CODE = "Файл: lab-01/src/store.ts\n" + "\n".join(
    [
        "12: export function saveFavorites(ids: number[]): void {",
        "13:   localStorage.setItem('favoriteIds', JSON.stringify(ids));",
        "14: }",
        "16: export function loadFavorites(): number[] {",
        "17:   const raw = localStorage.getItem('favoriteIds');",
        "18:   return raw ? JSON.parse(raw) : [];",
        "19: }",
    ]
)
CASES = {
    "general": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": "Чим відрізняються Promise, async/await і callback?"},
    ],
    "code": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": CODE + "\n\nЩо саме зберігається у localStorage і під яким ключем?"},
    ],
}


for name in sys.argv[1:] or ["qwen3.5:9b", "qwen3.5:4b"]:
    for case, messages in CASES.items():
        first, total, answer = chat(name, messages)
        print(json.dumps({"model": name, "case": case, "first": first, "total": total, "answer": answer}, ensure_ascii=False), flush=True)
