# Лабораторна робота №7. Observability: метрики, логи, дашборди й відкат за метриками

Покрокова інструкція: що вже додано в проєкт, які команди виконати, що показати та які скріншоти зробити для звіту.

**Ідея роботи в одному реченні:** Prometheus збирає метрики, Loki зберігає логи, Grafana їх показує. Argo Rollouts під час canary-релізу сам питає Prometheus: «Яка частка успішних запитів?». Якщо вона менша за 95%, реліз сам відкочується.

---

## Два репозиторії

| Репозиторій | Шлях | Що в ньому міняємо |
| --- | --- | --- |
| Код застосунку | `C:\Users\Tetiana\PycharmProjects\beauty_studo` | `backend/app/main.py`, `backend/requirements.txt`, `backend/Dockerfile`, `backend/tests/test_main.py` |
| GitOps | `C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops` | `argocd-apps/*.yaml`, `charts/beauty-studio/...`, `scripts/load-generator.yaml` |

Argo CD стежить за гілкою **`main`** репозиторію GitOps, тому всі коміти в GitOps робимо в `main`.

## Вікна PowerShell

Відкрийте одразу 4 вікна:

| Вікно | Для чого | Команда |
| --- | --- | --- |
| 1 | git, kubectl | — |
| 2 | Argo CD UI → https://localhost:8080 | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |
| 3 | Grafana → http://localhost:3000 (логін `admin` / пароль `admin`) | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` |
| 4 | Prometheus → http://localhost:9090 | `kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090` |

Вікна 3 і 4 запускайте **після** завдання 1, бо до нього сервісів ще немає.

## Підготовка

```powershell
minikube start
kubectl get pods -n argocd           # Argo CD працює (ЛР-5)
kubectl get pods -n argo-rollouts    # контролер Rollouts працює (ЛР-6)
kubectl get pods -n beauty-studio    # застосунок працює

cd C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops
git switch main                      # незакомічені зміни перейдуть разом із вами
```

> Стек моніторингу «важкий». Якщо в завданні 1 поди висять у `Pending` через нестачу пам'яті, кластер треба створити з більшими ресурсами: `minikube delete`, потім `minikube start --memory=6144 --cpus=4`, і повторити bootstrap з ЛР-5.

---

## Завдання 1. Стек моніторингу через Argo CD

### 1.1. Що додано

У папці `argocd-apps/` з'явилися три нові Application. Кореневий застосунок `root` (App of Apps з ЛР-5) підхопить їх із Git автоматично.

| Файл | Helm-чарт | Що ставить |
| --- | --- | --- |
| `argocd-apps/kube-prometheus-stack.yaml` | `prometheus-community/kube-prometheus-stack` 65.8.1 | Prometheus, Alertmanager, Grafana, Prometheus Operator |
| `argocd-apps/loki.yaml` | `grafana/loki` 6.27.0 | Loki в режимі одного процесу (`deploymentMode: SingleBinary`) |
| `argocd-apps/alloy.yaml` | `grafana/alloy` 0.11.0 | Агент, який читає логи всіх подів і відправляє їх у Loki |

Найважливіші налаштування в `kube-prometheus-stack.yaml`:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false   # бачити ServiceMonitor з БУДЬ-ЯКОГО чарту (і з нашого)
    ruleSelectorNilUsesHelmValues: false             # те саме для PrometheusRule
grafana:
  adminPassword: admin
  sidecar:
    dashboards:
      label: grafana_dashboard                       # Grafana сама імпортує ConfigMap з цією міткою
      searchNamespace: ALL
  additionalDataSources:
    - name: Loki                                     # джерело логів у Grafana
      uid: loki
      type: loki
      url: http://loki.monitoring.svc:3100
```

У `loki.yaml` головне: `deploymentMode: SingleBinary`, `singleBinary.replicas: 1`, а `read/write/backend.replicas: 0`.

У `alloy.yaml` є конфігурація Alloy, яка робить три речі: знаходить усі поди (`discovery.kubernetes`), додає мітки `namespace`, `pod`, `container`, `app`, `rollouts_pod_template_hash` і пише логи в Loki (`loki.write`).

### 1.2. Закомітьте тільки `argocd-apps/`

Спершу ставимо лише моніторинг. Наш чарт використовує тип `ServiceMonitor`, а його CRD з'являється тільки після встановлення kube-prometheus-stack.

```powershell
cd C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops
git add argocd-apps/
git commit -m "feat(lab7): monitoring stack via Argo CD (kube-prometheus-stack, loki, alloy)"
git push origin main
```

### 1.3. Перевірте

Зачекайте 2–5 хвилин (або в Argo CD натисніть **root → Refresh**).

```powershell
kubectl get applications -n argocd
kubectl get pods -n monitoring
```

Очікувано всі поди в `Running`:

- `kube-prometheus-stack-operator-…`
- `prometheus-kube-prometheus-stack-prometheus-0`
- `alertmanager-kube-prometheus-stack-alertmanager-0`
- `kube-prometheus-stack-grafana-…`
- `kube-prometheus-stack-kube-state-metrics-…`
- `kube-prometheus-stack-prometheus-node-exporter-…`
- `loki-0`
- `alloy-…`

Запустіть port-forward у вікнах 3 і 4, відкрийте Grafana http://localhost:3000 (`admin`/`admin`) і перейдіть у **Connections → Data sources**. Там мають бути **Prometheus** і **Loki**.

📸 **Для звіту:**
- **1.1** — `kubectl get pods -n monitoring`, усі поди `Running`.
- **1.2** — Argo CD: застосунки `kube-prometheus-stack`, `loki`, `alloy` у стані **Synced / Healthy**.
- **1.3** — Grafana відкрита, сторінка Data sources з Prometheus і Loki.

---

## Завдання 2. Метрики застосунку

### 2a. Ендпоінт `/metrics` у коді (репозиторій `beauty_studo`)

**`backend/requirements.txt`** — додано рядок:

```
prometheus-client==0.21.0
```

**`backend/app/main.py`** — головне:

```python
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = "7.0.0"

# Лічильник запитів: мітки метод, маршрут, статус
REQUEST_COUNT = Counter("http_requests_total", "Total HTTP requests",
                        ["method", "endpoint", "status"])

# Гістограма тривалості запитів
REQUEST_DURATION = Histogram("http_request_duration_seconds", "HTTP request duration in seconds",
                             ["method", "endpoint"],
                             buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0])

def get_route_path(request):
    # /api/bookings/15 -> /api/bookings/{booking_id}  (мала кардинальність!)
    ...

@app.middleware("http")
async def monitor_and_log_requests(request, call_next):
    ...  # рахує REQUEST_COUNT і REQUEST_DURATION для кожного запиту

@app.get("/metrics")
def get_metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

**Чому мітки мають малу кардинальність:** `method` має кілька значень (GET, POST, DELETE), `status` — кілька кодів, а `endpoint` — це шаблон маршруту, а не реальний URL з id. Тому кількість часових рядів не росте з кожним новим записом. Не можна використовувати як мітку id користувача, повний URL з параметрами чи IP.

**`backend/tests/test_main.py`** — додано тести `test_metrics_endpoint` і `test_slow_endpoint`.

**`backend/Dockerfile`** — до команди запуску додано `--no-access-log`, щоб uvicorn не писав свої текстові логи поряд із нашими JSON-логами:

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
```

Перевірте, закомітьте, зберіть і запуште образ `7.0.0`:

```powershell
cd C:\Users\Tetiana\PycharmProjects\beauty_studo
cd backend; ..\.venv\Scripts\python -m pytest -q; cd ..      # має бути 5 passed

git switch -c lab7_observability
git add backend/
git commit -m "feat(backend): /metrics, JSON logs, FAIL_RATE, /api/slow (lab7)"
git push -u origin lab7_observability

docker build -t tetiana88/beauty-backend:7.0.0 ./backend
docker push tetiana88/beauty-backend:7.0.0
```

> Новий тег `7.0.0` (а не `5.0.0`) потрібен тому, що старий `5.0.0` міг бути зібраний раніше без `/metrics`. Через `pullPolicy: IfNotPresent` minikube узяв би закешовану стару версію.

### 2b. ServiceMonitor у чарті (репозиторій GitOps)

**`charts/beauty-studio/templates/backend-service.yaml`** — портові дано ім'я, бо ServiceMonitor шукає порт за ім'ям:

```yaml
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.backend.service.port }}
```

**`charts/beauty-studio/templates/servicemonitor.yaml`** (новий):

```yaml
{{- if .Values.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "beauty-studio.fullname" . }}-backend
spec:
  selector:
    matchLabels:
      app: backend          # мітка Service бекенду
  endpoints:
    - port: http            # ім'я порту в Service
      path: /metrics
      interval: 10s
{{- end }}
```

**`charts/beauty-studio/values-minikube.yaml`** — новий образ:

```yaml
backend:
  image:
    tag: "7.0.0"
  config:
    failRate: "0.0"
```

### 2.1. Запустіть генератор навантаження

Генератор потрібен уже зараз: canary-аналіз (завдання 6) входить у кожен реліз, і йому потрібні запити, щоб порахувати частку успішних.

Файл **`scripts/load-generator.yaml`** — це Pod з `curl`, який безкінечно шле запити на Service бекенду **всередині кластера**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: beauty-studio
spec:
  restartPolicy: Never
  containers:
    - name: load
      image: curlimages/curl:8.10.1
      command: ["sh", "-c"]
      args:
        - |
          while true; do
            curl -s -o /dev/null http://beauty-studio-backend:8000/api/bookings
            curl -s -o /dev/null http://beauty-studio-backend:8000/version
            sleep 0.05
          done
```

> Чому не `kubectl port-forward` + скрипт на ПК: `port-forward svc/...` під'єднується лише до **одного** пода. Тоді canary-под не отримав би трафіку і відкат не спрацював би. Запити зсередини кластера Service розподіляє між **усіма** подами.

```powershell
cd C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops
kubectl apply -f scripts/load-generator.yaml
kubectl get pod load-generator -n beauty-studio      # Running
```

### 2.2. Закомітьте весь чарт ЛР-7

Чарт комітимо одним комітом, бо всі шаблони пов'язані між собою. Пояснення до інших файлів — у завданнях 3, 4 і 6.

```powershell
git add charts/ scripts/
git commit -m "feat(lab7): ServiceMonitor, dashboard, AnalysisTemplate, PrometheusRule, backend 7.0.0"
git push origin main
```

Щоб Argo CD не чекав 3 хвилини, примусово оновіть застосунок:

```powershell
kubectl annotate application beauty-studio -n argocd argocd.argoproj.io/refresh=normal --overwrite
kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio --watch
```

Пройде звичайний canary-реліз `7.0.0` (25% → аналіз → 50% → 75% → 100%, приблизно 2–3 хв). Аналіз має бути **Successful**, бо помилок немає. Закрийте `--watch` через Ctrl+C.

### 2.3. Перевірте ціль і метрику в Prometheus

1. http://localhost:9090 → **Status → Targets** (у новій версії UI — **Status → Target health**).
2. Знайдіть `serviceMonitor/beauty-studio/beauty-studio-backend/0`. Там 4 ендпоінти (4 поди), стан **UP**.
3. Вкладка **Graph** (або **Query**), виконайте:

```promql
http_requests_total{namespace="beauty-studio"}
```

```promql
sum(rate(http_requests_total[1m])) by (endpoint)
```

Перевірити сам ендпоінт можна так:

```powershell
kubectl exec -n beauty-studio load-generator -- curl -s http://beauty-studio-backend:8000/metrics
```

📸 **Для звіту:**
- **2.1** — фрагмент виводу `/metrics` з рядками `http_requests_total{...}` і `http_request_duration_seconds_bucket{...}`.
- **2.2** — Prometheus Targets, ціль `beauty-studio-backend` у стані **UP**.
- **2.3** — результат запиту `http_requests_total` у Prometheus.

---

## Завдання 3. Логи в JSON і пошук у Loki

### 3.1. Що зроблено в коді

У тому ж middleware в `main.py` після кожного запиту в stdout виводиться **один рядок JSON**:

```python
log_entry = {
    "time": datetime.now(timezone.utc).isoformat(),
    "level": level,                    # INFO / WARNING / ERROR
    "message": f"{request.method} {route_path} completed",
    "method": request.method,
    "route": route_path,
    "status": status_code,
    "duration": duration,              # секунди
}
print(json.dumps(log_entry), flush=True)
```

Перевірка:

```powershell
kubectl logs -n beauty-studio -l app=backend --tail=5
```

Приклад рядка:

```json
{"time": "2026-11-10T12:00:01.123+00:00", "level": "INFO", "message": "GET /api/bookings completed", "method": "GET", "route": "/api/bookings", "status": 200, "duration": 0.0123}
```

### 3.2. Пошук у Grafana Explore

Grafana → **Explore** → джерело **Loki** → перемкніть редактор у режим **Code** і введіть запити.

Усі логи бекенду:

```logql
{namespace="beauty-studio", container="backend"}
```

Тільки запити з помилкою 5xx (`| json` розбирає JSON на поля):

```logql
{namespace="beauty-studio", container="backend"} | json | status >= 500
```

Зараз помилок немає, тож результат буде порожній, і це нормально. Щоб показати, що фільтр працює, зробіть кілька запитів, що повертають 4xx:

```logql
{namespace="beauty-studio", container="backend"} | json | status >= 400
```

```powershell
kubectl exec -n beauty-studio load-generator -- curl -s -X DELETE http://beauty-studio-backend:8000/api/bookings/999999
```

Справжні 5xx з'являться в завданні 6. Тоді зробіть скріншот 3.2.

📸 **Для звіту:**
- **3.1** — `kubectl logs …` з JSON-рядками.
- **3.2** — Grafana Explore із запитом `| json | status >= 500` (з результатами під час завдання 6).

---

## Завдання 4. Дашборд

### 4.1. Що зроблено

Файл **`charts/beauty-studio/templates/dashboard-configmap.yaml`** — це ConfigMap з міткою `grafana_dashboard: "1"`, а всередині JSON дашборду. Sidecar Grafana знаходить такі ConfigMap і сам імпортує дашборд. Доставка йде через Argo CD разом із чартом.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "beauty-studio.fullname" . }}-dashboard
  labels:
    grafana_dashboard: "1"
data:
  beauty-studio-dashboard.json: |-
    { ... "title": "Beauty Studio Observability", "panels": [ ... ] }
```

Панелі та їхні запити:

| Панель | Запит |
| --- | --- |
| Запити за секунду (RPS) | `sum(rate(http_requests_total{endpoint!~"/metrics\|/health"}[1m])) by (endpoint, method)` |
| Частка помилок 5xx (%) | `sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m])) * 100` |
| p95 затримки | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[1m])) by (le, endpoint))` |
| CPU подів | `sum(rate(container_cpu_usage_seconds_total{container="backend"}[1m])) by (pod)` |
| Пам'ять подів | `sum(container_memory_working_set_bytes{container="backend"}) by (pod)` |
| Логи з Loki | `{container="backend"}` |

> У JSON дашборду фігурні дужки легенди екрановані так: `{{`{{pod}}`}}`. Інакше Helm сприйняв би `{{pod}}` як свій шаблон.

### 4.2. Перевірка

```powershell
kubectl get configmap -n beauty-studio -l grafana_dashboard=1
```

Grafana → **Dashboards** → **Beauty Studio Observability**.

📸 **Для звіту:**
- **4.1** — дашборд, видно всі 6 панелей.
- **4.2** (за бажанням) — Argo CD: у дереві застосунку `beauty-studio` видно ConfigMap `beauty-studio-dashboard`.

---

## Завдання 5. Навантаження

### 5.1. Дашборд під навантаженням

Генератор уже працює (запустили в п. 2.1). Щоб показати момент «до/після», перезапустіть його:

```powershell
kubectl delete -f scripts/load-generator.yaml     # зупинити, почекати 1–2 хв (графіки падають)
kubectl apply  -f scripts/load-generator.yaml     # запустити знову
```

На дашборді (часовий діапазон **Last 15 minutes**) видно:
- **RPS** росте з ~0 до кількох десятків запитів/с;
- **CPU** подів зростає;
- **p95 затримки** зростає і тримається на новому рівні.

📸 **5.1** — дашборд, де видно зростання RPS, затримки та CPU після старту генератора.

### 5.2. Додаткова зміна: повільний ендпоінт

У `main.py` є ендпоінт `/api/slow?delay=…`, який навмисно «спить» задану кількість секунд:

```python
@app.get("/api/slow")
def slow_endpoint(delay: float = 0.5):
    time.sleep(delay)
    return {"status": "delayed", "delay_seconds": delay}
```

Протягом ~1 хвилини шлемо на нього запити з затримкою 1 с:

```powershell
kubectl exec -n beauty-studio load-generator -- sh -c 'for i in $(seq 1 60); do curl -s -o /dev/null http://beauty-studio-backend:8000/api/slow?delay=1; done'
```

На панелі **p95 Latency** з'являється лінія `p95 /api/slow` на рівні ~1 с, а на RPS — новий маршрут `/api/slow`.

📸 **5.2** — панель p95 Latency зі стрибком для `/api/slow`.

---

## Завдання 6. Автоматичний відкат за метриками

### 6a. AnalysisTemplate і крок `analysis` у canary

**`charts/beauty-studio/templates/analysistemplate.yaml`:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: {{ include "beauty-studio.fullname" . }}-success-rate     # = beauty-studio-success-rate
spec:
  metrics:
    - name: success-rate
      interval: 10s          # питати Prometheus кожні 10 с
      count: 3               # 3 рази
      failureLimit: 0        # перший поганий вимір = аналіз Failed
      successCondition: isNaN(result[0]) || result[0] >= 0.95
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc:9090
          query: |
            sum(rate(http_requests_total{status!~"5..", endpoint!~"/metrics|/health"}[1m]))
            /
            sum(rate(http_requests_total{endpoint!~"/metrics|/health"}[1m]))
```

- Запит повертає **частку успішних запитів**: запити без 5xx, поділені на всі запити.
- `isNaN(...)` потрібен на випадок, коли трафіку немає взагалі (0/0). Тоді аналіз не вважається проваленим.

**`charts/beauty-studio/values.yaml`** — до кроків canary з ЛР-6 додано крок `analysis`:

```yaml
backend:
  rollout:
    canary:
      steps:
        - setWeight: 25
        - pause: { duration: 30s }   # canary-под 30 с отримує трафік
        - analysis:                  # ЛР-7: перевірка в Prometheus
            templates:
              - templateName: beauty-studio-success-rate
        - setWeight: 50
        - pause: { duration: 30s }
        - setWeight: 75
        - pause: { duration: 30s }
```

Крок `analysis` — **блокуючий**: Rollout не піде на 50%, доки аналіз не завершиться успішно. Якщо аналіз Failed, Rollout сам робить **abort**: canary-под прибирається, і весь трафік повертається на stable.

### 6b. «Погана» поведінка: `FAIL_RATE`

У `main.py` (на початку middleware):

```python
FAIL_RATE = float(os.getenv("FAIL_RATE", "0.0"))
...
if FAIL_RATE > 0.0 and route_path not in ["/health", "/metrics"] and random.random() < FAIL_RATE:
    # рахуємо метрику зі status=500, пишемо JSON-лог з level=ERROR
    return JSONResponse(status_code=500, content={"detail": "Simulated error (FAIL_RATE)"})
```

`/health` і `/metrics` не ламаються навмисно: інакше Kubernetes вважав би под неготовим, а Prometheus не зміг би його скрапити.

У **`backend-rollout.yaml`** змінна прокидається в контейнер із values:

```yaml
          env:
            - name: FAIL_RATE
              value: {{ .Values.backend.config.failRate | default "0.0" | quote }}
```

### 6c. Поганий реліз під навантаженням

**1) Переконайтеся, що генератор працює:**

```powershell
kubectl get pod load-generator -n beauty-studio
```

**2) Відкрийте все для спостереження:**
- Grafana: дашборд **Beauty Studio Observability**, діапазон **Last 15 minutes**;
- вікно 1:

```powershell
kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio --watch
```

**3) Випустіть погану версію через Git.** В іншому вікні PowerShell у файлі `charts/beauty-studio/values-minikube.yaml` змініть один рядок:

```yaml
  config:
    failRate: "0.5"         # 50% запитів на нових подах отримують 500
```

```powershell
cd C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops
git add charts/beauty-studio/values-minikube.yaml
git commit -m "release: backend 7.0.0 with FAIL_RATE=0.5 (bad release)"
git push origin main
kubectl annotate application beauty-studio -n argocd argocd.argoproj.io/refresh=normal --overwrite
```

Зміна змінної оточення змінює шаблон пода, тому Argo Rollouts запускає новий canary-реліз.

**4) Що відбувається (приблизно 1–1,5 хв):**

1. `setWeight: 25` — з'являється 1 новий под (revision з новим хешем). Він отримує ~25% трафіку, половина з них — 500.
2. `pause 30s` — помилки накопичуються в Prometheus.
3. `analysis` — створюється **AnalysisRun**. Частка успішних ≈ 88–94% (< 95%) → вимір **Failed**.
4. AnalysisRun **Failed** → Rollout **сам робить abort**: canary-под видаляється, усі 4 поди знову stable, статус Rollout — **Degraded** (`RolloutAborted`).

Перевірка AnalysisRun:

```powershell
kubectl get analysisrun -n beauty-studio
kubectl describe analysisrun -n beauty-studio <ім'я-останнього-AnalysisRun>
```

У `describe` видно `Phase: Failed` і виміряне значення (`Value: [0.9...]`).

**5) Сплеск помилок на дашборді:** на панелі **5xx Error Rate (%)** видно пік, який після abort спадає до 0.

**6) Логи помилок лише з нової версії (Loki).** Grafana → Explore → Loki:

```logql
{namespace="beauty-studio", container="backend"} | json | status >= 500
```

Розгорніть будь-який рядок і подивіться мітку `pod`: це той самий canary-под. Найнаочніше — порахувати помилки по подах:

```logql
sum by (pod, rollouts_pod_template_hash) (count_over_time({namespace="beauty-studio", container="backend"} | json | status >= 500 [10m]))
```

У результаті буде **лише один под** з хешем нової ревізії. Хеш можна звірити з виводом `kubectl argo rollouts get rollout …`: там видно хеш кожної revision.

**7) Завершіть відкат через Git.** Кластер уже повернувся на stable, але в Git досі записана погана версія. Повертаємо Git у відповідність:

```powershell
git revert HEAD --no-edit          # failRate знову "0.0"
git push origin main
kubectl annotate application beauty-studio -n argocd argocd.argoproj.io/refresh=normal --overwrite
kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio
```

Тепер шаблон у Git збігається зі stable, тож Rollout стає **Healthy** без нового релізу. В Argo CD застосунок `beauty-studio` знову **Synced / Healthy**.

📸 **Для звіту:**
- **6.1** — `kubectl argo rollouts get rollout …` під час abort: статус **Degraded**, AnalysisRun ✖ **Failed**.
- **6.2** — `kubectl get analysisrun` / `describe` з `Phase: Failed` і значенням < 0.95.
- **6.3** — дашборд: сплеск на 5xx Error Rate (і рядки ERROR на панелі логів).
- **6.4** — Loki: помилки 5xx тільки з одного (canary) пода.
- **6.5** — Rollout **Healthy** після `git revert`.
- **3.2** — скріншот із завдання 3 (тепер із результатами).

### 6d*. (за бажанням) Алерт PrometheusRule

**`charts/beauty-studio/templates/prometheusrule.yaml`:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "beauty-studio.fullname" . }}-alerts
spec:
  groups:
    - name: beauty-studio-alerts
      rules:
        - alert: HighErrorRate5xx
          expr: |
            ( sum(rate(http_requests_total{status=~"5.."}[1m]))
              / sum(rate(http_requests_total[1m])) ) * 100 > 5
          for: 15s
          labels:
            severity: critical
```

Під час кроку 6c відкрийте http://localhost:9090/alerts. `HighErrorRate5xx` спершу буде **Pending**, потім **Firing**. Вікно `[1m]` тримає помилки ще ~1 хв після abort, тож алерт встигає спрацювати. Якщо не встигли зробити скріншот, повторіть 6c.

📸 **6.6** — алерт `HighErrorRate5xx` у стані **Firing**.

### Після лабораторної

```powershell
kubectl delete -f scripts/load-generator.yaml
```

---

## Додаток. Шпаргалка для захисту

Сценарій лайв-демонстрації:

1. `kubectl get pods -n monitoring` і Argo CD з `kube-prometheus-stack`/`loki`/`alloy`.
2. Prometheus → Targets (ціль UP) і запит `http_requests_total`.
3. `kubectl apply -f scripts/load-generator.yaml` і дашборд під навантаженням.
4. Loki: `{container="backend"} | json | status >= 500`.
5. Поганий реліз (`failRate: "0.5"` → push) → AnalysisRun Failed → abort → `git revert`.

### PromQL

| Що просять | Запит |
| --- | --- |
| RPS усього | `sum(rate(http_requests_total[1m]))` |
| RPS по маршрутах | `sum by (endpoint) (rate(http_requests_total[1m]))` |
| Тільки 2xx | `sum(rate(http_requests_total{status=~"2.."}[1m]))` |
| Частка 5xx, % | `sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m])) * 100` |
| Частка успішних (як в аналізі) | `sum(rate(http_requests_total{status!~"5.."}[1m])) / sum(rate(http_requests_total[1m]))` |
| Середня затримка | `sum(rate(http_request_duration_seconds_sum[1m])) / sum(rate(http_request_duration_seconds_count[1m]))` |
| p95 / p99 | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[1m])))` |
| RPS по подах | `sum by (pod) (rate(http_requests_total[1m]))` |
| CPU подів | `sum by (pod) (rate(container_cpu_usage_seconds_total{container="backend"}[1m]))` |
| Пам'ять подів | `sum by (pod) (container_memory_working_set_bytes{container="backend"})` |
| Чи живі цілі | `up{namespace="beauty-studio"}` |

### LogQL

| Що просять | Запит |
| --- | --- |
| Усі логи бекенду | `{namespace="beauty-studio", container="backend"}` |
| Текстовий пошук | `{container="backend"} \|= "bookings"` |
| 5xx | `{container="backend"} \| json \| status >= 500` |
| Рівень ERROR | `{container="backend"} \| json \| level = "ERROR"` |
| Конкретний маршрут | `{container="backend"} \| json \| route = "/api/bookings"` |
| Повільні запити > 0.5 с | `{container="backend"} \| json \| duration > 0.5` |
| К-сть помилок по подах | `sum by (pod) (count_over_time({container="backend"} \| json \| status >= 500 [5m]))` |
| Логи за секунду | `sum(rate({container="backend"}[1m]))` |

### Короткі відповіді на можливі питання

- **Що таке кардинальність?** Кількість унікальних комбінацій міток, тобто кількість часових рядів. Мітка з id або повним URL «вибухає» на мільйони рядів і кладе Prometheus.
- **Counter і Histogram?** Counter тільки росте, з нього рахують `rate`. Histogram рахує кількість спостережень у «кошиках» (`_bucket`), з нього рахують перцентилі через `histogram_quantile`.
- **Як Prometheus знайшов застосунок?** Prometheus Operator читає ServiceMonitor, знаходить Service з `app: backend`, бере його ендпоінти (усі поди) і скрапить `/metrics` на порту `http`.
- **Як логи потрапляють у Loki?** Застосунок пише JSON у stdout → Kubernetes зберігає логи контейнера → Alloy читає їх через API, додає мітки (namespace, pod, container) і шле в Loki.
- **Як дашборд потрапив у Grafana?** ConfigMap з міткою `grafana_dashboard: "1"` у чарті → Argo CD створив його → sidecar Grafana імпортував.
- **Чому відкат автоматичний?** Крок `analysis` створює AnalysisRun. Той питає Prometheus, порівнює з порогом 0.95 і при провалі переводить Rollout в abort без участі людини.
- **Навіщо потім `git revert`?** Abort повертає кластер на stable, але в Git записана погана версія. Щоб Git знову був джерелом правди (GitOps), відкат треба зафіксувати в Git.
