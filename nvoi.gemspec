# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "nvoi"
  spec.version       = File.read(File.expand_path("lib/nvoi/version.rb", __dir__)).match(/VERSION = "(.*)"/)[1]
  spec.authors       = ["NVOI"]
  spec.email         = ["support@nvoi.io"]

  spec.summary       = "NVOI deployment tool"
  spec.description   = "A deployment tool that automates application deployment to cloud providers (Hetzner, AWS) with K3s orchestration and Cloudflare tunnels."
  spec.homepage      = "https://github.com/getnvoi/nvoi"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end + Dir["templates/**/*"]

  spec.bindir        = "exe"
  spec.executables   = ["nvoi"]
  spec.require_paths = ["lib"]

  # CLI
  spec.add_dependency "thor", "~> 1.3"

  # Cloud providers
  spec.add_dependency "aws-sdk-ec2", "~> 1.400"
  spec.add_dependency "hcloud", "~> 1.3"

  # HTTP client
  spec.add_dependency "faraday", "~> 2.7"

  # SSH
  spec.add_dependency "net-ssh", "~> 7.2"
  spec.add_dependency "net-scp", "~> 4.0"

  # Development
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "rubocop", "~> 1.57"
end
