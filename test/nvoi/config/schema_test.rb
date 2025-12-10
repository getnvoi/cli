# frozen_string_literal: true

require "test_helper"

class Nvoi::Config::SchemaTest < Minitest::Test
  def test_steps_returns_all_steps
    steps = Nvoi::Config::Schema.steps
    assert_kind_of Array, steps
    assert_equal 8, steps.length
  end

  def test_step_returns_specific_step
    step = Nvoi::Config::Schema.step(:compute_provider)
    assert_equal :compute_provider, step[:key]
    assert_equal "Compute Provider", step[:title]
    assert step[:required]
    assert_empty step[:depends_on]
  end

  def test_step_returns_nil_for_unknown
    assert_nil Nvoi::Config::Schema.step(:unknown_step)
  end

  def test_compute_provider_step_has_required_fields
    step = Nvoi::Config::Schema.step(:compute_provider)
    fields = step[:fields]

    provider_field = fields.find { |f| f[:key] == :provider }
    assert provider_field
    assert provider_field[:required]
    assert_equal :select, provider_field[:type]
    assert_equal 2, provider_field[:options].length

    api_token_field = fields.find { |f| f[:key] == :api_token }
    assert api_token_field
    assert api_token_field[:secret]
  end

  def test_servers_step_is_collection
    step = Nvoi::Config::Schema.step(:servers)
    assert step[:collection]
    assert_equal 1, step[:min_items]
    assert_equal :name, step[:item_key_field]
  end

  def test_servers_step_has_volumes_field
    step = Nvoi::Config::Schema.step(:servers)
    volumes_field = step[:fields].find { |f| f[:key] == :volumes }

    assert volumes_field
    assert_equal :collection, volumes_field[:type]
    assert volumes_field[:item_fields]

    name_field = volumes_field[:item_fields].find { |f| f[:key] == :name }
    size_field = volumes_field[:item_fields].find { |f| f[:key] == :size }

    assert name_field
    assert size_field
    assert_equal 10, size_field[:default]
  end

  def test_app_services_step_has_mounts_field
    step = Nvoi::Config::Schema.step(:app_services)
    mounts_field = step[:fields].find { |f| f[:key] == :mounts }

    assert mounts_field
    assert_equal :key_value, mounts_field[:type]
    assert_equal :server_volumes, mounts_field[:key_options_from]
  end

  def test_fetch_options_provider_server_types_hetzner
    config = { "application" => { "compute_provider" => { "hetzner" => {} } } }
    options = Nvoi::Config::Schema.fetch_options(:provider_server_types, config)

    assert_kind_of Array, options
    assert options.any? { |o| o[:value] == "cx22" }
    assert options.any? { |o| o[:value] == "cx32" }
  end

  def test_fetch_options_provider_server_types_aws
    config = { "application" => { "compute_provider" => { "aws" => {} } } }
    options = Nvoi::Config::Schema.fetch_options(:provider_server_types, config)

    assert_kind_of Array, options
    assert options.any? { |o| o[:value] == "t3.micro" }
    assert options.any? { |o| o[:value] == "t3.medium" }
  end

  def test_fetch_options_provider_locations_hetzner
    config = { "application" => { "compute_provider" => { "hetzner" => {} } } }
    options = Nvoi::Config::Schema.fetch_options(:provider_locations, config)

    assert_kind_of Array, options
    assert options.any? { |o| o[:value] == "fsn1" }
    assert options.any? { |o| o[:value] == "nbg1" }
  end

  def test_fetch_options_defined_servers
    config = {
      "application" => {
        "servers" => {
          "master" => { "type" => "cx22" },
          "workers" => { "type" => "cx22", "count" => 2 }
        }
      }
    }
    options = Nvoi::Config::Schema.fetch_options(:defined_servers, config)

    assert_equal 2, options.length
    assert options.any? { |o| o[:value] == "master" }
    assert options.any? { |o| o[:value] == "workers" }
  end

  def test_fetch_options_server_volumes_all
    config = {
      "application" => {
        "servers" => {
          "master" => {
            "volumes" => {
              "database" => { "size" => 20 },
              "uploads" => { "size" => 10 }
            }
          },
          "workers" => {
            "volumes" => {}
          }
        }
      }
    }
    options = Nvoi::Config::Schema.fetch_options(:server_volumes, config)

    assert_equal 2, options.length
    assert options.any? { |o| o[:value] == "database" && o[:label].include?("20GB") }
    assert options.any? { |o| o[:value] == "uploads" && o[:label].include?("10GB") }
  end

  def test_fetch_options_server_volumes_specific_server
    config = {
      "application" => {
        "servers" => {
          "master" => {
            "volumes" => {
              "database" => { "size" => 20 }
            }
          }
        }
      }
    }
    options = Nvoi::Config::Schema.fetch_options(:server_volumes, config, server: "master")

    assert_equal 1, options.length
    assert_equal "database", options.first[:value]
    assert_includes options.first[:label], "20GB"
  end

  def test_fetch_options_returns_empty_for_unknown
    options = Nvoi::Config::Schema.fetch_options(:unknown_option, {})
    assert_empty options
  end

  def test_field_show_if_conditions
    step = Nvoi::Config::Schema.step(:compute_provider)

    hetzner_token = step[:fields].find { |f| f[:key] == :api_token }
    assert_equal({ field: :provider, equals: :hetzner }, hetzner_token[:show_if])

    aws_key = step[:fields].find { |f| f[:key] == :access_key_id }
    assert_equal({ field: :provider, equals: :aws }, aws_key[:show_if])
  end

  def test_database_step_has_mount_field
    step = Nvoi::Config::Schema.step(:database)
    mount_field = step[:fields].find { |f| f[:key] == :mount }

    assert mount_field
    assert_equal :key_value, mount_field[:type]
    assert_equal :server_volumes, mount_field[:key_options_from]
  end
end
