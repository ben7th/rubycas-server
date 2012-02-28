module SSOClientControllerMethods
  def ajax_login_failure
    render :layout=>false, :file=>File.join(File.dirname(__FILE__), 'views', 'ajax_login_failure.html.haml')
  end
  
  def crosslogin
    session[:ST] = params[:st]
    
    _set_user_id_from_st
    _set_remember_me_cookie if 'true' == params[:remember_me]
    
    _cross_callback
  end
  
  def ajax_login_success
    render :layout=>false, :file=>File.join(File.dirname(__FILE__), 'views', 'ajax_login_success.html.haml')
  end
  
  def crosslogout
    session[:ST] = nil
    session[:user_id] = nil
    
    _remove_remember_me_cookie
    
    _cross_callback
  end
end