module CASServer; end

require 'active_record'
require 'active_support'
require 'sinatra/base'
require 'builder' # for XML views
require 'logger'
require "oauth"
require "nokogiri"
$LOG = Logger.new(STDOUT)
require 'custom_lib/user_auth_methods'
require 'custom_lib/tsina'
require 'casserver/server'
require 'custom_lib/connect_user'

