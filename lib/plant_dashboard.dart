import 'dart:async';
import 'package:flutter/material.dart';
import 'thingspeak_service.dart';
import 'settings_page.dart';
import 'history_page.dart';

class PlantDashboard extends StatefulWidget {
  const PlantDashboard({super.key});

  @override
  _PlantDashboardState createState() => _PlantDashboardState();
}

class _PlantDashboardState extends State<PlantDashboard> {
  double temperature = 24.5;
  double humidity = 65.0;
  double soilMoisture = 78.0;
  double lightLevel = 85.0;
  bool isLightOn = false;
  bool isWatering = false;
  bool isAutoMode = true;
  bool isLoading = true;
  bool isDataFromCache = false;
  String lastUpdateTime = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadThingSpeakData();
    _startAutoRefresh();
    _initializeControlFields();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadThingSpeakData() async {
    setState(() {
      isLoading = true;
    });

    try {
      print('🔄 Loading latest data from ThingSpeak...');

      final data = await ThingSpeakService.getLatestData();
      if (data.isNotEmpty) {
        print('✅ Received data from ThingSpeak: $data');

        // Check if data is from cache
        final isFromCache = ThingSpeakService.isDataFromCache();
        final dataAge = ThingSpeakService.getDataAgeInfo();

        setState(() {
          temperature = data['temperature'] ?? temperature;
          humidity = data['humidity'] ?? humidity;
          soilMoisture = data['soil_moisture'] ?? soilMoisture;
          lightLevel = data['light_level'] ?? lightLevel;
          lastUpdateTime = _formatTimestamp(data['timestamp']);
          isDataFromCache = isFromCache;
        });

        if (isFromCache) {
          print('📦 Data is from cache: $dataAge');
          print(
              '📊 Cached sensor values: Temp=$temperature°C, Humidity=$humidity%, Soil=$soilMoisture%, Light=$lightLevel%');
        } else {
          print('🆕 Fresh data from ThingSpeak');
          print(
              '📊 Updated sensor values: Temp=$temperature°C, Humidity=$humidity%, Soil=$soilMoisture%, Light=$lightLevel%');
        }
      } else {
        print(
            '⚠️ No new data received from ThingSpeak, keeping previous values');
        // Keep the existing values instead of resetting them
        // This ensures the app always shows the last known good data
      }

      // Also load device status from ThingSpeak
      print('🔄 Loading device status from ThingSpeak...');
      final deviceStatus = await ThingSpeakService.getDeviceStatus();
      if (deviceStatus.isNotEmpty) {
        print('✅ Received device status: $deviceStatus');

        setState(() {
          isLightOn = deviceStatus['grow_light'] ?? isLightOn;
          isWatering = deviceStatus['watering'] ?? isWatering;
          isAutoMode = deviceStatus['auto_mode'] ?? isAutoMode;
        });

        print(
            '🎛️ Updated device status: Light=$isLightOn, Watering=$isWatering, Auto=$isAutoMode');
      } else {
        print('⚠️ No device status received, keeping previous values');
        // Keep existing device status values
      }
    } catch (e) {
      print('❌ Error loading ThingSpeak data: $e');

      // Show error message to user but don't reset the data
      String errorMessage = 'Could not refresh data';

      if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout - check your internet';
      } else if (e.toString().contains('credentials')) {
        errorMessage = 'Invalid credentials - check Settings';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network error - check your connection';
      } else {
        errorMessage = 'Error: ${e.toString().split(':').last.trim()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('⚠️ $errorMessage')),
            ],
          ),
          backgroundColor: Colors.orange.shade600,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              print('🔄 User requested retry');
              _loadThingSpeakData();
            },
          ),
        ),
      );

      // Keep existing values - don't reset them on error
      print('🔄 Keeping existing data values due to error');
    } finally {
      setState(() {
        isLoading = false;
      });
      print('✅ Data loading completed');
    }
  }

  Future<void> _initializeControlFields() async {
    try {
      print('Initializing IoT control fields to default values...');
      final success = await ThingSpeakService.initializeControlFields();
      if (success) {
        print('IoT control fields initialized to 0 successfully');
      } else {
        print('IoT control fields initialization skipped or failed');
      }
    } catch (e) {
      print('Error initializing control fields: $e');
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _loadThingSpeakData();
    });
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ${difference.inMinutes % 60}min ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        // For older data, show the actual date
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color: Colors.red.shade500,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade200.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.notifications,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => _showNotifications(context),
            tooltip: 'Notifications',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.green.shade200.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.eco,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'PlantKipper',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B5E20),
        elevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.teal.shade50,
                Colors.green.shade50,
                Colors.lightGreen.shade50,
                Colors.lime.shade50,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isAutoMode
                    ? [Colors.green.shade400, Colors.green.shade600]
                    : [Colors.grey.shade300, Colors.grey.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: isAutoMode
                      ? Colors.green.shade200.withOpacity(0.4)
                      : Colors.grey.shade300.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isAutoMode ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: isAutoMode ? Colors.white : Colors.grey.shade600,
                size: 20,
              ),
              onPressed: () => _toggleAutoMode(!isAutoMode),
              tooltip: 'Auto Mode',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.shade400,
                  Colors.amber.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.shade200.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isLoading ? Icons.refresh : Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
              onPressed: isLoading ? null : _loadThingSpeakData,
              tooltip: 'Refresh Data',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade400,
                  Colors.indigo.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade200.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.settings,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
              tooltip: 'Settings',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade400,
                    Colors.green.shade600,
                    Colors.green.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade200.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.eco,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back! 🌱',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your plants are thriving today',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                color: Colors.white.withOpacity(0.8),
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Row(
                                children: [
                                  Text(
                                    'Last updated: $lastUpdateTime',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isDataFromCache) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'CACHED',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Plant Health Status - Now second
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade600,
                    Colors.teal.shade500,
                    Colors.lightGreen.shade400,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade200.withOpacity(0.6),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Health Icon and Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.health_and_safety,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plant Health Status',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Real-time monitoring',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'EXCELLENT HEALTH',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Health Description
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: const Text(
                      'All systems are operating at optimal levels. Your plants are receiving perfect care with ideal temperature, humidity, and lighting conditions.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Status Overview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade200.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Status Overview',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Status Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _buildStatusCard(
                  'Temperature',
                  '${temperature.toStringAsFixed(1)}°C',
                  Icons.thermostat,
                  Colors.red.shade500,
                  _getTemperatureStatus(),
                ),
                _buildStatusCard(
                  'Humidity',
                  '${humidity.toStringAsFixed(1)}%',
                  Icons.water_drop,
                  Colors.blue.shade500,
                  _getHumidityStatus(),
                ),
                _buildStatusCard(
                  'Soil Moisture',
                  '${soilMoisture.toStringAsFixed(1)}%',
                  Icons.grass,
                  Colors.green.shade600,
                  _getMoistureStatus(),
                ),
                _buildStatusCard(
                  'Light Level',
                  '${lightLevel.toStringAsFixed(1)}%',
                  Icons.wb_sunny,
                  Colors.orange.shade500,
                  _getLightStatus(),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Controls Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade200.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Smart Controls',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Control Cards
            _buildControlCard(
              'Grow Light',
              'Control artificial lighting for optimal growth',
              Icons.lightbulb,
              isLightOn ? Colors.amber.shade600 : Colors.orange.shade400,
              isLightOn ? 'ACTIVE' : 'INACTIVE',
              Switch(
                value: isLightOn,
                onChanged:
                    _toggleGrowLight, // Use the new method for immediate feedback
                activeThumbColor: Colors.green.shade600,
              ),
              isLightOn,
            ),
            const SizedBox(height: 16),

            _buildControlCard(
              'Watering System',
              'Smart irrigation control system',
              Icons.water_drop,
              isWatering ? Colors.blue.shade600 : Colors.teal.shade400,
              isWatering ? 'WATERING...' : 'READY',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Start Watering Button
                  ElevatedButton(
                    onPressed: isWatering ? null : () => _toggleWatering(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isWatering
                          ? Colors.grey.shade300
                          : Colors.green.shade600,
                      foregroundColor:
                          isWatering ? Colors.grey.shade600 : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: isWatering ? 0 : 4,
                      shadowColor: Colors.green.shade200,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                      isWatering ? 'Watering...' : 'Water Now',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  // Manual Stop Button (only show when watering)
                  if (isWatering) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _toggleWatering(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                        shadowColor: Colors.red.shade200,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: const Text(
                        'Stop Now',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              isWatering,
            ),
            const SizedBox(height: 40),

            // Quick Actions
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.purple.shade600,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.shade200.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    'View History',
                    Icons.history,
                    Colors.blue.shade600,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HistoryPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildQuickActionButton(
                    'Add Plant',
                    Icons.add,
                    Colors.green.shade600,
                    () {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
      String title, String value, IconData icon, Color color, String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            color.withOpacity(0.05),
            color.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.2),
                      color.withOpacity(0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              shadows: [
                Shadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getStatusColor(status).withOpacity(0.2),
                  _getStatusColor(status).withOpacity(0.3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _getStatusColor(status).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: _getStatusColor(status),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard(String title, String subtitle, IconData icon,
      Color iconColor, String status, Widget control, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isActive ? iconColor.withOpacity(0.1) : Colors.green.shade50,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isActive ? iconColor.withOpacity(0.2) : Colors.green.shade100,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  isActive ? iconColor.withOpacity(0.1) : Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? iconColor.withOpacity(0.1)
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? iconColor : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
      String title, IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Column(
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Normal':
      case 'OK':
        return Colors.green.shade600;
      case 'Cold':
      case 'Hot':
      case 'Low':
      case 'High':
      case 'Dry':
      case 'Wet':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Normal':
      case 'OK':
        return Icons.check_circle;
      case 'Cold':
      case 'Hot':
      case 'Low':
      case 'High':
      case 'Dry':
      case 'Wet':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }

  String _getTemperatureStatus() {
    if (temperature < 18) return 'Cold';
    if (temperature > 30) return 'Hot';
    return 'Normal';
  }

  String _getHumidityStatus() {
    if (humidity < 40) return 'Low';
    if (humidity > 80) return 'High';
    return 'Normal';
  }

  String _getMoistureStatus() {
    if (soilMoisture < 30) return 'Dry';
    if (soilMoisture > 90) return 'Wet';
    return 'Normal';
  }

  String _getLightStatus() {
    if (lightLevel < 50) return 'Low';
    if (lightLevel > 90) return 'High';
    return 'Normal';
  }

  void _showNotifications(BuildContext context) {
    // Generate dynamic notifications based on current sensor data
    final notifications = _generateNotifications();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red.shade400,
                            Colors.pink.shade500,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Notifications list
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All systems are running smoothly!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return _buildNotificationItem(
                            notification['title'],
                            notification['message'],
                            notification['time'],
                            notification['icon'],
                            notification['color'],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _generateNotifications() {
    final notifications = <Map<String, dynamic>>[];
    final now = DateTime.now();

    // Check for critical alerts first
    if (temperature < 18) {
      notifications.add({
        'title': 'Temperature Alert',
        'message':
            'Temperature is too low (${temperature.toStringAsFixed(1)}°C). Consider moving plants to a warmer location.',
        'time': 'Just now',
        'icon': Icons.thermostat,
        'color': Colors.red.shade600,
      });
    } else if (temperature > 30) {
      notifications.add({
        'title': 'Temperature Alert',
        'message':
            'Temperature is too high (${temperature.toStringAsFixed(1)}°C). Consider providing shade or cooling.',
        'time': 'Just now',
        'icon': Icons.thermostat,
        'color': Colors.red.shade600,
      });
    }

    if (humidity < 40) {
      notifications.add({
        'title': 'Humidity Alert',
        'message':
            'Humidity is low (${humidity.toStringAsFixed(1)}%). Consider using a humidifier.',
        'time': 'Just now',
        'icon': Icons.water_drop,
        'color': Colors.orange.shade600,
      });
    } else if (humidity > 80) {
      notifications.add({
        'title': 'Humidity Alert',
        'message':
            'Humidity is high (${humidity.toStringAsFixed(1)}%). Ensure proper ventilation.',
        'time': 'Just now',
        'icon': Icons.water_drop,
        'color': Colors.orange.shade600,
      });
    }

    if (soilMoisture < 30) {
      notifications.add({
        'title': 'Soil Moisture Alert',
        'message':
            'Soil moisture is low (${soilMoisture.toStringAsFixed(1)}%). Plants need watering.',
        'time': 'Just now',
        'icon': Icons.grass,
        'color': Colors.red.shade600,
      });
    } else if (soilMoisture > 90) {
      notifications.add({
        'title': 'Soil Moisture Alert',
        'message':
            'Soil is too wet (${soilMoisture.toStringAsFixed(1)}%). Reduce watering frequency.',
        'time': 'Just now',
        'icon': Icons.grass,
        'color': Colors.orange.shade600,
      });
    }

    if (lightLevel < 50) {
      notifications.add({
        'title': 'Light Level Alert',
        'message':
            'Light level is low (${lightLevel.toStringAsFixed(1)}%). Consider using grow lights.',
        'time': 'Just now',
        'icon': Icons.wb_sunny,
        'color': Colors.orange.shade600,
      });
    }

    // Add system status notifications
    if (isDataFromCache) {
      notifications.add({
        'title': 'Offline Mode',
        'message': 'Showing cached data. ESP32 device may be offline.',
        'time': 'Just now',
        'icon': Icons.wifi_off,
        'color': Colors.orange.shade600,
      });
    }

    if (isWatering) {
      notifications.add({
        'title': 'Watering Active',
        'message': 'Automatic watering system is currently running.',
        'time': 'Just now',
        'icon': Icons.water_drop,
        'color': Colors.blue.shade600,
      });
    }

    if (isLightOn) {
      notifications.add({
        'title': 'Grow Light Active',
        'message': 'Grow lights are currently turned on.',
        'time': 'Just now',
        'icon': Icons.lightbulb,
        'color': Colors.amber.shade600,
      });
    }

    // Add recent activity notifications
    if (lastUpdateTime.isNotEmpty && lastUpdateTime != 'Just now') {
      notifications.add({
        'title': 'Data Updated',
        'message': 'Sensor data was last updated $lastUpdateTime.',
        'time': 'Just now',
        'icon': Icons.sync,
        'color': Colors.green.shade600,
      });
    }

    // Add system notifications
    notifications.add({
      'title': 'System Status',
      'message': isAutoMode
          ? 'Auto mode is enabled. System will manage plants automatically.'
          : 'Manual mode is active. You control all systems.',
      'time': 'Just now',
      'icon': isAutoMode ? Icons.auto_awesome : Icons.settings,
      'color': isAutoMode ? Colors.green.shade600 : Colors.blue.shade600,
    });

    // Add a general health status
    final hasAlerts =
        notifications.any((n) => n['color'] == Colors.red.shade600);
    if (!hasAlerts) {
      notifications.add({
        'title': 'Plant Health Status',
        'message': 'All plants are healthy and growing well!',
        'time': 'Just now',
        'icon': Icons.health_and_safety,
        'color': Colors.green.shade600,
      });
    }

    return notifications;
  }

  Widget _buildNotificationItem(
      String title, String message, String time, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Control methods with immediate UI feedback
  Future<void> _toggleGrowLight(bool value) async {
    print('🚀 Toggling grow light to: ${value ? "ON" : "OFF"}');

    // Update UI immediately for instant feedback
    setState(() {
      isLightOn = value;
    });

    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('🌱 Grow light ${value ? "turning ON" : "turning OFF"}...'),
        backgroundColor: Colors.blue.shade600,
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Send command to ThingSpeak
      final success = await ThingSpeakService.controlGrowLight(value);

      if (success) {
        print('✅ Grow light command sent successfully');

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Grow light ${value ? "turned ON" : "turned OFF"} successfully'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );

        // Don't sync immediately - let the user see their action
        // The next auto-refresh will sync the status
        print('🔄 Grow light command sent. Status will sync on next refresh.');
      } else {
        print('❌ Failed to send grow light command');

        // Revert UI if command failed
        setState(() {
          isLightOn = !value;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                '❌ Failed to control grow light. Check console for details.'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('💥 Error toggling grow light: $e');

      // Revert UI on error
      setState(() {
        isLightOn = !value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💥 Error: $e'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _toggleWatering(bool value) async {
    print('🚀 Toggling watering to: ${value ? "START" : "STOP"}');

    // Update UI immediately for instant feedback
    setState(() {
      isWatering = value;
    });

    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('💧 Watering system ${value ? "starting" : "stopping"}...'),
        backgroundColor: Colors.blue.shade600,
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Send command to ThingSpeak
      final success = await ThingSpeakService.controlWatering(value);

      if (success) {
        print('✅ Watering command sent successfully');

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Watering system ${value ? "started" : "stopped"} successfully'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );

        // Don't sync immediately - let the user see their action
        // The next auto-refresh will sync the status
        print('🔄 Watering command sent. Status will sync on next refresh.');

        // If watering started, automatically stop after 3 seconds
        if (value) {
          print('⏰ Setting auto-stop timer for watering (3 seconds)');

          // Use a more reliable timer approach
          Timer(const Duration(minutes: 3), () async {
            print('🔄 Auto-stopping watering after 3 minutes');

            // Check if watering is still active before stopping
            if (isWatering) {
              print('💧 Auto-stopping watering system');

              // Send stop command to ThingSpeak
              final stopSuccess =
                  await ThingSpeakService.controlWatering(false);

              if (stopSuccess) {
                print('✅ Auto-stop watering command sent successfully');

                // Update UI
                setState(() {
                  isWatering = false;
                });

                // Show completion message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('💧 Watering completed automatically'),
                    backgroundColor: Colors.green.shade600,
                    duration: const Duration(seconds: 2),
                  ),
                );

                // Don't sync immediately - let the UI show the change
                print(
                    '🔄 Auto-stop watering completed. Status will sync on next refresh.');
              } else {
                print('❌ Failed to auto-stop watering');

                // Force UI update even if ThingSpeak command fails
                setState(() {
                  isWatering = false;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                        '⚠️ Watering stopped but ThingSpeak sync failed'),
                    backgroundColor: Colors.orange.shade600,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              print('💧 Watering already stopped, no need for auto-stop');
            }
          });
        }
      } else {
        print('❌ Failed to send watering command');

        // Revert UI if command failed
        setState(() {
          isWatering = !value;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                '❌ Failed to control watering. Check console for details.'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('💥 Error toggling watering: $e');

      // Revert UI on error
      setState(() {
        isWatering = !value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💥 Error: $e'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _toggleAutoMode(bool value) async {
    print('🚀 Toggling auto mode to: ${value ? "ENABLED" : "DISABLED"}');

    // Update UI immediately for instant feedback
    setState(() {
      isAutoMode = value;
    });

    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🤖 Auto mode ${value ? "enabling" : "disabling"}...'),
        backgroundColor: Colors.blue.shade600,
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Send command to ThingSpeak
      final success = await ThingSpeakService.setAutoMode(value);

      if (success) {
        print('✅ Auto mode command sent successfully');

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Auto mode ${value ? "enabled" : "disabled"} successfully'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );

        // Don't sync immediately - let the user see their action
        // The next auto-refresh will sync the status
        print('🔄 Auto mode command sent. Status will sync on next refresh.');
      } else {
        print('❌ Failed to send auto mode command');

        // Revert UI if command failed
        setState(() {
          isAutoMode = !value;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                '❌ Failed to change auto mode. Check console for details.'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('💥 Error toggling auto mode: $e');

      // Revert UI on error
      setState(() {
        isAutoMode = !value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💥 Error: $e'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
