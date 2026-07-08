{{/* ---- common/templates/_deployment.tpl ---- */}}

{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.labels" . | nindent 8 }}
    spec:
      {{- with .Values.initContainers }}
      initContainers:
        {{- range . }}
        - image: "{{ if $.Values.global.imageRegistry }}{{ $.Values.global.imageRegistry }}/{{ end }}{{ .image }}"
          {{- toYaml (omit . "image") | nindent 10 }}
        {{- end }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ if .Values.global.imageRegistry }}{{ .Values.global.imageRegistry }}/{{ end }}{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ .Values.port }}
          {{- if or .Values.config .Values.secret }}
          envFrom:
            {{- if .Values.config }}
            - configMapRef:
                name: {{ .Chart.Name }}-config
            {{- end }}
            {{- if .Values.secret }}
            - secretRef:
                name: {{ .Chart.Name }}-secret
            {{- end }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
{{- end -}}
