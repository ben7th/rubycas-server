# MINDPIN SSO 验证服务，基于 RubyCas 修改而来

需要进行单点登录的工程，引用Client的方法：

1 在 config.autoload_paths 中增加Client相关代码的引用路径，如：

```ruby
  config.autoload_paths += Dir["/web/2010/mindpin-sso/lib/custom_lib/**/"]
```

2 在 routes 配置里增加如下配置：

```ruby
  get '/ajax_login_failure' => 'sso_auth#ajax_login_failure'
  get '/crosslogin'         => 'sso_auth#crosslogin'
  get '/ajax_login_success' => 'sso_auth#ajax_login_success'
  get '/crosslogout'        => 'sso_auth#crosslogout'
```

3 增加 SsoAuthController 代码如下：

```ruby
  class SsoAuthController < ApplicationController
    include SSOClientControllerMethods
    skip_before_filter :sso_validate_st
    
    def login
    end
  end
```
  
4 在 ApplicationController 添加如下声明

```ruby
  class ApplicationController < ActionController::Base
    # ....
  
    include SSOAuthenticatedSystem
    def _this_app_name; '应用名称'; end
    before_filter :sso_validate_st
  end
```  

5 在 User 类 include UserAuthMethods
