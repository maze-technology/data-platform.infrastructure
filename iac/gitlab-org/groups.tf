# Org-wide GitLab groups mirroring former GitHub teams.
# Memberships intentionally omitted — Keycloak SSO / OIDC will populate later.
# Empty groups only; do not put this in infrastructure-base.

locals {
  create = var.gitlab_groups_enabled
}

# Parent: engineers (may already exist as OIDC ACL roster from gitlab-ci-cosign —
# import if so: tofu import 'gitlab_group.engineers[0]' engineers)
resource "gitlab_group" "engineers" {
  count = local.create ? 1 : 0

  name             = "engineers"
  path             = "engineers"
  description      = "Maze Engineers"
  visibility_level = "private"

  # Allow tofu-managed subgroups; projects stay out of the roster parent.
  project_creation_level  = "maintainer"
  subgroup_creation_level = "owner"
  request_access_enabled  = false
}

resource "gitlab_group" "infrastructure_engineers" {
  count = local.create ? 1 : 0

  name             = "infrastructure-engineers"
  path             = "infrastructure-engineers"
  description      = "Maze Infrastructure engineers"
  visibility_level = "private"
  parent_id        = gitlab_group.engineers[0].id

  request_access_enabled = false
}

resource "gitlab_group" "release_engineers" {
  count = local.create ? 1 : 0

  name             = "release-engineers"
  path             = "release-engineers"
  description      = "Maze Release engineers"
  visibility_level = "private"
  parent_id        = gitlab_group.engineers[0].id

  request_access_enabled = false
}

resource "gitlab_group" "project_managers" {
  count = local.create ? 1 : 0

  name             = "project-managers"
  path             = "project-managers"
  description      = "Maze Project managers"
  visibility_level = "private"

  request_access_enabled = false
}
