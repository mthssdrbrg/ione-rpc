# encoding: utf-8

require 'ione'


module Ione
  module Rpc
    TimeoutError = Class.new(StandardError)
  end
end

require 'ione/rpc/peer'
require 'ione/rpc/client_peer'
require 'ione/rpc/server'
require 'ione/rpc/client'
require 'ione/rpc/codec'
