# Token: set GITLAB_TOKEN, or TF_VAR_gitlab_token / -var gitlab_token=...
# Do not pass an empty token string — that overrides env fallback.
provider "gitlab" {
  base_url = var.gitlab_base_url
  token    = var.gitlab_token != "" ? var.gitlab_token : null
}
