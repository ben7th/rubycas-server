class Tsina
  class OauthFailureError<StandardError;end
  class ContentLengthError<StandardError;end
  class RepeatSendError<StandardError;end

  API_KEY = "1526151944"
  API_SECRET = "a00a7048df478244376d69b14bb7ae07"
  API_SITE = "http://api.t.sina.com.cn"

  def initialize
    @request_token = Tsina.get_request_token
  end
  
  def authorize_url(app)
    @request_token.authorize_url({:oauth_callback=>"http://dev.sso.mindpin.com/connect_tsina_callback?app=#{app}"})
  end
  
  def request_token
    @request_token
  end
  
    # 得到一个 request_token
  def self.get_request_token
    consumer = OAuth::Consumer.new(API_KEY,API_SECRET,{:site=>API_SITE})
    consumer.get_request_token
  end
  
  def self.get_tsina_user_info(oauth_token,oauth_token_secret,oauth_verifier)
    consumer = OAuth::Consumer.new(API_KEY,API_SECRET,{:site=>API_SITE})
    rt = OAuth::RequestToken.new(consumer, oauth_token, oauth_token_secret)
    rt.params = {"oauth_token"=>oauth_token,"oauth_token_secret"=>oauth_token_secret}
    # 根据 request_token 和 oauth_verifier
    # 得到授权后的 access_token
    # 用 access_token.token 和 access_token.secret 就可以使用用户的 新浪微博资源了
    access_token = rt.get_access_token(:oauth_verifier =>oauth_verifier)
    # 用 access_token.token 和 access_token.secret 获取用户的 新浪微博信息
    xml = access_token.get("/account/verify_credentials.xml").body
    doc = Nokogiri::XML(xml)
    raise Tsina::OauthFailureError,"远程网站授权无效，认证失败" if !doc.at_css("error").blank?
    connect_id = doc.at_css("id").content
    user_name = doc.at_css("name").content
    profile_image_url = doc.at_css("profile_image_url").content
    followers_count = doc.at_css("followers_count").content
    friends_count = doc.at_css("friends_count").content
    statuses_count = doc.at_css("statuses_count").content
    {
      "connect_id"=>connect_id,"user_name"=>user_name,
      "profile_image_url"=>profile_image_url,"followers_count"=>followers_count,
      "friends_count"=>friends_count,"statuses_count"=>statuses_count
    }
  end
end