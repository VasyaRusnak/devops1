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
