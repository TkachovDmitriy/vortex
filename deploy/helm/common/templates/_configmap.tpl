{{/* ---- common/templates/_configmap.tpl ---- */}}

{{- define "common.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Chart.Name }}-config
  labels:
    {{- include "common.labels" . | nindent 4 }}
data:
  {{- range $key := .Values.config | keys | sortAlpha }}
  {{ $key }}: {{ index $.Values.config $key | quote }}
  {{- end }}
{{- end -}}
