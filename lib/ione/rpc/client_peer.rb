# encoding: utf-8

require 'ione'


module Ione
  module Rpc
    # @private
    class ClientPeer < Peer
      def initialize(connection, codec, scheduler, max_channels)
        raise ArgumentError, 'More than 2**15 channels is not supported' if max_channels > 2**15
        super(connection, codec, scheduler)
        @lock = Mutex.new
        @channels = [nil] * max_channels
        @queue = []
        @encode_eagerly = @codec.recoding?
      end

      def send_message(request, timeout=nil)
        promise = Ione::Promise.new
        channel = nil
        @lock.lock
        begin
          channel = take_channel(promise)
        ensure
          @lock.unlock
        end
        if channel
          @connection.write(@codec.encode(request, channel))
        else
          pair = [@encode_eagerly ? @codec.encode(request, -1) : request, promise]
          @lock.lock
          begin
            @queue << pair
          ensure
            @lock.unlock
          end
        end
        if timeout
          @scheduler.schedule_timer(timeout).on_value do
            unless promise.future.completed?
              error = Rpc::TimeoutError.new('No response received within %ss' % timeout.to_s)
              promise.fail(error)
            end
          end
        end
        promise.future
      end

      private

      def handle_message(response, channel)
        promise = nil
        @lock.lock
        begin
          promise = @channels[channel]
          @channels[channel] = nil
        ensure
          @lock.unlock
        end
        if promise && !promise.future.completed?
          promise.fulfill(response)
        end
        flush_queue
      end

      def flush_queue
        @lock.lock
        count = 0
        max = @queue.size
        while count < max
          request, promise = @queue[count]
          if (channel = take_channel(promise))
            if @encode_eagerly
              @connection.write(@codec.recode(request, channel))
            else
              @connection.write(@codec.encode(request))
            end
            count += 1
          else
            break
          end
        end
        @queue = @queue.drop(count)
      ensure
        @lock.unlock
      end

      def take_channel(promise)
        if (channel = @channels.index(nil))
          @channels[channel] = promise
          channel
        end
      end

      def handle_closed(cause=nil)
        error = Io::ConnectionClosedError.new('Connection closed')
        promises_to_fail = @lock.synchronize { @channels.reject(&:nil?) }
        promises_to_fail.each { |p| p.fail(error) }
        super
      end
    end
  end
end
