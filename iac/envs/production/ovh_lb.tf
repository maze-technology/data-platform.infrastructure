# OVH Public Cloud Load Balancer — public surface is WireGuard UDP only.
# App HTTPS is VPN-internal (ingress ClusterIP via CoreDNS); ACME uses DNS-01.

data "ovh_cloud_project_network_privates" "all" {
  service_name = local.ovh_project
}

locals {
  ovh_private_network_id = [
    for n in data.ovh_cloud_project_network_privates.all.networks :
    n.id if n.name == var.ovh_private_network_name
  ][0]
}

data "ovh_cloud_project_network_private" "maze" {
  service_name = local.ovh_project
  network_id   = local.ovh_private_network_id
}

data "ovh_cloud_project_network_private_subnets" "maze" {
  service_name = local.ovh_project
  network_id   = data.ovh_cloud_project_network_private.maze.network_id
}

data "ovh_cloud_project_loadbalancer_flavors" "region" {
  service_name = local.ovh_project
  region_name  = var.ovh_lb_region
}

locals {
  ovh_lb_openstack_network_id = data.ovh_cloud_project_network_private.maze.regions_openstack_ids[var.ovh_lb_region]

  ovh_lb_subnet_id = [
    for s in data.ovh_cloud_project_network_private_subnets.maze.subnets : s.id
    if length([for p in s.ip_pools : p if p.region == var.ovh_lb_region]) > 0
  ][0]

  ovh_lb_flavor_id = [
    for f in data.ovh_cloud_project_loadbalancer_flavors.region.flavors :
    f.id if f.name == var.ovh_lb_flavor_name
  ][0]

  ovh_lb_members = [
    for node in var.ovh_lb_backend_nodes : {
      name          = node.name
      address       = node.private_ip
      protocol_port = var.wireguard_node_port
      weight        = 1
    }
  ]
}

resource "ovh_cloud_project_loadbalancer" "vpn" {
  count = var.ovh_lb_enabled ? 1 : 0

  service_name = local.ovh_project
  region_name  = var.ovh_lb_region
  flavor_id    = local.ovh_lb_flavor_id
  name         = var.ovh_lb_name
  description  = "maze.trading — WireGuard UDP only (VPN-only public surface)"

  network = {
    private = {
      network = {
        id        = local.ovh_lb_openstack_network_id
        subnet_id = local.ovh_lb_subnet_id
      }
      floating_ip = {
        id = var.ovh_lb_floating_ip_id
      }
      gateway = {
        id = var.ovh_lb_gateway_id
      }
    }
  }

  listeners = [
    {
      name     = "wireguard-udp"
      port     = var.wireguard_node_port
      protocol = "udp"
      pool = {
        name      = "wireguard-nodes"
        protocol  = "udp"
        algorithm = "roundRobin"
        # Members are attached post-create (OVH rejects bare-metal vRack IPs at create).
        members = []
      }
    }
  ]
}

# OVH validates create-time members against OpenStack allocations; bare-metal
# vRack IPs must be attached afterward (same approach as the previous manual LB).
resource "null_resource" "ovh_lb_wireguard_members" {
  count = var.ovh_lb_enabled ? 1 : 0

  triggers = {
    lb_id   = ovh_cloud_project_loadbalancer.vpn[0].id
    members = jsonencode(local.ovh_lb_members)
    port    = tostring(var.wireguard_node_port)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OVH_ENDPOINT         = var.ovh_endpoint != "" ? var.ovh_endpoint : "ovh-eu"
      OVH_CLOUD_PROJECT_ID = var.ovh_cloud_project_id
      OVH_LB_REGION        = var.ovh_lb_region
      OVH_LB_ID            = ovh_cloud_project_loadbalancer.vpn[0].id
      OVH_LB_MEMBERS_JSON  = jsonencode(local.ovh_lb_members)
    }
    command = <<-EOT
      set -euo pipefail
      # Credentials from process env (Makefile / .env): OVH_APPLICATION_KEY/SECRET/CONSUMER_KEY
      : "$${OVH_APPLICATION_KEY:?}" "$${OVH_APPLICATION_SECRET:?}" "$${OVH_CONSUMER_KEY:?}"
      VENV="$(mktemp -d)/venv"
      python3 -m venv "$VENV"
      "$VENV/bin/pip" -q install ovh
      "$VENV/bin/python" - <<'PY'
import json, os, time
import ovh

c = ovh.Client(
    endpoint=os.environ.get("OVH_ENDPOINT", "ovh-eu"),
    application_key=os.environ["OVH_APPLICATION_KEY"],
    application_secret=os.environ["OVH_APPLICATION_SECRET"],
    consumer_key=os.environ["OVH_CONSUMER_KEY"],
)
project = os.environ["OVH_CLOUD_PROJECT_ID"]
region = os.environ["OVH_LB_REGION"]
lb = os.environ["OVH_LB_ID"]
wanted = json.loads(os.environ["OVH_LB_MEMBERS_JSON"])

pool_id = None
for _ in range(60):
    pools = c.get(f"/cloud/project/{project}/region/{region}/loadbalancing/pool")
    for p in pools:
        if p.get("loadbalancerId") == lb and p.get("name") == "wireguard-nodes":
            pool_id = p["id"]
            break
    if pool_id:
        break
    time.sleep(5)
if not pool_id:
    raise SystemExit("wireguard-nodes pool not found")

existing = c.get(f"/cloud/project/{project}/region/{region}/loadbalancing/pool/{pool_id}/member")
have = {m["address"] for m in existing}
to_add = [m for m in wanted if m["address"] not in have]
if not to_add:
    print("all members already present")
else:
    print(f"adding {len(to_add)} members")
    c.call(
        "POST",
        f"/cloud/project/{project}/region/{region}/loadbalancing/pool/{pool_id}/member",
        {"members": [
            {
                "name": m["name"],
                "address": m["address"],
                "protocolPort": m["protocol_port"],
                "weight": m.get("weight", 1),
            }
            for m in to_add
        ]},
        True,
    )
print("wireguard members ok")
PY
    EOT
  }

  depends_on = [ovh_cloud_project_loadbalancer.vpn]
}
