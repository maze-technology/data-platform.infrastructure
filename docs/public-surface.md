# Public attack surface (VPN-only)

**Rule:** the only service intentionally reachable from the public internet is **WireGuard UDP**. No public HTTP/HTTPS, no public Git SSH, no public registry.

## What is public

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `vpn.<domain>` → OVH LB floating IP | UDP (WireGuard NodePort, e.g. 31820) | Join the cluster VPN |

Managed in OpenTofu (`ovh_lb.tf`): listeners must stay WireGuard-only.

## What is VPN-internal

| Name | How clients reach it |
|------|----------------------|
| `scm.<domain>`, `auth.<domain>`, `crates.<domain>`, … | Split-DNS `~<domain>` → CoreDNS → ingress ClusterIP |
| `git-ssh.<domain>` | CoreDNS → `gitlab-gitlab-shell` ClusterIP (git over SSH) |
| `registry.scm.<domain>` | VPN + CoreDNS (Envoy or ingress, as configured) |

Bare-metal SSH to node private IPs (`192.168.10.x`) also requires VPN (`AllowedIPs` includes the vRack CIDR).

## Git over SSH (operators)

```sshconfig
Host scm.maze.trading
  IdentityFile ~/.ssh/scm.maze.trading
  HostName git-ssh.maze.trading
  Port 22
```

Do **not** expose gitlab-shell or `scm:22` on the public LB to “make git work without VPN”.

## AI / change checklist

Before adding any load balancer port, NodePort, or public DNS A record:

1. Is it WireGuard UDP? If no → **reject** unless there is an explicit, reviewed exception.
2. Prefer VPN peer access or in-cluster Service DNS.
3. Update this doc if the public surface ever changes (it should not grow).
