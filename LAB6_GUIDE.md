# Лабораторна робота №6: Progressive delivery з Argo Rollouts
## Покрокова інструкція (Beauty Studio, стратегія **canary**)

---

## Ідея в двох реченнях

* **Раніше (ЛР-5):** змінили тег у Git, і Deployment одразу замінив усі поди на нову версію.
* **Тепер (ЛР-6):** замість Deployment буде **Rollout**. Він міняє поди **частинами** (25% → 50% → 75% → 100%) і може **зупинитися** посередині. На паузі ми перевіряємо нову версію, а потім кажемо `promote` (їдемо далі) або `abort` (повертаємо стару версію).

### Чому canary, а не blue-green (сказати на захисті)

1. Бекенд Beauty Studio **без стану** (stateless): усі поди працюють з однією БД PostgreSQL, тому стара й нова версії можуть працювати **одночасно**.
2. Canary пускає на нову версію **тільки частину запитів** (1 под з 4 = 25%). Якщо з нею щось не так, постраждає мало користувачів.
3. Blue-green тримає **два повні комплекти** подів (4 + 4). На minikube це зайві ресурси.
4. Canary не потребує додаткових Service (`activeService`, `previewService`), достатньо наявного `beauty-studio-backend`.

### Що змінюється в репозиторії

| Файл | Що робимо | Пункт ЛР |
| --- | --- | --- |
| `argocd-apps/argo-rollouts.yaml` | **новий**: Application, який ставить контролер Argo Rollouts з Helm-чарту | 1a |
| `charts/beauty-studio/templates/backend-rollout.yaml` | **новий**: шаблон Rollout | 2 |
| `charts/beauty-studio/templates/backend-deployment.yaml` | обгорнути в `if`: Deployment створюється, лише коли Rollout вимкнено | 2 |
| `charts/beauty-studio/values.yaml` | додати блок `backend.rollout` з кроками canary | 2, 3 |
| `charts/beauty-studio/values-minikube.yaml` | `replicaCount: 4`, `rollout.enabled: true`, далі тут міняємо тег | 2, 4, 5 |

### Позначення

* `PS>` це PowerShell, сам `PS>` не вводьте.
* 📸 означає **зробіть скріншот**.
* Усі команди виконуються з кореня репозиторію `beauty-studio-gitops`, якщо не сказано інше.
* Знадобляться **4 вікна PowerShell**:
  * **Вікно 1:** основне (git, kubectl).
  * **Вікно 2:** `kubectl port-forward` до Argo CD (як у ЛР-5, не закривати).
  * **Вікно 3:** `kubectl argo rollouts get rollout ... --watch` (живий стан релізу).
  * **Вікно 4:** цикл запитів усередині кластера (видно, яка версія відповідає).

> Якщо викладач видав код для ЛР-6, додавайте його в кінець кожного commit-повідомлення.

---

## Крок 0. Підготовка

```powershell
PS> minikube start
PS> kubectl get pods -n argocd
PS> kubectl get pods -n beauty-studio
```

Вікно 2 (Argo CD UI, як у ЛР-5):

```powershell
PS> kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Відкрийте https://localhost:8080 і увійдіть. Застосунок `beauty-studio` має бути **Synced / Healthy** з версією `2.0.0`.

---

## Крок 1. Образи нових версій (3.0.0, 4.0.0, 5.0.0)

Щоб у відповідях було видно, яка версія відповіла, кожен образ має свій `APP_VERSION`.
Версії: `3.0.0` для релізу з promote, `4.0.0` для релізу з abort, `5.0.0` запасна для захисту.

У репозиторії застосунку `PycharmProjects/beauty_studo`:

1. Відкрийте `backend/app/main.py`, змініть рядок на `APP_VERSION = "3.0.0"`, збережіть.
2. Зберіть і опублікуйте образ:

```powershell
PS> cd C:\Users\Tetiana\PycharmProjects\beauty_studo
PS> docker login
PS> $DOCKER_USER = "tetiana88"
PS> docker build -t "$DOCKER_USER/beauty-backend:3.0.0" ./backend
PS> docker push "$DOCKER_USER/beauty-backend:3.0.0"
```

3. Повторіть пункти 1–2 для `4.0.0` і `5.0.0` (кожного разу міняйте і `APP_VERSION`, і тег у команді).
4. (За бажанням) закомітьте `main.py` у репозиторій застосунку.

📸 **Скріншот 1:** сторінка `tetiana88/beauty-backend` на Docker Hub, вкладка Tags: видно `3.0.0`, `4.0.0`, `5.0.0`.

Поверніться в `beauty-studio-gitops`:

```powershell
PS> cd C:\Users\Tetiana\PycharmProjects\beauty-studio-gitops
```

---

## Крок 2. Контролер Argo Rollouts через Argo CD (п. 1a)

### 2.1. Дізнайтеся актуальну версію Helm-чарту

```powershell
PS> helm repo add argo https://argoproj.github.io/argo-helm
PS> helm repo update
PS> helm search repo argo/argo-rollouts
```

Запам'ятайте число з колонки **CHART VERSION** (наприклад `2.40.5`).

### 2.2. Створіть файл `argocd-apps/argo-rollouts.yaml`

Замініть `2.40.5` на версію з попереднього кроку.

```yaml
# Application для контролера Argo Rollouts (ЛР-6, п. 1a).
# Контролер ставиться з Git так само, як і застосунок: його створює root (App of Apps).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-rollouts
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://argoproj.github.io/argo-helm   # Helm-репозиторій, а не Git
    chart: argo-rollouts
    targetRevision: 2.40.5                           # версія чарту з helm search
    helm:
      releaseName: argo-rollouts
  destination:
    server: https://kubernetes.default.svc
    namespace: argo-rollouts
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true   # CRD Rollout великий, звичайний apply може не влізти в ліміт анотації
```

### 2.3. Commit і push

```powershell
PS> git add argocd-apps/argo-rollouts.yaml
PS> git commit -m "feat: argo-rollouts controller via Argo CD"
PS> git push
```

`root` побачить новий файл у `argocd-apps/` і сам створить Application `argo-rollouts`. Щоб не чекати 3 хв:

```powershell
PS> argocd app sync root
PS> argocd app list
PS> kubectl get pods -n argo-rollouts
PS> kubectl get crd rollouts.argoproj.io
```

> **Важливо:** не переходьте до кроку 4, поки `argo-rollouts` не стане **Synced / Healthy**. Інакше Argo CD не знатиме, що таке `kind: Rollout`, і синхронізація `beauty-studio` впаде.

📸 **Скріншот 2:** Argo CD UI, на головній сторінці три застосунки: `root`, `beauty-studio`, `argo-rollouts`, усі Healthy.
📸 **Скріншот 3:** `kubectl get pods -n argo-rollouts`, под контролера `Running`.

---

## Крок 3. Плагін `kubectl argo rollouts` (п. 1b)

Папка `$HOME\bin` уже є в PATH з ЛР-5 (там лежить `argocd.exe`).

```powershell
PS> Invoke-WebRequest -Uri "https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-windows-amd64" -OutFile "$HOME\bin\kubectl-argo-rollouts.exe"
PS> kubectl argo rollouts version
```

Назва файлу саме `kubectl-argo-rollouts.exe`: тоді `kubectl` сам знаходить плагін.

📸 **Скріншот 4:** вивід `kubectl argo rollouts version`.

---

## Крок 4. Rollout у Helm-чарті (пп. 2, 3)

### 4.1. `values.yaml`: опис стратегії

У `charts/beauty-studio/values.yaml` у блоці `backend:` **після** `config:` додайте (відступ 2 пробіли, як у `config`):

```yaml
  # ЛР-6: Argo Rollouts замість Deployment.
  rollout:
    enabled: false          # true -> створюється Rollout, Deployment не створюється
    canary:
      # Без service mesh вага задається кількістю подів: при 4 репліках 25% = 1 под нової версії.
      steps:
        - setWeight: 25
        - pause: {}               # ручна пауза: стоїть, поки не зроблять promote (або abort)
        - setWeight: 50
        - pause: {duration: 30s}  # пауза з таймером: через 30 с іде далі сама
        - setWeight: 75
        - pause: {duration: 30s}
        # після останнього кроку автоматично 100%
```

Це виконує вимоги п. 3a: три кроки `setWeight` (25, 50, 75), одна ручна пауза `pause: {}`, дві паузи з таймером.

### 4.2. `values-minikube.yaml`: увімкнути Rollout і 4 репліки

У `charts/beauty-studio/values-minikube.yaml` змініть блок `backend:` так (тег поки лишається `2.0.0`):

```yaml
backend:
  replicaCount: 4           # ЛР-6: не менше 4, щоб було видно співвідношення версій
  rollout:
    enabled: true           # ЛР-6: Rollout замість Deployment
  image:
    repository: docker.io/tetiana88/beauty-backend
    tag: "2.0.0"
    pullPolicy: IfNotPresent
  config:
    appEnv: "minikube"
    logLevel: "debug"
```

### 4.3. Вимкнути Deployment, коли увімкнено Rollout

У `charts/beauty-studio/templates/backend-deployment.yaml`:

* **одразу після** першого рядка `# DVO-L4-3C8B52` додайте рядок:

```yaml
{{- if not .Values.backend.rollout.enabled }}
```

* **у самий кінець файлу** (після блоку `readinessProbe`) додайте рядок:

```yaml
{{- end }}
```

Так само зроблено в `ingress.yaml` з `ingress.enabled`.

### 4.4. Новий шаблон `templates/backend-rollout.yaml`

Створіть `charts/beauty-studio/templates/backend-rollout.yaml`. Блок `template:` скопійовано з Deployment без змін, нове тільки `apiVersion`, `kind` і `strategy`.

```yaml
# DVO-L4-3C8B52
# ЛР-6: Rollout (Argo Rollouts) замість Deployment. Вмикається backend.rollout.enabled.
{{- if .Values.backend.rollout.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: {{ include "beauty-studio.fullname" . }}-backend
  labels:
    {{- include "beauty-studio.labels" . | nindent 4 }}
    app: backend
  annotations:
    {{- include "beauty-studio.annotations" . | nindent 4 }}
spec:
  replicas: {{ .Values.backend.replicaCount }}
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      {{- include "beauty-studio.backend.selectorLabels" . | nindent 6 }}
  # Кроки релізу беруться з values (backend.rollout.canary.steps).
  # Сервіс beauty-studio-backend бачить і старі, і нові поди, тому трафік ділиться пропорційно кількості подів.
  strategy:
    canary:
      steps:
        {{- toYaml .Values.backend.rollout.canary.steps | nindent 8 }}
  template:
    metadata:
      labels:
        {{- include "beauty-studio.labels" . | nindent 8 }}
        {{- include "beauty-studio.backend.selectorLabels" . | nindent 8 }}
      annotations:
        {{- include "beauty-studio.annotations" . | nindent 8 }}
    spec:
      automountServiceAccountToken: false
      containers:
        - name: backend
          image: "{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}"
          imagePullPolicy: {{ .Values.backend.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.backend.service.port }}
          envFrom:
            - configMapRef:
                name: {{ include "beauty-studio.fullname" . }}-config
            - secretRef:
                name: {{ include "beauty-studio.secretName" . }}
          resources:
            {{- toYaml .Values.backend.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: /health
              port: {{ .Values.backend.service.port }}
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: {{ .Values.backend.service.port }}
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
{{- end }}
```

`backend-service.yaml` **не чіпаємо**: він вибирає поди за мітками `app: backend` тощо, а поди Rollout мають ті самі мітки.

### 4.5. (За бажанням) підніміть версію чарту

У `Chart.yaml`: `version: 0.2.0` → `version: 0.3.0`.

### 4.6. Перевірка локально перед push

```powershell
PS> helm lint charts/beauty-studio -f charts/beauty-studio/values-minikube.yaml
PS> helm template beauty-studio charts/beauty-studio -f charts/beauty-studio/values-minikube.yaml | Select-String "^kind:"
```

У списку має бути `kind: Rollout` і **не** має бути `Deployment` для бекенду (лишаються Deployment `frontend` і `db`).

### 4.7. Commit і push

```powershell
PS> git add charts/
PS> git commit -m "feat: backend Rollout with canary strategy, 4 replicas"
PS> git push
PS> argocd app sync beauty-studio
```

Що станеться: Argo CD видалить старий Deployment бекенду (бо `prune: true`) і створить Rollout. **Перший** запуск Rollout іде одразу на 100% без кроків: кроки працюють лише при **оновленні**.

```powershell
PS> kubectl get rollout -n beauty-studio
PS> kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio
```

Має бути `Status: ✔ Healthy`, 4 поди з образом `2.0.0`.

📸 **Скріншот 5:** вивід `kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio` (Healthy, 4 поди).
📸 **Скріншот 6:** Argo CD UI → `beauty-studio`: у дереві ресурсів замість Deployment бекенду видно **Rollout** `beauty-studio-backend`.

---

## Крок 5. Реліз 3.0.0 через Git з promote (п. 4a)

### 5.1. Відкрийте вікна спостереження

**Вікно 3** (живий стан Rollout, оновлюється сам):

```powershell
PS> kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio --watch
```

**Вікно 4** (цикл запитів **усередині кластера**: тимчасовий под з curl раз на пів секунди питає `/version`):

```powershell
PS> kubectl run curl-loop -n beauty-studio --rm -it --image=curlimages/curl --restart=Never -- sh -c 'while true; do curl -s http://beauty-studio-backend:8000/version; echo; sleep 0.5; done'
```

Зараз там тільки `{"version":"2.0.0"}`. Зупинити цикл: `Ctrl+C`.

**(За бажанням) дашборд Rollouts** в ще одному вікні:

```powershell
PS> kubectl argo rollouts dashboard
```

і відкрийте http://localhost:3100.

### 5.2. Змініть тег у Git (Вікно 1)

У `charts/beauty-studio/values-minikube.yaml`: `tag: "2.0.0"` → `tag: "3.0.0"`.

```powershell
PS> git add charts/beauty-studio/values-minikube.yaml
PS> git commit -m "release: backend 3.0.0 (canary)"
PS> git push
PS> argocd app sync beauty-studio
```

### 5.3. Проміжний стан (ручна пауза на 25%)

Rollout зробить `setWeight: 25` і зупиниться на `pause: {}`.

* **Вікно 3:** `Status: ॥ Paused`, `Step: 1/6`, `SetWeight: 25`, `ActualWeight: 25`; 4 поди `stable` (2.0.0) і 1 под `canary` (3.0.0).
* **Вікно 4:** вперемішку `{"version":"2.0.0"}` і зрідка `{"version":"3.0.0"}` (приблизно кожна 4–5 відповідь).
* **Argo CD UI:** `beauty-studio` **Synced**, здоров'я **Suspended** (жовта іконка паузи): так Argo CD показує Rollout на паузі.

```powershell
PS> kubectl get pods -n beauty-studio -L rollouts-pod-template-hash
```

📸 **Скріншот 7:** Вікно 3 на паузі (Paused, SetWeight 25, видно stable і canary поди).
📸 **Скріншот 8:** Вікно 4, у відповідях є і `2.0.0`, і `3.0.0`.
📸 **Скріншот 9:** Argo CD UI, `beauty-studio` Synced / Suspended, видно дерево з двома ReplicaSet під Rollout.
📸 (за бажанням) **Скріншот 10:** дашборд Rollouts http://localhost:3100.

### 5.4. Promote (Вікно 1)

```powershell
PS> kubectl argo rollouts promote beauty-studio-backend -n beauty-studio
```

Далі Rollout іде сам: 50% → пауза 30 с → 75% → пауза 30 с → 100%. У Вікні 4 частка `3.0.0` росте, а в кінці лишається тільки `3.0.0`. У Вікні 3 `Status: ✔ Healthy`, усі 4 поди `stable` з 3.0.0. Argo CD показує **Synced / Healthy**.

📸 **Скріншот 11:** Вікно 3 на кроці 50% або 75% (видно таймерну паузу).
📸 **Скріншот 12:** фінал: Вікно 3 Healthy (3.0.0), Вікно 4 тільки `3.0.0`, Argo CD Synced / Healthy.

---

## Крок 6. Реліз 4.0.0 і скасування abort (п. 5)

### 6.1. Запустіть реліз (Вікно 1)

`values-minikube.yaml`: `tag: "3.0.0"` → `tag: "4.0.0"`.

```powershell
PS> git add charts/beauty-studio/values-minikube.yaml
PS> git commit -m "release: backend 4.0.0 (canary, will be aborted)"
PS> git push
PS> argocd app sync beauty-studio
```

Дочекайтеся паузи на 25% (Вікно 3: `Paused`, Вікно 4: є `4.0.0`).

### 6.2. Abort

```powershell
PS> kubectl argo rollouts abort beauty-studio-backend -n beauty-studio
```

Що відбувається:

* canary-под 4.0.0 видаляється, усі 4 поди знову **stable 3.0.0**;
* Вікно 4: тільки `{"version":"3.0.0"}`;
* Вікно 3: `Status: ✖ Degraded`, `Message: RolloutAborted: Rollout aborted update to revision ...`;
* Argo CD: **Synced / Degraded**.

📸 **Скріншот 13:** Вікно 3 після abort (Degraded, RolloutAborted, 4 поди 3.0.0).
📸 **Скріншот 14:** Вікно 4, знову тільки `3.0.0`.
📸 **Скріншот 15:** Argo CD UI, `beauty-studio` **Synced / Degraded**.

### 6.3. Чому саме Synced / Degraded (пояснити на захисті)

* **Synced:** Argo CD порівнює **Git** із **маніфестом** у кластері. У Git тег `4.0.0`, і в `spec` Rollout теж `4.0.0`. Вони однакові, тому Synced. `abort` не змінює `spec`, він змінює тільки `status` Rollout.
* **Degraded:** здоров'я Argo CD бере з `status` Rollout. Контролер каже: «бажану версію 4.0.0 скасовано, працює стара». Бажаний стан не досягнуто, тому Degraded.
* Тобто **Git каже «4.0.0», а реально працює 3.0.0**. Таку розбіжність треба виправити в Git, а не руками в кластері (інакше `selfHeal` все одно поверне значення з Git).

### 6.4. Завершити відкат через Git

```powershell
PS> git revert --no-edit HEAD
PS> git push
PS> argocd app sync beauty-studio
```

`git revert` створює новий коміт, який повертає `tag: "3.0.0"`. Тепер `spec` Rollout збігається зі stable-версією, тому контролер не робить жодних кроків і одразу ставить **Healthy**. Argo CD: **Synced / Healthy**.

```powershell
PS> git log --oneline -5
PS> kubectl argo rollouts get rollout beauty-studio-backend -n beauty-studio
```

📸 **Скріншот 16:** `git log --oneline -5`: видно коміт release 4.0.0 і `Revert "release: backend 4.0.0 ..."`.
📸 **Скріншот 17:** Argo CD Synced / Healthy, Rollout Healthy на 3.0.0.

---

## Крок 7. Підготовка до захисту (п. 6)

Перед захистом стан має бути: **3.0.0, Synced / Healthy**. Відкрийте заздалегідь Вікна 2, 3, 4 і Argo CD UI.

План лайв-демонстрації (≈5 хв):

| # | Що робите | Що показуєте |
| --- | --- | --- |
| 1 | Тег `3.0.0` → `4.0.0`, commit, push, `argocd app sync beauty-studio` | реліз комітом |
| 2 | Чекаєте паузу 25% | Вікно 3 Paused, Вікно 4 мікс `3.0.0`/`4.0.0`, Argo CD Suspended |
| 3 | `kubectl argo rollouts promote beauty-studio-backend -n beauty-studio` | кроки 50% → 75% → 100%, Healthy на `4.0.0` |
| 4 | Тег `4.0.0` → `5.0.0`, commit, push, sync | новий реліз, пауза 25% |
| 5 | `kubectl argo rollouts abort beauty-studio-backend -n beauty-studio` | усі поди знову `4.0.0`, Argo CD **Synced / Degraded**, пояснення |
| 6 | `git revert --no-edit HEAD`, push, sync | Argo CD **Synced / Healthy** на `4.0.0` |

Типові питання:

* **Чому canary?** Див. початок файлу.
* **Як ділиться трафік?** Без service mesh/ingress-контролера вагу дає кількість подів: 1 з 4 = 25%. Сервіс шле запити на всі поди з міткою `app: backend`.
* **Чим `pause: {}` відрізняється від `pause: {duration: 30s}`?** Перша чекає людину (`promote`), друга йде далі сама через 30 с.
* **Чому перше створення Rollout пройшло без кроків?** Кроки потрібні лише для переходу між версіями. Коли старої версії немає, ділити трафік немає з ким.
* **Чому не `kubectl argo rollouts undo`?** Це змінило б `spec` у кластері в обхід Git, і Argo CD з `selfHeal` повернув би його назад. У GitOps відкат робиться комітом.

---

## Якщо щось пішло не так

| Проблема | Що робити |
| --- | --- |
| `beauty-studio` у стані Sync failed: `no matches for kind "Rollout"` | Контролер ще не встановився. Дочекайтеся `argo-rollouts` Healthy (крок 2), потім `argocd app sync beauty-studio` |
| `argo-rollouts` Sync failed через CRD (`metadata.annotations: Too long`) | Перевірте, що в Application є `ServerSideApply=true` |
| `kubectl argo rollouts` → `unknown command` | Файл має називатися точно `kubectl-argo-rollouts.exe` і лежати в папці з PATH. Відкрийте нове вікно PowerShell |
| Новий под `ImagePullBackOff` | Образ з таким тегом не запушено в Docker Hub (крок 1) |
| Поди `Pending` | Мало ресурсів у minikube: `kubectl describe pod ...`; можна `minikube stop`, `minikube start --cpus=4 --memory=6g` |
| Argo CD довго не бачить коміт | `argocd app sync beauty-studio` або кнопка **Refresh** в UI |
| `kubectl run curl-loop` пише `AlreadyExists` | `kubectl delete pod curl-loop -n beauty-studio` і запустіть знову |
