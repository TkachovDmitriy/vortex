{{/* ---- common/templates/_service.tpl ---- */}}

{{- define "common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Chart.Name }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  selector:
    {{- include "common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      protocol: {{ .Values.service.protocol | default "TCP" }}
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort | default .Values.port }}
{{- end -}}
