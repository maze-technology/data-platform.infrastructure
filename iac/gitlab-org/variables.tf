variable "state_encryption_passphrase" {
  description = "Client-side AES-GCM passphrase for remote state (same as production)"
  type        = string
  sensitive   = true
}

variable "gitlab_base_url" {
  description = "GitLab API base URL"
  type        = string
  default     = "https://scm.maze.trading/api/v4"
}

variable "gitlab_token" {
  description = "GitLab API token with api scope (prefer GITLAB_TOKEN env; empty keeps env fallback)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_groups_enabled" {
  description = "When false, skip creating org groups (no resources)"
  type        = bool
  default     = true
}
