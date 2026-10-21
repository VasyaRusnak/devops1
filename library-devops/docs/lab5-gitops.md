# ЛР№5: GitOps через Argo CD — порядок виконання і матеріали для звіту

Варіант репозиторію: **б)** каталоги `bootstrap/`, `argocd-apps/`, `charts/` у репозиторії застосунку.

```
bootstrap/root-app.yaml          кореневий Application (App of Apps), застосовується вручну
argocd-apps/library.yaml         Application застосунку (Argo CD бере його з Git)
charts/library/                  Helm-чарт з ЛР№4 + values-minikube.yaml
```

Що змінилося в чарті порівняно з ЛР№4 (`chart/`):
- `secret.existingSecret`: Secret не зберігається в Git, його створюють у кластері вручну.
- `helmHooks.enabled`: Argo CD запускає `pre-upgrade` хук як PreSync і при першому sync, коли MongoDB ще немає, тому для minikube хук і тест вимкнено.
- `progressDeadlineSeconds`: у minikube 60 с, щоб стан Degraded з'являвся за хвилину, а не за 10.

Перед початком перевір у `bootstrap/root-app.yaml` і `argocd-apps/library.yaml` поля `repoURL` (твій репозиторій) і `targetRevision` (назва гілки, `main` чи `master`).

---

## Пункт 2. Образ із версією

Нова версія застосунку має ендпоінт `GET /version`. Версія вшивається при збірці через `--build-arg`.

```powershell
docker build --build-arg APP_VERSION=1.2.0 -t vasya1221/catalog-api:1.2.0 ./catalog-api
docker build --build-arg APP_VERSION=1.2.0 -t vasya1221/reviews-api:1.2.0 ./reviews-api
docker push vasya1221/catalog-api:1.2.0
docker push vasya1221/reviews-api:1.2.0
```
Перевірка локально (у другому вікні `curl`):
```powershell
docker run --rm -p 8001:8000 vasya1221/catalog-api:1.2.0
curl http://localhost:8001/version
```
Очікується `{"service":"catalog-api","version":"1.2.0"}`. Образи на Docker Hub мають бути публічними, щоб кластер тягнув їх без секретів.

Для звіту: вивід `docker push` і відповідь `/version`.

## Перевірка чарта і коміт

```powershell
helm lint charts/library -f charts/library/values-minikube.yaml
helm template library charts/library -n library-catalog -f charts/library/values-minikube.yaml | findstr "image: replicas"
git add .
git commit -m "feat: add GitOps config for Argo CD and /version endpoint"
git push
```

## Пункт 3. Встановлення Argo CD

```powershell
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd -w
```
Дочекайся, поки всі поди `Running` (1–3 хвилини).

CLI:
```powershell
Invoke-WebRequest -Uri https://github.com/argoproj/argo-cd/releases/latest/download/argocd-windows-amd64.exe -OutFile argocd.exe
Move-Item argocd.exe "$env:LOCALAPPDATA\Microsoft\WinGet\Links\argocd.exe"
argocd version --client
```
Веб-інтерфейс (вікно 1, не закривати):
```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Початковий пароль і вхід (вікно 2):
```powershell
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
argocd account update-password
```
Відкрий `https://localhost:8080` (браузер попередить про сертифікат, погодься), увійди як `admin` з новим паролем.

Якщо репозиторій приватний:
```powershell
argocd repo add https://github.com/<логін>/<репо>.git --username <логін> --password <токен GitHub>
```
Токен у Git не потрапляє.

Для звіту: скрін `kubectl get pods -n argocd`, скрін входу в інтерфейс, вивід `argocd account update-password`.

## Секрет застосунку (не в Git)

```powershell
kubectl create namespace library-catalog
$pw = "Придумай123Пароль"   # лише латиниця і цифри
kubectl create secret generic library-secret -n library-catalog `
  --from-literal=MONGO_ROOT_USERNAME=admin `
  --from-literal=MONGO_ROOT_PASSWORD=$pw `
  --from-literal=MONGO_URI="mongodb://admin:${pw}@library-mongo:27017/library?authSource=admin"
```
Підстав свій пароль замість прикладу, використовуй лише латиницю й цифри.

## Пункт 4. Application і App of Apps

Вручну застосовується тільки кореневий об'єкт:
```powershell
kubectl apply -f bootstrap/root-app.yaml
argocd app list
argocd app get library
kubectl get pods -n library-catalog
```
В інтерфейсі з'являться `root` і `library`. Відкрий `library` і покажи дерево об'єктів зі статусом **Synced / Healthy**.

Для звіту: скрін списку застосунків, скрін дерева `library` (Synced / Healthy), вивід `argocd app get library`.

## Пункт 5. Оновлення через Git

1. Зроби видиму зміну в коді, наприклад у `catalog-api/app/main.py` змін `title="Library Catalog API"` на `title="Library Catalog API (release 1.3)"`. Назва видна на `/docs`.
2. Збери й опублікуй нову версію:
```powershell
docker build --build-arg APP_VERSION=1.3.0 -t vasya1221/catalog-api:1.3.0 ./catalog-api
docker build --build-arg APP_VERSION=1.3.0 -t vasya1221/reviews-api:1.3.0 ./reviews-api
docker push vasya1221/catalog-api:1.3.0
docker push vasya1221/reviews-api:1.3.0
```
3. У `charts/library/values-minikube.yaml` заміни обидва `tag: "1.2.0"` на `tag: "1.3.0"`, потім:
```powershell
git add .
git commit -m "release: bump images to 1.3.0"
git push
```
4. Argo CD опитує Git кожні ~3 хвилини. Щоб не чекати, натисни Refresh в інтерфейсі або виконай `argocd app get library --refresh`.
5. Перевірка:
```powershell
kubectl port-forward -n library-catalog svc/library-catalog 8001:8000
curl http://localhost:8001/version
```
Очікується `"version":"1.3.0"`.

Для звіту: скрін коміту з правкою тега, скрін Argo CD під час синхронізації, відповідь `/version` з новою версією.

## Пункт 6a. Дрейф і selfHeal

Спершу `selfHeal: false` (так у `argocd-apps/library.yaml`):
```powershell
kubectl scale deployment library-catalog -n library-catalog --replicas=5
argocd app get library
```
Статус стане **OutOfSync**, і Argo CD його не виправляє.

Тепер увімкни selfHeal через Git: у `argocd-apps/library.yaml` зміни `selfHeal: false` на `selfHeal: true`, потім:
```powershell
git add .
git commit -m "feat: enable selfHeal for library"
git push
```
Кореневий Application сам застосує цю зміну до `library`. Після цього:
```powershell
kubectl scale deployment library-catalog -n library-catalog --replicas=5
kubectl get pods -n library-catalog -w
```
Argo CD за кілька секунд поверне 2 репліки з Git.

Для звіту: скрін OutOfSync, коміт з `selfHeal: true`, скрін повернення реплік.

## Пункт 6b. Synced, але Degraded

У `charts/library/values-minikube.yaml` встав неіснуючий тег: `tag: "9.9.9-not-exist"` (для catalog), потім commit і push.
Приблизно через хвилину (`progressDeadlineSeconds: 60`):
```powershell
argocd app get library
kubectl get pods -n library-catalog
```
Статус: **Synced** (кластер відповідає Git), але **Degraded** (нові поди в `ImagePullBackOff`, стара версія продовжує працювати).

Для звіту: скрін інтерфейсу Synced + Degraded, вивід `kubectl get pods`.

## Пункт 6c. Відкат через git revert

```powershell
git revert HEAD --no-edit
git push
git log --oneline
argocd app history library
argocd app get library
```
Argo CD повертає застосунок у Healthy. У `git log` видно коміт `Revert "..."`, а в `argocd app history` послідовність ревізій.

Для звіту: вивід `git log --oneline` і `argocd app history library`, скрін Synced / Healthy.

---

## Підготовка до захисту (пункт 7)

Наживо покажи по порядку: інтерфейс Argo CD, реліз комітом (зміна тега), ручний `kubectl scale`, який повертає selfHeal, Synced + Degraded з неіснуючим тегом, відкат `git revert`. Щоб демонстрація йшла швидко:
- тримай відкритими `kubectl port-forward svc/argocd-server -n argocd 8080:443` і вкладку з інтерфейсом;
- образи `1.2.0` і `1.3.0` вже опублікуй заздалегідь;
- після кожного `git push` тисни Refresh в інтерфейсі, не чекай 3 хвилини.
