<#
  ЛР7: керування демонстрацією. Кожна дія - одна команда.

  Запуск (з будь-якої папки):
    powershell -ExecutionPolicy Bypass -File .\scripts\lab7-demo.ps1 -Action <дія>

  Дії:
    status           стан застосунків Argo CD, подів, Rollout і AnalysisRun
    ui               відкрити Grafana, Prometheus, Alertmanager і Argo CD (port-forward + браузер)
    load-start       запустити генератор навантаження (-Rate запитів/с, типово 30)
    load-stop        зупинити генератор навантаження
    enable-analysis  увімкнути автоматичний аналіз метрик (commit + push)
    bad-release      поганий реліз: FAIL_RATE=0.5 (commit + push)
    revert           відкат через git revert останнього коміту (commit + push)
    watch            стежити за Rollout у реальному часі
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "ui", "load-start", "load-stop", "enable-analysis", "bad-release", "revert", "watch")]
    [string]$Action,
    [int]$Rate = 30,
    [string]$Branch = "gitops"
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ValuesFile = Join-Path $ProjectRoot "charts\library\values-minikube.yaml"
$env:Path += ";C:\Program Files\Kubernetes\Minikube;$env:LOCALAPPDATA\Microsoft\WinGet\Links"

function Run {
    param([string]$Cmd)
    Write-Host ">> $Cmd" -ForegroundColor Cyan
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Команда завершилась з помилкою ($LASTEXITCODE): $Cmd" }
}

function Edit-Values {
    param([string]$Pattern, [string]$Replacement)
    $text = [IO.File]::ReadAllText($ValuesFile)
    if ($text -notmatch $Pattern) { throw "У values-minikube.yaml не знайдено очікуваний рядок: $Pattern" }
    $text = [regex]::Replace($text, $Pattern, $Replacement)
    [IO.File]::WriteAllText($ValuesFile, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Commit-Push {
    param([string]$Message)
    Run "git -C `"$ProjectRoot`" switch $Branch"
    Run "git -C `"$ProjectRoot`" add -- charts"
    Run "git -C `"$ProjectRoot`" commit -m `"$Message`""
    Run "git -C `"$ProjectRoot`" push"
    Refresh
}

function Refresh {
    # оновити Argo CD одразу, не чекаючи 3 хвилини
    kubectl annotate application root -n argocd argocd.argoproj.io/refresh=hard --overwrite | Out-Null
    kubectl annotate application library -n argocd argocd.argoproj.io/refresh=hard --overwrite | Out-Null
    Write-Host "Argo CD оновлюється. Стежити: lab7-demo.ps1 -Action watch" -ForegroundColor Green
}

switch ($Action) {
    "status" {
        kubectl get applications -n argocd
        kubectl get pods -n library-catalog
        kubectl get rollout,analysisrun -n library-catalog
        kubectl get pods -n monitoring
    }
    "ui" {
        $forwards = @(
            "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80",
            "kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090",
            "kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093",
            "kubectl port-forward -n argocd svc/argocd-server 8080:443"
        )
        foreach ($f in $forwards) {
            Start-Process powershell -ArgumentList "-NoExit", "-Command", $f
        }
        Start-Sleep -Seconds 5
        Start-Process "http://localhost:3000"
        Start-Process "http://localhost:9090/targets"
        Start-Process "http://localhost:9093"
        Start-Process "https://localhost:8080"
        Write-Host "Відкрито 4 вікна port-forward. Не закривай їх під час демонстрації." -ForegroundColor Green
    }
    "load-start" {
        kubectl delete job loadgen -n library-catalog --ignore-not-found | Out-Null
        $src = [IO.File]::ReadAllText((Join-Path $ProjectRoot "loadtest\loadgen.yaml"))
        $src = [regex]::Replace($src, '(?s)(name: RATE\s*\r?\n\s*value: )"\d+"', ('$1"' + $Rate + '"'))
        $tmp = Join-Path $env:TEMP "loadgen-run.yaml"
        [IO.File]::WriteAllText($tmp, $src, (New-Object System.Text.UTF8Encoding $false))
        Run "kubectl apply -f `"$tmp`""
        Write-Host "Навантаження запущено: $Rate запитів/с." -ForegroundColor Green
    }
    "load-stop" {
        Run "kubectl delete job loadgen -n library-catalog --ignore-not-found"
    }
    "enable-analysis" {
        Edit-Values '(analysis:\s*\r?\n\s*enabled: )false' '${1}true'
        Commit-Push "feat: enable canary analysis"
    }
    "bad-release" {
        Edit-Values 'failRate: "0"' 'failRate: "0.5"'
        Commit-Push "release: catalog with FAIL_RATE=0.5 (bad)"
        Write-Host "Поганий реліз запушено. Тепер: lab7-demo.ps1 -Action watch" -ForegroundColor Yellow
    }
    "revert" {
        Run "git -C `"$ProjectRoot`" switch $Branch"
        Run "git -C `"$ProjectRoot`" revert HEAD --no-edit"
        Run "git -C `"$ProjectRoot`" push"
        Refresh
        Run "git -C `"$ProjectRoot`" log --oneline -5"
    }
    "watch" {
        Run "kubectl argo rollouts get rollout library-catalog -n library-catalog -w"
    }
}
