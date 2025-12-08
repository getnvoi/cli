# frozen_string_literal: true

module Nvoi
  class Logger
    COLORS = {
      reset: "\e[0m",
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      blue: "\e[34m",
      magenta: "\e[35m",
      cyan: "\e[36m",
      white: "\e[37m",
      bold: "\e[1m"
    }.freeze

    def initialize(output: $stdout, color: true)
      @output = output
      @color = color && output.tty?
    end

    def info(message, *args)
      log(:blue, "INFO", format_message(message, args))
    end

    def success(message, *args)
      log(:green, "SUCCESS", format_message(message, args))
    end

    def warning(message, *args)
      log(:yellow, "WARNING", format_message(message, args))
    end

    def error(message, *args)
      log(:red, "ERROR", format_message(message, args))
    end

    def debug(message, *args)
      return unless ENV["NVOI_DEBUG"]

      log(:magenta, "DEBUG", format_message(message, args))
    end

    def separator
      @output.puts colorize(:cyan, "-" * 60)
    end

    def blank
      @output.puts
    end

    private

      def format_message(message, args)
        return message if args.empty?

        format(message, *args)
      end

      def log(color, level, message)
        timestamp = Time.now.strftime("%H:%M:%S")
        prefix = colorize(color, "[#{timestamp}] [#{level}]")
        @output.puts "#{prefix} #{message}"
      end

      def colorize(color, text)
        return text unless @color

        "#{COLORS[color]}#{text}#{COLORS[:reset]}"
      end
  end
end
