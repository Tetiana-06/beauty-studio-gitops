# _helpers.tpl — це файл зі спільними шаблонами-функціями у Helm-чарті. Іншими шаблонами їх можна викликати повторно.
# Як він працює
# - Підкреслення на початку (_) означає для Helm, що з цього файлу не треба генерувати Kubernetes-маніфест.
# Файли deployment.yaml, service.yaml тощо перетворюються на ресурси, а _helpers.tpl лише зберігає визначення.
{{/*
Expand the name of the chart.
*/}}
{{- define "beauty-studio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "beauty-studio.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "beauty-studio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels required by standard conventions and Додаток А
*/}}
{{- define "beauty-studio.labels" -}}
helm.sh/chart: {{ include "beauty-studio.chart" . }}
{{ include "beauty-studio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
student: tetiana
mascot: tetiana
{{- end }}

{{/*
Common annotations required by Додаток А
*/}}
{{- define "beauty-studio.annotations" -}}
devops-lab/mascot-approved: "true"
student: "tetiana"
mascot: "tetiana"
{{- end }}

{{/*
Ім'я Secret з паролем БД.
Якщо задано database.auth.existingSecret — беремо готовий Secret, створений вручну (пароля немає в Git).
Інакше — Secret, який створює сам чарт (templates/secret.yaml).
*/}}
{{- define "beauty-studio.secretName" -}}
{{- if .Values.database.auth.existingSecret }}
{{- .Values.database.auth.existingSecret }}
{{- else }}
{{- include "beauty-studio.fullname" . }}-secret
{{- end }}
{{- end }}

{{/*
Selector labels for general chart resources
*/}}
{{- define "beauty-studio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beauty-studio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Backend specific selector labels
*/}}
{{- define "beauty-studio.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beauty-studio.name" . }}-backend
app.kubernetes.io/instance: {{ .Release.Name }}
app: backend
{{- end }}

{{/*
Frontend specific selector labels
*/}}
{{- define "beauty-studio.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beauty-studio.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
app: frontend
{{- end }}

{{/*
Database specific selector labels
*/}}
{{- define "beauty-studio.database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beauty-studio.name" . }}-db
app.kubernetes.io/instance: {{ .Release.Name }}
app: postgres
{{- end }}
