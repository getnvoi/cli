# frozen_string_literal: true

# Core extensions for blank?/present? checks

class NilClass
  def blank? = true
  def present? = false
end

class String
  def blank? = empty?
  def present? = !empty?
end

class Array
  def blank? = empty?
  def present? = !empty?
end

class Hash
  def blank? = empty?
  def present? = !empty?
end
