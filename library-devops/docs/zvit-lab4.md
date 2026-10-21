# Звіт до ЛР№4: Helm-чарт

Проєкт: library-devops (catalog-api, reviews-api, MongoDB). Чарт: `chart/`, назва `library`, namespace `library-catalog`.
Середовище: Windows 11, Docker Desktop, minikube (Kubernetes v1.37.0), Helm v4.3.0.
Нижче наведено реальний вивід команд, виконаних 12.10.2026.

---

## Підготовка (п.1)

```powershell
helm version
kubectl get nodes
kubectl delete -f k8s/
kubectl get ns
```
```text
version.BuildInfo{Version:"v4.3.0", GitCommit:"bec5b06ed841fe5269972d864d5177944fd5970f", GitTreeState:"clean", GoVersion:"go1.27.1", KubeClientVersion:"v1.37"}

NAME       STATUS   ROLES           AGE     VERSION
minikube   Ready    control-plane   6d15h   v1.37.0

namespace "library-catalog" deleted
configmap "app-config" deleted from library-catalog namespace
secret "mongo-secret" deleted from library-catalog namespace
persistentvolumeclaim "mongo-pvc" deleted from library-catalog namespace
deployment.apps "mongo" deleted from library-catalog namespace
service "mongo" deleted from library-catalog namespace
deployment.apps "catalog-api" deleted from library-catalog namespace
service "catalog-api" deleted from library-catalog namespace
deployment.apps "reviews-api" deleted from library-catalog namespace
service "reviews-api" deleted from library-catalog namespace
ingress.networking.k8s.io "library-ingress" deleted from library-catalog namespace

NAME              STATUS   AGE
default           Active   6d15h
kube-node-lease   Active   6d15h
kube-public       Active   6d15h
kube-system       Active   6d15h
```
Реліз з ЛР№3 видалено, namespace `library-catalog` зник, конфлікту імен немає. Встановлено Helm 4.3.0 (у завданні згадано Helm 3): чарт має `apiVersion: v2`, який працює в обох версіях.

---

## Пункт 6. Два середовища

### 6a. Файли значень
`chart/values-dev.yaml` і `chart/values-prod.yaml` перекривають `values.yaml` (за замовчуванням це dev).

| Параметр | dev | prod |
|---|---|---|
| Репліки catalog | 1 | 3 |
| Репліки reviews | 1 | 2 |
| Ресурси catalog (requests / limits) | 50m, 64Mi / 200m, 128Mi | 100m, 128Mi / 300m, 256Mi |
| Ресурси reviews (requests / limits) | 50m, 64Mi / 200m, 128Mi | 100m, 128Mi / 300m, 256Mi |
| Тег образу catalog | 1.1.0 | 1.0.0 |
| Ingress | вимкнено | увімкнено (`library.local`) |
| Пароль MongoDB | демо-значення у values.yaml | порожній, передається через `--set` |

### 6b. Різниця середовищ без встановлення в кластер
```powershell
helm template library chart/ -n library-catalog -f chart/values-dev.yaml | Out-File -Encoding utf8 dev.yaml
helm template library chart/ -n library-catalog -f chart/values-prod.yaml --set secret.mongoRootPassword=x | Out-File -Encoding utf8 prod.yaml
Compare-Object (Get-Content dev.yaml) (Get-Content prod.yaml)
```
`helm template` лише рендерить маніфести локально й нічого не створює в кластері. Вивід порівняння (скорочено): `=>` рядок є тільки в prod, `<=` тільки в dev.
```text
InputObject                                                                                   SideIndicator
  MONGO_ROOT_PASSWORD: "x"                                                                    =>
  MONGO_URI: "mongodb://admin:x@library-mongo:27017/library?authSource=admin"                 =>
  replicas: 3                                                                                 =>
          image: "vasya1221/catalog-api:1.0.0"                                                =>
              cpu: 300m                                                                       =>
              memory: 256Mi                                                                   =>
              cpu: 100m                                                                       =>
  replicas: 2                                                                                 =>
              cpu: 300m                                                                       =>
              memory: 256Mi                                                                   =>
              cpu: 100m                                                                       =>
# Source: library/templates/ingress.yaml                                                      =>
kind: Ingress                                                                                 =>
    - host: "library.local"                                                                   =>
  ... (решта рядків об'єкта Ingress, він є лише в prod) ...
  MONGO_ROOT_PASSWORD: "dev-demo-password"                                                    <=
  MONGO_URI: "mongodb://admin:dev-demo-password@library-mongo:27017/library?authSource=admin" <=
  replicas: 1                                                                                 <=
          image: "vasya1221/catalog-api:1.1.0"                                                <=
              cpu: 200m                                                                       <=
              cpu: 50m                                                                        <=
              memory: 64Mi                                                                    <=
  replicas: 1                                                                                 <=
              cpu: 200m                                                                       <=
              cpu: 50m                                                                        <=
              memory: 64Mi                                                                    <=
```
Середовища відрізняються кількістю реплік, ресурсами, тегом образу catalog та наявністю Ingress, а також паролем.
Примітка: `Compare-Object` порівнює рядки як множину, тому значення, що збігаються з іншим місцем файлу (наприклад, `memory: 128Mi` у dev), у виводі не показані. Повний перелік різниць дає таблиця 6a.

### 6c. Пріоритет значень
Від найнижчого до найвищого: `values.yaml` чарта → файли `-f` (чим правіше в команді, тим вищий пріоритет) → `--set`.

Перевірка: dev-файл задає тег catalog `1.1.0`, а `--set` його перекриває.
```powershell
helm template library chart/ -n library-catalog -f chart/values-dev.yaml --set catalog.image.tag=1.0.0 | findstr "image:"
```
```text
          image: "vasya1221/catalog-api:1.0.0"
          image: "mongo:7"
          image: "vasya1221/reviews-api:1.0.0"
      image: busybox:1.36
          image: busybox:1.36
```
Без `--set` тег catalog у dev був би `1.1.0` (див. 6b), з `--set` став `1.0.0`: `--set` має найвищий пріоритет.

---

## Пункт 7. Перевірка та встановлення

### 7a. Перевірка на помилки
```powershell
helm lint chart/
```
```text
==> Linting chart/
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```
Помилок немає. Єдине інформаційне повідомлення стосується необов'язкового поля `icon`.

### 7b. Порівняння з маніфестами ЛР№3
```powershell
helm template library chart/ -n library-catalog -f chart/values-dev.yaml
```
Шаблон згенерував такі об'єкти (за рядками `# Source:`): `secret`, `configmap`, `mongo-pvc`, `catalog-service`, `mongo-service`, `reviews-service`, `catalog-deployment`, `mongo-deployment`, `reviews-deployment`, а також `tests/test-connection` (Pod для `helm test`) і `hooks/pre-upgrade-job` (Job-хук). Ingress у dev не створюється, бо `ingress.enabled: false`.

Порівняння з `k8s/` з ЛР№3:
- Той самий набір об'єктів: ConfigMap, Secret, PVC, 3 Deployment, 3 Service і Ingress (у prod). Namespace Helm не створює сам, його створює `--create-namespace`.
- Назви складаються з імені релізу: `library-catalog`, `library-reviews`, `library-mongo`, `library-config`, `library-secret` (раніше `catalog-api`, `reviews-api`, `mongo`, `app-config`, `mongo-secret`). Тому чарт можна встановити двічі під різними іменами релізу.
- Мітки `app: ...` замінені на стандартні `app.kubernetes.io/*`.
- Репліки, образи, ресурси, ConfigMap і Secret беруться з `.Values`, пароль у шаблоні не зберігається.

### 7c. Встановлення
```powershell
helm install library chart/ -n library-catalog --create-namespace -f chart/values-dev.yaml
kubectl get pods -n library-catalog
```
```text
NAME: library
LAST DEPLOYED: Mon Oct 12 14:57:55 2026
NAMESPACE: library-catalog
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
Реліз "library" встановлено в namespace "library-catalog".

Як відкрити застосунок:

  Ingress вимкнено. Використайте port-forward:

  kubectl port-forward -n library-catalog svc/library-catalog 8001:8000
  kubectl port-forward -n library-catalog svc/library-reviews 8002:8000

  Потім відкрийте http://localhost:8001/docs та http://localhost:8002/docs

Перевірити реліз:  helm test library -n library-catalog

NAME                               READY   STATUS              RESTARTS   AGE
library-catalog-5cf96b8d85-ckrv8   0/1     ContainerCreating   0          1s
library-mongo-599b4f6876-vqp97     0/1     Pending             0          1s
library-reviews-6f47b7547d-qlbwg   0/1     ContainerCreating   0          1s
```
Знімок подів зроблено через 1 секунду після встановлення, тому поди ще створюються. Через ~75 секунд усі три були `1/1 Running` (див. вивід `kubectl get pods,ingress` у 8b).

### 7d. Реліз, статус і значення
```powershell
helm list -n library-catalog
helm status library -n library-catalog
helm get values library -n library-catalog
```
```text
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART           APP VERSION
library library-catalog 1               2026-10-12 14:57:55.3571875 +0300 EEST  deployed        library-0.1.0   1.0.0

NAME: library
STATUS: deployed
REVISION: 1
RESOURCES:
==> v1/Deployment      library-catalog, library-mongo, library-reviews
==> v1/Secret          library-secret (DATA 3)
==> v1/ConfigMap       library-config (DATA 2)
==> v1/PersistentVolumeClaim   library-mongo   Bound   pvc-3ca95005-...   1Gi   RWO   standard
==> v1/Service         library-catalog, library-mongo, library-reviews (ClusterIP)

USER-SUPPLIED VALUES:
catalog:
  image:
    tag: 1.1.0
  replicaCount: 1
  resources:
    limits:
      cpu: 200m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi
ingress:
  enabled: false
reviews:
  replicaCount: 1
```
`helm get values` показує лише значення, передані користувачем через `-f` і `--set`. Решта береться зі `values.yaml` (повний набір показує `helm get values --all`). PVC має статус `Bound`, тобто том для MongoDB створено.

### 7e. Де Helm зберігає стан релізу
```powershell
kubectl get secrets -n library-catalog -l owner=helm
```
```text
NAME                            TYPE                 DATA   AGE
sh.helm.release.v1.library.v1   helm.sh/release.v1   1      1s
```
Helm зберігає кожну ревізію релізу як Secret типу `helm.sh/release.v1` з іменем `sh.helm.release.v1.<реліз>.v<ревізія>` у namespace релізу. У ньому лежать стиснуті маніфести, значення та метадані ревізії. Саме звідси беруться `helm history` і `helm rollback`.

---

## Пункт 8. Життєвий цикл релізу

### 8a. Оновлення тега через --set
```powershell
helm upgrade library chart/ -n library-catalog -f chart/values-dev.yaml --set catalog.image.tag=1.0.0
```
```text
Release "library" has been upgraded. Happy Helming!
NAME: library
LAST DEPLOYED: Mon Oct 12 14:59:04 2026
NAMESPACE: library-catalog
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
```
Ревізія 2: змінився лише тег образу catalog (з 1.1.0 на 1.0.0), тому Kubernetes перестворює тільки поди catalog.

### 8b. Оновлення з файлом іншого середовища
```powershell
helm upgrade library chart/ -n library-catalog -f chart/values-prod.yaml --set secret.mongoRootPassword=dev-demo-password
kubectl get pods,ingress -n library-catalog
```
```text
Release "library" has been upgraded. Happy Helming!
LAST DEPLOYED: Mon Oct 12 14:59:08 2026
STATUS: deployed
REVISION: 3
DESCRIPTION: Upgrade complete

NAME                                   READY   STATUS              RESTARTS   AGE
pod/library-catalog-5cf96b8d85-ckrv8   1/1     Running             0          77s
pod/library-catalog-5cf96b8d85-kkl9l   0/1     Terminating         0          1s
pod/library-catalog-754f5d6b85-l62n2   0/1     ContainerCreating   0          0s
pod/library-catalog-7dc44f65b-fkdm6    0/1     Running             0          5s
pod/library-catalog-7dc44f65b-n279l    0/1     ContainerCreating   0          1s
pod/library-mongo-599b4f6876-vqp97     1/1     Running             0          77s
pod/library-reviews-6f47b7547d-qlbwg   1/1     Running             0          77s
pod/library-reviews-6f47b7547d-x5vtk   0/1     ContainerCreating   0          1s
pod/library-reviews-7c7968f467-wq5bw   0/1     ContainerCreating   0          1s

NAME                                CLASS   HOSTS           ADDRESS   PORTS   AGE
ingress.networking.k8s.io/library   nginx   library.local             80      1s
```
Ревізія 3: збільшилась кількість реплік (catalog 3, reviews 2), змінились ресурси, створився Ingress `library`. Знімок зроблено під час rolling update: частина подів ще `ContainerCreating`, старі `Terminating`. Пароль MongoDB переданий той самий, що в dev, бо база задає пароль root лише при першому створенні тому.

### 8c. Історія ревізій
```powershell
helm history library -n library-catalog
```
```text
REVISION        UPDATED                         STATUS          CHART           APP VERSION     DESCRIPTION
1               Mon Oct 12 14:57:55 2026        superseded      library-0.1.0   1.0.0           Install complete
2               Mon Oct 12 14:59:04 2026        superseded      library-0.1.0   1.0.0           Upgrade complete
3               Mon Oct 12 14:59:08 2026        deployed        library-0.1.0   1.0.0           Upgrade complete
```
| Ревізія | Що змінилося |
|---|---|
| 1 | встановлення з `values-dev.yaml`: catalog 1.1.0, по 1 репліці, Ingress вимкнено |
| 2 | `--set catalog.image.tag=1.0.0`: змінився тег образу catalog |
| 3 | перехід на `values-prod.yaml`: репліки 3 і 2, більші ресурси, створено Ingress |

Колонка `APP VERSION` однакова (1.0.0), бо це `appVersion` з `Chart.yaml`: вона не залежить від тега образу, який ми перекриваємо через values.

### 8d. Відкат
```powershell
helm rollback library 1 -n library-catalog
helm history library -n library-catalog
```
```text
Rollback was a success! Happy Helming!

REVISION        UPDATED                         STATUS          CHART           APP VERSION     DESCRIPTION
1               Mon Oct 12 14:57:55 2026        superseded      library-0.1.0   1.0.0           Install complete
2               Mon Oct 12 14:59:04 2026        superseded      library-0.1.0   1.0.0           Upgrade complete
3               Mon Oct 12 14:59:08 2026        superseded      library-0.1.0   1.0.0           Upgrade complete
4               Mon Oct 12 14:59:12 2026        deployed        library-0.1.0   1.0.0           Rollback to 1
```
Відкат не видаляє історію: Helm створив нову ревізію 4 з вмістом ревізії 1 (`Rollback to 1`), а ревізія 3 стала `superseded`. Поточний стан відповідає dev-конфігурації: 1 репліка, Ingress прибрано.

### 8e. Видалення однією командою
```powershell
helm uninstall library -n library-catalog
kubectl get all,cm,secret,pvc,ingress -n library-catalog
```
```text
release "library" uninstalled

NAME                                   READY   STATUS        RESTARTS   AGE
pod/library-catalog-5cf96b8d85-ckrv8   0/1     Completed     0          90s
pod/library-catalog-7dc44f65b-n279l    1/1     Terminating   0          14s
pod/library-reviews-6f47b7547d-qlbwg   1/1     Terminating   0          90s
pod/library-reviews-6f47b7547d-x5vtk   1/1     Terminating   0          14s
pod/library-reviews-7c7968f467-wq5bw   1/1     Terminating   0          14s

NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      90s
```
Helm видалив усі об'єкти релізу (Deployment, Service, Secret, ConfigMap, PVC). Поди на знімку мають статус `Terminating`: Kubernetes завершує їх із затримкою (graceful shutdown), після чого вони зникають. `kube-root-ca.crt` створює сам Kubernetes у кожному namespace, до чарта він не належить.

---

## Пункт 9b. Хук і тест релізу

### Тест релізу
Файл `chart/templates/tests/test-connection.yaml`: Pod з анотацією `helm.sh/hook: test`, що робить `wget` на `/health` обох сервісів.
```powershell
helm test library -n library-catalog
```
```text
NAME: library
LAST DEPLOYED: Mon Oct 12 14:57:55 2026
NAMESPACE: library-catalog
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE:     library-test
Last Started:   Mon Oct 12 14:58:16 2026
Last Completed: Mon Oct 12 14:58:33 2026
Phase:          Succeeded
```
Тест пройшов (`Phase: Succeeded`): обидва сервіси відповіли на `/health`.

### Хук pre-upgrade
Файл `chart/templates/hooks/pre-upgrade-job.yaml`: Job з анотацією `helm.sh/hook: pre-upgrade`. Перед кожним `helm upgrade` він перевіряє, що Service MongoDB відповідає (`nc -z`). Якби перевірка не пройшла, `helm upgrade` завершився б помилкою й оновлення не відбулося б. Політика `hook-succeeded` видаляє успішний Job, тому після оновлення його в кластері немає.

Підтвердження: усі три оновлення (8a, 8b і відкат у 8d) завершилися `Upgrade complete` / `Rollback was a success`, тобто хук щоразу відпрацьовував успішно. Сам Job окремим знімком не зафіксовано.
