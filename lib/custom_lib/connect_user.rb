class ConnectUser < ActiveRecord::Base
  establish_connection(CASServer::Server.config[:user_database][ENV["RAILS_ENV"]])
  belongs_to :user

  TSINA_CONNECT_TYPE = "tsina"

  validates_presence_of :connect_id
  validates_presence_of :connect_type
  validates_presence_of :user_id

  def validate_on_create
    cu = ConnectUser.find_by_connect_type_and_connect_id(self.connect_type,self.connect_id)
    errors.add(:base,"重复绑定") if !cu.blank?
    cu = ConnectUser.find_by_connect_type_and_user_id(self.connect_type,self.user_id)
    errors.add(:base,"重复绑定") if !cu.blank?
  end

  def self.get_by_tsina_connect_id(connect_id)
    self.find_by_connect_type_and_connect_id(TSINA_CONNECT_TYPE,connect_id)
  end
end
