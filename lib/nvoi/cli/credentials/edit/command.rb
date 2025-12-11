# frozen_string_literal: true

module Nvoi
  class Cli
    module Credentials
      module Edit
        # Command handles editing encrypted credentials
        class Command
          DEFAULT_ENCRYPTED_FILE = "deploy.enc"
          DEFAULT_KEY_FILE = "deploy.key"

          def initialize(options)
            @options = options
            @log = Nvoi.logger
          end

          def run
            @log.info "Credentials Editor"

            working_dir = resolve_working_dir
            enc_path = resolve_enc_path(working_dir)

            manager = if File.exist?(enc_path)
              Utils::Crypto.new(working_dir, @options[:credentials], @options[:master_key])
            else
              @log.info "Creating new encrypted credentials file"
              Utils::Crypto.for_init(working_dir)
            end

            # Open in editor
            edit_credentials(manager)

            # Update .gitignore on first run
            if manager.key_path
              begin
                update_gitignore(working_dir)
                @log.info "Added %s to .gitignore", DEFAULT_KEY_FILE
              rescue StandardError => e
                @log.warning "Failed to update .gitignore: %s", e.message
              end

              @log.success "Master key saved to: %s", manager.key_path
              @log.warning "Keep this key safe! You cannot decrypt credentials without it."
            end
          end

          def set(path, value)
            @log.info "Setting credential value"

            working_dir = resolve_working_dir
            manager = Utils::Crypto.new(working_dir, @options[:credentials], @options[:master_key])

            # Read current content
            content = manager.read
            data = YAML.safe_load(content, permitted_classes: [Symbol])

            # Navigate path and set value
            keys = path.split(".")
            current = data

            # Handle 'application.' prefix - it's implied
            keys.shift if keys.first == "application"

            # Navigate to parent
            keys[0..-2].each do |key|
              current["application"] ||= {}
              current = current["application"]
              current[key] ||= {}
              current = current[key]
            end

            # Set the value
            if keys.length == 1
              data["application"] ||= {}
              data["application"][keys.last] = value
            else
              current[keys.last] = value
            end

            # Write back
            new_content = YAML.dump(data)
            manager.write(new_content)

            @log.success "Updated: %s = %s", path, value
          end

          private

            def resolve_working_dir
              wd = @options[:dir]
              if wd.nil? || wd.empty? || wd == "."
                Dir.pwd
              else
                File.expand_path(wd)
              end
            end

            def resolve_enc_path(working_dir)
              enc_path = @options[:credentials]
              return File.join(working_dir, DEFAULT_ENCRYPTED_FILE) if enc_path.nil? || enc_path.empty?

              enc_path
            end

            def edit_credentials(manager)
              require "tempfile"

              # Decrypt to temp file
              content = manager.read rescue ""
              content = "# Deployment credentials\napplication:\n  name: myapp\n" if content.empty?

              temp_file = Tempfile.new(["credentials", ".yml"])
              begin
                temp_file.write(content)
                temp_file.close

                # Get editor
                editor = ENV["EDITOR"] || "vim"

                # Open editor
                system(editor, temp_file.path)

                # Read back and validate
                new_content = File.read(temp_file.path)

                # Basic YAML validation
                YAML.safe_load(new_content, permitted_classes: [Symbol])

                # Write back encrypted
                manager.write(new_content)

                @log.success "Credentials saved"
              ensure
                temp_file.unlink
              end
            end

            def update_gitignore(working_dir)
              gitignore_path = File.join(working_dir, ".gitignore")
              existing = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""

              return if existing.include?(DEFAULT_KEY_FILE)

              File.open(gitignore_path, "a") do |f|
                f.puts "" unless existing.end_with?("\n") || existing.empty?
                f.puts "# Nvoi master key - DO NOT COMMIT"
                f.puts DEFAULT_KEY_FILE
              end
            end
        end
      end
    end
  end
end
