variable "environment_name" {
  description = "Name of the environment"
  type        = string
  default     = "retail-store"
}

variable "istio_enabled" {
  description = "Boolean value that enables istio."
  type        = bool
  default     = false
}

variable "opentelemetry_enabled" {
  description = "Boolean value that enables OpenTelemetry."
  type        = bool
  default     = false
}

variable "manage_kubernetes_resources" {
  description = "When true, the module will create Kubernetes (k8s/helm) resources. Set to false for control-plane-only apply." 
  type    = bool
  default = false
}
