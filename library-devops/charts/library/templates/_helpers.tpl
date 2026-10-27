{{/* Коротке ім'я чарта */}}
{{- define "library.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Повне ім'я об'єктів: <реліз>-<чарт>, щоб чарт можна було встановити двічі */}}
{{- define "library.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Назва та версія чарта для мітки helm.sh/chart */}}
{{- define "library.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Спільний набір міток (приймає кореневий контекст) */}}
{{- define "library.labels" -}}
helm.sh/chart: {{ include "library.chart" . }}
app.kubernetes.io/name: {{ include "library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Мітки-селектор для компонента: dict "root" . "component" "catalog" */}}
{{- define "library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "library.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Назва Secret: наявний (existingSecret) або створений чартом */}}
{{- define "library.secretName" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "library.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Pod template каталогу: єдине джерело і для Deployment, і для Rollout.
Тому при перемиканні catalog.rollout.enabled змінюється лише тип об'єкта, а не вміст пода.
*/}}
{{- define "library.catalog.podTemplate" -}}
metadata:
  labels:
    {{- include "library.selectorLabels" (dict "root" . "component" "catalog") | nindent 4 }}
spec:
  containers:
    - name: catalog-api
      image: "{{ .Values.catalog.image.repository }}:{{ .Values.catalog.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      ports:
        - containerPort: 8000
      envFrom:
        - configMapRef:
            name: {{ include "library.fullname" . }}-config
      env:
        - name: MONGO_URI
          valueFrom:
            secretKeyRef:
              name: {{ include "library.secretName" . }}
              key: MONGO_URI
      resources:
        {{- toYaml .Values.catalog.resources | nindent 8 }}
      readinessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 5
        periodSeconds: 5
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 10
        periodSeconds: 10
{{- end }}
