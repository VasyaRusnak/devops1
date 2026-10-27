# ЛР№6: Progressive delivery з Argo Rollouts (canary) — порядок виконання і матеріали для звіту

Обрана стратегія: **canary** для `catalog-api`. Сервіс `reviews-api` і MongoDB лишаються звичайними Deployment.

## Що змінилося в репозиторії

```
argocd-apps/argo-rollouts.yaml                       НОВИЙ: Application контролера Argo Rollouts (Helm-чарт argo/argo-rollouts 2.40.9)
argocd-apps/library.yaml                             retry + SkipDryRunOnMissingResource (Rollout потребує CRD)
charts/library/templates/catalog-rollout.yaml        НОВИЙ: Rollout, замінює Deployment каталогу
charts/library/templates/catalog-deployment.yaml     Deployment створюється лише коли catalog.rollout.enabled=false
charts/library/templates/_helpers.tpl                спільний pod template (library.catalog.podTemplate)
charts/library/values.yaml                           catalog.rollout.* : стратегія canary і її кроки
charts/library/values-minikube.yaml                  catalog.replicaCount: 4, catalog.rollout.enabled: true
charts/library/Chart.yaml                            версія чарта 0.3.0
```

Pod template каталогу винесено в один helper: при перемиканні `catalog.rollout.enabled` змінюється лише тип об'єкта (Deployment ↔ Rollout), а вміст пода лишається тим самим.

Стратегія описана у `values.yaml`:

```yaml
catalog:
  rollout:
    enabled: false
    revisionHistoryLimit: 3
    canary:
      maxSurge: 1
      maxUnavailable: 0
      steps:
        - setWeight: 25
        - pause: {duration: 30s}   # таймер
        - setWeight: 50
        - pause: {}                # ручна пауза, чекає promote
        - setWeight: 75
        - pause: {duration: 30s}
```

Чотири репліки дають цілі співвідношення: 25% = 1 под нової версії з 4, 50% = 2, 75% = 3.

---

## Пункт 1. Argo Rollouts через Argo CD

**Коміт 1** (лише контролер, щоб перевірити його окремо від застосунку):

```powershell
git add argocd-apps/argo-rollouts.yaml
git commit -m "feat: install Argo Rollouts controller via Argo CD"
git push
argocd app get root --refresh
argocd app list
kubectl get pods -n argo-rollouts
kubectl get crd rollouts.argoproj.io
```

Очікується: Application `argo-rollouts` у стані Synced / Healthy, в namespace `argo-rollouts` працюють поди контролера і дашборду, CRD `rollouts.argoproj.io` існує.

Якщо Argo CD скаржиться на `metadata.annotations: Too long`, переконайтеся, що в Application є `ServerSideApply=true` (воно вже є у файлі).

**Плагін kubectl argo rollouts (Windows, PowerShell):**

```powershell
Invoke-WebRequest -Uri https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-windows-amd64 -OutFile kubectl-argo-rollouts.exe
Move-Item kubectl-argo-rollouts.exe "$env:LOCALAPPDATA\Microsoft\WinGet\Links\kubectl-argo-rollouts.exe"
kubectl argo rollouts version
```

Каталог `WinGet\Links` уже є в PATH (туди ж у ЛР5 клали `argocd.exe`).

Для звіту: скрін Application `argo-rollouts` в Argo CD (Synced / Healthy), `kubectl get pods -n argo-rollouts`, вивід `kubectl argo rollouts version`.

---

## Пункт 2. Rollout у Helm-чарті

Перед комітом перевірте шаблони:

```powershell
helm lint charts/library -f charts/library/values-minikube.yaml
helm template library charts/library -n library-catalog -f charts/library/values-minikube.yaml | findstr "kind: replicas:"
helm template library charts/library -n library-catalog -f charts/library/values-minikube.yaml --set catalog.rollout.enabled=false | findstr "kind: Deployment"
```

Перша команда з `rollout.enabled: true` має показати `kind: Rollout` і `replicas: 4`, друга (з `enabled=false`) повертає `kind: Deployment`.

**Коміт 2:**

```powershell
git add .
git commit -m "feat: replace catalog Deployment with Argo Rollouts canary"
git push
argocd app get library --refresh
kubectl argo rollouts get rollout library-catalog -n library-catalog
kubectl get pods -n library-catalog
```

Під час першого sync Argo CD створює Rollout `library-catalog` і видаляє (prune) однойменний Deployment. Через кілька секунд має бути 4 поди каталогу, статус Rollout `Healthy`.

Для звіту: скрін дерева `library` в Argo CD, де є об'єкт `Rollout` з ReplicaSet, і вивід `kubectl argo rollouts get rollout`.

---

## Пункт 3. Чому обрано canary (для усної відповіді на захисті)

- `catalog-api` без стану: дані лежать у спільній MongoDB, тому стара й нова версії можуть працювати одночасно проти однієї бази.
- Canary дає змогу показати новій версії лише частину реплік (25% → 50% → 75%) і зупинити реліз на проміжному кроці, поки більшість користувачів лишається на стабільній версії.
- Canary не вимагає подвоєння ресурсів: під час релізу додається лише 1 додатковий под (`maxSurge: 1`). Blue-green тримає дві повні копії застосунку (8 подів замість 4-5), що для minikube накладно.
- Для canary у такому варіанті не потрібен окремий ingress-контролер чи service mesh: розподіл навантаження відбувається за співвідношенням подів за одним Service.
- Обмеження: без traffic router розподіл запитів приблизний (визначається співвідношенням подів), а не точний відсоток. Blue-green був би кращим вибором, якби потрібне миттєве перемикання всього трафіку або сумісність зі зміною схеми даних між версіями.

---

## Пункт 4. Реліз через Git

Підготуйте образи нової версії (за потреби, як у ЛР5):

```powershell
docker build --build-arg APP_VERSION=1.3.0 -t vasya1221/catalog-api:1.3.0 ./catalog-api
docker push vasya1221/catalog-api:1.3.0
```

Підготуйте чотири вікна терміналу:

**Вікно 1** (стан реліза в реальному часі):
```powershell
kubectl argo rollouts get rollout library-catalog -n library-catalog -w
```

**Вікно 2** (цикл запитів усередині кластера, підрахунок версій у відповідях):
```powershell
kubectl run curl-test -n library-catalog --rm -it --restart=Never --image=curlimages/curl --command -- sh -c 'for i in $(seq 1 40); do curl -s http://library-catalog:8000/version; echo; done | sort | uniq -c'
```
Результат у вигляді: `30 {"service":"catalog-api","version":"1.2.0"}` і `10 {"service":"catalog-api","version":"1.3.0"}`.

**Вікно 3**: Argo CD (`kubectl port-forward svc/argocd-server -n argocd 8080:443`, відкрити `https://localhost:8080`, застосунок `library`).

**Вікно 4** (дашборд Rollouts, необов'язково): `kubectl argo rollouts dashboard -n library-catalog`, відкрити `http://localhost:3100/rollouts`.

**Реліз.** У `charts/library/values-minikube.yaml` змініть тег **тільки каталогу**: `tag: "1.2.0"` на `tag: "1.3.0"` (у блоці `catalog`), далі:

```powershell
git add .
git commit -m "release: catalog 1.3.0 (canary)"
git push
argocd app get library --refresh
```

Що буде видно:
1. **Крок 25%:** 1 под нової версії і 3 стабільні. Цикл запитів у вікні 2 показує приблизно 1 відповідь з 4 від версії 1.3.0. Далі пауза 30 секунд проходить сама.
2. **Крок 50%, ручна пауза:** 2 пода нової версії і 2 стабільні, співвідношення відповідей приблизно 1:1. Статус Rollout `Paused`, в Argo CD Health застосунку `Suspended`. Тут запустіть цикл запитів і зробіть скрін.
3. Перевірити поди й ReplicaSet:
```powershell
kubectl get pods -n library-catalog -L rollouts-pod-template-hash
kubectl get rs -n library-catalog
```
4. **promote:**
```powershell
kubectl argo rollouts promote library-catalog -n library-catalog
```
Реліз іде до 75%, пауза 30 секунд, далі 100%. Усі 4 поди стають версією 1.3.0, старий ReplicaSet масштабується до 0, статус `Healthy`.
5. Перевірка: повторіть цикл запитів: усі відповіді мають версію 1.3.0.

Для звіту: скрін коміту, скрін CLI з проміжним станом (25% або 50%), результат циклу запитів з обома версіями, скрін Argo CD зі статусом `Suspended` на ручній паузі, результат `promote`, фінальний стан Healthy.

---

## Пункт 5. Скасування релізу (abort) і відкат через Git

Підготуйте ще одну версію:

```powershell
docker build --build-arg APP_VERSION=1.4.0 -t vasya1221/catalog-api:1.4.0 ./catalog-api
docker push vasya1221/catalog-api:1.4.0
```

У `values-minikube.yaml` змініть тег каталогу на `1.4.0`, commit, push, Refresh. Дочекайтеся ручної паузи (50%), після чого:

```powershell
kubectl argo rollouts abort library-catalog -n library-catalog
kubectl argo rollouts get rollout library-catalog -n library-catalog
kubectl get pods -n library-catalog
argocd app get library
```

Очікується:
- canary-поди видалено, усі 4 поди знову працюють на стабільній версії 1.3.0 (цикл запитів показує лише 1.3.0);
- Rollout у стані `Degraded` (повідомлення про abort);
- Argo CD: **Sync Status: Synced, Health Status: Degraded**.

**Чому Synced, але Degraded.** Synced означає, що стан кластера збігається з Git: у Git записано тег 1.4.0, і Rollout з таким тегом існує. Degraded означає, що сам реліз не вдався: його скасовано, нова версія не стала стабільною. Тобто Git каже «має бути 1.4.0», а кластер після abort працює на 1.3.0. Argo CD це розходження не показує як OutOfSync, бо порівнює маніфести, а не те, яка версія реально обслуговує трафік.

**Завершення відкату через Git** (джерелом правди має лишитися Git, тому `kubectl argo rollouts undo` не використовуємо):

```powershell
git revert HEAD --no-edit
git push
argocd app get library --refresh
kubectl argo rollouts get rollout library-catalog -n library-catalog
argocd app get library
git log --oneline
```

Тег у Git знову 1.3.0, збігається зі stable-версією, Rollout повертається у `Healthy`, застосунок у `Synced / Healthy`.

Для звіту: вивід abort, `kubectl argo rollouts get rollout` з Degraded, скрін Argo CD (Synced + Degraded), вивід `git log --oneline` з revert-комітом, скрін Synced / Healthy після відкату.

---

## Захист (пункт 6): сценарій для живої демонстрації

1. Показати Argo CD: `library` Synced / Healthy, Rollout з 4 подами версії 1.2.0 (або 1.3.0).
2. Змінити тег у `values-minikube.yaml`, зробити commit і push, натиснути Refresh.
3. Показати проміжний стан (CLI `get rollout -w`), цикл запитів з двома версіями, статус `Suspended` у Argo CD.
4. Виконати `promote`, показати завершення (100%).
5. Запустити ще один реліз (інший тег), на проміжному кроці виконати `abort`, показати Synced + Degraded і пояснити це.
6. Зробити `git revert HEAD`, push і показати повернення в Healthy.

Підготовка: образи 1.2.0, 1.3.0 і 1.4.0 опубліковані заздалегідь; відкриті `port-forward` Argo CD і вкладка з інтерфейсом; плагін перевірено командою `kubectl argo rollouts version`.

## Типові проблеми

| Симптом | Причина і рішення |
|---|---|
| `no matches for kind "Rollout"` при sync `library` | Контролер/CRD ще не встановлено. Спершу Коміт 1 (контролер), переконатися у наявності CRD; Application `library` також повторює sync (`retry`). |
| `metadata.annotations: Too long` | CRD Argo Rollouts великі, потрібен `ServerSideApply=true` в Application `argo-rollouts` (вже додано). |
| Rollout не рухається далі 50% | Це ручна пауза `pause: {}`: виконайте `kubectl argo rollouts promote`. |
| Новий под у `ImagePullBackOff` | Образ з таким тегом не опубліковано або приватний. Після `progressDeadlineSeconds` Rollout стає Degraded; зробіть `abort` або відкат через Git. |
| Усі відповіді циклу мають одну версію | Цикл запущено на кроці без нової версії (до 25% або після promote). Запускайте його на ручній паузі (50%). |
