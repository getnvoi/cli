# Scaleway Bucket Automation

Automate bucket provisioning for new tenants/environments.

## API

No separate management API - use S3-compatible REST API directly via `aws-sdk-s3` gem.

```ruby
require "aws-sdk-s3"

client = Aws::S3::Client.new(
  region: "fr-par",
  endpoint: "https://s3.fr-par.scw.cloud",
  access_key_id: Rails.application.credentials.dig(:scaleway, :access_key_id),
  secret_access_key: Rails.application.credentials.dig(:scaleway, :secret_key)
)

# Create bucket
client.create_bucket(bucket: "tenant-#{tenant_slug}-#{Rails.env}")

# Set CORS
client.put_bucket_cors(
  bucket: bucket_name,
  cors_configuration: {
    cors_rules: [{
      allowed_origins: ["https://notiplus.com", "https://*.notiplus.com"],
      allowed_methods: ["GET", "PUT"],
      allowed_headers: ["*"],
      max_age_seconds: 3000
    }]
  }
)
```

## Tasks

- [ ] Create `Scaleway::BucketService` to handle create/configure
- [ ] Add rake task for provisioning new environment buckets
- [ ] Hook into tenant creation flow (if multi-tenant)
- [ ] Add lifecycle rules for old/temp files cleanup
