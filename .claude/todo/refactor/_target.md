lib/nvoi/
│
├── cli.rb # Thor routing only
│
├── cli/
│ ├── deploy/
│ │ ├── command.rb
│ │ └── steps/
│ │ ├── provision_network.rb
│ │ ├── provision_server.rb
│ │ ├── provision_volume.rb
│ │ ├── setup_k3s.rb
│ │ ├── configure_tunnel.rb
│ │ ├── build_image.rb
│ │ ├── deploy_service.rb
│ │ └── cleanup_images.rb
│ │
│ ├── delete/
│ │ ├── command.rb
│ │ └── steps/
│ │ ├── teardown_tunnel.rb
│ │ ├── teardown_dns.rb
│ │ ├── detach_volumes.rb
│ │ ├── teardown_server.rb
│ │ ├── teardown_volume.rb
│ │ ├── teardown_firewall.rb
│ │ └── teardown_network.rb
│ │
│ ├── exec/
│ │ └── command.rb
│ │
│ └── credentials/
│ ├── edit/
│ │ └── command.rb
│ └── show/
│ └── command.rb
│
├── external/
│ ├── cloud/
│ │ ├── base.rb
│ │ ├── hetzner.rb
│ │ ├── aws.rb
│ │ └── scaleway.rb
│ ├── dns/
│ │ └── cloudflare.rb
│ ├── ssh.rb
│ ├── kubectl.rb
│ └── containerd.rb
│
├── objects/
│ ├── server.rb
│ ├── network.rb
│ ├── firewall.rb
│ ├── volume.rb
│ ├── tunnel.rb
│ ├── dns_record.rb
│ ├── zone.rb
│ ├── service_spec.rb
│ └── config.rb
│
└── utils/
├── namer.rb
├── env_resolver.rb
├── crypto.rb
├── templates.rb
├── logger.rb
└── constants.rb

---

Summary:

| Folder        | Purpose                | Rule                                  |
| ------------- | ---------------------- | ------------------------------------- |
| cli/          | Command entrypoints    | 1 command = 1 command.rb              |
| cli/\*/steps/ | Multi-step pipelines   | Only for commands with ordered phases |
| external/     | Outside world adapters | APIs, SSH, CLIs                       |
| objects/      | Data structures        | No behavior, just shape               |
| utils/        | Stateless helpers      | Used everywhere                       |
