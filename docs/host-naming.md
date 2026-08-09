# HMS host naming

Bare-metal nodes use **Royal Navy ship** names plus a **stable 4-hex** suffix derived from the public IP:

```text
hms-<ship>-<4hex>
```

Current production mapping:

| Slot | Public IP | Name |
|------|-----------|------|
| BM01 | 145.239.4.186 | `hms-conqueror-30bd` |
| BM02 | 145.239.255.21 | `hms-vengeful-4d19` |
| BM03 | 51.89.153.125 | `hms-dreadnought-3623` |

Inventory still uses `BM01_*` / `BM02_*` / `BM03_*` as **slots**; only `BM0N_NAME` holds the HMS hostname.

Regenerate a suffix:

```bash
python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:4])' <public-ip>
```

Rename live nodes with [`scripts/bare-metal/rename-nodes-hms.sh`](../scripts/bare-metal/rename-nodes-hms.sh) (OS hostname + kubeadm rejoin), then update Rook `storage_nodes` in tfvars to match.
