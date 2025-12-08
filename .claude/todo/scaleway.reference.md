# Scaleway API Reference Documentation

## 1. Authentication

- **Base URL**: `https://api.scaleway.com`
- **Auth Header**: `X-Auth-Token: <secret_key>` (NOT Bearer token)
- **Content-Type**: `application/json`

## 2. API Structure

Scaleway uses **zoned** and **regional** APIs:

```
# Zoned APIs (Instances, Block Storage)
https://api.scaleway.com/instance/v1/zones/{zone}/servers
https://api.scaleway.com/block/v1alpha1/zones/{zone}/volumes

# Regional APIs (VPC/Private Networks)
https://api.scaleway.com/vpc/v2/regions/{region}/private-networks
```

### Zones
- `fr-par-1`, `fr-par-2`, `fr-par-3`
- `nl-ams-1`, `nl-ams-2`, `nl-ams-3`
- `pl-waw-1`, `pl-waw-2`, `pl-waw-3`

### Regions
- `fr-par` (Paris)
- `nl-ams` (Amsterdam)
- `pl-waw` (Warsaw)

### Zone to Region Mapping
- `fr-par-1`, `fr-par-2`, `fr-par-3` → `fr-par`
- `nl-ams-1`, `nl-ams-2`, `nl-ams-3` → `nl-ams`
- `pl-waw-1`, `pl-waw-2`, `pl-waw-3` → `pl-waw`

---

## 3. Servers (Instances) API

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List servers | GET | `/instance/v1/zones/{zone}/servers` |
| Get server | GET | `/instance/v1/zones/{zone}/servers/{id}` |
| Create server | POST | `/instance/v1/zones/{zone}/servers` |
| Delete server | DELETE | `/instance/v1/zones/{zone}/servers/{id}` |
| Server action | POST | `/instance/v1/zones/{zone}/servers/{id}/action` |
| List server types | GET | `/instance/v1/zones/{zone}/products/servers` |
| List images | GET | `/instance/v1/zones/{zone}/images` |

### Create Server Request Body

```json
{
  "name": "my-server",
  "commercial_type": "DEV1-S",
  "image": "881d7a33-4cfa-4046-b5cf-c33cb9c62fb6",
  "project": "697ef834-9bd0-4181-ae29-b0bcd0e574ae",
  "enable_ipv6": false,
  "boot_type": "local",
  "tags": ["tag1", "tag2"],
  "security_group": "sg-uuid"
}
```

### Server Response Structure

```json
{
  "server": {
    "id": "uuid",
    "name": "my-server",
    "state": "running",
    "commercial_type": "DEV1-S",
    "public_ip": {
      "id": "ip-uuid",
      "address": "51.15.x.x",
      "dynamic": false
    },
    "private_ip": null,
    "volumes": {},
    "security_group": {
      "id": "sg-uuid",
      "name": "sg-name"
    },
    "tags": [],
    "zone": "fr-par-1"
  }
}
```

### Server States
- `stopped`
- `stopping`
- `starting`
- `running`
- `locked`

### Server Action Request

```json
{
  "action": "poweron"
}
```

Available actions: `poweron`, `poweroff`, `reboot`, `terminate`

### List Server Types Response

```json
{
  "servers": {
    "DEV1-S": {
      "monthly_price": 0.0,
      "hourly_price": 0.0,
      "alt_names": [],
      "per_volume_constraint": {
        "l_ssd": {
          "min_size": 20000000000,
          "max_size": 80000000000
        }
      },
      "volumes_constraint": {
        "min_size": 20000000000,
        "max_size": 80000000000
      },
      "ncpus": 2,
      "ram": 2147483648,
      "arch": "x86_64",
      "baremetal": false
    }
  }
}
```

### Common Commercial Types
- `DEV1-S`, `DEV1-M`, `DEV1-L`, `DEV1-XL`
- `GP1-XS`, `GP1-S`, `GP1-M`, `GP1-L`, `GP1-XL`
- `PRO2-XXS`, `PRO2-XS`, `PRO2-S`, `PRO2-M`, `PRO2-L`

---

## 4. Security Groups API

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List | GET | `/instance/v1/zones/{zone}/security_groups` |
| Get | GET | `/instance/v1/zones/{zone}/security_groups/{id}` |
| Create | POST | `/instance/v1/zones/{zone}/security_groups` |
| Update | PUT | `/instance/v1/zones/{zone}/security_groups/{id}` |
| Delete | DELETE | `/instance/v1/zones/{zone}/security_groups/{id}` |
| List rules | GET | `/instance/v1/zones/{zone}/security_groups/{id}/rules` |
| Create rule | POST | `/instance/v1/zones/{zone}/security_groups/{id}/rules` |
| Delete rule | DELETE | `/instance/v1/zones/{zone}/security_groups/{id}/rules/{rule_id}` |

### Create Security Group Request

```json
{
  "name": "my-firewall",
  "description": "SSH access",
  "organization": "org-uuid",
  "project": "project-uuid",
  "stateful": true,
  "inbound_default_policy": "drop",
  "outbound_default_policy": "accept",
  "enable_default_security": true
}
```

### Security Group Response

```json
{
  "security_group": {
    "id": "uuid",
    "name": "my-firewall",
    "description": "SSH access",
    "enable_default_security": true,
    "inbound_default_policy": "drop",
    "outbound_default_policy": "accept",
    "organization": "org-uuid",
    "project": "project-uuid",
    "stateful": true,
    "state": "available",
    "servers": [],
    "zone": "fr-par-1"
  }
}
```

### Create Rule Request

```json
{
  "protocol": "TCP",
  "direction": "inbound",
  "action": "accept",
  "ip_range": "0.0.0.0/0",
  "dest_port_from": 22,
  "dest_port_to": 22,
  "position": 1,
  "editable": true
}
```

### Rule Protocols
- `TCP`
- `UDP`
- `ICMP`
- `ANY`

### Rule Directions
- `inbound`
- `outbound`

### Rule Actions
- `accept`
- `drop`

---

## 5. Private Networks (VPC) API

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List | GET | `/vpc/v2/regions/{region}/private-networks` |
| Get | GET | `/vpc/v2/regions/{region}/private-networks/{id}` |
| Create | POST | `/vpc/v2/regions/{region}/private-networks` |
| Update | PATCH | `/vpc/v2/regions/{region}/private-networks/{id}` |
| Delete | DELETE | `/vpc/v2/regions/{region}/private-networks/{id}` |

### Create Private Network Request

```json
{
  "name": "my-network",
  "project_id": "project-uuid",
  "subnets": ["10.0.1.0/24"],
  "vpc_id": "vpc-uuid",
  "tags": ["tag1"]
}
```

### Private Network Response

```json
{
  "id": "pn-uuid",
  "name": "my-network",
  "organization_id": "org-uuid",
  "project_id": "project-uuid",
  "region": "fr-par",
  "subnets": [
    {
      "id": "subnet-uuid",
      "subnet": "10.0.1.0/24",
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    }
  ],
  "vpc_id": "vpc-uuid",
  "dhcp_enabled": true,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "tags": []
}
```

### List Response

```json
{
  "private_networks": [...],
  "total_count": 1
}
```

---

## 6. Private NICs API (Instance to Network Attachment)

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List | GET | `/instance/v1/zones/{zone}/servers/{server_id}/private_nics` |
| Get | GET | `/instance/v1/zones/{zone}/servers/{server_id}/private_nics/{nic_id}` |
| Create | POST | `/instance/v1/zones/{zone}/servers/{server_id}/private_nics` |
| Update | PATCH | `/instance/v1/zones/{zone}/servers/{server_id}/private_nics/{nic_id}` |
| Delete | DELETE | `/instance/v1/zones/{zone}/servers/{server_id}/private_nics/{nic_id}` |

### Create Private NIC Request

```json
{
  "private_network_id": "pn-uuid",
  "ip_ids": []
}
```

### Private NIC Response

```json
{
  "private_nic": {
    "id": "nic-uuid",
    "server_id": "server-uuid",
    "private_network_id": "pn-uuid",
    "mac_address": "02:00:00:00:00:01",
    "state": "available",
    "tags": []
  }
}
```

### Private NIC States
- `available`
- `syncing`
- `syncing_error`

---

## 7. Block Storage API

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List | GET | `/block/v1alpha1/zones/{zone}/volumes` |
| Get | GET | `/block/v1alpha1/zones/{zone}/volumes/{id}` |
| Create | POST | `/block/v1alpha1/zones/{zone}/volumes` |
| Update | PATCH | `/block/v1alpha1/zones/{zone}/volumes/{id}` |
| Delete | DELETE | `/block/v1alpha1/zones/{zone}/volumes/{id}` |

### Create Volume Request

```json
{
  "name": "my-volume",
  "perf_iops": 5000,
  "from_empty": {
    "size": 53687091200
  },
  "project_id": "project-uuid",
  "tags": []
}
```

### Volume Response

```json
{
  "id": "vol-uuid",
  "name": "my-volume",
  "type": "sbs_5k",
  "size": 53687091200,
  "project_id": "project-uuid",
  "zone": "fr-par-1",
  "specs": {
    "perf_iops": 5000,
    "class": "sbs"
  },
  "status": "available",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "references": [],
  "parent_snapshot_id": null,
  "tags": []
}
```

### Volume IOPS Options
- `5000` - Standard
- `15000` - High performance

### Volume Statuses
- `unknown_status`
- `creating`
- `available`
- `in_use`
- `deleting`
- `error`
- `snapshotting`
- `resizing`
- `locked`

### Attaching Volumes to Instances

Volume attachment is done via Instance API by updating the server's volumes:

```
PATCH /instance/v1/zones/{zone}/servers/{server_id}
```

```json
{
  "volumes": {
    "0": {
      "id": "root-volume-uuid"
    },
    "1": {
      "id": "block-volume-uuid"
    }
  }
}
```

**Important Notes:**
- Since April 2024, Block API cannot create volumes attached to instances
- Volumes must be attached via Instance API
- Include ALL volumes (including root) when updating

---

## 8. VPC API

### Endpoints

| Operation | Method | Path |
|-----------|--------|------|
| List | GET | `/vpc/v2/regions/{region}/vpcs` |
| Get | GET | `/vpc/v2/regions/{region}/vpcs/{id}` |
| Create | POST | `/vpc/v2/regions/{region}/vpcs` |
| Update | PATCH | `/vpc/v2/regions/{region}/vpcs/{id}` |
| Delete | DELETE | `/vpc/v2/regions/{region}/vpcs/{id}` |

### Create VPC Request

```json
{
  "name": "my-vpc",
  "project_id": "project-uuid",
  "tags": [],
  "enable_routing": true
}
```

### VPC Response

```json
{
  "id": "vpc-uuid",
  "name": "my-vpc",
  "organization_id": "org-uuid",
  "project_id": "project-uuid",
  "region": "fr-par",
  "tags": [],
  "is_default": false,
  "routing_enabled": true,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "private_network_count": 0
}
```

---

## 9. Error Response Format

```json
{
  "type": "invalid_request_error",
  "message": "Validation Error",
  "fields": {
    "name": ["name is required"]
  }
}
```

### HTTP Status Codes
- `200` - Success
- `201` - Created
- `204` - No Content (successful delete)
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `409` - Conflict
- `422` - Unprocessable Entity
- `429` - Rate Limited
- `500` - Internal Server Error

---

## 10. Pagination

List endpoints support pagination:

```
GET /instance/v1/zones/{zone}/servers?page=1&per_page=50
```

Response includes:
```json
{
  "servers": [...],
  "total_count": 100
}
```

---

## 11. Sources

- [Scaleway Instance API](https://www.scaleway.com/en/developers/api/instances/)
- [Scaleway VPC API](https://www.scaleway.com/en/developers/api/vpc/)
- [Scaleway Block Storage API](https://www.scaleway.com/en/developers/api/block/)
- [Scaleway CLI - Instance](https://cli.scaleway.com/instance/)
- [Scaleway CLI - VPC](https://cli.scaleway.com/vpc/)
- [Scaleway CLI - Block](https://cli.scaleway.com/block/)
- [Security Groups API Reference](https://bump.sh/demo/hub/scaleway-developers/doc/instance-v1/group/endpoint-security-groups)
- [Scaleway API Overview](https://www.scaleway.com/en/developers/api/)
