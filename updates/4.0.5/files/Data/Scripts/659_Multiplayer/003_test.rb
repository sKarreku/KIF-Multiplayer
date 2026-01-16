#===============================================================================
# Win32API HTTP Test Script
#===============================================================================
# Tests if Win32API can make HTTP requests using WinINet.dll
#===============================================================================

if defined?(MultiplayerDebug)
  MultiplayerDebug.info("WIN32-HTTP-TEST", "=" * 60)
  MultiplayerDebug.info("WIN32-HTTP-TEST", "Testing Win32API HTTP availability...")
  MultiplayerDebug.info("WIN32-HTTP-TEST", "=" * 60)

  # Test 1: Check if Win32API is available (already loaded by game)
  begin
    # Win32API is already available in Pokemon Essentials, no require needed
    MultiplayerDebug.info("WIN32-HTTP-TEST", "[OK] Win32API is available (class exists: #{defined?(Win32API)})")
    win32_available = defined?(Win32API) == 'constant'
  rescue => e
    MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] Win32API check failed: #{e.message}")
    win32_available = false
  end

  if win32_available
    # Test 2: Try to access WinINet.dll functions
    begin
      # InternetOpenA - Initialize WinINet
      internet_open = Win32API.new('wininet', 'InternetOpenA', ['P', 'L', 'P', 'P', 'L'], 'L')

      # InternetOpenUrlA - Open URL connection
      internet_open_url = Win32API.new('wininet', 'InternetOpenUrlA', ['L', 'P', 'P', 'L', 'L', 'L'], 'L')

      # InternetReadFile - Read data from URL
      internet_read_file = Win32API.new('wininet', 'InternetReadFile', ['L', 'P', 'L', 'P'], 'I')

      # InternetCloseHandle - Close handle
      internet_close_handle = Win32API.new('wininet', 'InternetCloseHandle', ['L'], 'I')

      MultiplayerDebug.info("WIN32-HTTP-TEST", "[OK] WinINet.dll functions loaded successfully")
      wininet_available = true
    rescue => e
      MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] Failed to load WinINet.dll: #{e.class} - #{e.message}")
      wininet_available = false
    end

    # Test 3: Try a simple HTTP request
    if wininet_available
      MultiplayerDebug.info("WIN32-HTTP-TEST", "Attempting HTTP request via Win32API...")
      begin
        # Initialize WinINet session
        h_internet = internet_open.call("RubyHTTPTest", 1, nil, nil, 0)

        if h_internet != 0
          MultiplayerDebug.info("WIN32-HTTP-TEST", "[OK] WinINet session initialized (handle: #{h_internet})")

          # Try to open URL (simple HTTP, not HTTPS for testing)
          test_url = "http://example.com"
          h_url = internet_open_url.call(h_internet, test_url, nil, 0, 0, 0)

          if h_url != 0
            MultiplayerDebug.info("WIN32-HTTP-TEST", "[OK] URL opened successfully (handle: #{h_url})")

            # Try to read some data
            buffer = "\0" * 1024
            bytes_read = [0].pack('L')
            result = internet_read_file.call(h_url, buffer, 1024, bytes_read)

            if result != 0
              bytes = bytes_read.unpack('L')[0]
              MultiplayerDebug.info("WIN32-HTTP-TEST", "[OK] HTTP request successful! Read #{bytes} bytes")
              MultiplayerDebug.info("WIN32-HTTP-TEST", "Response preview: #{buffer[0..100].gsub(/[^\x20-\x7E]/, '')}...")
            else
              MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] InternetReadFile failed")
            end

            # Close URL handle
            internet_close_handle.call(h_url)
          else
            MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] Failed to open URL: #{test_url}")
          end

          # Close session handle
          internet_close_handle.call(h_internet)
        else
          MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] InternetOpen failed")
        end

      rescue => e
        MultiplayerDebug.info("WIN32-HTTP-TEST", "[FAIL] HTTP request failed: #{e.class} - #{e.message}")
        MultiplayerDebug.info("WIN32-HTTP-TEST", "Backtrace: #{e.backtrace.first(3).join(' | ')}")
      end
    end
  end

  # Summary
  MultiplayerDebug.info("WIN32-HTTP-TEST", "=" * 60)
  MultiplayerDebug.info("WIN32-HTTP-TEST", "SUMMARY")
  MultiplayerDebug.info("WIN32-HTTP-TEST", "=" * 60)
  MultiplayerDebug.info("WIN32-HTTP-TEST", "Win32API:      #{win32_available ? 'YES' : 'NO'}")
  MultiplayerDebug.info("WIN32-HTTP-TEST", "WinINet.dll:   #{defined?(wininet_available) && wininet_available ? 'YES' : 'NO'}")
  MultiplayerDebug.info("WIN32-HTTP-TEST", "HTTP Requests: #{defined?(wininet_available) && wininet_available ? 'POSSIBLE' : 'NOT POSSIBLE'}")
  MultiplayerDebug.info("WIN32-HTTP-TEST", "=" * 60)
end
