#===============================================================================
# HTTP Wrapper Module - Win32API WinINet Implementation
#===============================================================================
# Provides HTTP GET and file download capabilities using Win32API
# No external dependencies - uses Windows WinINet.dll
#===============================================================================

module HTTPWrapper
  module_function

  # WinINet function handles (initialized on first use)
  @internet_open = nil
  @internet_open_url = nil
  @internet_read_file = nil
  @internet_close_handle = nil
  @internet_query_data_available = nil
  @http_query_info = nil

  # Initialize WinINet functions
  def init_wininet
    return if @internet_open # Already initialized

    @internet_open = Win32API.new('wininet', 'InternetOpenA', ['P', 'L', 'P', 'P', 'L'], 'L')
    @internet_open_url = Win32API.new('wininet', 'InternetOpenUrlA', ['L', 'P', 'P', 'L', 'L', 'L'], 'L')
    @internet_read_file = Win32API.new('wininet', 'InternetReadFile', ['L', 'P', 'L', 'P'], 'I')
    @internet_close_handle = Win32API.new('wininet', 'InternetCloseHandle', ['L'], 'I')
    @internet_query_data_available = Win32API.new('wininet', 'InternetQueryDataAvailable', ['L', 'P', 'L', 'L'], 'I')
    @http_query_info = Win32API.new('wininet', 'HttpQueryInfoA', ['L', 'L', 'P', 'P', 'P'], 'I')
  rescue => e
    MultiplayerDebug.error("HTTP-WRAPPER", "Failed to initialize WinINet: #{e.message}") if defined?(MultiplayerDebug)
    return false
  end

  # Get HTTP status code from WinINet handle
  # @param h_url [Integer] WinINet URL handle
  # @return [Integer, nil] HTTP status code or nil on failure
  def get_http_status_code(h_url)
    return nil unless @http_query_info

    # HTTP_QUERY_STATUS_CODE = 19
    # HTTP_QUERY_FLAG_NUMBER = 0x20000000
    buffer = "\0" * 4  # DWORD buffer
    buffer_len = [4].pack('L')
    index = [0].pack('L')

    result = @http_query_info.call(h_url, 19 | 0x20000000, buffer, buffer_len, index)
    return nil if result == 0

    status_code = buffer.unpack('L')[0]
    return status_code
  end

  # Perform HTTP GET request
  # @param url [String] URL to fetch
  # @param timeout [Integer] Timeout in seconds (default 30)
  # @return [String, nil] Response body or nil on failure
  def http_get(url, timeout = 30)
    init_wininet
    return nil unless @internet_open

    h_internet = nil
    h_url = nil

    begin
      # Open internet session
      h_internet = @internet_open.call("KIF-Multiplayer-Updater/1.0", 1, nil, nil, 0)
      return nil if h_internet == 0

      # Open URL connection (HTTPS supported automatically)
      h_url = @internet_open_url.call(h_internet, url, nil, 0, 0, 0)
      return nil if h_url == 0

      # Check HTTP status code
      status_code = get_http_status_code(h_url)
      if status_code && status_code != 200
        MultiplayerDebug.error("HTTP-WRAPPER", "HTTP #{status_code} for #{url}") if defined?(MultiplayerDebug)
        return nil
      end

      # Read response in chunks
      response = ""
      buffer_size = 4096
      buffer = "\0" * buffer_size
      bytes_read = [0].pack('L')

      loop do
        result = @internet_read_file.call(h_url, buffer, buffer_size, bytes_read)
        break if result == 0

        read_count = bytes_read.unpack('L')[0]
        break if read_count == 0

        response << buffer[0, read_count]
      end

      MultiplayerDebug.info("HTTP-WRAPPER", "GET #{url} - #{response.length} bytes") if defined?(MultiplayerDebug)
      return response

    rescue => e
      MultiplayerDebug.error("HTTP-WRAPPER", "GET failed: #{e.message}") if defined?(MultiplayerDebug)
      return nil
    ensure
      @internet_close_handle.call(h_url) if h_url && h_url != 0
      @internet_close_handle.call(h_internet) if h_internet && h_internet != 0
    end
  end

  # Download file from URL with MD5 verification
  # @param url [String] URL to download from
  # @param local_path [String] Local file path to save to
  # @param expected_md5 [String, nil] Expected MD5 hash (optional)
  # @return [Boolean] True if successful, false otherwise
  def http_download_file(url, local_path, expected_md5 = nil)
    init_wininet
    return false unless @internet_open

    temp_path = "#{local_path}.tmp"
    h_internet = nil
    h_url = nil

    begin
      # Ensure parent directory exists
      parent_dir = File.dirname(local_path)
      if !Dir.exist?(parent_dir)
        parts = parent_dir.split(/[\/\\]/)
        current = ""
        parts.each do |part|
          current = current.empty? ? part : File.join(current, part)
          Dir.mkdir(current) unless Dir.exist?(current)
        end
      end

      # Open internet session
      h_internet = @internet_open.call("KIF-Multiplayer-Updater/1.0", 1, nil, nil, 0)
      return false if h_internet == 0

      # Open URL connection
      h_url = @internet_open_url.call(h_internet, url, nil, 0, 0, 0)
      return false if h_url == 0

      # Check HTTP status code
      status_code = get_http_status_code(h_url)
      if status_code && status_code != 200
        MultiplayerDebug.error("HTTP-WRAPPER", "HTTP #{status_code} for #{url}") if defined?(MultiplayerDebug)
        return false
      end

      # Download to temp file
      File.open(temp_path, 'wb') do |file|
        buffer_size = 8192
        buffer = "\0" * buffer_size
        bytes_read = [0].pack('L')

        loop do
          result = @internet_read_file.call(h_url, buffer, buffer_size, bytes_read)
          break if result == 0

          read_count = bytes_read.unpack('L')[0]
          break if read_count == 0

          file.write(buffer[0, read_count])
        end
      end

      # Verify MD5 if provided
      if expected_md5
        actual_md5 = calculate_md5(temp_path)
        if actual_md5 != expected_md5
          MultiplayerDebug.error("HTTP-WRAPPER", "MD5 mismatch for #{url}") if defined?(MultiplayerDebug)
          File.delete(temp_path) if File.exist?(temp_path)
          return false
        end
      end

      # Atomic move: delete old file, rename temp to final
      File.delete(local_path) if File.exist?(local_path)
      File.rename(temp_path, local_path)

      MultiplayerDebug.info("HTTP-WRAPPER", "Downloaded #{url} -> #{local_path}") if defined?(MultiplayerDebug)
      return true

    rescue => e
      MultiplayerDebug.error("HTTP-WRAPPER", "Download failed: #{e.message}") if defined?(MultiplayerDebug)
      File.delete(temp_path) if File.exist?(temp_path)
      return false
    ensure
      @internet_close_handle.call(h_url) if h_url && h_url != 0
      @internet_close_handle.call(h_internet) if h_internet && h_internet != 0
    end
  end

  # Calculate MD5 hash of a file
  # @param file_path [String] Path to file
  # @return [String] MD5 hash in hexadecimal
  def calculate_md5(file_path)
    PureMD5.file_hexdigest(file_path)
  end

  # Check if URL is accessible (HEAD request simulation)
  # @param url [String] URL to check
  # @return [Boolean] True if accessible
  def url_accessible?(url)
    response = http_get(url)
    return !response.nil? && response.length > 0
  end
end

#-------------------------------------------------------------------------------
# Module loaded successfully
#-------------------------------------------------------------------------------
if defined?(MultiplayerDebug)
  MultiplayerDebug.info("HTTP-WRAPPER", "=" * 60)
  MultiplayerDebug.info("HTTP-WRAPPER", "001_HTTP_Wrapper.rb loaded successfully")
  MultiplayerDebug.info("HTTP-WRAPPER", "HTTP downloads enabled via Win32API WinINet")
  MultiplayerDebug.info("HTTP-WRAPPER", "=" * 60)
end
