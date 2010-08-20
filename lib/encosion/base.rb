require 'net/http'
require 'rubygems'
require 'httpclient'
require 'json'

module Encosion
  
  # Generic Encosion error class
  class EncosionError < StandardError
  end
  
  # Raised when there is no token (required to use the Brightcove API)
  class MissingToken < EncosionError
  end
  
  # Raised when some parameter is missing that we need in order to do a search
  class AssetNotFound < EncosionError
  end
  
  # Raised when Brightcove doesn't like the call that was made for whatever reason
  class BrightcoveException < EncosionError
  end
  
  # Raised when Brightcove doesn't like the call that was made for whatever reason
  class NoFile < EncosionError
  end
  
  class BrightcoveTimeoutException < EncosionError
  end
  
  class HttpException < EncosionError
  end
  
  
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
          url += "#{server}:#{port}#{path}"
        
          options.merge!({'command' => command })
          query_string = options.collect { |key,value| "#{key.to_s}=#{value.to_s}" }.join('&')
        
          response = http.get(url, query_string)

          header = response.header
        
          http_error_check(header)

          body = response.body.content.strip == 'null' ? nil : JSON.parse(response.body.content.strip)   # if the call returns 'null' then there were no valid results
        
          api_error_check(body)
        rescue BrightcoveTimeoutException => e
          retry if (retries -=1 ) > 0
          raise e
        rescue BrightcoveException => e
          raise e
        end        
        # puts "url: #{url}\nquery_string:#{query_string}"

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
        
        retries = 5
        
        begin
          api_error_check(body)
        rescue BrightcoveTimeoutException
          retry if (retries -=1 ) > 0
        end
        
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
        unless body['error'].blank?
          if body['code'] == '103'
            message = 'Brightcove Timeout'
            raise BrightcoveTimeoutException, message
          else            
            message = "Brightcove responded with an error: #{body['error']} (code #{body['code']})"
            raise BrightcoveException, message
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
