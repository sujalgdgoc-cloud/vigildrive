import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vigil_drive/screens/scanScreen.dart';

class DriverHomePage extends StatefulWidget {
  final String truckId;

  const DriverHomePage({
    super.key,
    required this.truckId,
  });

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  // ============================================================
  // DJANGO API
  // ============================================================

  static const String djangoApiUrl =
      'https://vigildrivebackend.onrender.com/api/v2/driverinfo/?format=json';
  // ============================================================
  // DATA
  // ============================================================

  Map<String, dynamic>? _truckData;

  bool _isLoading = true;
  bool _isStartingTrip = false;

  bool _locationGranted = false;
  bool _cameraGranted = false;
  bool _motionAvailable = false;

  // ============================================================
  // SENSOR SUBSCRIPTIONS
  // ============================================================

  StreamSubscription<AccelerometerEvent>?
  _accelerometerSubscription;

  StreamSubscription<GyroscopeEvent>?
  _gyroscopeSubscription;

  // ============================================================
  // 15 MINUTE SCAN TIMER
  // ============================================================

  Timer? _scanTimer;

  Duration _remainingTime = const Duration(seconds: 15);

  static const Duration _scanInterval =
  Duration(seconds: 15);

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadTruckData();
    _startScanTimer();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _scanTimer?.cancel();

    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    super.dispose();
  }

  // ============================================================
  // LOAD TRUCK DATA FROM DJANGO
  // ============================================================

  Future<void> _loadTruckData() async {
    try {
      final response = await http.get(
        Uri.parse(djangoApiUrl),
        headers: {
          'Accept': 'application/json',
        },
      );

      debugPrint(
        'DRIVER INFO STATUS: ${response.statusCode}',
      );

      debugPrint(
        'DRIVER INFO RESPONSE: ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Server returned ${response.statusCode}',
        );
      }

      final dynamic decoded = jsonDecode(response.body);

      List<dynamic> trucks;

      // ========================================================
      // SUPPORT BOTH:
      //
      // [
      //   {...}
      // ]
      //
      // AND DRF PAGINATION:
      //
      // {
      //   "results": [
      //     {...}
      //   ]
      // }
      // ========================================================

      if (decoded is List) {
        trucks = decoded;
      } else if (decoded is Map &&
          decoded['results'] is List) {
        trucks = decoded['results'];
      } else {
        throw Exception(
          'Invalid API response format.',
        );
      }

      final String requiredTruckId =
      widget.truckId.trim().toLowerCase();

      Map<String, dynamic>? matchedTruck;

      for (final item in trucks) {
        if (item is Map) {
          final String apiTruckId =
              item['truck_id']
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
                  '';

          if (apiTruckId == requiredTruckId) {
            matchedTruck =
            Map<String, dynamic>.from(item);

            break;
          }
        }
      }

      if (matchedTruck == null) {
        throw Exception(
          'The assigned Truck ID could not be found.',
        );
      }

      if (!mounted) return;

      setState(() {
        _truckData = matchedTruck;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'TRUCK DATA ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'Unable to load your assigned truck.',
        isError: true,
      );
    }
  }

  // ============================================================
  // REQUEST PERMISSIONS
  // ============================================================

  Future<bool> _requestPermissions() async {
    if (!mounted) return false;

    setState(() {
      _isStartingTrip = true;
    });

    try {
      // ========================================================
      // LOCATION
      // ========================================================

      final PermissionStatus locationStatus =
      await Permission.locationWhenInUse.request();

      debugPrint(
        'LOCATION PERMISSION: $locationStatus',
      );

      if (!locationStatus.isGranted) {
        if (mounted) {
          _showPermissionDialog(
            title: 'Location Permission Required',
            message:
            'Location access is required to track your trip and determine your current position.',
          );
        }

        return false;
      }

      // ========================================================
      // CAMERA
      // ========================================================

      final PermissionStatus cameraStatus =
      await Permission.camera.request();

      debugPrint(
        'CAMERA PERMISSION: $cameraStatus',
      );

      if (!cameraStatus.isGranted) {
        if (mounted) {
          _showPermissionDialog(
            title: 'Camera Permission Required',
            message:
            'Camera access is required for driver monitoring during the trip.',
          );
        }

        return false;
      }

      // ========================================================
      // MOTION / SENSOR ACCESS
      // ========================================================
      //
      // Android accelerometer and gyroscope normally do not
      // require a runtime permission.
      //
      // We start listening to both sensors here.
      // ========================================================

      try {
        // Cancel previous subscriptions if they exist.
        await _accelerometerSubscription?.cancel();
        await _gyroscopeSubscription?.cancel();

        _accelerometerSubscription =
            accelerometerEventStream().listen(
                  (AccelerometerEvent event) {
                debugPrint(
                  'ACCELEROMETER: '
                      'X=${event.x} '
                      'Y=${event.y} '
                      'Z=${event.z}',
                );
              },
              onError: (error) {
                debugPrint(
                  'Accelerometer error: $error',
                );
              },
            );

        _gyroscopeSubscription =
            gyroscopeEventStream().listen(
                  (GyroscopeEvent event) {
                debugPrint(
                  'GYROSCOPE: '
                      'X=${event.x} '
                      'Y=${event.y} '
                      'Z=${event.z}',
                );
              },
              onError: (error) {
                debugPrint(
                  'Gyroscope error: $error',
                );
              },
            );

        _motionAvailable = true;

        debugPrint(
          'MOTION SENSORS: AVAILABLE',
        );
      } catch (e) {
        debugPrint(
          'Motion sensor error: $e',
        );

        _motionAvailable = false;
      }

      if (!mounted) return false;

      setState(() {
        _locationGranted = true;
        _cameraGranted = true;
      });

      return true;
    } catch (e) {
      debugPrint(
        'PERMISSION ERROR: $e',
      );

      if (mounted) {
        _showMessage(
          'Unable to request required permissions.',
          isError: true,
        );
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isStartingTrip = false;
        });
      }
    }
  }

  // ============================================================
  // START TRIP
  // ============================================================

  Future<void> _startTrip() async {
    final bool permissionsGranted =
    await _requestPermissions();

    if (!permissionsGranted) {
      return;
    }

    if (!mounted) return;

    _showMessage(
      'All permissions granted. Trip can start.',
      isError: false,
    );

    // ==========================================================
    // PUT YOUR TRIP START API CALL HERE
    // ==========================================================
    //
    // Example:
    //
    // await http.patch(
    //   Uri.parse(
    //     'http://127.0.0.1:8000/api/v2/driverinfo/'
    //     '${_truckData!['id']}/',
    //   ),
    //   headers: {
    //     'Content-Type': 'application/json',
    //   },
    //   body: jsonEncode({
    //     'status': 'IN_PROGRESS',
    //   }),
    // );
    //
    // ==========================================================
  }

  // ============================================================
  // START 15 MINUTE SCAN TIMER
  // ============================================================

  void _startScanTimer() {
    _scanTimer?.cancel();

    _remainingTime = _scanInterval;

    _scanTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_remainingTime.inSeconds <= 1) {
          timer.cancel();

          setState(() {
            _remainingTime = Duration.zero;
          });

          _goToScanScreen();
        } else {
          setState(() {
            _remainingTime -=
            const Duration(seconds: 1);
          });
        }
      },
    );
  }

  // ============================================================
  // GO TO SCAN SCREEN
  // ============================================================

  void _goToScanScreen() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
        const SafetyScanScreen(),
      ),
    );
  }

  // ============================================================
  // PERMISSION DIALOG
  // ============================================================

  void _showPermissionDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'CANCEL',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                const Color(0xFF2563EB),
                foregroundColor:
                Colors.white,
              ),
              child: const Text(
                'OPEN SETTINGS',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showMessage(
      String message, {
        required bool isError,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          behavior:
          SnackBarBehavior.floating,
          margin:
          const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(12),
          ),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      const Color(0xFFF8F7F4),
      body: SafeArea(
        child: _isLoading
            ? const Center(
          child:
          CircularProgressIndicator(
            color:
            Color(0xFF2563EB),
          ),
        )
            : _truckData == null
            ? _buildErrorState()
            : _buildDriverScreen(),
      ),
    );
  }

  // ============================================================
  // ERROR STATE
  // ============================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration:
              BoxDecoration(
                color:
                const Color(0xFFFEE2E2),
                borderRadius:
                BorderRadius.circular(
                  20,
                ),
              ),
              child: const Icon(
                Icons
                    .local_shipping_outlined,
                size: 34,
                color:
                Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Truck information unavailable',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                FontWeight.w800,
                color:
                Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'We could not find your assigned truck.',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color:
                Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });

                _loadTruckData();
              },
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                const Color(0xFF2563EB),
                foregroundColor:
                Colors.white,
              ),
              child: const Text(
                'TRY AGAIN',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN DRIVER SCREEN
  // ============================================================

  Widget _buildDriverScreen() {
    final Map<String, dynamic> truck =
    _truckData!;

    final String truckId =
        truck['truck_id']?.toString() ??
            '-';

    final String truckNumber =
        truck['truck_no']?.toString() ??
            '-';

    final String driver =
        truck['driver']?.toString() ??
            '-';

    final String startPoint =
        truck['start_point']?.toString() ??
            '-';

    final String endPoint =
        truck['end_point']?.toString() ??
            '-';

    final String latitude =
        truck['lat']?.toString() ??
            '-';

    final String longitude =
        truck['lon']?.toString() ??
            '-';

    final String status =
        truck['status']?.toString() ??
            '-';

    return Column(
      children: [
        Expanded(
          child:
          SingleChildScrollView(
            padding:
            const EdgeInsets.fromLTRB(
              14,
              26,
              14,
              24,
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                // ==================================================
                // HEADER
                // ==================================================

                const Text(
                  'Welcome, Driver',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing: -0.7,
                    color:
                    Color(0xFF111827),
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Your assigned vehicle and trip',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                    Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 22),

                // ==================================================
                // TRUCK CARD
                // ==================================================

                _buildCard(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Text(
                        'ASSIGNED VEHICLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                          FontWeight
                              .w800,
                          letterSpacing:
                          0.7,
                          color:
                          Color(0xFF4B5563),
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration:
                            const BoxDecoration(
                              color:
                              Color(
                                0xFFEFF2F6,
                              ),
                              shape:
                              BoxShape
                                  .circle,
                            ),
                            child:
                            const Icon(
                              Icons
                                  .local_shipping_rounded,
                              color:
                              Color(
                                0xFF2563EB,
                              ),
                              size: 27,
                            ),
                          ),

                          const SizedBox(
                            width: 14,
                          ),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                const Text(
                                  'Truck ID',
                                  style:
                                  TextStyle(
                                    fontSize:
                                    11.5,
                                    color:
                                    Color(
                                      0xFF6B7280,
                                    ),
                                  ),
                                ),

                                const SizedBox(
                                  height: 2,
                                ),

                                Text(
                                  truckId,
                                  style:
                                  const TextStyle(
                                    fontSize:
                                    20,
                                    fontWeight:
                                    FontWeight
                                        .w800,
                                    color:
                                    Color(
                                      0xFF111827,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // LOCKED TRUCK ID
                          Container(
                            padding:
                            const EdgeInsets
                                .all(8),
                            decoration:
                            BoxDecoration(
                              color:
                              const Color(
                                0xFFEFF6FF,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                10,
                              ),
                            ),
                            child:
                            const Icon(
                              Icons
                                  .lock_outline_rounded,
                              size: 18,
                              color:
                              Color(
                                0xFF2563EB,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      const Divider(
                        height: 1,
                        color:
                        Color(0xFFE5E7EB),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      _buildInfoRow(
                        icon: Icons
                            .confirmation_number_outlined,
                        title:
                        'Truck Number',
                        value:
                        truckNumber,
                      ),

                      const SizedBox(
                        height: 13,
                      ),

                      _buildInfoRow(
                        icon: Icons
                            .person_outline_rounded,
                        title: 'Driver',
                        value: driver,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ==================================================
                // ROUTE CARD
                // ==================================================

                _buildCard(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Text(
                        'ROUTE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                          FontWeight
                              .w800,
                          letterSpacing:
                          0.7,
                          color:
                          Color(0xFF4B5563),
                        ),
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      _buildRoutePoint(
                        title: startPoint,
                        label:
                        'Start Point',
                        color:
                        const Color(
                          0xFF2563EB,
                        ),
                        isFirst: true,
                      ),

                      _buildRouteLine(),

                      _buildRoutePoint(
                        title: endPoint,
                        label:
                        'End Point',
                        color:
                        const Color(
                          0xFFDC2626,
                        ),
                        isFirst: false,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ==================================================
                // TRIP INFORMATION
                // ==================================================

                _buildCard(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Text(
                        'TRIP INFORMATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                          FontWeight
                              .w800,
                          letterSpacing:
                          0.7,
                          color:
                          Color(0xFF4B5563),
                        ),
                      ),

                      const SizedBox(
                        height: 17,
                      ),

                      Row(
                        children: [
                          Expanded(
                            child:
                            _buildDataBox(
                              icon: Icons
                                  .flag_outlined,
                              title: 'Status',
                              value:
                              _formatStatus(
                                status,
                              ),
                              valueColor:
                              _statusColor(
                                status,
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 12,
                          ),

                          Expanded(
                            child:
                            _buildDataBox(
                              icon: Icons
                                  .tag_rounded,
                              title:
                              'Trip ID',
                              value:
                              '#${truck['id'] ?? '-'}',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      _buildDataBox(
                        icon: Icons
                            .location_on_outlined,
                        title:
                        'Current Coordinates',
                        value:
                        'Lat $latitude   •   Lon $longitude',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ==================================================
                // 15 MINUTE SCAN TIMER
                // ==================================================

                _buildScanTimerCard(),

                const SizedBox(height: 14),

                // ==================================================
                // PERMISSIONS
                // ==================================================

                _buildCard(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration:
                            BoxDecoration(
                              color:
                              const Color(
                                0xFFEFF6FF,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                12,
                              ),
                            ),
                            child:
                            const Icon(
                              Icons
                                  .security_rounded,
                              color:
                              Color(
                                0xFF2563EB,
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 12,
                          ),

                          const Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                Text(
                                  'Permissions Required',
                                  style:
                                  TextStyle(
                                    fontSize:
                                    16,
                                    fontWeight:
                                    FontWeight
                                        .w800,
                                    color:
                                    Color(
                                      0xFF111827,
                                    ),
                                  ),
                                ),

                                SizedBox(
                                  height: 3,
                                ),

                                Text(
                                  'Required before starting your trip',
                                  style:
                                  TextStyle(
                                    fontSize:
                                    12,
                                    color:
                                    Color(
                                      0xFF6B7280,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      Row(
                        children: [
                          Expanded(
                            child:
                            _buildPermissionItem(
                              icon: Icons
                                  .location_on_outlined,
                              title:
                              'Location',
                              granted:
                              _locationGranted,
                            ),
                          ),

                          Expanded(
                            child:
                            _buildPermissionItem(
                              icon: Icons
                                  .camera_alt_outlined,
                              title: 'Camera',
                              granted:
                              _cameraGranted,
                            ),
                          ),

                          Expanded(
                            child:
                            _buildPermissionItem(
                              icon: Icons
                                  .motion_photos_on_rounded,
                              title: 'Motion',
                              granted:
                              _motionAvailable,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==================================================
                // DATA SECURITY
                // ==================================================

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment
                      .center,
                  children: [
                    Icon(
                      Icons
                          .verified_user_outlined,
                      size: 15,
                      color:
                      Colors.grey.shade500,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      'Trip data is securely protected',
                      style: TextStyle(
                        fontSize: 11.5,
                        color:
                        Colors.grey
                            .shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ========================================================
        // START TRIP BUTTON
        // ========================================================

        Container(
          padding:
          const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            16,
          ),
          decoration:
          const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(
                color:
                Color(0xFFE5E7EB),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isStartingTrip
                  ? null
                  : _startTrip,
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                const Color(
                  0xFF2563EB,
                ),
                disabledBackgroundColor:
                const Color(
                  0xFF93B4F4,
                ),
                foregroundColor:
                Colors.white,
                elevation: 0,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius
                      .circular(8),
                ),
              ),
              child: _isStartingTrip
                  ? const SizedBox(
                width: 22,
                height: 22,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                  AlwaysStoppedAnimation<
                      Color>(
                    Colors.white,
                  ),
                ),
              )
                  : const Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                children: [
                  Text(
                    'START TRIP',
                    style:
                    TextStyle(
                      fontSize: 15,
                      fontWeight:
                      FontWeight
                          .w800,
                      letterSpacing:
                      0.2,
                    ),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Icon(
                    Icons
                        .arrow_forward_rounded,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SCAN TIMER CARD
  // ============================================================

  Widget _buildScanTimerCard() {
    final int minutes =
        _remainingTime.inMinutes;

    final int seconds =
        _remainingTime.inSeconds % 60;

    final String timeText =
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';

    final double progress =
        _remainingTime.inSeconds /
            _scanInterval.inSeconds;

    return _buildCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration:
                BoxDecoration(
                  color:
                  const Color(
                    0xFFEFF6FF,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color:
                  Color(0xFF2563EB),
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      'Next Safety Scan',
                      style:
                      TextStyle(
                        fontSize: 16,
                        fontWeight:
                        FontWeight
                            .w800,
                        color:
                        Color(
                          0xFF111827,
                        ),
                      ),
                    ),

                    SizedBox(height: 3),

                    Text(
                      'Automatic driver monitoring check',
                      style:
                      TextStyle(
                        fontSize: 12,
                        color:
                        Color(
                          0xFF6B7280,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Text(
                timeText,
                style:
                const TextStyle(
                  fontSize: 21,
                  fontWeight:
                  FontWeight.w800,
                  color:
                  Color(0xFF2563EB),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius:
            BorderRadius.circular(
              10,
            ),
            child:
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor:
              const Color(
                0xFFE5E7EB,
              ),
              valueColor:
              const AlwaysStoppedAnimation<
                  Color>(
                Color(0xFF2563EB),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
            children: const [
              Text(
                'Scan will start automatically',
                style:
                TextStyle(
                  fontSize: 11.5,
                  color:
                  Color(
                    0xFF6B7280,
                  ),
                ),
              ),

              Icon(
                Icons
                    .arrow_forward_rounded,
                size: 17,
                color:
                Color(0xFF2563EB),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _buildCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color:
          const Color(0xFFD9DEE8),
        ),
      ),
      child: child,
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 19,
          color:
          const Color(0xFF2563EB),
        ),

        const SizedBox(width: 10),

        Text(
          '$title: ',
          style:
          const TextStyle(
            fontSize: 12,
            color:
            Color(0xFF6B7280),
          ),
        ),

        Expanded(
          child: Text(
            value,
            textAlign:
            TextAlign.right,
            style:
            const TextStyle(
              fontSize: 13.5,
              fontWeight:
              FontWeight.w700,
              color:
              Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ROUTE POINT
  // ============================================================

  Widget _buildRoutePoint({
    required String title,
    required String label,
    required Color color,
    required bool isFirst,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin:
          const EdgeInsets.only(
            top: 5,
            left: 2,
          ),
          decoration:
          BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 14),

        Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style:
              const TextStyle(
                fontSize: 16,
                fontWeight:
                FontWeight.w700,
                color:
                Color(0xFF111827),
              ),
            ),

            const SizedBox(height: 3),

            Text(
              label,
              style:
              const TextStyle(
                fontSize: 12,
                color:
                Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // ROUTE LINE
  // ============================================================

  Widget _buildRouteLine() {
    return Container(
      margin:
      const EdgeInsets.only(
        left: 7,
        top: 4,
        bottom: 4,
      ),
      height: 28,
      width: 2,
      color:
      const Color(0xFFD1D5DB),
    );
  }

  // ============================================================
  // DATA BOX
  // ============================================================

  Widget _buildDataBox({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
        const Color(0xFFF8FAFC),
        borderRadius:
        BorderRadius.circular(11),
        border: Border.all(
          color:
          const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color:
            const Color(0xFF2563EB),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  title,
                  style:
                  const TextStyle(
                    fontSize: 10.5,
                    color:
                    Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Text(
                  value,
                  maxLines: 2,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                    FontWeight.w700,
                    color: valueColor ??
                        const Color(
                          0xFF111827,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PERMISSION ITEM
  // ============================================================

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required bool granted,
  }) {
    return Column(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration:
          BoxDecoration(
            color: granted
                ? const Color(
              0xFFF0FDF4,
            )
                : const Color(
              0xFFEFF6FF,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 21,
            color: granted
                ? const Color(
              0xFF16A34A,
            )
                : const Color(
              0xFF2563EB,
            ),
          ),
        ),

        const SizedBox(height: 7),

        Text(
          title,
          style:
          const TextStyle(
            fontSize: 11.5,
            fontWeight:
            FontWeight.w700,
            color:
            Color(0xFF374151),
          ),
        ),

        const SizedBox(height: 3),

        Icon(
          granted
              ? Icons
              .check_circle_rounded
              : Icons.circle_outlined,
          size: 15,
          color: granted
              ? const Color(
            0xFF16A34A,
          )
              : const Color(
            0xFF9CA3AF,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // STATUS COLOR
  // ============================================================

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'IN_PROGRESS':
        return const Color(
          0xFF2563EB,
        );

      case 'COMPLETED':
        return const Color(
          0xFF16A34A,
        );

      case 'CANCELLED':
        return const Color(
          0xFFDC2626,
        );

      case 'PENDING':
        return const Color(
          0xFFD97706,
        );

      default:
        return const Color(
          0xFF374151,
        );
    }
  }

  // ============================================================
  // FORMAT STATUS
  // ============================================================

  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isEmpty
          ? word
          : word[0].toUpperCase() +
          word
              .substring(1)
              .toLowerCase(),
    )
        .join(' ');
  }
}