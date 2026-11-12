# ЛР№7: Observability — метрики, логи, дашборди і відкат за метриками

Усі команди PowerShell виконуй **по одній** (кожен блок коду окремо), не склеюючи рядки.
Кластер: minikube. Репозиторій: гілка `gitops` (на `main` діє Branch Protection).

## Швидкий шлях: скрипти замість ручних команд

Розпакуй `lab7-changes.zip` поверх `devops1\library-devops`, відкрий PowerShell у цій папці й виконуй лише ці команди.

Підготовка (один раз): перевірка інструментів, секрет Grafana, тести, збірка і push образів `1.4.0`, коміт і push у `gitops`:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\lab7-setup.ps1
```
Скрипт спитає лише пароль для Grafana. Прапорці: `-SkipTests`, `-SkipBuild`, `-SkipGit`.

Демонстрація, кожна дія окремою командою:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\lab7-demo.ps1 -Action status
```
| Дія (`-Action`) | Що робить | Відповідає кроку |
|---|---|---|
| `status` | застосунки Argo CD, поди, Rollout, AnalysisRun | 5 |
| `ui` | відкриває Grafana, Prometheus, Alertmanager, Argo CD | 5–6 |
| `load-start` (`-Rate 60`) | запускає навантаження | 7 |
| `enable-analysis` | вмикає аналіз метрик, commit і push | 7 |
| `bad-release` | поганий реліз `FAIL_RATE=0.5`, commit і push | 8 |
| `watch` | стежить за Rollout у реальному часі | 8 |
| `revert` | відкат через `git revert`, push | 8 |
| `load-stop` | зупиняє навантаження | після демонстрації |

Порядок для захисту: `ui` → `load-start` → `enable-analysis` → `bad-release` → `watch` → `revert`.
Скріни для звіту і перегляд Prometheus, Grafana, Loki ти робиш у браузері (розділи 5–8 нижче показують, що відкривати). Решта документа пояснює, що скрипти роблять, і потрібна для ручного режиму та для відповідей викладачу.

## 0. Що змінилося

```
argocd-apps/kube-prometheus-stack.yaml            НОВИЙ: Prometheus, Alertmanager, Grafana
argocd-apps/loki.yaml                             НОВИЙ: Loki (Monolithic, файлове сховище)
argocd-apps/alloy.yaml                            НОВИЙ: Grafana Alloy, збір логів подів
catalog-api/app/observability.py                  НОВИЙ: /metrics, JSON-логи, FAIL_RATE (те саме в reviews-api)
catalog-api/app/main.py, Dockerfile, requirements.txt   підключення модуля (те саме в reviews-api)
catalog-api/tests/test_observability.py           НОВИЙ: тести метрик, FAIL_RATE, JSON-логів (те саме в reviews-api)
charts/library/templates/servicemonitor.yaml      НОВИЙ: ServiceMonitor (ціль у Prometheus)
charts/library/templates/analysistemplate.yaml    НОВИЙ: AnalysisTemplate success-rate >= 95%
charts/library/templates/prometheusrule.yaml      НОВИЙ: алерт на частку 5xx > 5%
charts/library/templates/dashboard-configmap.yaml НОВИЙ: ConfigMap з міткою grafana_dashboard
charts/library/dashboards/library-overview.json   НОВИЙ: дашборд Grafana (JSON)
charts/library/templates/catalog-rollout.yaml     кроки analysis у canary
charts/library/templates/_helpers.tpl             змінна FAIL_RATE, іменований порт http
charts/library/templates/*-service.yaml           порт Service названо http (для ServiceMonitor)
charts/library/values.yaml, values-minikube.yaml  параметри metrics, analysis, alerts, dashboards, failRate; тег 1.4.0
loadtest/loadgen.yaml                             НОВИЙ: генератор навантаження k6
```

Як це працює разом:
- Застосунок віддає `/metrics` (лічильник `http_requests_total{method,route,status}` і гістограма `http_request_duration_seconds{method,route}`), логи пише в JSON у stdout.
- ServiceMonitor каже Prometheus збирати метрики з Service. Мітка пода `rollouts-pod-template-hash` копіюється в метрику як `rollouts_pod_template_hash`, тому нову версію видно окремо від старої.
- Alloy читає логи подів namespace `library-catalog` і шле в Loki; Grafana показує їх поруч із метриками.
- AnalysisTemplate питає Prometheus про частку не-5xx запитів **лише canary-пода**. Нижче 95% аналіз провалюється, Argo Rollouts робить abort і лишає stable.
- Погана версія імітується змінною `FAIL_RATE`: частка запитів (крім `/health`, `/metrics`, `/version`) отримує 500. Це змінює pod template, тож Rollout запускає canary без нового образу.

## 1. Перед стартом

Моніторинг важкий для minikube. Перевір, скільки пам'яті має вузол:

```powershell
kubectl get node -o jsonpath="{.items[0].status.allocatable.memory}"
```
Бажано 5–6 ГіБ і більше (значення в КіБ: 5 000 000 і вище). Менше не вистачить: збільш пам'ять Docker Desktop і перестворюй minikube (`minikube delete`, потім `minikube start --cpus=4 --memory=6144`), після чого Argo CD і секрети треба поставити заново.

Версії чартів у файлах Application узяті з офіційних джерел на листопад 2026. Перевір, що вони існують:

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```
```powershell
helm repo add grafana-community https://grafana-community.github.io/helm-charts
```
```powershell
helm repo add grafana https://grafana.github.io/helm-charts
```
```powershell
helm repo update
```
```powershell
helm search repo prometheus-community/kube-prometheus-stack --versions | Select-Object -First 3
```
```powershell
helm search repo grafana-community/loki --versions | Select-Object -First 3
```
```powershell
helm search repo grafana/alloy --versions | Select-Object -First 3
```
Якщо `targetRevision` у `argocd-apps/*.yaml` не знайдеться, підстав версію з виводу. Для Loki і Alloy там діапазони `18.*` та `1.*`.

## 2. Секрет Grafana (не в Git)

```powershell
kubectl create namespace monitoring
```
```powershell
kubectl create secret generic grafana-admin -n monitoring --from-literal=admin-user=admin --from-literal=admin-password=ПридумайПароль123
```
Підстав свій пароль (латиниця й цифри). Без цього секрета Grafana не запуститься.

## 3. Образи 1.4.0

Нова версія застосунку з метриками, JSON-логами і `FAIL_RATE`. З папки `devops1\library-devops`:

```powershell
docker build --build-arg APP_VERSION=1.4.0 -t vasya1221/catalog-api:1.4.0 ./catalog-api
```
```powershell
docker build --build-arg APP_VERSION=1.4.0 -t vasya1221/reviews-api:1.4.0 ./reviews-api
```
```powershell
docker push vasya1221/catalog-api:1.4.0
```
```powershell
docker push vasya1221/reviews-api:1.4.0
```
Швидка перевірка образу локально (бази даних немає, тому перевіряємо лише службові маршрути):
```powershell
docker run -d --name vtest -p 8001:8000 vasya1221/catalog-api:1.4.0
```
```powershell
Start-Sleep -Seconds 5; curl.exe http://localhost:8001/version
```
```powershell
curl.exe -s http://localhost:8001/metrics | findstr http_request
```
```powershell
docker logs vtest --tail 3
```
`/version` повертає `1.4.0`, `/metrics` відповідає, у логах рядки JSON. Поведінку `FAIL_RATE` перевіряють тести (`pytest`, крок 4) і потім кластер. Прибери контейнер:
```powershell
docker rm -f vtest
```

## 4. Файли, перевірка і коміт

Розпакуй `lab7-changes.zip` **поверх** папки `devops1\library-devops` (погодься на заміну файлів). Архів містить лише нові і змінені файли, `bootstrap/` та `argocd-apps/library.yaml` у ньому немає, тож твої налаштування гілки `gitops` не зачіпаються. У `values-minikube.yaml` перевір, що `image.tag` обох сервісів `1.4.0`.

Перевірка до коміту (з папки `library-devops`):
```powershell
helm lint charts/library -f charts/library/values-minikube.yaml
```
```powershell
helm template library charts/library -n library-catalog -f charts/library/values-minikube.yaml | findstr "kind: name:"
```
Мають з'явитись `ServiceMonitor`, `PrometheusRule`, `Rollout`, ConfigMap дашборда. `AnalysisTemplate` поки немає (там `analysis.enabled: false`).

```powershell
cd catalog-api; ruff check app tests; pytest; cd ..
```
```powershell
cd reviews-api; ruff check app tests; pytest; cd ..
```
Потім у кореневій папці репозиторію (`devops1`) на гілці `gitops`:
```powershell
git switch gitops
```
```powershell
git add library-devops
```
```powershell
git commit -m "feat: observability stack, app metrics, JSON logs, dashboard"
```
```powershell
git push
```

## 5. Стек моніторингу (п.1 завдання)

```powershell
argocd app get root --refresh
```
```powershell
kubectl get applications -n argocd
```
Мають з'явитися `kube-prometheus-stack`, `loki`, `alloy`. Дочекайся Synced / Healthy (кілька хвилин, образи великі).

```powershell
kubectl get pods -n monitoring
```
Усі поди `Running`. Перевір також, що застосунок оновився до 1.4.0:
```powershell
kubectl argo rollouts get rollout library-catalog -n library-catalog
```
```powershell
kubectl get pods -n library-catalog
```
Доступ до інтерфейсів (кожен у своєму вікні, не закривати):

| Що | Команда | Адреса |
|---|---|---|
| Grafana | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` | http://localhost:3000 |
| Prometheus | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | http://localhost:9090 |
| Alertmanager | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093` | http://localhost:9093 |
| Rollouts | `kubectl argo rollouts dashboard` | http://localhost:3100 |

Grafana: логін `admin`, пароль із кроку 2.

Для звіту: список Application в Argo CD, `kubectl get pods -n monitoring`, відкрита Grafana.

## 6. Метрики, логи, дашборд (пп.2–4)

**Ціль у Prometheus (п.2b).** `http://localhost:9090` → Status → Targets. Знайди `serviceMonitor/library-catalog/library/0`, стан **UP** (спершу можуть бути DOWN поди старої версії 1.2.0, поки Rollout не завершився).
Запит до своєї метрики (вкладка Graph):
```
sum by (route, status) (rate(http_requests_total{namespace="library-catalog"}[1m]))
```
Без навантаження графік порожній: спершу запусти крок 7.

**Логи (п.3).** Grafana → Explore → джерело **Loki**:
```
{namespace="library-catalog", component="catalog"}
```
Лише помилки 5xx:
```
{namespace="library-catalog", component="catalog"} | json | status >= 500
```
Логи JSON: `ts`, `level`, `message`, `method`, `route`, `status`, `duration_ms`.

**Дашборд (п.4).** Grafana → Dashboards → **Library: застосунок**. Він доставлений через Argo CD (ConfigMap `library-dashboard` з міткою `grafana_dashboard`). Панелі: запити за секунду, частка 5xx, p95, запити за версіями, CPU, пам'ять, логи, логи з 5xx.

## 7. Навантаження (п.5) і вмикання аналізу

Запусти генератор:
```powershell
kubectl apply -f loadtest/loadgen.yaml
```
```powershell
kubectl get pods -n library-catalog -l app=loadgen
```
Відкрий дашборд: зростають запити за секунду, затримка і CPU. Зроби скрін до і після.

**Друга зміна на вибір.** Наприклад, більше реплік через Git: у `values-minikube.yaml` `catalog.replicaCount: 4` → `6`, commit, push, Refresh. На дашборді з'являються нові поди, CPU на под зменшується. Потім поверни `4`.

**Вмикання аналізу.** Коли навантаження йде, в `charts/library/values-minikube.yaml` зміни:
```yaml
analysis:
  enabled: true
```
```powershell
git add library-devops/charts; git commit -m "feat: enable canary analysis"; git push
```
Після sync перевір, що шаблон з'явився:
```powershell
kubectl get analysistemplate -n library-catalog
```

## 8. Автоматичний відкат за метриками (п.6)

Навантаження має працювати (крок 7). Підготуй три вікна: `kubectl argo rollouts get rollout library-catalog -n library-catalog -w`, дашборд Grafana і Alertmanager.

**Поганий реліз.** У `values-minikube.yaml` зміни `catalog.failRate: "0"` на `"0.5"`, потім:
```powershell
git add library-devops/charts; git commit -m "release: catalog 1.4.0 with FAIL_RATE=0.5 (bad)"; git push
```
```powershell
argocd app get library --refresh
```
Що відбувається і що показати:
1. Rollout піднімає canary-под (`setWeight: 25`), запускається AnalysisRun:
```powershell
kubectl get analysisrun -n library-catalog
```
2. За 1–2 хвилини AnalysisRun стає **Failed** (частка успішних запитів canary близько 50% < 95%), Rollout робить **abort**, статус **Degraded**, трафік лишається на stable:
```powershell
kubectl describe analysisrun -n library-catalog
```
3. На дашборді в панелі «Частка помилок 5xx» і «Запити за версіями» видно сплеск 5xx лише в нової версії.
4. Логи лише з подів нової версії. Хеш canary видно в `kubectl argo rollouts get rollout ...`, а також у дашборді як мітку `rollouts_pod_template_hash`. Підстав його:
```
{namespace="library-catalog", component="catalog", rollouts_pod_template_hash="ХЕШ_CANARY"} | json | status >= 500
```
5. Алерт (завдання 6d): у Alertmanager (http://localhost:9093) або Prometheus → Alerts стан **Firing** для `LibraryHighErrorRate`. Алерт має спрацювати, поки йдуть помилки. Якщо не встиг, збільш навантаження: у `loadtest/loadgen.yaml` зміни `RATE` на `60`, видали Job (`kubectl delete job loadgen -n library-catalog`) і застосуй файл знову.

**Відкат через Git.**
```powershell
git revert HEAD --no-edit
```
```powershell
git push
```
```powershell
argocd app get library --refresh
```
Rollout повертається до healthy (pod template збігається зі stable), застосунок знову Synced / Healthy. Для звіту: `git log --oneline -5`, `argocd app history library`.

## 9. Для захисту (п.7)

Перед захистом: Argo CD, Grafana, Prometheus у відкритих вкладках, `loadgen` запущений, в Git `failRate: "0"`, `analysis.enabled: true`.
Сценарій: ціль у Prometheus (UP) → дашборд під навантаженням → логи в Loki → поганий реліз (`failRate: "0.5"`) → AnalysisRun Failed і abort → логи 5xx нової версії → `git revert`.

Запити, які можуть попросити написати:
```
sum(rate(http_requests_total{namespace="library-catalog"}[1m]))
sum by (status) (rate(http_requests_total{service="library-catalog"}[1m]))
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="library-catalog"}[5m])))
sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m]))
up{namespace="library-catalog"}
```
```
{namespace="library-catalog"} | json | route="/books"
{namespace="library-catalog"} | json | duration_ms > 100
sum by (component) (count_over_time({namespace="library-catalog"} | json | status >= 500 [1m]))
```

## 10. Якщо щось не працює

- **Grafana в `CreateContainerConfigError`:** немає Secret `grafana-admin` у `monitoring` (крок 2).
- **Application `kube-prometheus-stack` у `OutOfSync` з помилкою про CRD:** перевір `ServerSideApply=true` у файлі.
- **Application `library` скаржиться, що не знає `ServiceMonitor` / `AnalysisTemplate`:** CRD ще не створені, Argo CD повторить sync сам (є `retry`), зачекай.
- **У Prometheus немає цілі:** `kubectl get servicemonitor -n library-catalog`; перевір, що Service має порт з іменем `http` (`kubectl get svc library-catalog -n library-catalog -o yaml`).
- **Логів у Loki немає:** `kubectl logs -n monitoring deploy/alloy`; перевір, що Loki `Running` і в Grafana є джерело Loki.
- **AnalysisRun завершується `Error`:** немає трафіку на canary (запусти `loadgen`) або Prometheus недоступний за адресою `analysis.prometheusAddress`.
- **Недостатньо пам'яті, поди `Pending`/`OOMKilled`:** крок 1.
