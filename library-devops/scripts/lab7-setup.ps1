<#
  ЛР7: одноразова підготовка. Робить усе з кроків 1-4 runbook одним запуском:
  перевірка інструментів, секрет Grafana, збірка і push образів, тести, коміт і push у гілку gitops.

  Запуск (з будь-якої папки):
    powershell -ExecutionPolicy Bypass -File .\scripts\lab7-setup.ps1
#>
param(
    [string]$DockerUser = "vasya1221",
    [string]$Version = "1.4.0",
    [string]$Branch = "gitops",
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$SkipGit
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$env:Path += ";C:\Program Files\Kubernetes\Minikube;$env:LOCALAPPDATA\Microsoft\WinGet\Links"

function Run {
    param([string]$Cmd)
    Write-Host ">> $Cmd" -ForegroundColor Cyan
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Команда завершилась з помилкою ($LASTEXITCODE): $Cmd" }
}

function Step { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Green }

Step "1/6 Перевірка інструментів і кластера"
foreach ($tool in @("docker", "kubectl", "helm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Не знайдено '$tool' у PATH" }
}
Run "kubectl get nodes"
$mem = kubectl get node -o jsonpath="{.items[0].status.allocatable.memory}"
Write-Host "Пам'ять вузла (allocatable): $mem (бажано від 5 000 000 Ki)"

Step "2/6 Репозиторії Helm і версії чартів (для інформації)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
helm repo add grafana-community https://grafana-community.github.io/helm-charts | Out-Null
helm repo add grafana https://grafana.github.io/helm-charts | Out-Null
helm repo update | Out-Null
helm search repo prometheus-community/kube-prometheus-stack --versions | Select-Object -First 3
helm search repo grafana-community/loki --versions | Select-Object -First 3
helm search repo grafana/alloy --versions | Select-Object -First 3
Write-Host "Якщо версії відрізняються від targetRevision у argocd-apps/*.yaml, виправ їх у файлах."

Step "3/6 Секрет Grafana (namespace monitoring)"
kubectl get namespace monitoring *> $null
if ($LASTEXITCODE -ne 0) { Run "kubectl create namespace monitoring" }
kubectl get secret grafana-admin -n monitoring *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Секрет grafana-admin вже існує, пропускаю."
} else {
    $secure = Read-Host "Придумай пароль для Grafana (латиниця і цифри)" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    kubectl create secret generic grafana-admin -n monitoring --from-literal=admin-user=admin "--from-literal=admin-password=$plain"
    if ($LASTEXITCODE -ne 0) { throw "Не вдалося створити секрет grafana-admin" }
    Write-Host "Секрет створено. Логін Grafana: admin, пароль - той, що ти ввів."
}

Step "4/6 Тести і перевірка чарта"
if ($SkipTests) {
    Write-Host "Пропущено (-SkipTests)"
} else {
    foreach ($svc in @("catalog-api", "reviews-api")) {
        Push-Location (Join-Path $ProjectRoot $svc)
        Run "ruff check app tests"
        Run "pytest -q"
        Pop-Location
    }
}
Run "helm lint `"$ProjectRoot\charts\library`" -f `"$ProjectRoot\charts\library\values-minikube.yaml`""

Step "5/6 Образи $Version (збірка і push у Docker Hub)"
if ($SkipBuild) {
    Write-Host "Пропущено (-SkipBuild)"
} else {
    foreach ($svc in @("catalog-api", "reviews-api")) {
        Run "docker build --build-arg APP_VERSION=$Version -t $DockerUser/${svc}:$Version `"$ProjectRoot\$svc`""
        Run "docker push $DockerUser/${svc}:$Version"
    }
}

Step "6/6 Коміт і push у гілку $Branch"
if ($SkipGit) {
    Write-Host "Пропущено (-SkipGit)"
} else {
    # теги образів у values-minikube.yaml мають збігатися з версією
    $values = Join-Path $ProjectRoot "charts\library\values-minikube.yaml"
    $text = [IO.File]::ReadAllText($values)
    $text = $text -replace 'tag: "[^"]+"', ('tag: "' + $Version + '"')
    [IO.File]::WriteAllText($values, $text, (New-Object System.Text.UTF8Encoding $false))

    Run "git -C `"$ProjectRoot`" switch $Branch"
    Run "git -C `"$ProjectRoot`" add -- . ':(exclude).github'"
    git -C "$ProjectRoot" diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Немає змін для коміту."
    } else {
        Run "git -C `"$ProjectRoot`" commit -m `"feat: observability stack, app metrics, JSON logs, dashboard`""
        Run "git -C `"$ProjectRoot`" push"
    }
    kubectl annotate application root -n argocd argocd.argoproj.io/refresh=hard --overwrite
}

Write-Host "`nГотово. Далі стежи за станом:" -ForegroundColor Green
Write-Host "  kubectl get applications -n argocd"
Write-Host "  kubectl get pods -n monitoring"
Write-Host "Відкрити інтерфейси: .\scripts\lab7-demo.ps1 -Action ui"
