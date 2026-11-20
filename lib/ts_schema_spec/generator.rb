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

    # node exits on stdin's EOF, unless a forked child still holds the pipe.
    EXIT_TIMEOUT = 5

    # node's phrasing when the project's node_modules lacks either package the
    # server loads. Anything looser — a bare "not found" — swallows the
    # generator's real diagnostic.
    MISSING_PACKAGE = %r{Error: Cannot find module '(ts-json-schema-generator|typescript)(/[^']*)?'}

    UNSUPPORTED_GENERATOR = /ts_schema_spec supports ts-json-schema-generator .*/

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
      rescue ServerExit, Errno::ENOENT => e
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
          exchange(args) || raise(ServerExit, stop_server)
        rescue Errno::EPIPE, IOError
          raise ServerExit, stop_server
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
        return unless line

        reply = JSON.parse(line)
        raise JSON::ParserError unless reply.is_a?(Hash) && reply.key?("status")

        reply
      rescue JSON::ParserError
        raise ServerExit, "node wrote something that is not a reply: #{line.chomp}\n\n#{stop_server(kill: true)}"
      end

      def start_server
        cwd = Dir.pwd
        stdin, stdout, stderr, wait = begin
          Open3.popen3("node", SERVER, chdir: cwd)
        rescue Errno::ENOENT => e
          raise unless e.message.end_with?(" - node")

          raise GenerationError, <<~MSG
            could not run node (#{e.message}).

            ts_schema_spec runs ts-json-schema-generator with node, so node must
            be on the PATH of the process running your specs.
          MSG
        end
        begin
          at_exit { stop_at_exit } unless @stop_registered
          @stop_registered = true
          reader = Thread.new do
            stderr.read
          rescue IOError
            nil
          ensure
            stderr.close
          end
          Server.new(stdin, stdout, reader, wait, cwd)
        rescue Exception
          terminate(wait)
          [stdin, stdout, stderr].each(&:close)
          raise
        end
      end

      # A thread still mid-request holds MUTEX; node then sees EOF once this
      # process exits and closes its pipes.
      def stop_at_exit
        return unless MUTEX.try_lock

        begin
          stop_server
        ensure
          MUTEX.unlock
        end
      end

      def stop_server(kill: false)
        server = @server
        return unless server

        @server = nil
        sent = terminate(server.wait) if kill
        server.stdin.close unless server.stdin.closed?
        server.stdout.close unless server.stdout.closed?
        unless server.wait.join(EXIT_TIMEOUT)
          sent = terminate(server.wait) || sent
          sent = terminate(server.wait, "KILL") || sent unless server.wait.join(EXIT_TIMEOUT)
          server.wait.join
        end
        status = server.wait.value
        ended = "node ended: #{status}" if status
        ended += " after ts_schema_spec sent it #{sent}" if ended && sent
        "#{server.stderr.value.to_s.strip}\n\n#{ended}".strip
      end

      # Once the waiter has reaped node, its pid may belong to another process.
      # Checking first narrows that window; only a pidfd could close it.
      def terminate(wait, signal = "TERM")
        return unless wait.alive?

        Process.kill(signal, wait.pid)
        signal
      rescue Errno::ESRCH
        nil
      end

      def missing_generator(command, stderr = nil)
        message = <<~MSG
          could not load ts-json-schema-generator from your node_modules.

          The generator parses your app's TypeScript, so it resolves from your
          node_modules rather than from the gem:

            npm install --save-dev ts-json-schema-generator

          Rerun: #{command.join(" ")}
        MSG
        return message if stderr.to_s.strip.empty?

        "#{message}\n#{stderr.strip}\n"
      end

      def failure(command, stderr)
        stderr = stderr.to_s.scrub
        return missing_generator(command, stderr) if stderr.match?(MISSING_PACKAGE)

        unsupported = stderr[UNSUPPORTED_GENERATOR]
        return "#{unsupported}\n" if unsupported

        <<~MSG
          ts-json-schema-generator failed.

          Rerun: #{command.join(" ")}

          #{stderr.strip}
        MSG
      end
    end
  end
end
