{{/*
Expand the name of the chart.
*/}}
{{- define "ecom-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ecom-frontend.fullname" -}}
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

{{- define "ecom-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ecom-frontend.labels" -}}
helm.sh/chart: {{ include "ecom-frontend.chart" . }}
{{ include "ecom-frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ecom
{{- end }}

{{- define "ecom-frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ecom-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ecom-frontend.frontendSelectorLabels" -}}
{{ include "ecom-frontend.selectorLabels" . }}
app.kubernetes.io/component: frontend
app: ecom-frontend
{{- end }}

{{- define "ecom-frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ecom-frontend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "ecom-frontend.postgres.fullname" -}}
{{- printf "%s-postgres" (include "ecom-frontend.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ecom-frontend.redis.fullname" -}}
{{- printf "%s-redis" (include "ecom-frontend.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ecom-frontend.secretName" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecret }}
{{- else }}
{{- printf "%s-app" (include "ecom-frontend.fullname" .) }}
{{- end }}
{{- end }}

{{- define "ecom-frontend.configMapName" -}}
{{- printf "%s-app" (include "ecom-frontend.fullname" .) }}
{{- end }}

{{- define "ecom-frontend.databaseUrl" -}}
{{- if .Values.database.url }}
{{- .Values.database.url }}
{{- else if .Values.postgres.enabled }}
{{- printf "postgresql://%s:%s@%s:%v/%s" .Values.postgres.auth.username .Values.postgres.auth.password (include "ecom-frontend.postgres.fullname" .) .Values.postgres.service.port .Values.postgres.auth.database }}
{{- end }}
{{- end }}

{{- define "ecom-frontend.redisUrl" -}}
{{- if .Values.cache.url }}
{{- .Values.cache.url }}
{{- else if .Values.redis.enabled }}
{{- printf "redis://%s:%v" (include "ecom-frontend.redis.fullname" .) .Values.redis.service.port }}
{{- end }}
{{- end }}
