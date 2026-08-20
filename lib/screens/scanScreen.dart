import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SafetyScanScreen extends StatefulWidget {
  const SafetyScanScreen({super.key});

  @override
  State<SafetyScanScreen> createState() => _SafetyScanScreenState();
}

class _SafetyScanScreenState extends State<SafetyScanScreen>
    with WidgetsBindingObserver {
  // ============================================================
  // API CONFIGURATION
  // ============================================================

  static const String fastApiUrl =
      'https://driver-safety-2-1.onrender.com/api/analyze-video';

  static const String djangoUrl =
      'https://vigildrivebackend.onrender.com/api/v2/driverdata/?format=json';

  String? accessToken;

  // ============================================================
  // SCAN CONFIGURATION
  // ============================================================

  static const int scanDurationSeconds = 5;

  // ============================================================
  // CAMERA
  // ============================================================

  CameraController? _cameraController;

  bool _cameraReady = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _scanFinished = false;
  bool _cameraInitializing = false;

  Timer? _scanTimer;
  Timer? _countdownTimer;

  int _remainingSeconds = scanDurationSeconds;

  // ============================================================
  // LOCAL VIDEO STORAGE
  // ============================================================

  String? _localVideoPath;

  // ============================================================
  // SENSOR DATA
  // ============================================================

  StreamSubscription<UserAccelerometerEvent>?
  _accelerometerSubscription;

  StreamSubscription<GyroscopeEvent>?
  _gyroscopeSubscription;

  final List<Map<String, dynamic>> _accelerometerData = [];
  final List<Map<String, dynamic>> _gyroscopeData = [];

  // ============================================================
  // MOTION DETECTION
  // ============================================================

  int _suddenBrakingEvents = 0;
  int _swervingEvents = 0;

  DateTime? _lastBrakingEvent;
  DateTime? _lastSwervingEvent;

  static const double brakingThreshold = 6.0;
  static const double swervingThreshold = 5.0;

  static const Duration motionEventCooldown =
  Duration(milliseconds: 700);

  // ============================================================
  // FASTAPI RESULT
  // ============================================================

  Map<String, dynamic>? _fastApiResult;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scanTimer?.cancel();
    _countdownTimer?.cancel();

    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    _cameraController?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    final controller = _cameraController;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Never dispose the camera while recording.
      if (!_isRecording &&
          controller != null) {
        _disposeCamera();
      }

      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (!_isRecording &&
          !_isProcessing &&
          !_scanFinished &&
          !_cameraReady) {
        _initializeCamera();
      }
    }
  }

  // ============================================================
  // DISPOSE CAMERA
  // ============================================================

  Future<void> _disposeCamera() async {
    final controller = _cameraController;

    _cameraController = null;

    if (mounted) {
      setState(() {
        _cameraReady = false;
      });
    }

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint(
          'Camera dispose error: $e',
        );
      }
    }
  }

  // ============================================================
  // CAMERA INITIALIZATION
  // ============================================================

  Future<void> _initializeCamera() async {
    if (_cameraInitializing ||
        _isRecording ||
        _isProcessing) {
      return;
    }

    _cameraInitializing = true;

    try {
      await _disposeCamera();

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        debugPrint(
          'No cameras available.',
        );

        if (mounted) {
          _showError(
            'No camera was found on this device.',
          );
        }

        return;
      }

      CameraDescription selectedCamera =
          cameras.first;

      // Prefer front camera for driver monitoring.
      for (final camera in cameras) {
        if (camera.lensDirection ==
            CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
      }

      debugPrint(
        'Selected camera: ${selectedCamera.name}',
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _cameraController = controller;

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraReady = true;
      });

      debugPrint(
        'Camera initialized successfully.',
      );

      // Start scan automatically.
      if (!_scanFinished &&
          !_isRecording &&
          !_isProcessing) {
        await _startSafetyScan();
      }
    } on CameraException catch (e) {
      debugPrint(
        'Camera initialization error: '
            '${e.code} - ${e.description}',
      );

      _cameraController = null;

      if (mounted) {
        setState(() {
          _cameraReady = false;
        });

        _showError(
          'Camera could not be initialized.\n'
              '${e.description ?? e.code}',
        );
      }
    } catch (e) {
      debugPrint(
        'Camera initialization error: $e',
      );

      _cameraController = null;

      if (mounted) {
        setState(() {
          _cameraReady = false;
        });

        _showError(
          'Unable to initialize the camera.',
        );
      }
    } finally {
      _cameraInitializing = false;
    }
  }

  // ============================================================
  // START 5 SECOND SCAN
  // ============================================================

  Future<void> _startSafetyScan() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isProcessing) {
      return;
    }

    try {
      _resetScanData();

      _startSensorMonitoring();

      debugPrint(
        'Starting $scanDurationSeconds second safety recording...',
      );

      await controller.startVideoRecording();

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecording = true;
        _remainingSeconds =
            scanDurationSeconds;
      });

      // ----------------------------------------------------------
      // COUNTDOWN
      // ----------------------------------------------------------

      _countdownTimer?.cancel();

      _countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
            (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }

          if (_remainingSeconds > 0) {
            setState(() {
              _remainingSeconds--;
            });
          }

          if (_remainingSeconds <= 0) {
            timer.cancel();
          }
        },
      );

      // ----------------------------------------------------------
      // ACTUAL RECORDING TIMER
      // ----------------------------------------------------------

      _scanTimer?.cancel();

      _scanTimer = Timer(
        const Duration(
          seconds: scanDurationSeconds,
        ),
        _finishSafetyScan,
      );
    } on CameraException catch (e) {
      debugPrint(
        'Could not start recording: '
            '${e.code} - ${e.description}',
      );

      _stopSensorMonitoring();

      if (mounted) {
        setState(() {
          _isRecording = false;
        });

        _showError(
          'Unable to start camera recording.',
        );
      }
    } catch (e) {
      debugPrint(
        'Could not start recording: $e',
      );

      _stopSensorMonitoring();

      if (mounted) {
        setState(() {
          _isRecording = false;
        });

        _showError(
          'Unable to start safety scan.',
        );
      }
    }
  }

  // ============================================================
  // FINISH 5 SECOND SCAN
  // ============================================================

  Future<void> _finishSafetyScan() async {
    if (!_isRecording ||
        _scanFinished) {
      return;
    }

    _scanTimer?.cancel();
    _countdownTimer?.cancel();

    _stopSensorMonitoring();

    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isRecordingVideo) {
      debugPrint(
        'Camera is not recording when scan finished.',
      );

      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isProcessing = true;
        });
      }

      // ========================================================
      // STEP 1
      // STOP RECORDING
      // ========================================================

      debugPrint(
        'Stopping camera recording...',
      );

      final XFile recordedFile =
      await controller.stopVideoRecording();

      debugPrint(
        'Camera recording stopped.',
      );

      // ========================================================
      // STEP 2
      // STORE VIDEO LOCALLY
      // ========================================================

      final String localPath =
      await _storeVideoLocally(
        recordedFile,
      );

      _localVideoPath = localPath;

      debugPrint(
        'Video stored locally at:',
      );

      debugPrint(localPath);

      // ========================================================
      // STEP 3
      // UPLOAD LOCAL VIDEO TO FASTAPI
      // ========================================================

      debugPrint(
        'Uploading local video to FastAPI...',
      );

      final Map<String, dynamic>?
      fastApiResult =
      await _sendLocalVideoToFastAPI(
        localPath,
      );

      // ========================================================
      // FASTAPI FAILED
      // ========================================================

      if (fastApiResult == null) {
        debugPrint(
          'FastAPI processing failed.',
        );

        // Keep local video so it can be retried.

        if (mounted) {
          setState(() {
            _isProcessing = false;
          });

          _showError(
            'Safety analysis failed.\n'
                'The recorded scan has been kept locally.',
          );
        }

        return;
      }

      _fastApiResult = fastApiResult;

      debugPrint(
        'FastAPI analysis completed successfully.',
      );

      // ========================================================
      // STEP 4
      // BUILD SENSOR ANALYSIS
      // ========================================================

      final Map<String, dynamic>
      motionAnalysis =
      _buildMotionAnalysis();

      // ========================================================
      // STEP 5
      // SEND RESULTS TO DJANGO
      // ========================================================

      await _sendResultToDjango(
        fastApiResult: fastApiResult,
        motionAnalysis: motionAnalysis,
      );

      // ========================================================
      // STEP 6
      // CHECK RISK
      // ========================================================

      final String riskLevel =
      (fastApiResult['risk_level'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      debugPrint(
        'Final risk level: $riskLevel',
      );

      // ========================================================
      // CRITICAL
      // ========================================================

      if (riskLevel == 'critical') {
        _scanFinished = true;

        await _deleteLocalVideo();

        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(
            '/home',
                (route) => false,
          );
        }

        return;
      }

      // ========================================================
      // NORMAL RESULT
      // ========================================================

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _scanFinished = true;
        });

        Navigator.of(context).pop();
      }

      // ========================================================
      // DELETE LOCAL VIDEO AFTER SUCCESS
      // ========================================================

      await _deleteLocalVideo();
    } on CameraException catch (e) {
      debugPrint(
        'Camera error while finishing scan: '
            '${e.code} - ${e.description}',
      );

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Safety scan error: $e',
      );

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
        });

        _showError(
          'An error occurred while processing the scan.',
        );
      }
    }
  }

  // ============================================================
  // STORE VIDEO LOCALLY
  // ============================================================

  Future<String> _storeVideoLocally(
      XFile recordedFile,
      ) async {
    final Directory appDirectory =
    await getApplicationDocumentsDirectory();

    final Directory scanDirectory =
    Directory(
      path.join(
        appDirectory.path,
        'safety_scans',
      ),
    );

    if (!await scanDirectory.exists()) {
      await scanDirectory.create(
        recursive: true,
      );
    }

    final String timestamp =
    DateTime.now()
        .toUtc()
        .millisecondsSinceEpoch
        .toString();

    final String localFileName =
        'safety_scan_$timestamp.mp4';

    final String localPath =
    path.join(
      scanDirectory.path,
      localFileName,
    );

    // Save without loading the whole video into RAM.
    await recordedFile.saveTo(localPath);

    final File localFile =
    File(localPath);

    if (!await localFile.exists()) {
      throw Exception(
        'Local video file was not created.',
      );
    }

    final int fileSize =
    await localFile.length();

    debugPrint(
      'Local video size: $fileSize bytes',
    );

    if (fileSize <= 0) {
      throw Exception(
        'Local video file is empty.',
      );
    }

    return localPath;
  }

  // ============================================================
  // SEND LOCAL VIDEO TO FASTAPI
  // ============================================================

  Future<Map<String, dynamic>?>
  _sendLocalVideoToFastAPI(
      String localVideoPath,
      ) async {
    try {
      final File videoFile =
      File(localVideoPath);

      if (!await videoFile.exists()) {
        debugPrint(
          'Local video does not exist:',
        );

        debugPrint(localVideoPath);

        return null;
      }

      final int fileSize =
      await videoFile.length();

      debugPrint(
        'Preparing FastAPI upload...',
      );

      debugPrint(
        'File: $localVideoPath',
      );

      debugPrint(
        'File size: $fileSize bytes',
      );

      if (fileSize <= 0) {
        debugPrint(
          'Video file is empty.',
        );

        return null;
      }

      final Uri uri =
      Uri.parse(fastApiUrl);

      final http.MultipartRequest request =
      http.MultipartRequest(
        'POST',
        uri,
      );

      // ========================================================
      // JWT
      // ========================================================

      if (accessToken != null &&
          accessToken!.isNotEmpty) {
        request.headers['Authorization'] =
        'Bearer $accessToken';
      }

      // ========================================================
      // IMPORTANT
      //
      // FastAPI expects:
      //
      // file: UploadFile
      //
      // NOT:
      //
      // video
      //
      // Your 422 error was caused by this field name.
      // ========================================================

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          localVideoPath,
          filename:
          path.basename(localVideoPath),
        ),
      );

      debugPrint(
        'Multipart field name: file',
      );

      debugPrint(
        'Sending request to FastAPI...',
      );

      // ========================================================
      // SEND REQUEST
      // ========================================================

      final http.StreamedResponse
      streamedResponse =
      await request.send();

      final http.Response response =
      await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        'FastAPI status: '
            '${response.statusCode}',
      );

      debugPrint(
        'FastAPI response: '
            '${response.body}',
      );

      // ========================================================
      // ERROR
      // ========================================================

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        debugPrint(
          'FastAPI error: '
              '${response.body}',
        );

        return null;
      }

      // ========================================================
      // JSON
      // ========================================================

      final dynamic decoded =
      jsonDecode(response.body);

      if (decoded is! Map) {
        debugPrint(
          'FastAPI response is not a JSON object.',
        );

        return null;
      }

      return Map<String, dynamic>.from(
        decoded,
      );
    } on SocketException catch (e) {
      debugPrint(
        'FastAPI SocketException: $e',
      );

      return null;
    } on http.ClientException catch (e) {
      debugPrint(
        'FastAPI ClientException: $e',
      );

      return null;
    } catch (e) {
      debugPrint(
        'FastAPI upload error: $e',
      );

      return null;
    }
  }

  // ============================================================
  // DELETE LOCAL VIDEO
  // ============================================================

  Future<void> _deleteLocalVideo() async {
    final String? localPath =
        _localVideoPath;

    if (localPath == null ||
        localPath.isEmpty) {
      return;
    }

    try {
      final File file =
      File(localPath);

      if (await file.exists()) {
        await file.delete();

        debugPrint(
          'Local safety video deleted.',
        );
      }

      _localVideoPath = null;
    } catch (e) {
      debugPrint(
        'Could not delete local video: $e',
      );
    }
  }

  // ============================================================
  // SENSOR MONITORING
  // ============================================================

  void _startSensorMonitoring() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    _accelerometerData.clear();
    _gyroscopeData.clear();

    _accelerometerSubscription =
        userAccelerometerEventStream().listen(
              (event) {
            final int timestamp =
                DateTime.now()
                    .millisecondsSinceEpoch;

            _accelerometerData.add({
              'timestamp': timestamp,
              'x': event.x,
              'y': event.y,
              'z': event.z,
            });

            _detectBraking(event);
            _detectSwerving(event);
          },
          onError: (error) {
            debugPrint(
              'Accelerometer error: $error',
            );
          },
        );

    _gyroscopeSubscription =
        gyroscopeEventStream().listen(
              (event) {
            final int timestamp =
                DateTime.now()
                    .millisecondsSinceEpoch;

            _gyroscopeData.add({
              'timestamp': timestamp,
              'x': event.x,
              'y': event.y,
              'z': event.z,
            });
          },
          onError: (error) {
            debugPrint(
              'Gyroscope error: $error',
            );
          },
        );
  }

  void _stopSensorMonitoring() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
  }

  // ============================================================
  // SUDDEN BRAKING
  // ============================================================

  void _detectBraking(
      UserAccelerometerEvent event,
      ) {
    final DateTime now =
    DateTime.now();

    if (_lastBrakingEvent != null &&
        now.difference(
          _lastBrakingEvent!,
        ) <
            motionEventCooldown) {
      return;
    }

    if (event.z < -brakingThreshold) {
      _suddenBrakingEvents++;

      _lastBrakingEvent = now;

      debugPrint(
        'Sudden braking detected: '
            '${event.z}',
      );
    }
  }

  // ============================================================
  // SWERVING
  // ============================================================

  void _detectSwerving(
      UserAccelerometerEvent event,
      ) {
    final DateTime now =
    DateTime.now();

    if (_lastSwervingEvent != null &&
        now.difference(
          _lastSwervingEvent!,
        ) <
            motionEventCooldown) {
      return;
    }

    if (event.x.abs() >
        swervingThreshold) {
      _swervingEvents++;

      _lastSwervingEvent = now;

      debugPrint(
        'Possible swerving detected: '
            '${event.x}',
      );
    }
  }

  // ============================================================
  // MOTION ANALYSIS
  // ============================================================

  Map<String, dynamic>
  _buildMotionAnalysis() {
    double maxAccelerationMagnitude = 0;

    double totalAccelerationMagnitude = 0;

    for (final data
    in _accelerometerData) {
      final double x =
      (data['x'] as num)
          .toDouble();

      final double y =
      (data['y'] as num)
          .toDouble();

      final double z =
      (data['z'] as num)
          .toDouble();

      final double magnitude =
      math.sqrt(
        (x * x) +
            (y * y) +
            (z * z),
      );

      totalAccelerationMagnitude +=
          magnitude;

      if (magnitude >
          maxAccelerationMagnitude) {
        maxAccelerationMagnitude =
            magnitude;
      }
    }

    double averageAccelerationMagnitude =
    0;

    if (_accelerometerData.isNotEmpty) {
      averageAccelerationMagnitude =
          totalAccelerationMagnitude /
              _accelerometerData.length;
    }

    double maxGyroscopeMagnitude = 0;

    for (final data
    in _gyroscopeData) {
      final double x =
      (data['x'] as num)
          .toDouble();

      final double y =
      (data['y'] as num)
          .toDouble();

      final double z =
      (data['z'] as num)
          .toDouble();

      final double magnitude =
      math.sqrt(
        (x * x) +
            (y * y) +
            (z * z),
      );

      if (magnitude >
          maxGyroscopeMagnitude) {
        maxGyroscopeMagnitude =
            magnitude;
      }
    }

    return {
      'sudden_braking_detected':
      _suddenBrakingEvents > 0,

      'sudden_braking_events':
      _suddenBrakingEvents,

      'swerving_detected':
      _swervingEvents > 0,

      'swerving_events':
      _swervingEvents,

      'accelerometer_samples':
      _accelerometerData.length,

      'gyroscope_samples':
      _gyroscopeData.length,

      'max_acceleration_magnitude':
      maxAccelerationMagnitude,

      'average_acceleration_magnitude':
      averageAccelerationMagnitude,

      'max_gyroscope_magnitude':
      maxGyroscopeMagnitude,

      'accelerometer_data':
      _accelerometerData,

      'gyroscope_data':
      _gyroscopeData,
    };
  }

  // ============================================================
  // SEND RESULTS TO DJANGO
  // ============================================================

  Future<void> _sendResultToDjango({
    required Map<String, dynamic>
    fastApiResult,
    required Map<String, dynamic>
    motionAnalysis,
  }) async {
    try {
      final Uri uri =
      Uri.parse(djangoUrl);

      final Map<String, dynamic> body = {
        // ======================================================
        // FASTAPI DATA
        // ======================================================

        'status':
        fastApiResult['status'],

        'total_frames_processed':
        fastApiResult[
        'total_frames_processed'],

        'overall_risk_score':
        fastApiResult[
        'overall_risk_score'],

        'risk_level':
        fastApiResult['risk_level'],

        'environment_warning':
        fastApiResult[
        'environment_warning'],

        'spoof_detected':
        fastApiResult[
        'spoof_detected'],

        'spoof_reasons':
        fastApiResult[
        'spoof_reasons'],

        'final_perclos':
        fastApiResult[
        'final_perclos'],

        'max_blink_duration_ms':
        fastApiResult[
        'max_blink_duration_ms'],

        // ======================================================
        // MOTION
        // ======================================================

        'motion_analysis':
        motionAnalysis,

        // ======================================================
        // TIMESTAMP
        // ======================================================

        'scan_timestamp':
        DateTime.now()
            .toUtc()
            .toIso8601String(),
      };

      final Map<String, String> headers = {
        'Content-Type':
        'application/json',
      };

      if (accessToken != null &&
          accessToken!.isNotEmpty) {
        headers['Authorization'] =
        'Bearer $accessToken';
      }

      debugPrint(
        'Sending analysis result to Django...',
      );

      final http.Response response =
      await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint(
        'Django status: '
            '${response.statusCode}',
      );

      debugPrint(
        'Django response: '
            '${response.body}',
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        debugPrint(
          'Django API error: '
              '${response.body}',
        );
      }
    } catch (e) {
      debugPrint(
        'Django API error: $e',
      );
    }
  }

  // ============================================================
  // RESET
  // ============================================================

  void _resetScanData() {
    _accelerometerData.clear();
    _gyroscopeData.clear();

    _suddenBrakingEvents = 0;
    _swervingEvents = 0;

    _lastBrakingEvent = null;
    _lastSwervingEvent = null;

    _fastApiResult = null;
    _scanFinished = false;
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  void _showError(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
          SnackBarBehavior.floating,
          backgroundColor:
          const Color(0xFFDC2626),
        ),
      );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child:
              _buildScanBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color:
        const Color(0xFFE5E7EB),
        border: Border(
          bottom: BorderSide(
            color:
            Colors.grey.shade400,
            width: 1,
          ),
        ),
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration:
            const BoxDecoration(
              shape:
              BoxShape.circle,
              color:
              Color(0xFF1764C0),
            ),
            child: const Center(
              child: Icon(
                Icons.navigation,
                color:
                Colors.white,
                size: 27,
              ),
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          const Text(
            'VigilDrive',
            style: TextStyle(
              fontSize: 24,
              fontWeight:
              FontWeight.w700,
              color:
              Color(0xFF075BC5),
            ),
          ),

          const Spacer(),

          Container(
            width: 24,
            height: 24,
            decoration:
            BoxDecoration(
              shape:
              BoxShape.circle,
              border: Border.all(
                color:
                const Color(
                  0xFF0062CE,
                ),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.check,
              color:
              Color(0xFF0062CE),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SCAN BODY
  // ============================================================

  Widget _buildScanBody() {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        return SingleChildScrollView(
          physics:
          const NeverScrollableScrollPhysics(),
          child: SizedBox(
            height:
            constraints.maxHeight,
            child: Column(
              children: [
                const SizedBox(
                  height: 20,
                ),

                // =================================================
                // RADAR
                // =================================================

                SizedBox(
                  width: 300,
                  height: 300,
                  child: Stack(
                    alignment:
                    Alignment.center,
                    children: [
                      Container(
                        width: 260,
                        height: 260,
                        decoration:
                        BoxDecoration(
                          shape:
                          BoxShape.circle,
                          border:
                          Border.all(
                            color:
                            const Color(
                              0xFFB3C6FF,
                            ),
                            width: 4,
                          ),
                        ),
                      ),

                      Container(
                        width: 230,
                        height: 230,
                        decoration:
                        BoxDecoration(
                          shape:
                          BoxShape.circle,
                          border:
                          Border.all(
                            color:
                            const Color(
                              0xFFD5DEFF,
                            ),
                            width: 2,
                          ),
                        ),
                      ),

                      Container(
                        width: 180,
                        height: 180,
                        decoration:
                        BoxDecoration(
                          shape:
                          BoxShape.circle,
                          border:
                          Border.all(
                            color:
                            const Color(
                              0xFF1764C0,
                            ),
                            width: 1.2,
                          ),
                        ),
                      ),

                      Positioned(
                        left: 55,
                        right: 55,
                        child:
                        Container(
                          height: 5,
                          decoration:
                          BoxDecoration(
                            gradient:
                            const LinearGradient(
                              colors: [
                                Color(
                                  0x003B82F6,
                                ),
                                Color(
                                  0xFF1764C0,
                                ),
                                Color(
                                  0x003B82F6,
                                ),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                const Color(
                                  0xFF1764C0,
                                ).withOpacity(
                                  0.45,
                                ),
                                blurRadius:
                                8,
                                spreadRadius:
                                2,
                              ),
                            ],
                          ),
                        ),
                      ),

                      Container(
                        width: 50,
                        height: 50,
                        decoration:
                        BoxDecoration(
                          shape:
                          BoxShape.circle,
                          border:
                          Border.all(
                            color:
                            const Color(
                              0xFF3477D1,
                            ),
                            width: 5,
                          ),
                        ),
                        child:
                        Container(
                          margin:
                          const EdgeInsets
                              .all(6),
                          decoration:
                          const BoxDecoration(
                            shape:
                            BoxShape.circle,
                            color:
                            Color(
                              0xFF3477D1,
                            ),
                          ),
                          child:
                          const Icon(
                            Icons.radar,
                            color:
                            Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // =================================================
                // TITLE
                // =================================================

                Text(
                  _isProcessing
                      ? 'Processing Safety Scan'
                      : 'Safety Scan in Progress',
                  textAlign:
                  TextAlign.center,
                  style:
                  const TextStyle(
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w500,
                    color:
                    Color(0xFF222222),
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                // =================================================
                // DESCRIPTION
                // =================================================

                Padding(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 28,
                  ),
                  child: Text(
                    _isProcessing
                        ? 'Uploading and analyzing your safety scan...'
                        : 'Please remain attentive and keep your eyes\n'
                        'on the road.',
                    textAlign:
                    TextAlign.center,
                    style:
                    const TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color:
                      Color(0xFF555967),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                // =================================================
                // HIDDEN CAMERA PREVIEW
                // =================================================

                if (_cameraReady &&
                    _cameraController !=
                        null)
                  SizedBox(
                    width: 1,
                    height: 1,
                    child:
                    CameraPreview(
                      _cameraController!,
                    ),
                  ),

                // =================================================
                // RECORDING COUNTDOWN
                // =================================================

                if (_isRecording)
                  Text(
                    'Recording: '
                        '$_remainingSeconds s',
                    style:
                    const TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w600,
                      color:
                      Color(0xFF2563EB),
                    ),
                  ),

                // =================================================
                // PROCESSING
                // =================================================

                if (_isProcessing)
                  const Padding(
                    padding:
                    EdgeInsets.only(
                      top: 14,
                    ),
                    child:
                    SizedBox(
                      width: 22,
                      height: 22,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),

                // =================================================
                // CAMERA RETRY
                // =================================================

                if (!_cameraReady &&
                    !_isProcessing)
                  Padding(
                    padding:
                    const EdgeInsets
                        .only(
                      top: 18,
                    ),
                    child:
                    ElevatedButton(
                      onPressed:
                      _initializeCamera,
                      child:
                      const Text(
                        'RETRY CAMERA',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}