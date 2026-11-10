"""
Простий генератор навантаження для ЛР-7 (Beauty Studio).
Запускає неперервні HTTP-запити до бекенду для формування метрик у Prometheus та дашборді.
"""
import time
import urllib.request
import urllib.error
import sys

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"

print(f"=== Запуск генератора навантаження на {BASE_URL} ===")
print("Натисніть Ctrl+C для зупинки.\n")

endpoints = [
    "/api/bookings",
    "/health",
    "/version",
    "/api/slow?delay=0.1",
]

total = 0
success = 0
errors = 0
start_time = time.time()

try:
    while True:
        for ep in endpoints:
            url = f"{BASE_URL}{ep}"
            total += 1
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "LoadGenerator/1.0"})
                with urllib.request.urlopen(req, timeout=3) as resp:
                    if resp.status < 400:
                        success += 1
                    else:
                        errors += 1
            except urllib.error.HTTPError as e:
                errors += 1
            except Exception:
                errors += 1

            if total % 20 == 0:
                elapsed = time.time() - start_time
                rps = round(total / elapsed, 1)
                err_pct = round((errors / total) * 100, 1)
                print(f"[{time.strftime('%H:%M:%S')}] Запитів: {total} | Успішно: {success} | Помилок: {errors} ({err_pct}%) | RPS: {rps}")

            time.sleep(0.05)
except KeyboardInterrupt:
    print("\n=== Генератор зупинено ===")
    print(f"Всього: {total}, Успішно: {success}, Помилок: {errors}")
