# Scaleway Provider Implementation Guide

## Overview

This document provides implementation details for creating a Scaleway provider that conforms to the existing `Nvoi::Providers::Base` interface.

## Files to Create

```
lib/nvoi/providers/
├── scaleway.rb          # Main provider class
└── scaleway_client.rb   # HTTP client for Scaleway API
```

---

## 1. ScalewayClient (`lib/nvoi/providers/scaleway_client.rb`)

### Class Structure

```ruby
# frozen_string_literal: true

require "faraday"
require "json"

module Nvoi
  module Providers
    class ScalewayClient
      INSTANCE_API_BASE = "https://api.scaleway.com/instance/v1"
      VPC_API_BASE = "https://api.scaleway.com/vpc/v2"
      BLOCK_API_BASE = "https://api.scaleway.com/block/v1alpha1"

      def initialize(secret_key, project_id, zone: "fr-par-1")
        @secret_key = secret_key
        @project_id = project_id
        @zone = zone
        @region = zone_to_region(zone)
        @conn = build_connection
      end

      # ... methods below
    end
  end
end
```

### Required Methods

#### HTTP Helpers

```ruby
def get(url)
def post(url, payload = {})
def patch(url, payload = {})
def delete(url)
def handle_response(response)
```

#### Server Methods

```ruby
def list_servers
  # GET /instance/v1/zones/{zone}/servers
  # Returns: array of server hashes

def get_server(id)
  # GET /instance/v1/zones/{zone}/servers/{id}
  # Returns: server hash

def create_server(payload)
  # POST /instance/v1/zones/{zone}/servers
  # Payload: { name:, commercial_type:, image:, project:, security_group:, tags: }
  # Returns: server hash

def delete_server(id)
  # DELETE /instance/v1/zones/{zone}/servers/{id}

def server_action(id, action)
  # POST /instance/v1/zones/{zone}/servers/{id}/action
  # Payload: { action: "poweron" | "poweroff" | "terminate" }
```

#### Server Type / Image Methods

```ruby
def list_server_types
  # GET /instance/v1/zones/{zone}/products/servers
  # Returns: hash of server_type_name => details

def list_images(name: nil, arch: "x86_64")
  # GET /instance/v1/zones/{zone}/images?name={name}&arch={arch}
  # Returns: array of image hashes
```

#### Security Group Methods

```ruby
def list_security_groups
  # GET /instance/v1/zones/{zone}/security_groups
  # Returns: array of security_group hashes

def get_security_group(id)
  # GET /instance/v1/zones/{zone}/security_groups/{id}

def create_security_group(payload)
  # POST /instance/v1/zones/{zone}/security_groups
  # Payload: { name:, project:, stateful:, inbound_default_policy:, outbound_default_policy: }

def delete_security_group(id)
  # DELETE /instance/v1/zones/{zone}/security_groups/{id}

def create_security_group_rule(security_group_id, payload)
  # POST /instance/v1/zones/{zone}/security_groups/{id}/rules
  # Payload: { protocol:, direction:, action:, ip_range:, dest_port_from:, dest_port_to: }
```

#### Private Network Methods (Regional - VPC API)

```ruby
def list_private_networks
  # GET /vpc/v2/regions/{region}/private-networks
  # Returns: array of private_network hashes

def get_private_network(id)
  # GET /vpc/v2/regions/{region}/private-networks/{id}

def create_private_network(payload)
  # POST /vpc/v2/regions/{region}/private-networks
  # Payload: { name:, project_id:, subnets: ["10.0.1.0/24"] }

def delete_private_network(id)
  # DELETE /vpc/v2/regions/{region}/private-networks/{id}
```

#### Private NIC Methods (Zoned - Instance API)

```ruby
def list_private_nics(server_id)
  # GET /instance/v1/zones/{zone}/servers/{server_id}/private_nics

def create_private_nic(server_id, private_network_id)
  # POST /instance/v1/zones/{zone}/servers/{server_id}/private_nics
  # Payload: { private_network_id: }

def delete_private_nic(server_id, nic_id)
  # DELETE /instance/v1/zones/{zone}/servers/{server_id}/private_nics/{nic_id}
```

#### Volume Methods (Zoned - Block API)

```ruby
def list_volumes
  # GET /block/v1alpha1/zones/{zone}/volumes

def get_volume(id)
  # GET /block/v1alpha1/zones/{zone}/volumes/{id}

def create_volume(payload)
  # POST /block/v1alpha1/zones/{zone}/volumes
  # Payload: { name:, perf_iops:, from_empty: { size: }, project_id: }

def delete_volume(id)
  # DELETE /block/v1alpha1/zones/{zone}/volumes/{id}

def update_server_volumes(server_id, volumes_hash)
  # PATCH /instance/v1/zones/{zone}/servers/{server_id}
  # Payload: { volumes: { "0": { id: }, "1": { id: } } }
```

#### Helper Methods

```ruby
private

def zone_to_region(zone)
  # "fr-par-1" => "fr-par"
  zone.split("-")[0..1].join("-")
end

def instance_url(path)
  "#{INSTANCE_API_BASE}/zones/#{@zone}#{path}"
end

def vpc_url(path)
  "#{VPC_API_BASE}/regions/#{@region}#{path}"
end

def block_url(path)
  "#{BLOCK_API_BASE}/zones/#{@zone}#{path}"
end

def build_connection
  Faraday.new do |f|
    f.request :json
    f.response :json
    f.headers["X-Auth-Token"] = @secret_key
    f.headers["Content-Type"] = "application/json"
  end
end
```

---

## 2. Scaleway Provider (`lib/nvoi/providers/scaleway.rb`)

### Class Structure

```ruby
# frozen_string_literal: true

require_relative "scaleway_client"

module Nvoi
  module Providers
    class Scaleway < Base
      def initialize(secret_key, project_id, zone: "fr-par-1")
        @client = ScalewayClient.new(secret_key, project_id, zone: zone)
        @project_id = project_id
        @zone = zone
      end

      # ... interface methods below
    end
  end
end
```

### Interface Method Implementations

#### Network Operations

```ruby
def find_or_create_network(name)
  # 1. List private networks, find by name
  # 2. If found, return to_network(network)
  # 3. If not found, create with:
  #    - name: name
  #    - project_id: @project_id
  #    - subnets: [Constants::SUBNET_CIDR]
  # 4. Return to_network(created_network)
end

def get_network_by_name(name)
  # 1. List private networks, find by name
  # 2. Raise NetworkError if not found
  # 3. Return to_network(network)
end

def delete_network(id)
  # 1. First detach all resources (list servers, check private_nics)
  # 2. Delete private network
  # NOTE: Network must have no attached resources before deletion
end
```

#### Firewall Operations

```ruby
def find_or_create_firewall(name)
  # 1. List security groups, find by name
  # 2. If found, return to_firewall(sg)
  # 3. If not found, create security group:
  #    - name: name
  #    - project: @project_id
  #    - stateful: true
  #    - inbound_default_policy: "drop"
  #    - outbound_default_policy: "accept"
  # 4. Add SSH rule (port 22, TCP, inbound, accept, 0.0.0.0/0)
  # 5. Return to_firewall(created_sg)
end

def get_firewall_by_name(name)
  # 1. List security groups, find by name
  # 2. Raise FirewallError if not found
  # 3. Return to_firewall(sg)
end

def delete_firewall(id)
  # DELETE security group
  # NOTE: Cannot delete if servers are using it
end
```

#### Server Operations

```ruby
def find_server(name)
  # 1. List servers, find by name
  # 2. Return nil if not found
  # 3. Return to_server(server)
end

def list_servers
  # 1. List all servers
  # 2. Map to to_server(s)
end

def create_server(opts)
  # 1. Resolve image name to UUID if needed
  # 2. Validate commercial_type exists
  # 3. Create server with:
  #    - name: opts.name
  #    - commercial_type: opts.type
  #    - image: resolved_image_uuid
  #    - project: @project_id
  #    - security_group: opts.firewall_id (if provided)
  #    - tags: []
  # 4. If opts.user_data provided, set via cloud-init (see note below)
  # 5. Power on the server (action: poweron)
  # 6. If opts.network_id provided, create private NIC after server is running
  # 7. Return to_server(server)

  # NOTE: user_data/cloud-init may need to be passed differently
  # Check if Scaleway supports user_data in create payload
end

def wait_for_server(server_id, max_attempts)
  # 1. Loop max_attempts times
  # 2. Get server, check state == "running"
  # 3. Sleep Constants::SERVER_READY_INTERVAL between checks
  # 4. Raise ServerCreationError if timeout
  # 5. Return to_server(server)
end

def delete_server(id)
  # 1. Get server to check current state
  # 2. List private NICs, delete each one
  # 3. Remove from security group (or just delete server)
  # 4. Terminate server (action: terminate)
  # NOTE: Scaleway may require server to be stopped first
end
```

#### Volume Operations

```ruby
def create_volume(opts)
  # 1. Get server to find zone
  # 2. Create volume via Block API:
  #    - name: opts.name
  #    - perf_iops: 5000 (or configurable)
  #    - from_empty: { size: opts.size * 1_000_000_000 } # GB to bytes
  #    - project_id: @project_id
  # 3. Return to_volume(volume)
end

def get_volume(id)
  # 1. Get volume from Block API
  # 2. Return nil if not found
  # 3. Return to_volume(volume)
end

def get_volume_by_name(name)
  # 1. List volumes, find by name
  # 2. Return nil if not found
  # 3. Return to_volume(volume)
end

def delete_volume(id)
  # 1. Ensure volume is detached (status != "in_use")
  # 2. Delete via Block API
end

def attach_volume(volume_id, server_id)
  # 1. Get server to get current volumes
  # 2. Build new volumes hash including existing + new volume
  # 3. PATCH server with updated volumes
  # NOTE: Must include ALL volumes in the update, including root
end

def detach_volume(volume_id)
  # 1. Find which server has this volume
  # 2. Get server's current volumes
  # 3. Remove this volume from the hash
  # 4. PATCH server with updated volumes
end
```

#### Validation Operations

```ruby
def validate_instance_type(instance_type)
  # 1. List server types
  # 2. Check if instance_type exists in the list
  # 3. Raise ValidationError if not found
  # 4. Return true
end

def validate_region(region)
  # 1. Check if region/zone is valid
  # Valid zones: fr-par-1, fr-par-2, fr-par-3, nl-ams-1, nl-ams-2, nl-ams-3, pl-waw-1, pl-waw-2, pl-waw-3
  # 2. Raise ValidationError if invalid
  # 3. Return true
end

def validate_credentials
  # 1. Try to list server types (simple API call)
  # 2. If AuthenticationError, raise ValidationError
  # 3. Return true
end
```

#### Private Converters

```ruby
private

def find_network_by_name(name)
  @client.list_private_networks.find { |n| n["name"] == name }
end

def find_security_group_by_name(name)
  @client.list_security_groups.find { |sg| sg["name"] == name }
end

def find_server_by_name(name)
  @client.list_servers.find { |s| s["name"] == name }
end

def find_image(name)
  # Map common names to Scaleway equivalents
  image_name = case name
               when "ubuntu-24.04" then "ubuntu_noble"
               when "ubuntu-22.04" then "ubuntu_jammy"
               when "ubuntu-20.04" then "ubuntu_focal"
               when "debian-12" then "debian_bookworm"
               else name
               end

  images = @client.list_images(name: image_name)
  images&.first
end

def to_network(data)
  Network.new(
    id: data["id"],
    name: data["name"],
    ip_range: data.dig("subnets", 0, "subnet") || data["subnets"]&.first
  )
end

def to_firewall(data)
  Firewall.new(
    id: data["id"],
    name: data["name"]
  )
end

def to_server(data)
  Server.new(
    id: data["id"],
    name: data["name"],
    status: data["state"],  # NOTE: Scaleway uses "state", not "status"
    public_ipv4: data.dig("public_ip", "address")
  )
end

def to_volume(data)
  # Find server_id from references if attached
  server_id = data["references"]&.find { |r| r["product_resource_type"] == "instance_server" }&.dig("product_resource_id")

  Volume.new(
    id: data["id"],
    name: data["name"],
    size: data["size"] / 1_000_000_000, # bytes to GB
    location: data["zone"],
    status: data["status"],
    server_id: server_id,
    device_path: nil  # Scaleway doesn't provide device path in API
  )
end
```

---

## 3. Key Differences from Hetzner Implementation

| Aspect | Hetzner | Scaleway |
|--------|---------|----------|
| Auth header | `Authorization: Bearer` | `X-Auth-Token` |
| Server status field | `status` | `state` |
| Public IP path | `public_net.ipv4.ip` | `public_ip.address` |
| Server type param | `server_type` | `commercial_type` |
| Image format | name string | UUID (resolve from name) |
| Network attachment | At server creation | Via Private NIC (separate call) |
| Firewall concept | Separate Firewall resource | Security Group |
| Firewall rules | Defined at creation | Added via separate endpoint |
| Volume API | Instance API | Block API (separate) |
| Volume size | Integer GB | Bytes |
| Volume attach | `attach` action | PATCH server volumes |
| Location concept | `location` (datacenter) | `zone` (availability zone) |
| Network scope | Network zone | Region |

---

## 4. Configuration Requirements

Add to config loading (likely in `config/loader.rb` or similar):

```ruby
# Scaleway credentials
scaleway_secret_key: ENV["SCALEWAY_SECRET_KEY"]
scaleway_project_id: ENV["SCALEWAY_PROJECT_ID"]
scaleway_zone: ENV["SCALEWAY_ZONE"] || "fr-par-1"
```

---

## 5. Provider Registration

Update `lib/nvoi/service/provider.rb` to include Scaleway:

```ruby
def self.for(config)
  case config.provider
  when "hetzner"
    Providers::Hetzner.new(config.hetzner_token)
  when "scaleway"
    Providers::Scaleway.new(
      config.scaleway_secret_key,
      config.scaleway_project_id,
      zone: config.scaleway_zone
    )
  when "aws"
    Providers::AWS.new(...)
  else
    raise ConfigError, "unknown provider: #{config.provider}"
  end
end
```

---

## 6. Testing Checklist

Create test file: `test/nvoi/providers/scaleway_test.rb`

Test cases to implement:
- [ ] `test_find_or_create_network_creates_when_missing`
- [ ] `test_find_or_create_network_returns_existing`
- [ ] `test_get_network_by_name_raises_when_missing`
- [ ] `test_delete_network`
- [ ] `test_find_or_create_firewall_creates_with_ssh_rule`
- [ ] `test_find_or_create_firewall_returns_existing`
- [ ] `test_delete_firewall`
- [ ] `test_find_server`
- [ ] `test_list_servers`
- [ ] `test_create_server`
- [ ] `test_create_server_with_network`
- [ ] `test_create_server_with_firewall`
- [ ] `test_wait_for_server_success`
- [ ] `test_wait_for_server_timeout`
- [ ] `test_delete_server_cleans_up_nics`
- [ ] `test_create_volume`
- [ ] `test_attach_volume`
- [ ] `test_detach_volume`
- [ ] `test_delete_volume`
- [ ] `test_validate_instance_type_valid`
- [ ] `test_validate_instance_type_invalid`
- [ ] `test_validate_region_valid`
- [ ] `test_validate_region_invalid`
- [ ] `test_validate_credentials_success`
- [ ] `test_validate_credentials_failure`

---

## 7. Error Handling

Map Scaleway errors to existing Nvoi errors:

```ruby
def handle_response(response)
  case response.status
  when 200..299
    response.body
  when 401
    raise AuthenticationError, "Invalid Scaleway API token"
  when 403
    raise AuthenticationError, "Forbidden: check project_id and permissions"
  when 404
    raise NotFoundError, parse_error(response)
  when 409
    raise ConflictError, parse_error(response)
  when 422
    raise ValidationError, parse_error(response)
  when 429
    raise RateLimitError, "Rate limited, retry later"
  else
    raise APIError, parse_error(response)
  end
end

def parse_error(response)
  if response.body.is_a?(Hash)
    response.body["message"] || response.body.to_s
  else
    "HTTP #{response.status}: #{response.body}"
  end
end
```

---

## 8. Cloud-Init / User Data

Scaleway supports cloud-init via the `user_data` field. Research needed on exact format:

```ruby
# Option 1: In create payload (if supported)
{
  "name": "server",
  "commercial_type": "DEV1-S",
  "image": "uuid",
  "user_data": {
    "cloud-init": "base64_encoded_cloud_config"
  }
}

# Option 2: Separate endpoint after creation
# PUT /instance/v1/zones/{zone}/servers/{id}/user_data/cloud-init
```

---

## 9. Implementation Order

1. **ScalewayClient** - HTTP client with all API methods
2. **Scaleway Provider** - Core interface implementation
3. **Image name resolution** - Map ubuntu-24.04 to Scaleway image UUIDs
4. **Tests** - Unit tests with mocked responses
5. **Integration** - Register in provider factory
6. **Config** - Add Scaleway config options
7. **Documentation** - Update README with Scaleway setup

---

## 10. Open Questions

1. **User data format**: Verify exact cloud-init payload format
2. **Default VPC**: Should we use default VPC or create custom?
3. **Volume device path**: Scaleway doesn't expose this - may need OS-level detection
4. **IP allocation**: Auto-assign public IP or require explicit request?
5. **Boot type**: Use `local` or `bootscript`?
