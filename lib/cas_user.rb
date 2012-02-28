class User < ActiveRecord::Base
  include UserAuthMethods
  establish_connection(CASServer::Server.config[:user_database][ENV["RAILS_ENV"]])
  
  def self.is_exists?(email_or_name)
    user = User.find_by_name(email_or_name)
    return true if !user.blank?
    user = User.find_by_email(email_or_name)
    return true if !user.blank?
    return false
  end
end

require 'casserver/authenticators/base'
class CasUser < CASServer::Authenticators::Base
  LT_ERROR = CASServer::Server::Error.new("e01","lt错误")
  USER_UNEXISTS_ERROR = CASServer::Server::Error.new("e02","用户不存在")
  PASSWORD_ERROR = CASServer::Server::Error.new("e03","用户名和密码不匹配")
  
  def validate(hash)
    if !User.is_exists?(hash[:email])
      return [false,USER_UNEXISTS_ERROR]
    end
    user = User.authenticate(hash[:email], hash[:password])
    if user.blank?
      return [false,PASSWORD_ERROR]
    end
    return [true,nil]
  end
end