{{/*
Expand the name of the chart.
*/}}
{{- define "bjj-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "bjj-api.fullname" -}}
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
{{- define "bjj-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "bjj-api.labels" -}}
helm.sh/chart: {{ include "bjj-api.chart" . }}
{{ include "bjj-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bjj-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bjj-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "bjj-api.serviceAccountName" -}}
{{- if .Values.api.serviceAccount.create }}
{{- default (include "bjj-api.fullname" .) .Values.api.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.api.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
MongoDB URI without password — password injected via $(MONGO_PASSWORD) env expansion.
*/}}
{{- define "bjj-api.mongodb.uriTemplate" -}}
mongodb://{{ .Values.mongodb.config.user }}:$(MONGO_PASSWORD)@{{ .Values.mongodb.config.host }}:{{ .Values.mongodb.config.port }}/{{ .Values.mongodb.config.database }}?authSource=admin&authMechanism=SCRAM-SHA-256
{{- end }}
