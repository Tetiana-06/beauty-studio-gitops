# beauty-studio-gitops

Репозиторій конфігурації (GitOps) для застосунку Beauty Studio.
Тут описано **бажаний стан кластера**. Argo CD читає цей репозиторій і сам приводить кластер до нього.
Код застосунку лежить окремо: https://github.com/Tetiana-06/beauty_studio_devops

## Структура

```
beauty-studio-gitops/
├── bootstrap/
│   └── root-app.yaml            # кореневий Application (App of Apps). Застосовується вручну ОДИН раз
├── argocd-apps/
│   └── beauty-studio.yaml       # Application для чарту. Його створює root, а не людина
└── charts/
    └── beauty-studio/           # Helm-чарт із ЛР-4
        ├── Chart.yaml
        ├── values.yaml          # значення за замовчуванням
        ├── values-minikube.yaml # значення для minikube: тут міняємо тег образу
        └── templates/
```

Як усе пов'язано:

```
kubectl apply root-app.yaml  ->  root (дивиться в argocd-apps/)
                                   └── beauty-studio (дивиться в charts/beauty-studio/)
                                         └── Deployment, Service, ConfigMap, PVC ... у namespace beauty-studio
```

## Що змінено в чарті порівняно з ЛР-4

| Зміна | Навіщо |
| --- | --- |
| Пароль БД прибрано з `values.yaml`, додано `database.auth.existingSecret` | Паролі не зберігаються в Git. Secret `beauty-db-secret` створюється в кластері вручну |
| Образи беруться з Docker Hub (`docker.io/<логін>/beauty-*`) | Кластер сам завантажує образ, без `minikube image load` |
| `progressDeadlineSeconds: 60` у backend Deployment | Неіснуючий тег образу дає стан Degraded за 1 хв, а не за 10 |
| Видалено `pre-upgrade-hook.yaml`, `tests/`, `NOTES.txt`, `values-dev/prod.yaml` | Argo CD не запускає `helm upgrade` і `helm test`, а NOTES не показує. Для minikube лишився один файл значень |

## Запуск (один раз)

```powershell
kubectl create namespace beauty-studio
kubectl create secret generic beauty-db-secret -n beauty-studio `
  --from-literal=POSTGRES_USER=user `
  --from-literal=POSTGRES_PASSWORD=<пароль> `
  --from-literal=POSTGRES_DB=beauty_db `
  --from-literal=DATABASE_URL=postgresql://user:<пароль>@beauty-studio-db:5432/beauty_db
kubectl apply -n argocd -f bootstrap/root-app.yaml
```

Далі все робиться через Git: змінили файл → `git commit` → `git push` → Argo CD синхронізує.
