import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ThingSpeakService {
  static const String _baseUrl = 'https://api.thingspeak.com';

  // You'll need to replace these with your actual ThingSpeak channel ID and API keys
  static const String _channelId = '##';
  static const String _readApiKey = '####';
  static const String _writeApiKey = '####';

  // Cache credentials to avoid repeated SharedPreferences calls
  static Map<String, String?>? _cachedCredentials;
  static DateTime? _credentialsCacheTime;
  static const Duration _credentialsCacheExpiry = Duration(minutes: 5);

  // Cache last known good data to show when ESP32 is offline
  static Map<String, dynamic>? _lastKnownGoodData;
  static DateTime? _lastDataFetchTime;
  static const Duration _dataCacheExpiry =
      Duration(hours: 24); // Keep data for 24 hours

  // Field mappings for your ThingSpeak channel
  // Based on your actual data structure
  static const Map<String, int> _fieldMappings = {
    'temperature': 1, // Field 1: Temperature sensor
    'humidity': 2, // Field 2: Humidity sensor
    'soil_moisture': 3, // Field 3: Soil moisture sensor
    'light_level': 4, // Field 4: Light level sensor
    'extra_light': 5, // Field 5: Extra Light control (1=ON, 0=OFF)
    'watering': 6, // Field 6: Watering control (1=START, 0=STOP)
    'auto_mode': 7, // Field 7: Auto mode control (1=ENABLED, 0=DISABLED)
  };

  static Future<Map<String, dynamic>> getLatestData() async {
    try {
      // Load credentials dynamically
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final apiKey = credentials['read_api_key'] ?? _readApiKey;

      print('🔍 Fetching data from ThingSpeak...');
      print('📡 Channel ID: $channelId');
      print('🔑 API Key: ${apiKey.substring(0, 8)}...');

      // Check if using placeholder values
      if (channelId == _channelId || apiKey == _readApiKey) {
        print('❌ CRITICAL: Still using placeholder credentials!');
        print('❌ Channel ID: $channelId (should not be $_channelId)');
        print(
            '❌ API Key: ${apiKey.substring(0, 8)}... (should not be placeholder)');
        print(
            '❌ Please go to Settings and configure your actual ThingSpeak credentials');

        // Return cached data if available, otherwise return defaults
        if (_lastKnownGoodData != null) {
          print('📦 Returning cached data due to placeholder credentials');
          return _lastKnownGoodData!;
        }

        return {
          'temperature': 0.0,
          'humidity': 0.0,
          'soil_moisture': 0.0,
          'light_level': 0.0,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      print('✅ Using real credentials - proceeding with API call');

      // Try public access first (since you made your API public)
      String url;
      bool isPublicAccess = false;

      try {
        // Test public access first
        final publicUrl = '$_baseUrl/channels/$channelId/feeds.json?results=1';
        print('🌐 Testing public access first...');
        final publicResponse = await http
            .get(Uri.parse(publicUrl))
            .timeout(const Duration(seconds: 5));

        if (publicResponse.statusCode == 200) {
          print('✅ Channel is publicly accessible - using public URL');
          url = publicUrl;
          isPublicAccess = true;
        } else {
          print(
              '❌ Public access failed (Status: ${publicResponse.statusCode}) - using API key');
          url =
              '$_baseUrl/channels/$channelId/feeds.json?api_key=$apiKey&results=1';
        }
      } catch (e) {
        print('⚠️ Public access test failed, using API key: $e');
        url =
            '$_baseUrl/channels/$channelId/feeds.json?api_key=$apiKey&results=1';
      }

      print('🌐 Final URL: $url');

      // Add timeout for faster response
      print('🌐 Making HTTP request to ThingSpeak...');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body.substring(0, 500)}...');

      // Check for common HTTP errors
      if (response.statusCode == 401) {
        print('❌ ERROR: Unauthorized - Check your API key');
        print('❌ Make sure you\'re using the correct Read API Key');
      } else if (response.statusCode == 404) {
        print('❌ ERROR: Channel not found - Check your Channel ID');
        print('❌ Make sure the Channel ID exists');
      } else if (response.statusCode == 429) {
        print('❌ ERROR: Too many requests - ThingSpeak rate limit exceeded');
        print('❌ Wait a few minutes before trying again');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feeds = data['feeds'] as List;

        print('📈 Found ${feeds.length} feeds');

        if (feeds.isNotEmpty) {
          final latestFeed = feeds.first;
          print('🆕 Latest Feed: $latestFeed');

          // Check if fields exist and have valid data
          final field1 = latestFeed['field1'];
          final field2 = latestFeed['field2'];
          final field3 = latestFeed['field3'];
          final field4 = latestFeed['field4'];

          print('📊 Field Values:');
          print(
              '   Field1 (Temperature): $field1 (${field1 != null ? 'VALID' : 'NULL'})');
          print(
              '   Field2 (Humidity): $field2 (${field2 != null ? 'VALID' : 'NULL'})');
          print(
              '   Field3 (Soil Moisture): $field3 (${field3 != null ? 'VALID' : 'NULL'})');
          print(
              '   Field4 (Light Level): $field4 (${field4 != null ? 'VALID' : 'NULL'})');

          // Check if we have any valid sensor data (not null, empty, or zero)
          bool hasValidSensorData = false;
          double temp = double.tryParse(field1?.toString() ?? '0') ?? 0.0;
          double hum = double.tryParse(field2?.toString() ?? '0') ?? 0.0;
          double soil = double.tryParse(field3?.toString() ?? '0') ?? 0.0;
          double light = double.tryParse(field4?.toString() ?? '0') ?? 0.0;

          // Check if any sensor has meaningful data (not zero)
          if (temp > 0 || hum > 0 || soil > 0 || light > 0) {
            hasValidSensorData = true;
          }

          if (!hasValidSensorData) {
            print('⚠️ WARNING: No valid sensor data found in fields 1-4');
            print('⚠️ All values are zero or null - ESP32 may be offline');
            print('⚠️ Checking for cached data instead...');

            // Return cached data if available, otherwise return zeros
            if (_lastKnownGoodData != null && _lastDataFetchTime != null) {
              final timeSinceLastFetch =
                  DateTime.now().difference(_lastDataFetchTime!);

              if (timeSinceLastFetch < _dataCacheExpiry) {
                print(
                    '📦 Returning cached data (${timeSinceLastFetch.inMinutes} minutes old)');
                print('📊 Cached Data: $_lastKnownGoodData');
                return _lastKnownGoodData!;
              } else {
                print(
                    '⏰ Cached data is too old (${timeSinceLastFetch.inHours} hours)');
              }
            }

            print('🔄 No cached data available - returning zeros');
            return {
              'temperature': 0.0,
              'humidity': 0.0,
              'soil_moisture': 0.0,
              'light_level': 0.0,
              'timestamp': latestFeed['created_at'],
            };
          }

          final result = {
            'temperature': temp,
            'humidity': hum,
            'soil_moisture': soil,
            'light_level': light,
            'timestamp': latestFeed['created_at'],
          };

          // Cache this good data for offline use
          _lastKnownGoodData = result;
          _lastDataFetchTime = DateTime.now();
          print('💾 Cached valid sensor data for offline use');
          print('✅ Parsed Data: $result');
          return result;
        } else {
          print('⚠️ No feeds found in response');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
      }
    } catch (e) {
      print('💥 Error fetching ThingSpeak data: $e');
    }

    print('🔄 API call failed - checking for cached data...');

    // Check if we have cached data to return
    if (_lastKnownGoodData != null && _lastDataFetchTime != null) {
      final timeSinceLastFetch = DateTime.now().difference(_lastDataFetchTime!);

      if (timeSinceLastFetch < _dataCacheExpiry) {
        print(
            '📦 Returning cached data (${timeSinceLastFetch.inMinutes} minutes old)');
        print('📊 Cached Data: $_lastKnownGoodData');
        return _lastKnownGoodData!;
      } else {
        print('⏰ Cached data is too old (${timeSinceLastFetch.inHours} hours)');
      }
    }

    print('🔄 No cached data available - returning default values');
    // Return default values if API call fails and no cached data
    return {
      'temperature': 0.0,
      'humidity': 0.0,
      'soil_moisture': 0.0,
      'light_level': 0.0,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Future<List<Map<String, dynamic>>> getHistoricalData(
      {int results = 10}) async {
    try {
      // Load credentials dynamically
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final apiKey = credentials['read_api_key'] ?? _readApiKey;

      print('📊 Fetching historical data: $results results');
      print('📡 Channel ID: $channelId');

      // Check if using placeholder values
      if (channelId == _channelId || apiKey == _readApiKey) {
        print('❌ Cannot fetch historical data - using placeholder credentials');
        return [];
      }

      String url;
      // Try public access first
      try {
        final publicUrl =
            '$_baseUrl/channels/$channelId/feeds.json?results=$results';
        final publicResponse = await http
            .get(Uri.parse(publicUrl))
            .timeout(const Duration(seconds: 10));

        if (publicResponse.statusCode == 200) {
          print('✅ Using public access for historical data');
          url = publicUrl;
        } else {
          print('⚠️ Public access failed, using API key');
          url =
              '$_baseUrl/channels/$channelId/feeds.json?api_key=$apiKey&results=$results';
        }
      } catch (e) {
        print('⚠️ Public access test failed, using API key: $e');
        url =
            '$_baseUrl/channels/$channelId/feeds.json?api_key=$apiKey&results=$results';
      }

      print('🌐 Fetching from: $url');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      print('📊 Historical data response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feeds = data['feeds'] as List;

        print('📈 Found ${feeds.length} historical feeds');

        final historicalData = feeds
            .map((feed) => {
                  'temperature': double.tryParse(feed['field1'] ?? '0') ?? 0.0,
                  'humidity': double.tryParse(feed['field2'] ?? '0') ?? 0.0,
                  'soil_moisture':
                      double.tryParse(feed['field3'] ?? '0') ?? 0.0,
                  'light_level': double.tryParse(feed['field4'] ?? '0') ?? 0.0,
                  'timestamp': feed['created_at'],
                })
            .toList();

        print(
            '✅ Successfully parsed ${historicalData.length} historical records');
        return historicalData;
      } else {
        print('❌ Failed to fetch historical data: ${response.statusCode}');
        print('❌ Response: ${response.body}');
      }
    } catch (e) {
      print('💥 Error fetching historical ThingSpeak data: $e');
    }

    print('🔄 Returning empty historical data list');
    return [];
  }

  // Save ThingSpeak credentials
  static Future<void> saveCredentials(
      String channelId, String readApiKey, String writeApiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('thingspeak_channel_id', channelId);
      await prefs.setString('thingspeak_read_api_key', readApiKey);
      await prefs.setString('thingspeak_write_api_key', writeApiKey);

      // Clear cache to force reload of new credentials
      _cachedCredentials = null;
      _credentialsCacheTime = null;
      print('Credentials saved and cache cleared');
    } catch (e) {
      print('Error saving credentials: $e');
      // Fallback: Update the static constants directly
      _updateStaticCredentials(channelId, readApiKey, writeApiKey);
    }
  }

  // Load ThingSpeak credentials with caching
  static Future<Map<String, String?>> loadCredentials() async {
    // Check if we have valid cached credentials
    if (_cachedCredentials != null && _credentialsCacheTime != null) {
      final timeSinceCache = DateTime.now().difference(_credentialsCacheTime!);
      if (timeSinceCache < _credentialsCacheExpiry) {
        print('🔄 Using cached credentials (${timeSinceCache.inSeconds}s old)');
        return _cachedCredentials!;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final credentials = {
        'channel_id': prefs.getString('thingspeak_channel_id'),
        'read_api_key': prefs.getString('thingspeak_read_api_key'),
        'write_api_key': prefs.getString('thingspeak_write_api_key'),
      };

      print('🔑 Credentials loaded:');
      print('   Channel ID: ${credentials['channel_id'] ?? 'NULL'}');
      print(
          '   Read API Key: ${credentials['read_api_key'] != null ? 'SET' : 'NULL'}');
      print(
          '   Write API Key: ${credentials['write_api_key'] != null ? 'SET' : 'NULL'}');

      // Check if using placeholder values
      if (credentials['channel_id'] == _channelId ||
          credentials['read_api_key'] == _readApiKey ||
          credentials['write_api_key'] == _writeApiKey) {
        print('⚠️ WARNING: Using placeholder credentials!');
        print(
            '⚠️ Please configure your actual ThingSpeak credentials in Settings');
      }

      // Cache the credentials
      _cachedCredentials = credentials;
      _credentialsCacheTime = DateTime.now();
      print('💾 Credentials cached');

      return credentials;
    } catch (e) {
      print('💥 Error loading credentials: $e');
      // Return empty map if SharedPreferences fails
      return {
        'channel_id': null,
        'read_api_key': null,
        'write_api_key': null,
      };
    }
  }

  // Fallback method to update static credentials
  static void _updateStaticCredentials(
      String channelId, String readApiKey, String writeApiKey) {
    // This is a workaround when SharedPreferences fails
    // You can implement a different storage method here
    print('Credentials updated via fallback method');
    print('Channel ID: $channelId');
    print('Read API Key: $readApiKey');
    print('Write API Key: $writeApiKey');
  }

  // Update credentials if they exist
  static Future<void> updateCredentialsIfAvailable() async {
    final credentials = await loadCredentials();
    if (credentials['channel_id'] != null &&
        credentials['read_api_key'] != null) {
      // You can update the static constants here or use a different approach
      print('ThingSpeak credentials loaded: ${credentials['channel_id']}');
    }
  }

  // Initialize all control fields to 0 (default state)
  static Future<bool> initializeControlFields() async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Skipping initialization - using placeholder credentials');
        return false;
      }

      // Set all control fields to 0 using the correct API format
      final url =
          '$_baseUrl/update?api_key=$writeApiKey&field5=0&field6=0&field7=0';

      print('🚀 Initializing control fields to 0:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&field5=0&field6=0&field7=0');
      print('   Setting: Field5=0, Field6=0, Field7=0');

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Control fields initialized successfully to 0');
        return true;
      } else {
        print(
            '❌ Failed to initialize control fields. Status: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('💥 Error initializing control fields: $e');
      return false;
    }
  }

  // IoT Control Methods - Send commands to your devices
  static Future<bool> controlGrowLight(bool turnOn) async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Cannot send command - using placeholder credentials');
        return false;
      }

      // Field 5 for grow light control (1 = ON, 0 = OFF)
      final fieldValue = turnOn ? '1' : '0';

      // Use the correct API format: /update?api_key=...&field5=...
      final url = '$_baseUrl/update?api_key=$writeApiKey&field5=$fieldValue';

      print('🚀 Sending grow light command to ThingSpeak:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&field5=$fieldValue');
      print('   Field5 = $fieldValue (${turnOn ? "ON" : "OFF"})');

      // Use a very short timeout for faster response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Grow light command sent successfully: $fieldValue');
        return true;
      } else {
        print(
            '❌ Failed to send grow light command. Status: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('💥 Error controlling grow light: $e');
      return false;
    }
  }

  static Future<bool> controlWatering(bool startWatering) async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Cannot send command - using placeholder credentials');
        return false;
      }

      // Field 6 for watering control (1 = START, 0 = STOP)
      final fieldValue = startWatering ? '1' : '0';

      // Use the correct API format: /update?api_key=...&field6=...
      final url = '$_baseUrl/update?api_key=$writeApiKey&field6=$fieldValue';

      print('🚀 Sending watering command to ThingSpeak:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&field6=$fieldValue');
      print('   Field6 = $fieldValue (${startWatering ? "START" : "STOP"})');

      // Use a very short timeout for faster response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Watering command sent successfully: $fieldValue');
        return true;
      } else {
        print(
            '❌ Failed to send watering command. Status: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('💥 Error controlling watering: $e');
      return false;
    }
  }

  static Future<bool> setAutoMode(bool enable) async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Cannot send command - using placeholder credentials');
        return false;
      }

      // Field 7 for auto mode control (1 = ENABLED, 0 = DISABLED)
      final fieldValue = enable ? '1' : '0';

      // Use the correct API format: /update?api_key=...&field7=...
      final url = '$_baseUrl/update?api_key=$writeApiKey&field7=$fieldValue';

      print('🚀 Sending auto mode command to ThingSpeak:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&field7=$fieldValue');
      print('   Field7 = $fieldValue (${enable ? "ENABLED" : "DISABLED"})');

      // Use a very short timeout for faster response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Auto mode command sent successfully: $fieldValue');
        return true;
      } else {
        print(
            '❌ Failed to send auto mode command. Status: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('💥 Error setting auto mode: $e');
      return false;
    }
  }

  // Get device status from ThingSpeak
  static Future<Map<String, bool>> getDeviceStatus() async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final readApiKey = credentials['read_api_key'] ?? _readApiKey;

      final url =
          '$_baseUrl/channels/$channelId/feeds.json?api_key=$readApiKey&results=1';

      // Use timeout for faster response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feeds = data['feeds'] as List;

        if (feeds.isNotEmpty) {
          final latestFeed = feeds.first;
          return {
            'grow_light': latestFeed['field5'] == '1',
            'watering': latestFeed['field6'] == '1',
            'auto_mode': latestFeed['field7'] == '1',
          };
        }
      }
    } catch (e) {
      print('Error getting device status: $e');
    }

    return {
      'grow_light': false,
      'watering': false,
      'auto_mode': false,
    };
  }

  // Get immediate device status with public access support
  static Future<Map<String, bool>> getImmediateDeviceStatus() async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final readApiKey = credentials['read_api_key'] ?? _readApiKey;

      String url;

      // Try public access first (since you made your API public)
      try {
        final publicUrl = '$_baseUrl/channels/$channelId/feeds.json?results=1';
        final publicResponse = await http
            .get(Uri.parse(publicUrl))
            .timeout(const Duration(seconds: 2));

        if (publicResponse.statusCode == 200) {
          url = publicUrl;
        } else {
          url =
              '$_baseUrl/channels/$channelId/feeds.json?api_key=$readApiKey&results=1';
        }
      } catch (e) {
        url =
            '$_baseUrl/channels/$channelId/feeds.json?api_key=$readApiKey&results=1';
      }

      // Use very short timeout for immediate response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feeds = data['feeds'] as List;

        if (feeds.isNotEmpty) {
          final latestFeed = feeds.first;
          print('📊 Immediate Device Status:');
          print('   Field5 (Grow Light): ${latestFeed['field5']}');
          print('   Field6 (Watering): ${latestFeed['field6']}');
          print('   Field7 (Auto Mode): ${latestFeed['field7']}');

          return {
            'grow_light': latestFeed['field5'] == '1',
            'watering': latestFeed['field6'] == '1',
            'auto_mode': latestFeed['field7'] == '1',
          };
        }
      }
    } catch (e) {
      print('Error getting immediate device status: $e');
    }

    return {
      'grow_light': false,
      'watering': false,
      'auto_mode': false,
    };
  }

  // Test if channel is accessible without API key (public access)
  static Future<bool> testPublicAccess(String channelId) async {
    try {
      final publicUrl = '$_baseUrl/channels/$channelId/feeds.json?results=1';
      print('🌐 Testing public access to channel $channelId...');

      final response = await http
          .get(Uri.parse(publicUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Channel $channelId is publicly accessible');
        return true;
      } else {
        print(
            '❌ Channel $channelId is not publicly accessible (Status: ${response.statusCode})');
        return false;
      }
    } catch (e) {
      print('💥 Error testing public access: $e');
      return false;
    }
  }

  // Test connection to ThingSpeak
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final readApiKey = credentials['read_api_key'] ?? _readApiKey;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      print('🧪 Testing ThingSpeak connection...');
      print('📡 Channel ID: $channelId');
      print(
          '🔑 Read API Key: ${readApiKey != _readApiKey ? 'VALID' : 'PLACEHOLDER'}');
      print(
          '🔑 Write API Key: ${writeApiKey != _writeApiKey ? 'VALID' : 'PLACEHOLDER'}');

      // First test if channel is publicly accessible
      final isPublic = await testPublicAccess(channelId);

      // Test read access with API key
      final readUrl =
          '$_baseUrl/channels/$channelId/feeds.json?api_key=$readApiKey&results=1';
      final readResponse = await http
          .get(Uri.parse(readUrl))
          .timeout(const Duration(seconds: 10));

      // Test write access (send a test value to field5)
      final writeUrl = '$_baseUrl/update?api_key=$writeApiKey&field5=0';
      final writeResponse = await http
          .get(Uri.parse(writeUrl))
          .timeout(const Duration(seconds: 10));

      return {
        'read_status': readResponse.statusCode,
        'write_status': writeResponse.statusCode,
        'read_body': readResponse.body.substring(0, 200),
        'write_body': writeResponse.body,
        'channel_id': channelId,
        'is_public': isPublic,
        'credentials_valid': channelId != _channelId &&
            readApiKey != _readApiKey &&
            writeApiKey != _writeApiKey,
      };
    } catch (e) {
      print('💥 Error testing connection: $e');
      return {
        'error': e.toString(),
        'credentials_valid': false,
      };
    }
  }

  // Debug method to show current credential status
  static Future<void> debugCredentials() async {
    print('🔍 === THINGSPEAK CREDENTIALS DEBUG ===');

    final credentials = await loadCredentials();
    print('📡 Channel ID: ${credentials['channel_id'] ?? 'NULL'}');
    print(
        '🔑 Read API Key: ${credentials['read_api_key'] != null ? 'SET (${credentials['read_api_key']!.substring(0, 8)}...)' : 'NULL'}');
    print(
        '🔑 Write API Key: ${credentials['write_api_key'] != null ? 'SET (${credentials['write_api_key']!.substring(0, 8)}...)' : 'NULL'}');

    // Check if using placeholder values
    if (credentials['channel_id'] == _channelId) {
      print('❌ Channel ID is still placeholder: $_channelId');
    }
    if (credentials['read_api_key'] == _readApiKey) {
      print('❌ Read API Key is still placeholder: $_readApiKey');
    }
    if (credentials['write_api_key'] == _writeApiKey) {
      print('❌ Write API Key is still placeholder: $_writeApiKey');
    }

    if (credentials['channel_id'] != _channelId &&
        credentials['read_api_key'] != _readApiKey &&
        credentials['write_api_key'] != _writeApiKey) {
      print('✅ All credentials appear to be real (not placeholders)');
    } else {
      print('❌ Some credentials are still placeholders - check Settings');
    }
    print('🔍 === END DEBUG ===');
  }

  // Diagnose sensor data issues
  static Future<void> diagnoseSensorData() async {
    print('🔍 === SENSOR DATA DIAGNOSIS ===');

    try {
      final data = await getLatestData();
      print('📊 Current Sensor Readings:');
      print('   Temperature: ${data['temperature']}°C');
      print('   Humidity: ${data['humidity']}%');
      print('   Soil Moisture: ${data['soil_moisture']}%');
      print('   Light Level: ${data['light_level']}%');
      print('   Timestamp: ${data['timestamp']}');

      // Check if all values are 0.0 (indicating no data from IoT device)
      if (data['temperature'] == 0.0 &&
          data['humidity'] == 0.0 &&
          data['soil_moisture'] == 0.0 &&
          data['light_level'] == 0.0) {
        print('❌ PROBLEM: All sensor values are 0.0');
        print(
            '❌ This means your IoT device is NOT sending sensor data to ThingSpeak');
        print('');
        print(
            '🔧 SOLUTION: Your IoT device needs to send data to these fields:');
        print('   Field 1: Temperature sensor data');
        print('   Field 2: Humidity sensor data');
        print('   Field 3: Soil moisture sensor data');
        print('   Field 4: Light level sensor data');
        print('');
        print('📡 Your IoT device should send HTTP requests like:');
        print(
            '   GET https://api.thingspeak.com/update?api_key=YOUR_WRITE_API_KEY&field1=24.5&field2=65.0&field3=78.0&field4=85.0');
        print('');
        print(
            '⚠️  IMPORTANT: The app can only display data that your IoT device sends!');
      } else {
        print('✅ Sensor data is being received from ThingSpeak');
      }
    } catch (e) {
      print('💥 Error during diagnosis: $e');
    }

    print('🔍 === END DIAGNOSIS ===');
  }

  // Test sending sample sensor data to verify write API key
  static Future<bool> testSendSampleData() async {
    print('🧪 === TESTING SAMPLE DATA SEND ===');

    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Cannot test - using placeholder credentials');
        return false;
      }

      // Send sample sensor data to test if write API key works
      final sampleData = {
        'field1': '25.5', // Sample temperature
        'field2': '68.0', // Sample humidity
        'field3': '75.0', // Sample soil moisture
        'field4': '82.0', // Sample light level
      };

      final queryParams =
          sampleData.entries.map((e) => '${e.key}=${e.value}').join('&');
      final url = '$_baseUrl/update?api_key=$writeApiKey&$queryParams';

      print('🚀 Testing write API key with sample data:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&$queryParams');
      print('   Sample Data: $sampleData');

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ SUCCESS: Write API key is working!');
        print('✅ Sample data sent to ThingSpeak successfully');
        print('✅ Your IoT device should be able to send real sensor data');
        print('');
        print(
            '🔧 NEXT STEP: Configure your IoT device to send data to fields 1-4');
        print('   Example HTTP request your IoT device should send:');
        print(
            '   GET https://api.thingspeak.com/update?api_key=$writeApiKey&field1=24.5&field2=65.0&field3=78.0&field4=85.0');
        return true;
      } else {
        print('❌ FAILED: Write API key is not working');
        print('❌ Status: ${response.statusCode}, Body: ${response.body}');
        print('❌ Check your Write API Key in Settings');
        return false;
      }
    } catch (e) {
      print('💥 Error testing sample data send: $e');
      return false;
    }
  }

  // Get data age information for display
  static String getDataAgeInfo() {
    if (_lastDataFetchTime == null) {
      return 'No cached data available';
    }

    final timeSinceLastFetch = DateTime.now().difference(_lastDataFetchTime!);

    if (timeSinceLastFetch.inMinutes < 1) {
      return 'Just now';
    } else if (timeSinceLastFetch.inMinutes < 60) {
      return '${timeSinceLastFetch.inMinutes} min ago';
    } else if (timeSinceLastFetch.inHours < 24) {
      return '${timeSinceLastFetch.inHours}h ${timeSinceLastFetch.inMinutes % 60}min ago';
    } else {
      return '${timeSinceLastFetch.inDays} days ago';
    }
  }

  // Check if current data is from cache
  static bool isDataFromCache() {
    return _lastKnownGoodData != null && _lastDataFetchTime != null;
  }

  // Clear cached data
  static void clearCachedData() {
    _lastKnownGoodData = null;
    _lastDataFetchTime = null;
    print('🗑️ Cached data cleared');
  }

  // Clear all data (logout function)
  static Future<void> clearAllData() async {
    try {
      // Clear cached data
      _lastKnownGoodData = null;
      _lastDataFetchTime = null;
      _cachedCredentials = null;
      _credentialsCacheTime = null;

      // Clear stored credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('thingspeak_channel_id');
      await prefs.remove('thingspeak_read_api_key');
      await prefs.remove('thingspeak_write_api_key');

      print('🗑️ All data cleared for logout');
    } catch (e) {
      print('💥 Error clearing data: $e');
    }
  }

  // Get cache status information
  static Map<String, dynamic> getCacheStatus() {
    if (_lastKnownGoodData == null || _lastDataFetchTime == null) {
      return {
        'has_cached_data': false,
        'data_age': 'No cached data',
        'cached_values': null,
      };
    }

    final timeSinceLastFetch = DateTime.now().difference(_lastDataFetchTime!);
    String dataAge;

    if (timeSinceLastFetch.inMinutes < 1) {
      dataAge = 'Just now';
    } else if (timeSinceLastFetch.inMinutes < 60) {
      dataAge = '${timeSinceLastFetch.inMinutes} minutes ago';
    } else if (timeSinceLastFetch.inHours < 24) {
      dataAge = '${timeSinceLastFetch.inHours} hours ago';
    } else {
      dataAge = '${timeSinceLastFetch.inDays} days ago';
    }

    return {
      'has_cached_data': true,
      'data_age': dataAge,
      'cached_values': _lastKnownGoodData,
    };
  }

  // Test cache functionality by simulating offline scenario
  static Future<Map<String, dynamic>> testCacheFunctionality() async {
    print('🧪 === TESTING CACHE FUNCTIONALITY ===');

    // First, get some real data to cache
    print('📡 Step 1: Fetching real data to cache...');
    final realData = await getLatestData();
    print('📊 Real data received: $realData');

    // Check if we have cached data now
    final cacheStatus = getCacheStatus();
    print('📦 Cache status after real data: $cacheStatus');

    // Simulate offline scenario by temporarily clearing the cache
    print('📡 Step 2: Simulating offline scenario...');
    final originalCache = _lastKnownGoodData;
    final originalTime = _lastDataFetchTime;

    // Clear cache temporarily
    _lastKnownGoodData = null;
    _lastDataFetchTime = null;

    // Try to get data (should return zeros since no cache)
    print('📡 Step 3: Fetching data with no cache...');
    final noCacheData = await getLatestData();
    print('📊 Data with no cache: $noCacheData');

    // Restore cache
    _lastKnownGoodData = originalCache;
    _lastDataFetchTime = originalTime;

    // Try to get data again (should return cached data)
    print('📡 Step 4: Fetching data with cache restored...');
    final cachedData = await getLatestData();
    print('📊 Data with cache: $cachedData');

    print('🧪 === CACHE TEST COMPLETE ===');

    return {
      'real_data': realData,
      'no_cache_data': noCacheData,
      'cached_data': cachedData,
      'cache_status': cacheStatus,
    };
  }

  // Get IoT device configuration instructions
  static void showIoTDeviceInstructions() {
    print('🔧 === IOT DEVICE CONFIGURATION INSTRUCTIONS ===');
    print('');
    print(
        '📱 Your Flutter app is working correctly - it can send control commands!');
    print('📊 The issue is that your IoT device is not sending sensor data.');
    print('');
    print('🔧 WHAT YOUR IOT DEVICE NEEDS TO DO:');
    print('   1. Send HTTP GET requests to ThingSpeak every few minutes');
    print('   2. Include sensor readings in fields 1-4');
    print('   3. Use your Write API Key: 3XV1GLK3B5LAKGQK');
    print('');
    print('📡 EXAMPLE HTTP REQUEST:');
    print(
        '   GET https://api.thingspeak.com/update?api_key=3XV1GLK3B5LAKGQK&field1=24.5&field2=65.0&field3=78.0&field4=85.0');
    print('');
    print('📊 FIELD MAPPING:');
    print('   field1 = Temperature sensor (°C)');
    print('   field2 = Humidity sensor (%)');
    print('   field3 = Soil moisture sensor (%)');
    print('   field4 = Light level sensor (%)');
    print('');
    print('⏰ RECOMMENDED: Send data every 1-5 minutes');
    print('🔑 IMPORTANT: Use your Write API Key, not the Read API Key');
    print('');
    print(
        '💡 TIP: Test with a simple HTTP client first (like Postman or curl)');
    print('🔧 === END INSTRUCTIONS ===');
  }

  // Fast control method - send multiple commands at once
  static Future<bool> sendFastCommand({
    bool? growLight,
    bool? watering,
    bool? autoMode,
  }) async {
    try {
      final credentials = await loadCredentials();
      final channelId = credentials['channel_id'] ?? _channelId;
      final writeApiKey = credentials['write_api_key'] ?? _writeApiKey;

      if (channelId == _channelId || writeApiKey == _writeApiKey) {
        print('❌ Cannot send fast command - using placeholder credentials');
        return false;
      }

      // Build URL with only the fields that need to be updated
      final Map<String, String> fields = {};
      if (growLight != null) fields['field5'] = growLight ? '1' : '0';
      if (watering != null) fields['field6'] = watering ? '1' : '0';
      if (autoMode != null) fields['field7'] = autoMode ? '1' : '0';

      if (fields.isEmpty) return true;

      final queryParams =
          fields.entries.map((e) => '${e.key}=${e.value}').join('&');

      // Use the correct API format: /update?api_key=...&field5=...&field6=...
      final url = '$_baseUrl/update?api_key=$writeApiKey&$queryParams';

      print('🚀 Sending fast command to ThingSpeak:');
      print(
          '   URL: $_baseUrl/update?api_key=${writeApiKey.substring(0, 8)}...&$queryParams');
      print('   Fields: $fields');

      // Use very short timeout for faster response
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));

      print('📊 Response Status: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Fast command sent successfully: $fields');
        return true;
      } else {
        print('❌ Failed to send fast command. Status: ${response.statusCode}');
        print('❌ Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('💥 Error sending fast command: $e');
      return false;
    }
  }
}
