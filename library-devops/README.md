# Library Catalog — DevOps ЛР№1: Віртуалізація та контейнеризація

Проєкт: онлайн-каталог книг з рецензіями. Реалізовано на Python (FastAPI) + MongoDB,
складається з двох незалежних сервісів — знадобиться для подальших лабораторних
з мікросервісів.

## Відповідність вимогам ЛР№1

| Вимога | Як реалізовано |
|---|---|
| a. Будь-яка мова/стек | Python 3.12, FastAPI, MongoDB |
| b. Веб-додаток + БД/інфраструктура | 2 REST API + MongoDB + mongo-express (адмінка) |
| c. Юніт/інтеграційні тести | `pytest` у кожному сервісі (`tests/`), MongoDB замокано через `mongomock` |
| d. Декілька частин (мікросервіси) | `catalog-api` (книги) + `reviews-api` (рецензії та рейтинги) |
| Dockerfile на кожну частину | `catalog-api/Dockerfile`, `reviews-api/Dockerfile` |
| docker-compose піднімає все разом | `docker-compose.yml` (mongo, mongo-express, catalog-api, reviews-api) |

## Структура репозиторію

```
library-devops/
├── docker-compose.yml
├── catalog-api/           # CRUD книг: назва, автор, жанр, рік, ISBN
│   ├── app/
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
└── reviews-api/           # рецензії до книг + агрегація середнього рейтингу
    ├── app/
    ├── tests/
    ├── Dockerfile
    └── requirements.txt
```

## Запуск через Docker Compose

```bash
docker compose up --build
```

- `catalog-api` → http://localhost:8001 (Swagger: `/docs`)
- `reviews-api` → http://localhost:8002 (Swagger: `/docs`)
- `mongo-express` → http://localhost:8081 (перегляд бази)

Приклад використання:

```bash
# додати книгу
curl -X POST http://localhost:8001/books \
  -H "Content-Type: application/json" \
  -d '{"title": "Дюна", "author": "Френк Герберт", "genre": "sci-fi", "year": 1965}'

# список книг (з book_id із відповіді вище)
curl http://localhost:8001/books

# додати рецензію
curl -X POST http://localhost:8002/reviews \
  -H "Content-Type: application/json" \
  -d '{"book_id": "<book_id>", "reviewer_name": "Оксана", "rating": 5, "comment": "Класика!"}'

# середній рейтинг книги
curl http://localhost:8002/reviews/<book_id>/summary
```

## Запуск тестів локально (без Docker)

```bash
cd catalog-api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest

cd ../reviews-api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

Тести використовують `mongomock`, тому реальний MongoDB для їх запуску не потрібен.

## Git

```bash
git init
git add .
git commit -m "feat: containerize library catalog and reviews services"
git branch -M main
git remote add origin <URL_вашого_репозиторію>
git push -u origin main
```

---

# ЛР№2: Continuous Integration

CI/CD-інструмент: **GitHub Actions** (`.github/workflows/ci.yml`).
Реєстр образів: **GitHub Container Registry** (`ghcr.io`).

## Тригери

- `pull_request` → `main` — прогонятиме lint + build + test (без публікації образів).
- `push` у будь-яку гілку — прогонятиме весь пайплан; публікація образів вмикається лише
  для `push`-подій (`if: github.event_name == 'push'`), тег `latest` — лише для `main`.

## Структура пайплайна (4 jobs)

| Job | Залежить від | Що робить |
|---|---|---|
| `test` (matrix: `catalog-api`, `reviews-api`) | — | Lint (`ruff`, блокуючий) → Build (sanity import) → Test (`pytest`). Кешування pip через `actions/setup-python`. Матриця виконується паралельно й незалежно (`fail-fast: false`) |
| `build-image` (matrix) | `test` | Збирає Docker-образ кожного сервісу локально на раннері (без публікації), зберігає як artifact |
| `scan-image` (matrix) | `build-image` | Сканує зібраний образ **Trivy** на CRITICAL/HIGH-вразливості — блокуючий крок |
| `publish` (matrix) | `scan-image` | Лише для `push`: логін у `ghcr.io` через `secrets.GITHUB_TOKEN` (без збереження credentials у репо), публікує з тегами `<commit_sha>` завжди та `latest` тільки для `main` |

## Як перевірити опубліковані образи

```bash
docker pull ghcr.io/<owner>/<repo>/catalog-api:latest
docker run -p 8001:8000 ghcr.io/<owner>/<repo>/catalog-api:latest
```

(підставте свій GitHub-логін/організацію та назву репозиторію в нижньому регістрі — GHCR
вимагає lowercase).

## Налаштування Branch Protection (робиться в GitHub UI, не файлом)

1. Repo → **Settings → Branches → Add branch protection rule** → `main`.
2. Увімкнути **Require a pull request before merging** (заборона прямого push).
3. Увімкнути **Require status checks to pass before merging**, додати обов'язкові перевірки:
   - `test (catalog-api)`
   - `test (reviews-api)`
   - `build-image (catalog-api)`
   - `build-image (reviews-api)`
   - `scan-image (catalog-api)`
   - `scan-image (reviews-api)`
4. Зберегти.

## Демонстрація на захисті

1. Відкрити вкладку **Actions** — показати успішний прогін пайплайна з усіма 4 jobs.
2. Створити PR, який свідомо ламає лінт або тест (наприклад, зайвий пробіл, що триггерить
   `ruff`, або `assert False` у тесті) — показати червоний статус у PR і заблоковану кнопку
   **Merge**.
3. Показати вкладку **Packages** репозиторію з опублікованими образами `catalog-api` та
   `reviews-api`, зробити `docker pull` і запустити образ.
4. Показати **Settings → Branches** з увімкненим Branch Protection на `main`.

---

# ЛР№3: Розгортання в Kubernetes (minikube)

Усі маніфести — у `k8s/`, по одному файлу на об'єкт. Namespace проєкту: `library-catalog`.

## 1. Підготувати образ (дві версії, без `latest`)

Образи вже публікуються в GHCR пайплайном з ЛР№2. Щоб отримати дві версії для
демонстрації rolling update/rollback, протегуйте комміт git-тегом — CI сам збере і
опублікує образ із цим точним номером версії:

```bash
git tag v1.0.0 && git push origin v1.0.0
# ...зробіть видиму зміну в коді (наприклад, нове поле або повідомлення)...
git tag v1.1.0 && git push origin v1.1.0
```

У `k8s/30-catalog-deployment.yaml` та `k8s/40-reviews-deployment.yaml` замініть
`ghcr.io/OWNER/REPO` на свій реальний шлях (lowercase) і переконайтесь, що тег —
`1.0.0`, а не `latest`.

## 2. Розгорнути локальний кластер

```bash
minikube start --driver=docker
kubectl get nodes
kubectl get pods -n kube-system

minikube addons enable metrics-server
minikube addons enable ingress
```

## 3–5. Застосувати всі маніфести та перевірити

```bash
kubectl apply -f k8s/

kubectl get pods,deploy,rs,svc -n library-catalog

# доступ через Ingress (minikube на Linux/WSL з драйвером docker):
minikube tunnel &
echo "$(minikube ip) library.local" | sudo tee -a /etc/hosts
curl http://library.local/catalog/books
curl http://library.local/reviews/health

# або напряму без Ingress, для швидкої перевірки:
kubectl port-forward -n library-catalog svc/catalog-api 8001:8000
curl http://localhost:8001/books
```

Перевірка, що ConfigMap і Secret реально потрапили в контейнер:

```bash
kubectl exec -n library-catalog deploy/catalog-api -- env | grep -E 'DB_NAME|LOG_LEVEL|MONGO_URI'
kubectl logs -n library-catalog deploy/catalog-api | grep "DB_NAME"
```

## 6. Керування життєвим циклом

```bash
# a) самовідновлення
kubectl get pods -n library-catalog -l app=catalog-api
kubectl delete pod -n library-catalog <ім'я-пода>
kubectl get pods -n library-catalog -l app=catalog-api -w   # з'явився новий под

# b) масштабування
kubectl scale deployment catalog-api -n library-catalog --replicas=4
kubectl get pods -n library-catalog -l app=catalog-api -o wide

# c) rolling update на другу версію
kubectl set image deployment/catalog-api \
  catalog-api=ghcr.io/OWNER/REPO/catalog-api:1.1.0 -n library-catalog
kubectl rollout status deployment/catalog-api -n library-catalog

# під час rollout — у другому терміналі довести доступність:
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8001/health; sleep 1; done

# d) історія та відкат
kubectl rollout history deployment/catalog-api -n library-catalog
kubectl rollout undo deployment/catalog-api -n library-catalog
```

## 7. Діагностика (навмисна помилка)

```bash
kubectl set image deployment/catalog-api \
  catalog-api=ghcr.io/OWNER/REPO/catalog-api:9.9.9-not-exist -n library-catalog

kubectl get pods -n library-catalog            # STATUS: ImagePullBackOff
kubectl describe pod -n library-catalog <ім'я-пода>   # розділ Events — причина
kubectl logs -n library-catalog <ім'я-пода>
kubectl exec -it -n library-catalog deploy/reviews-api -- /bin/sh   # інший под, що працює

# виправлення:
kubectl set image deployment/catalog-api \
  catalog-api=ghcr.io/OWNER/REPO/catalog-api:1.1.0 -n library-catalog
kubectl rollout status deployment/catalog-api -n library-catalog
```

## Параметри ConfigMap і Secret

| Джерело | Ключ | Призначення |
|---|---|---|
| ConfigMap `app-config` | `DB_NAME` | назва бази MongoDB |
| ConfigMap `app-config` | `LOG_LEVEL` | рівень логування застосунку |
| Secret `mongo-secret` | `MONGO_ROOT_USERNAME` | логін адміністратора Mongo (для самого Mongo) |
| Secret `mongo-secret` | `MONGO_ROOT_PASSWORD` | пароль адміністратора Mongo (для самого Mongo) |
| Secret `mongo-secret` | `MONGO_URI` | повний рядок підключення з обліковими даними (для catalog-api/reviews-api) |

Значення в `k8s/11-secret.yaml` — навчальні, не реальні паролі робочих систем.

---

# ЛР№4: Helm-чарт

Чарт — у каталозі `chart/` (назва `library`). Він дає той самий набір об'єктів, що й `k8s/` з ЛР№3:
ConfigMap, Secret, PVC, Deployment і Service для `mongo`, `catalog` та `reviews`, Ingress (за прапорцем).
Namespace Helm не створює сам — його створює `--create-namespace`.

## version і appVersion

- `version` (0.1.0) — версія самого чарта: змінюється, коли змінюються шаблони чи структура `values`.
- `appVersion` ("1.0.0") — версія застосунку, який розгортає чарт; використовується як тег образу, якщо тег не заданий у values.

Приклад: виправили шаблон Ingress, не чіпаючи застосунок — росте `version`; випустили образ `1.1.0` — змінюється `appVersion`.

## Параметри values

| Параметр | За замовчуванням | Призначення |
|---|---|---|
| `catalog.image.repository` / `.tag` | `vasya1221/catalog-api` / `""` (= appVersion) | образ catalog-api |
| `reviews.image.repository` / `.tag` | `vasya1221/reviews-api` / `""` | образ reviews-api |
| `catalog.replicaCount`, `reviews.replicaCount` | `1` | кількість реплік |
| `catalog.service.type` / `.port` | `ClusterIP` / `8000` | сервіс catalog (аналогічно `reviews.*`) |
| `catalog.resources`, `reviews.resources`, `mongo.resources` | див. values.yaml | requests/limits |
| `mongo.persistence.enabled` / `.size` | `true` / `1Gi` | PVC для MongoDB |
| `config.dbName`, `config.logLevel` | `library`, `info` | ConfigMap |
| `secret.mongoRootUsername` / `.mongoRootPassword` | `admin` / `dev-demo-password` | Secret (для prod пароль задається через `--set`) |
| `ingress.enabled` / `.className` / `.host` | `false` / `nginx` / `library.local` | Ingress |

## Команди

```bash
helm version
helm lint chart/ 
helm template library chart/ -n library-catalog

# dev
helm install library chart/ -n library-catalog --create-namespace -f chart/values-dev.yaml

# prod (пароль передається ззовні)
helm install library chart/ -n library-catalog --create-namespace \
  -f chart/values-prod.yaml --set secret.mongoRootPassword=<пароль>

helm test library -n library-catalog
helm upgrade library chart/ -n library-catalog -f chart/values-dev.yaml --set catalog.image.tag=1.0.0
helm history library -n library-catalog
helm rollback library 1 -n library-catalog
helm uninstall library -n library-catalog
```

Додатково (п.9b): pre-upgrade хук `templates/hooks/pre-upgrade-job.yaml` перевіряє доступність MongoDB перед оновленням; тест `templates/tests/test-connection.yaml` запускається командою `helm test`.

---

# ЛР№5: GitOps через Argo CD

Конфігурація розгортання лежить у Git: `bootstrap/root-app.yaml` (кореневий Application), `argocd-apps/library.yaml` (Application застосунку), `charts/library/` (Helm-чарт і `values-minikube.yaml`). Покроковий порядок команд і перелік матеріалів для звіту: [docs/lab5-gitops.md](docs/lab5-gitops.md).

Застосунок показує версію на `GET /version` (значення береться з `APP_VERSION`, задається при збірці образу `--build-arg APP_VERSION=...`). Пароль MongoDB у Git не зберігається: Secret `library-secret` створюється в кластері вручну.
