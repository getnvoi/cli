# frozen_string_literal: true

require "test_helper"

class CloudBaseTest < Minitest::Test
  def setup
    @base = Nvoi::External::Cloud::Base.new
  end

  def test_find_or_create_network_raises_not_implemented
    assert_raises(NotImplementedError) { @base.find_or_create_network("test") }
  end

  def test_get_network_by_name_raises_not_implemented
    assert_raises(NotImplementedError) { @base.get_network_by_name("test") }
  end

  def test_delete_network_raises_not_implemented
    assert_raises(NotImplementedError) { @base.delete_network("123") }
  end

  def test_find_or_create_firewall_raises_not_implemented
    assert_raises(NotImplementedError) { @base.find_or_create_firewall("test") }
  end

  def test_get_firewall_by_name_raises_not_implemented
    assert_raises(NotImplementedError) { @base.get_firewall_by_name("test") }
  end

  def test_delete_firewall_raises_not_implemented
    assert_raises(NotImplementedError) { @base.delete_firewall("123") }
  end

  def test_find_server_raises_not_implemented
    assert_raises(NotImplementedError) { @base.find_server("test") }
  end

  def test_list_servers_raises_not_implemented
    assert_raises(NotImplementedError) { @base.list_servers }
  end

  def test_create_server_raises_not_implemented
    assert_raises(NotImplementedError) { @base.create_server(nil) }
  end

  def test_wait_for_server_raises_not_implemented
    assert_raises(NotImplementedError) { @base.wait_for_server("123", 10) }
  end

  def test_delete_server_raises_not_implemented
    assert_raises(NotImplementedError) { @base.delete_server("123") }
  end

  def test_create_volume_raises_not_implemented
    assert_raises(NotImplementedError) { @base.create_volume(nil) }
  end

  def test_get_volume_raises_not_implemented
    assert_raises(NotImplementedError) { @base.get_volume("123") }
  end

  def test_get_volume_by_name_raises_not_implemented
    assert_raises(NotImplementedError) { @base.get_volume_by_name("test") }
  end

  def test_delete_volume_raises_not_implemented
    assert_raises(NotImplementedError) { @base.delete_volume("123") }
  end

  def test_attach_volume_raises_not_implemented
    assert_raises(NotImplementedError) { @base.attach_volume("123", "456") }
  end

  def test_detach_volume_raises_not_implemented
    assert_raises(NotImplementedError) { @base.detach_volume("123") }
  end

  def test_validate_instance_type_raises_not_implemented
    assert_raises(NotImplementedError) { @base.validate_instance_type("t2.micro") }
  end

  def test_validate_region_raises_not_implemented
    assert_raises(NotImplementedError) { @base.validate_region("us-east-1") }
  end

  def test_validate_credentials_raises_not_implemented
    assert_raises(NotImplementedError) { @base.validate_credentials }
  end
end
