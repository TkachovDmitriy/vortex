{{/* ---- common/templates/_helpers.tpl ---- */}}

{{/* common.labels — the full recommended label set. */}}
{{- define "common.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
  common.selectorLabels — the IMMUTABLE subset only.
  No version here: selectors can't change across upgrades.
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
