require 'sinatra/base'
require 'casserver/localization'
require 'casserver/utils'
require 'casserver/cas'

require 'logger'
$LOG ||= Logger.new(STDOUT)

module CASServer
  class Server < Sinatra::Base
    set :protection, :except => :frame_options
    if ENV['CONFIG_FILE']
      CONFIG_FILE = ENV['CONFIG_FILE']
    elsif !(c_file = File.dirname(__FILE__) + "/../../config.yml").nil? && File.exist?(c_file)
      CONFIG_FILE = c_file
    else
      CONFIG_FILE = "/etc/rubycas-server/config.yml"
    end
    
    include CASServer::CAS # CAS protocol helpers
    include Localization

    set :app_file, __FILE__
    set :public_folder, Proc.new { settings.config[:public_dir] || File.join(root, "..", "..", "public") }

    config = HashWithIndifferentAccess.new(
      :maximum_unused_login_ticket_lifetime => 5.minutes,
      :maximum_unused_service_ticket_lifetime => 5.minutes, # CAS Protocol Spec, sec. 3.2.1 (recommended expiry time)
      :maximum_session_lifetime => 2.days, # all tickets are deleted after this period of time
      :log => {:file => 'casserver.log', :level => 'DEBUG'},
      :uri_path => ""
    )
    set :config, config

    def self.uri_path
      config[:uri_path]
    end
    
    # Strip the config.uri_path from the request.path_info...
    # FIXME: do we really need to override all of Sinatra's #static! to make this happen?
    def static!
      return if (public_dir = settings.public_folder).nil?
      public_dir = File.expand_path(public_dir)
      
      path = File.expand_path(public_dir + unescape(request.path_info.gsub(/^#{settings.config[:uri_path]}/,'')))
      return if path[0, public_dir.length] != public_dir
      return unless File.file?(path)

      env['sinatra.static_file'] = path
      send_file path, :disposition => nil
    end

    def self.run!(options={})
      set options

      handler      = detect_rack_handler
      handler_name = handler.name.gsub(/.*::/, '')
      
      puts "== RubyCAS-Server is starting up " +
        "on port #{config[:port] || port} for #{environment} with backup from #{handler_name}" unless handler_name =~/cgi/i
        
      begin
        opts = handler_options
      rescue Exception => e
        print_cli_message e, :error
        raise e
      end
        
      handler.run self, opts do |server|
        [:INT, :TERM].each { |sig| trap(sig) { quit!(server, handler_name) } }
        set :running, true
      end
    rescue Errno::EADDRINUSE => e
      puts "== Something is already running on port #{port}!"
    end

    def self.quit!(server, handler_name)
      ## Use thins' hard #stop! if available, otherwise just #stop
      server.respond_to?(:stop!) ? server.stop! : server.stop
      puts "\n== RubyCAS-Server is shutting down" unless handler_name =~/cgi/i
    end
    
    def self.print_cli_message(msg, type = :info)
      if respond_to?(:config) && config && config[:quiet]
        return
      end
      
      if type == :error
        io = $stderr
        prefix = "!!! "
      else
        io = $stdout
        prefix = ">>> "
      end
      
      io.puts
      io.puts "#{prefix}#{msg}"
      io.puts
    end

    def self.load_config_file(config_file)
      begin
        config_file = File.open(config_file)
      rescue Errno::ENOENT => e
        
        print_cli_message "Config file #{config_file} does not exist!", :error
        print_cli_message "Would you like the default config file copied to #{config_file.inspect}? [y/N]"
        if gets.strip.downcase == 'y'
          require 'fileutils'
          default_config = File.dirname(__FILE__) + '/../../config/config.example.yml'
          
          if !File.exists?(File.dirname(config_file))
            print_cli_message "Creating config directory..."
            FileUtils.mkdir_p(File.dirname(config_file), :verbose => true)
          end
          
          print_cli_message "Copying #{default_config.inspect} to #{config_file.inspect}..."
          FileUtils.cp(default_config, config_file, :verbose => true)
          print_cli_message "The default config has been copied. You should now edit it and try starting again."
          exit
        else
          print_cli_message "Cannot start RubyCAS-Server without a valid config file.", :error
          raise e
        end
      rescue Errno::EACCES => e
        print_cli_message "Config file #{config_file.inspect} is not readable (permission denied)!", :error
        raise e
      rescue => e
        print_cli_message "Config file #{config_file.inspect} could not be read!", :error
        raise e
      end
      
      config.merge! HashWithIndifferentAccess.new(YAML.load(config_file))
      set :server, config[:server] || 'webrick'
    end
    
    def self.reconfigure!(config)
      config.each do |key, val|
        self.config[key] = val
      end
      init_database!
      init_logger!
      init_authenticators!
    end

    def self.handler_options
      handler_options = {
        :Host => bind || config[:bind_address],
        :Port => config[:port] || 443
      }

      handler_options.merge(handler_ssl_options).to_hash.symbolize_keys!
    end

    def self.handler_ssl_options
      return {} unless config[:ssl_cert]

      cert_path = config[:ssl_cert]
      key_path = config[:ssl_key] || config[:ssl_cert]
      
      unless cert_path.nil? && key_path.nil?
        raise "The ssl_cert and ssl_key options cannot be used with mongrel. You will have to run your " +
          " server behind a reverse proxy if you want SSL under mongrel." if
            config[:server] == 'mongrel'

        raise "The specified certificate file #{cert_path.inspect} does not exist or is not readable. " +
          " Your 'ssl_cert' configuration setting must be a path to a valid " +
          " ssl certificate." unless
            File.exists? cert_path

        raise "The specified key file #{key_path.inspect} does not exist or is not readable. " +
          " Your 'ssl_key' configuration setting must be a path to a valid " +
          " ssl private key." unless
            File.exists? key_path

        require 'openssl'
        require 'webrick/https'

        cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
        key = OpenSSL::PKey::RSA.new(File.read(key_path))

        {
          :SSLEnable        => true,
          :SSLVerifyClient  => ::OpenSSL::SSL::VERIFY_NONE,
          :SSLCertificate   => cert,
          :SSLPrivateKey    => key
        }
      end
    end

    def self.init_authenticators!
      auth = []
      
      if config[:authenticator].nil?
        print_cli_message "No authenticators have been configured. Please double-check your config file (#{CONFIG_FILE.inspect}).", :error
        exit 1
      end
      
      begin
        # attempt to instantiate the authenticator
        config[:authenticator] = [config[:authenticator]] unless config[:authenticator].instance_of? Array
        config[:authenticator].each { |authenticator| auth << authenticator[:class].constantize}
      rescue NameError
        if config[:authenticator].instance_of? Array
          config[:authenticator].each do |authenticator|
            if !authenticator[:source].nil?
              # config.yml explicitly names source file
              require authenticator[:source]
            else
              # the authenticator class hasn't yet been loaded, so lets try to load it from the casserver/authenticators directory
              auth_rb = authenticator[:class].underscore.gsub('cas_server/', '')
              require 'casserver/'+auth_rb
            end
            auth << authenticator[:class].constantize
          end
        else
          if config[:authenticator][:source]
            # config.yml explicitly names source file
            require config[:authenticator][:source]
          else
            # the authenticator class hasn't yet been loaded, so lets try to load it from the casserver/authenticators directory
            auth_rb = config[:authenticator][:class].underscore.gsub('cas_server/', '')
            require 'casserver/'+auth_rb
          end

          auth << config[:authenticator][:class].constantize
          config[:authenticator] = [config[:authenticator]]
        end
      end

      auth.zip(config[:authenticator]).each_with_index{ |auth_conf, index|
        authenticator, conf = auth_conf
        $LOG.debug "About to setup #{authenticator} with #{conf.inspect}..."
        authenticator.setup(conf.merge('auth_index' => index)) if authenticator.respond_to?(:setup)
        $LOG.debug "Done setting up #{authenticator}."
      }

      set :auth, auth
    end

    def self.init_logger!
      if config[:log]
        if $LOG && config[:log][:file]
          print_cli_message "Redirecting RubyCAS-Server log to #{config[:log][:file]}"
          #$LOG.close
          $LOG = Logger.new(config[:log][:file])
        end
        $LOG.level = Logger.const_get(config[:log][:level]) if config[:log][:level]
      end
      
      if config[:db_log]
        if $LOG && config[:db_log][:file]
          $LOG.debug "Redirecting ActiveRecord log to #{config[:log][:file]}"
          #$LOG.close
          ActiveRecord::Base.logger = Logger.new(config[:db_log][:file])
        end
        ActiveRecord::Base.logger.level = Logger.const_get(config[:db_log][:level]) if config[:db_log][:level]
      end
    end

    def self.init_database!
      unless config[:disable_auto_migrations]
        ActiveRecord::Base.establish_connection(config[:database][ENV["RAILS_ENV"]])
        print_cli_message "Running migrations to make sure your database schema is up to date..."
        prev_db_log = ActiveRecord::Base.logger
        ActiveRecord::Base.logger = Logger.new(STDOUT)
        ActiveRecord::Migration.verbose = true
        ActiveRecord::Migrator.migrate(File.dirname(__FILE__) + "/../../db/migrate")
        ActiveRecord::Base.logger = prev_db_log
        print_cli_message "Your database is now up to date."
      end
      
      ActiveRecord::Base.establish_connection(config[:database][ENV["RAILS_ENV"]])
    end

    configure do
      load_config_file(CONFIG_FILE)
      init_logger!
      init_database!
      init_authenticators!
    end

    before do
      GetText.locale = determine_locale(request)
      content_type :html, 'charset' => 'utf-8'
      @theme = settings.config[:theme]
      @organization = settings.config[:organization]
      @uri_path = settings.config[:uri_path]
      @infoline = settings.config[:infoline]
      @custom_views = settings.config[:custom_views]
      @template_engine = settings.config[:template_engine] || :erb
      if @template_engine != :erb
        require @template_engine
        @template_engine = @template_engine.to_sym
      end
    end
    
      # Helpers
    def response_status_from_error(error)
      case error.code.to_s
      when /^INVALID_/, 'BAD_PGT'
        422
      when 'INTERNAL_ERROR'
        500
      else
        500
      end
    end
    
    def serialize_extra_attribute(builder, key, value)
      if value.kind_of?(String)
        builder.tag! key, value
      elsif value.kind_of?(Numeric)
        builder.tag! key, value.to_s
      else
        builder.tag! key do
          builder.cdata! value.to_yaml
        end
      end
    end

    def compile_template(engine, data, options, views)
      super engine, data, options, @custom_views || views
    rescue Errno::ENOENT
      raise unless @custom_views
      super engine, data, options, views
    end


    ##############自己 写的 action #################
     post "#{uri_path}/login" do
      Utils::log_controller_action(self.class, params)
      
      @email = params['email']
      @password = params['password']
      @app = params['app']
      @remember_me = params["remember_me"] 

      @email.strip! if @email
      
      credentials_are_valid = false
      extra_attributes = {}
      credentials_are_valid,@error = CasUser.new.validate(
            :email => @email,
            :password => @password,
            :app => @app,
            :request => @env
      )
      set_p3p_header
      if credentials_are_valid
        generate_tgt_and_st(@email,extra_attributes)
        render :haml,:"mindpin/auth_success"
      else
        render :haml,:"mindpin/auth_failure"
      end
    end
    
    get "#{uri_path}/logout" do
      CASServer::Utils::log_controller_action(self.class, params)
      @from = params['from']
      # 删除 cookie tgt
      tgt = CASServer::Model::TicketGrantingTicket.find_by_ticket(request.cookies['tgt'])
      response.delete_cookie 'tgt'
      
      # 删除 tgt 和其对应的 st的  数据库条目
      if tgt
        CASServer::Model::TicketGrantingTicket.transaction do
          tgt.granted_service_tickets{|st|st.destroy} 
          tgt.destroy
        end
      end
      status 200
      render :haml,:"mindpin/logout"
    end
    
    get "#{uri_path}/connect_tsina" do
      tsina = Tsina.new
      oauth_token_secret = tsina.request_token.params["oauth_token_secret"]
      response.set_cookie('oauth_token_secret', oauth_token_secret)
      redirect tsina.authorize_url(params[:app])
    end
    
    get "#{uri_path}/connect_tsina_callback" do
      oauth_token = params['oauth_token']
      oauth_token_secret = request.cookies['oauth_token_secret']
      response.delete_cookie 'oauth_token_secret'
      tsina_user_info = Tsina.get_tsina_user_info(oauth_token,oauth_token_secret,params[:oauth_verifier])
      
      connect_id = tsina_user_info["connect_id"]
      connect_user = ConnectUser.get_by_tsina_connect_id(connect_id)
      @app = params[:app]
      set_p3p_header
      user = connect_user.user
      if !user.blank?
        generate_tgt_and_st(user.email)
        render :haml,:"mindpin/tsina_connect_success"
      end
    end
    
    def generate_tgt_and_st(email,extra_attributes={})
      tgt = generate_ticket_granting_ticket(email, extra_attributes)
      response.set_cookie('tgt', tgt.to_s)
      @apps = settings.config["apps"]
      @st_hash = {}
      @apps.each do |app|
        st = generate_service_ticket(app, email, tgt)
        @st_hash[app] = st.to_s
      end
    end
    
    def set_p3p_header
      headers['P3P'] = 'CP="CURa ADMa DEVa PSAo PSDo OUR BUS UNI PUR INT DEM STA PRE COM NAV OTC NOI DSP COR"'
    end
    
    
    # st 过期，暂时不考虑这种情况
#    post "#{uri_path}/get_st" do
#      CASServer::Utils::log_controller_action(self.class, params)
#      @app = params['app']
#      
#      tgt = CASServer::Model::TicketGrantingTicket.find_by_ticket(request.cookies['tgt'])
#      
#      @apps = settings.config["apps"]
#      if tgt && @app && @apps.include?(@app)
#        st = tgt.granted_service_tickets.find_by_service(@app)
#        st.destroy
#        new_st = generate_service_ticket(@app, tgt.username, tgt)
#      end
#    end

  end
end
