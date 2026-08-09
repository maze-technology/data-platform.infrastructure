# HMS host naming

Bare-metal nodes use **Royal Navy ship** names plus a **stable 4-hex** suffix derived from the public IP:

```text
hms-<ship>-<4hex>
```

Current production mapping (OS hostname **and** Kubernetes Node name):

| Slot | Public IP | Private IP | Name |
|------|-----------|------------|------|
| BM01 | 145.239.4.186 | 192.168.10.1 | `hms-conqueror-30bd` |
| BM02 | 145.239.255.21 | 192.168.10.2 | `hms-vengeful-4d19` |
| BM03 | 51.89.153.125 | 192.168.10.3 | `hms-dreadnought-3623` |

Inventory still uses `BM01_*` / `BM02_*` / `BM03_*` as **slots**; `BM0N_NAME` / `BM0N_SSH` hold the HMS hostname and SSH target (public IP from the management VPS).

Regenerate a suffix:

```bash
python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:4])' <public-ip>
```

## Rename procedure

1. OS hostname + `/etc/hosts`: [`scripts/bare-metal/rename-nodes-hms.sh`](../scripts/bare-metal/rename-nodes-hms.sh)
2. Lower Ceph pool `size` to 2 for the rename window (size=3 blocks I/O with one OSD down).
3. Per node, oldest first if possible — **not** the current `controlPlaneEndpoint` host last without retargeting API:
   [`scripts/bare-metal/rename-k8s-node-hms.sh`](../scripts/bare-metal/rename-k8s-node-hms.sh) `bm-0N hms-… <ssh> <private-ip>`
4. After each rename: update Rook `storage_nodes`, purge the old crush host/OSD if it stays bound to the old name, wait for 3 OSDs up.
5. Before renaming the node that owns `controlPlaneEndpoint` (historically `192.168.10.1`): point kubectl/`cluster-info` at another CP, then restore the endpoint after rejoin.
6. Restore pool `size` to 3; set `storage_nodes` in `terraform.tfvars` to the three HMS names and `tofu apply` Rook if needed.
