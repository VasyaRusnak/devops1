# Звіт до ЛР№3: Розгортання в Kubernetes

Проєкт: `library-devops` (catalog-api + reviews-api + MongoDB), namespace `library-catalog`.

Для кожного пункту: виконай команду(и) в PowerShell → зроби скріншот вікна з результатом
(або скопіюй текстовий вивід) → встав замість `[СКРІН / ВИВІД]`.

---

## 5. Розгорнути застосунок

### 5a. Застосувати всі маніфести однією командою

```powershell
kubectl apply -f k8s/
```

[СКРІН / ВИВІД]

### 5b. Перелік створених об'єктів: поди, Deployment, ReplicaSet, Service

```powershell
kubectl get pods,deployment,replicaset,service -n library-catalog
```

[СКРІН / ВИВІД]

### 5c. Застосунок працює в браузері

```powershell
kubectl port-forward -n library-catalog svc/catalog-api 8001:8000
```

Відкрити в браузері `http://localhost:8001/docs` — зробити запит `GET /books` прямо
зі Swagger UI, показати відповідь 200.

[СКРІН браузера зі Swagger + відповіддю]

### 5d. Значення з ConfigMap і Secret справді потрапили в контейнер

```powershell
kubectl exec -n library-catalog deploy/catalog-api -- env | findstr "DB_NAME LOG_LEVEL MONGO_URI"
kubectl logs -n library-catalog deploy/catalog-api | findstr "DB_NAME"
```

[СКРІН / ВИВІД]

---

## 6. Керування життєвим циклом

### 6a. Самовідновлення

```powershell
kubectl get pods -n library-catalog -l app=catalog-api
# скопіювати ім'я одного пода з виводу вище і підставити нижче:
kubectl delete pod -n library-catalog <ІМ'Я_ПОДА>
kubectl get pods -n library-catalog -l app=catalog-api
```

[СКРІН до видалення] [СКРІН після — новий под з'явився автоматично]

### 6b. Масштабування

```powershell
kubectl scale deployment catalog-api -n library-catalog --replicas=4
kubectl get pods -n library-catalog -l app=catalog-api -o wide
```

[СКРІН: 4 поди, розподілені по статусу Running]

### 6c. Оновлення на другу версію (rolling update)

```powershell
kubectl set image deployment/catalog-api catalog-api=<ТВІЙ_ОБРАЗ>:1.1.0 -n library-catalog
kubectl rollout status deployment/catalog-api -n library-catalog
```

[СКРІН процесу rollout]

### 6d. Історія оновлень та відкат

```powershell
kubectl rollout history deployment/catalog-api -n library-catalog
kubectl rollout undo deployment/catalog-api -n library-catalog
kubectl rollout status deployment/catalog-api -n library-catalog
```

[СКРІН історії ревізій] [СКРІН відкату]

### 6e. Доступність під час оновлення

В окремому вікні PowerShell запустити цикл опитування **перед** командою з 6c і
лишити працювати під час оновлення:

```powershell
while ($true) { try { (Invoke-WebRequest -Uri http://localhost:8001/health -UseBasicParsing).StatusCode } catch { "ERR" }; Start-Sleep -Seconds 1 }
```

[СКРІН логу запитів під час rolling update — коди 200 без перерви]

---

## 7. Діагностика

### 7a. Навмисно неіснуючий тег образу

```powershell
kubectl set image deployment/catalog-api catalog-api=<ТВІЙ_ОБРАЗ>:9.9.9-not-exist -n library-catalog
kubectl get pods -n library-catalog
```

[СКРІН: STATUS = ImagePullBackOff / ErrImagePull]

### 7b. Причина — опис пода та Events

```powershell
kubectl describe pod -n library-catalog <ІМ'Я_ПОДА_З_ПОМИЛКОЮ>
```

[СКРІН розділу Events з описом причини]

### 7c. Логи та вхід у контейнер

```powershell
kubectl logs -n library-catalog deploy/reviews-api
kubectl exec -it -n library-catalog deploy/reviews-api -- /bin/sh
```

[СКРІН логів] [СКРІН інтерактивної сесії всередині контейнера]

### 7d. Виправлення

```powershell
kubectl set image deployment/catalog-api catalog-api=<ТВІЙ_ОБРАЗ>:1.1.0 -n library-catalog
kubectl rollout status deployment/catalog-api -n library-catalog
kubectl get pods -n library-catalog
```

[СКРІН: усі поди знову Running]

---

## Параметри ConfigMap і Secret (для п.8b, вже є в основному README)

| Джерело | Ключ | Призначення |
|---|---|---|
| ConfigMap `app-config` | `DB_NAME` | назва бази MongoDB |
| ConfigMap `app-config` | `LOG_LEVEL` | рівень логування застосунку |
| Secret `mongo-secret` | `MONGO_ROOT_USERNAME` | логін адміністратора Mongo |
| Secret `mongo-secret` | `MONGO_ROOT_PASSWORD` | пароль адміністратора Mongo |
| Secret `mongo-secret` | `MONGO_URI` | рядок підключення з обліковими даними |
