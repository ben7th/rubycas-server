require 'digest/sha1'
module UserAuthMethods
  def self.included(base)
    base.extend ClassMethods
  end
  
  # 创建 记住我 cookie 登录令牌
  def create_remember_me_cookie_token(expire = 30)
    value = "#{self.email}:#{expire.to_s}:#{self.hashed_remember_me_cookie_token_string}"
    
    {
      :value   => value,
      :expires => expire.days.from_now,
      :domain  => Rails.application.config.session_options[:domain]
    }
  end
  
  # 使用SHA1算法生成令牌字符串，用于记住我的cookie
  def hashed_remember_me_cookie_token_string
    Digest::SHA1.hexdigest(self.name + self.hashed_password + self.salt + 'onlyecho')
  end
  
  module ClassMethods
    # 电子邮箱或用户名 认证
    def authenticate(email_or_name, password)
      user = User.find_by_email(email_or_name) || User.find_by_name(email_or_name)
      return nil if user.blank?
      return user if valid_user_password(user,password)
      return nil
    end
    
    # 验证用户的密码是否正确
    # 会接受外部传入信息参数来验证，所以定义为类方法
    def valid_user_password(user, password)
      expected_password = encrypted_password(password, user.salt)
      user.hashed_password == expected_password
    end
    
    # 使用SHA1算法，根据内部密钥和明文密码计算加密后的密码
    def encrypted_password(password, salt)
      Digest::SHA1.hexdigest(password + 'jerry_sun' + salt)
    end
    
    # 验证 记住我 cookies令牌
    def authenticate_remember_me_cookie_token(token)
      email, expire, hashed_string = token.split(':')
      
      user = User.find_by_email(email)
      user = nil if !user.blank? && hashed_string != user.hashed_remember_me_cookie_token_string
      return user
    end
  end
end