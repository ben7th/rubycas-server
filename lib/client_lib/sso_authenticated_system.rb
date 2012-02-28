module SSOAuthenticatedSystem
  
  # 当某个action访问前必须先登录时，加上这个 before_filter
  def login_required(info = nil)
    logged_in? || access_denied(info)
  end
  
  # 作为全局的before_filter，用来在持有ST的时候交换user_id
  # TODO 处理ST的过期问题
  def sso_validate_st
    if !session[:ST].blank?
      
      # 登录信息完整。
      # 其中 session[:ST] 的值不一定是ST，有可能是 'EXPIRED'
      return true if !session[:user_id].blank?
      
      # 有ST但没有userid，后台去SSO验证st，换取user信息，并给session[:user_id]赋值
      # 此处有可能因为ST过期（过期时限设定为2小时）而验证失败，如果那样的话，
      # 来回重定向一次，用TGT换取新的ST（TGT在服务端永不过期，根据COOKIE的过期来过期）
      _set_user_id_from_st
      
    else
      
      # 没有ST，则认为是没有登录，清除 session[:user_id]
      session[:user_id] = nil
      
    end
  end
  

  private
    # 将几个方法添加到helper方法中，以便在页面使用
    def self.included(base)
      base.send :helper_method, :current_user, :logged_in?, :_this_app_name
    end
    
    # -------------------------------------------------------------------

    # 根据session里的信息，获取当前登录用户
    # 如果没有登录，则返回 nil
    def current_user
      @current_user ||= (
        _login_from_session || _login_from_remember_me_cookie
      ) unless false == @current_user
      
      return @current_user || nil
    end

    # 判断用户是否登录，同时预加载 @current_user 对象
    def logged_in?
      !!current_user
    end

    # ------------------------------------------------------------------------

    # 被 current_user 方法调用
    def _login_from_session
      return User.find_by_id(session[:user_id])
    end
  
    # 当登录时勾选了“记住我”会产生特定cookie，通过此cookie获得current_user
    def _login_from_remember_me_cookie
      value = cookies[_remember_me_cookie_key]
      
      if !value.blank?
        user = User.authenticate_remember_me_cookie_token(value)
        if !user.blank?
          session[:user_id] = user.id
          session[:ST] = :EXPIRED if session[:ST].blank? # ST 必须有一个值
          return user
        end
      end
      
      return nil
    end

    def _remember_me_cookie_key
      return :remember_me_token if Rails.env.production?
      return :remember_me_token_devel
    end

    def _cookie_domain
      Rails.application.config.session_options[:domain]
    end

    # ------------------------
    
    def _set_user_id_from_st
      st = CASServer::Model::ServiceTicket.find_by_ticket(session[:ST])
      if !st.blank?
        session[:user_id] = st.get_user(_this_app_name).id
      end
    end

    def _set_remember_me_cookie
      cookies[_remember_me_cookie_key] = current_user.create_remember_me_cookie_token(30)
    end
    
    def _remove_remember_me_cookie
      cookies[_remember_me_cookie_key] = {
        :value   => nil,
        :expires => 0.days.from_now,
        :domain  => _cookie_domain
      }
    end

    def _cross_callback
      render :text=>"#{params[:callback]}({app:'#{_this_app_name}'})"
    end

end