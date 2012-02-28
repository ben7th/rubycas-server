class CASServer::Model::ServiceTicket < ActiveRecord::Base
  establish_connection({
    :adapter=>'mysql2',
    :database=>'casserver_development',
    :username=>'root',
    :password=>'root',
    :host=>'localhost',
    :reconnect=>true
  })
  set_table_name 'casserver_st'
  
  def matches_service?(service)
    self.service == service
  end
  
  def consume!
    self.consumed = Time.now
    self.save!
  end
  
  def get_user(service)
    return if consumed?
    return if Time.now - created_on > 300
    return if !matches_service?(service) 
    consume!
    User.find_by_email(username)
  end
  
end