{{/*
Expand the name of the chart.
*/}}
{{- define "node-maintenance-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "node-maintenance-operator.fullname" -}}
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
{{- define "node-maintenance-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "node-maintenance-operator.labels" -}}
helm.sh/chart: {{ include "node-maintenance-operator.chart" . }}
{{ include "node-maintenance-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.additionalLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "node-maintenance-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "node-maintenance-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
control-plane: controller-manager
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "node-maintenance-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s-controller-manager" (include "node-maintenance-operator.fullname" .)) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the namespace to use
*/}}
{{- define "node-maintenance-operator.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Create image name with registry
*/}}
{{- define "node-maintenance-operator.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.image.repository }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Create proxy image name with registry
*/}}
{{- define "node-maintenance-operator.proxyImage" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.proxy.image.repository }}
{{- $tag := .Values.proxy.image.tag }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "node-maintenance-operator.annotations" -}}
{{- with .Values.additionalAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Webhook service name
*/}}
{{- define "node-maintenance-operator.webhookServiceName" -}}
{{- printf "%s-webhook-service" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Create webhook certificate secret name
*/}}
{{- define "node-maintenance-operator.webhookCertSecret" -}}
{{- printf "%s-webhook-server-cert" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Create webhook certificate name
*/}}
{{- define "node-maintenance-operator.webhookCertName" -}}
{{- printf "%s-serving-cert" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Manager role name
*/}}
{{- define "node-maintenance-operator.managerRoleName" -}}
{{- printf "%s-manager-role" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Manager role binding name
*/}}
{{- define "node-maintenance-operator.managerRoleBindingName" -}}
{{- printf "%s-manager-rolebinding" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Leader election role name
*/}}
{{- define "node-maintenance-operator.leaderElectionRoleName" -}}
{{- printf "%s-leader-election-role" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Leader election role binding name
*/}}
{{- define "node-maintenance-operator.leaderElectionRoleBindingName" -}}
{{- printf "%s-leader-election-rolebinding" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Proxy role name
*/}}
{{- define "node-maintenance-operator.proxyRoleName" -}}
{{- printf "%s-proxy-role" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Proxy role binding name
*/}}
{{- define "node-maintenance-operator.proxyRoleBindingName" -}}
{{- printf "%s-proxy-rolebinding" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Proxy client cluster role name
*/}}
{{- define "node-maintenance-operator.proxyClientClusterRoleName" -}}
{{- printf "%s-metrics-reader" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Proxy service name
*/}}
{{- define "node-maintenance-operator.proxyServiceName" -}}
{{- printf "%s-controller-manager-metrics-service" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
ValidatingWebhookConfiguration name
*/}}
{{- define "node-maintenance-operator.validatingWebhookName" -}}
{{- printf "%s-validating-webhook-configuration" (include "node-maintenance-operator.fullname" .) }}
{{- end }}

{{/*
Create operator arguments
*/}}
{{- define "node-maintenance-operator.args" -}}
{{- $args := list }}
{{- if .Values.leaderElection.enabled }}
{{- $args = append $args "--leader-elect" }}
{{- end }}
{{- if .Values.proxy.enabled }}
{{- $args = append $args "--health-probe-bind-address=:8081" }}
{{- $args = append $args "--metrics-bind-address=127.0.0.1:8080" }}
{{- else }}
{{- $args = append $args "--health-probe-bind-address=:8081" }}
{{- $args = append $args "--metrics-bind-address=:8080" }}
{{- end }}
{{- range .Values.operator.args }}
{{- $args = append $args . }}
{{- end }}
{{- toYaml $args }}
{{- end }} 