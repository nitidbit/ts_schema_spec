# frozen_string_literal: true

require "json"
require "open3"

module TsSchemaSpec
  module Generator
    COMMAND = %w[npx ts-json-schema-generator].freeze
    SERVER = File.expand_path("generator_server.cjs", __dir__)

    class ServerExit < StandardError; end

    Server = Struct.new(:stdin, :stdout, :stderr, :wait, :cwd)

    MUTEX = Mutex.new

    # node's phrasing when the project's node_modules lacks either package the
    # server loads. Anything looser — a bare "not found" — swallows the
    # generator's real diagnostic.
    MISSING_PACKAGE = /Cannot find module '(ts-json-schema-generator|typescript)[^']*'/

    class << self
      def generate(source)
        command = command_for(source)
        reply = request(command.drop(COMMAND.size))

        unless reply["status"].zero?
          raise GenerationError, failure(command, reply["stderr"])
        end

        JSON.parse(reply["stdout"])
      rescue JSON::ParserError => e
        raise GenerationError, failure(command, "#{e.message}\n\n#{reply&.fetch("stderr", nil)}")
      rescue Errno::ENOENT
        raise GenerationError, missing_generator(command)
      rescue ServerExit => e
        raise GenerationError, failure(command, e.message)
      end

      def command_for(source)
        COMMAND + ["--path", source.to_s, "--no-type-check"] + TsSchemaSpec.config.to_args
      end

      def stop
        MUTEX.synchronize { stop_server }
      end

      private

      def request(args)
        MUTEX.synchronize do
          # node resolves the generator, typescript and type roots from the
          # directory it starts in, and TypeScript memoizes it.
          stop_server unless @server&.wait&.alive? && @server.cwd == Dir.pwd
          @server ||= start_server
          exchange(args) || raise(ServerExit, stop_server(kill: true))
        rescue Errno::EPIPE, IOError
          raise ServerExit, stop_server(kill: true)
        rescue Exception
          # Anything that interrupts an exchange (Timeout, Interrupt) leaves
          # its reply unread, and the next request would read it as its own.
          stop_server(kill: true)
          raise
        end
      end

      def exchange(args)
        @server.stdin.puts(JSON.generate(args))
        line = @server.stdout.gets
        JSON.parse(line) if line
      end

      def start_server
        cwd = Dir.pwd
        stdin, stdout, stderr, wait = Open3.popen3("node", SERVER, chdir: cwd)
        begin
          at_exit { stop } unless @stop_registered
          @stop_registered = true
          Server.new(stdin, stdout, Thread.new { stderr.read }, wait, cwd)
        rescue Exception
          terminate(wait.pid)
          [stdin, stdout, stderr].each(&:close)
          raise
        end
      end

      def stop_server(kill: false)
        server = @server
        return unless server

        @server = nil
        terminate(server.wait.pid) if kill
        server.stdin.close unless server.stdin.closed?
        server.stdout.close unless server.stdout.closed?
        server.wait.join
        server.stderr.value
      end

      def terminate(pid)
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
        nil
      end

      def missing_generator(command, stderr = nil)
        message = <<~MSG
          could not run #{COMMAND.join(" ")}.

          The generator parses your app's TypeScript, so it resolves from your
          node_modules rather than from the gem:

            npm install --save-dev ts-json-schema-generator

          Rerun: #{command.join(" ")}
        MSG
        return message if stderr.to_s.strip.empty?

        "#{message}\n#{stderr.strip}\n"
      end

      def failure(command, stderr)
        return missing_generator(command, stderr) if stderr.to_s.match?(MISSING_PACKAGE)

        <<~MSG
          ts-json-schema-generator failed.

          Rerun: #{command.join(" ")}

          #{stderr.strip}
        MSG
      end
    end
  end
end
