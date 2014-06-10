# encoding: utf-8

module Ione
  module Rpc
    # This is the base class of server peers.
    #
    # To implement a server you need to create a subclass of this class and
    # implement {#handle_request}. You can also optionally implement
    # {#handle_connection} to do initialization when a new client connects.
    class Server
      attr_reader :port

      def initialize(port, codec, options={})
        @port = port
        @codec = codec
        @io_reactor = options[:io_reactor] || Io::IoReactor.new
        @stop_reactor = !options[:io_reactor]
        @queue_length = options[:queue_size] || 5
        @bind_address = options[:bind_address] || '0.0.0.0'
        @logger = options[:logger]
      end

      # Start listening for client connections. This also starts the IO reactor
      # if it was not already started.
      #
      # The returned future resolves when the server is ready to accept
      # connections, or fails if there is an error starting the server.
      #
      # @return [Ione::Future<Ione::Rpc::Server>] a future that resolves to the
      #   server when all hosts have been connected to.
      def start
        @io_reactor.start.flat_map { setup_server }.map(self)
      end

      # Stop the server and close all connections. This also stops the IO reactor
      # if it has not already stopped.
      #
      # @return [Ione::Future<Ione::Rpc::Server>] a future that resolves to the
      #   server when all connections have closed and the IO reactor has stopped.
      def stop
        @io_reactor.stop.map(self)
      end

      protected

      # Override this method to do work when a new client connects.
      #
      # This method may be called concurrently.
      #
      # @return [nil] the return value of this method is ignored
      def handle_connection(connection)
      end

      # Override this method to handle requests.
      #
      # You must respond to all requests, otherwise the client will eventually
      # use up all of its channels and not be able to send any more requests.
      #
      # This method may be called concurrently.
      #
      # @param [Object] message a (decoded) message from a client
      # @param [#host, #port, #on_closed] connection the client connection that
      #   received the message
      # @return [Ione::Future<Object>] a future that will resolve to the response.
      def handle_request(message, connection)
        Future.resolved
      end

      private

      def setup_server
        @io_reactor.bind(@bind_address, @port, @queue_length) do |acceptor|
          @logger.info('Server listening for connections on %s:%d' % [@bind_address, @port]) if @logger
          acceptor.on_accept do |connection|
            @logger.info('Connection from %s:%d accepted' % [connection.host, connection.port]) if @logger
            peer = ServerPeer.new(connection, @codec, self)
            peer.on_closed do
              @logger.info('Connection from %s:%d closed' % [connection.host, connection.port]) if @logger
            end
            handle_connection(peer)
          end
        end
      end

      # @private
      class ServerPeer < Peer
        def initialize(connection, codec, server)
          super(connection, codec)
          @server = server
        end

        def handle_message(message, channel)
          f = @server.handle_request(message, self)
          f.on_value do |response|
            @connection.write(@codec.encode(response, channel))
          end
        end
      end
    end
  end
end
