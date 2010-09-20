require 'net/http'
require 'rubygems'
require 'httpclient'
require 'json'
require 'uri'
require 'cgi'

module Encosion
  
  # The base for all Encosion objects
  class Base
    
    attr_accessor :read_token, :write_token

    #
    # Class methods
    #
    class << self
      
      # Does a GET to search photos and other good stuff
      def find(*args)
        options = extract_options(args)
        case args.first
        when :all   then find_all(options)
        else        find_from_ids(args,options)
        end
      end
      
        
      # This is an alias for find(:all)
      def all(*args)
        find(:all, *args)
      end
      

      # Performs an HTTP GET - listens for timeouts or other exceptions
      def get(server,port,secure,path,timeout,retries,command,options)

        body = nil        
        begin
          http = HTTPClient.new
          http.receive_timeout = timeout
          url = secure ? 'https://' : 'http://'
          # I've heard we shouldn't specify port on the real API
          if port != 80
            url += "#{server}:#{port}#{path}"
          else
            url += "#{server}#{path}"
          end
        
          options.merge!({'command' => command })
          query_string = options.collect { |key,value| "#{key.to_s}=#{CGI.escape(value.to_s)}" }.join('&')
          ext = {'Content-Type' => 'text/html;charset=UTF-8'}
          response = http.get(url, query_string, ext)

          header = response.header

          http_error_check(header)

          # Forcing encoding to UTF-8 for proper interaction with API due to HTTPClient bug
          # http://github.com/nahi/httpclient/issues#issue/26
          body = response.body.content.strip == 'null' ? nil : JSON.parse(response.body.content.force_encoding('UTF-8').strip)   # if the call returns 'null' then there were no valid results
        
          api_error_check(body)
        rescue EncosionError => e
          retry if (retries -=1 ) > 0 && e.okToRetry
          raise e
        rescue Exception => e
          raise e
        end        

        return body
      end
      
      
      # Performs an HTTP POST
      def post(server,port,secure,path,timeout,command,options,instance)
        http = HTTPClient.new
        http.send_timeout = timeout
        url = secure ? 'https://' : 'http://'
        url += "#{server}:#{port}#{path}"
        
        content = { 'json' => { 'method' => command, 'params' => options }.to_json }    # package up the variables as a JSON-RPC string
        content.merge!({ 'file' => instance.file }) if instance.respond_to?('file')             # and add a file if there is one

        response = http.post(url, content)
        # get the header and body for error checking
        body = JSON.parse(response.body.content.strip)
        header = response.header

        http_error_check(header)
        
       # if we get here then no exceptions were raised
        return body
      end
      
      
      def http_error_check(header)
        if header.status_code == 200
          return true
        else
          raise HttpException, "HTTP header status code: #{header.status_code}"
        end
      end
      
      def api_error_check(body)
        if body.nil?
          message = "Not Found or orther Brightcove Error"
          raise AssetNotFound, message
        elsif body.include?('error')
          case body['code']
          when 103
            message = 'Brightcove Timeout -- tried 5 times to contact the API, and it returned timeout errors all five times.'
            raise BrightcoveTimeoutException, message
          when 100..199
            message = "Brightcove responded with a system error: #{body['error']} (code #{body['code']})"
            raise BrightcoveLowLevelException, message
          when 200..299
            message = "Brightcove responded with an error: #{body['error']} (code #{body['code']})"
            raise BrightcoveLowLevelException, message
          when 300..399
            message = "Brightcove responded with an error: #{body['error']} (code #{body['code']})"
            raise BrightcoveHighLevelException, message
          else
            message = "Brightcove responded with an error: #{body['error']} (code #{body['code']})"
            raise EncosionError, message
          end
        else
          return true
        end
      end
      

      protected
        
        # Pulls any Hash off the end of an array of arguments and returns it
        def extract_options(opts)
          opts.last.is_a?(::Hash) ? opts.pop : {}
        end


        # Find an asset from a single or array of ids
        def find_from_ids(ids, options)
          expects_array = ids.first.kind_of?(Array)
          return ids.first if expects_array && ids.first.empty?

          ids = ids.flatten.compact.uniq

          case ids.size
            when 0
              raise AssetNotFound, "Couldn't find #{self.class} without an ID"
            when 1
              result = find_one(ids.first, options)
              expects_array ? [ result ] : result
            else
              find_some(ids, options)
          end
        end
        

        # Turns a hash into a query string and appends the token
        def queryize_args(args, type)
          case type
          when :read
            raise MissingToken, 'No read token found' if @read_token.nil?
            args.merge!({ :token => @read_token })
          when :write
            raise MissingToken, 'No write token found' if @write_token.nil?
            args.merge!({ :token => @write_token })
          end
          return args.collect { |key,value| "#{key.to_s}=#{value.to_s}" }.join('&')
        end
      
    end
    
    
  end
  
end
