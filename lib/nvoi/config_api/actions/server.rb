# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetServer < Base
        protected

          def mutate(data, name:, master: false, type: nil, location: nil, count: 1)
            raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
            raise ArgumentError, "count must be positive" if count && count < 1

            app(data)["servers"] ||= {}
            app(data)["servers"][name.to_s] = {
              "master" => master,
              "type" => type,
              "location" => location,
              "count" => count
            }.compact
          end
      end

      class DeleteServer < Base
        protected

          def mutate(data, name:)
            raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

            servers = app(data)["servers"] || {}
            raise Errors::ConfigValidationError, "server '#{name}' not found" unless servers.key?(name.to_s)

            servers.delete(name.to_s)
          end

          def validate(data)
            check_orphaned_references(data)
          end

        private

          def check_orphaned_references(data)
            servers = (app(data)["servers"] || {}).keys

            (app(data)["app"] || {}).each do |svc_name, svc|
              (svc["servers"] || []).each do |ref|
                raise Errors::ConfigValidationError, "app.#{svc_name} references non-existent server '#{ref}'" unless servers.include?(ref)
              end
            end

            db = app(data)["database"]
            if db
              (db["servers"] || []).each do |ref|
                raise Errors::ConfigValidationError, "database references non-existent server '#{ref}'" unless servers.include?(ref)
              end
            end

            (app(data)["services"] || {}).each do |svc_name, svc|
              (svc["servers"] || []).each do |ref|
                raise Errors::ConfigValidationError, "services.#{svc_name} references non-existent server '#{ref}'" unless servers.include?(ref)
              end
            end
          end
      end
    end
  end
end
