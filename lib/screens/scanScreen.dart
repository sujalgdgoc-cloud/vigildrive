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
  // API
  // ============================================================

  static const String fastApiUrl =
      'https://driver-safety-2-1.onrender.com/api/analyze-video';

  static const String djangoUrl =
      'https://vigildrivebackend.onrender.com/api/v2/driverdata/?format=json';

  String? accessToken;

  // ============================================================
  // SCAN CONFIG
  // ============================================================

  static const int scanDurationSeconds = 5;

  // Give Android MediaRecorder a little time to finalize
  // the MP4 container after stopVideoRecording().
  static const Duration videoFinalizeDelay =
  Duration(milliseconds: 800);

  // ============================================================
  // CAMERA
  // ============================================================

  CameraController? _cameraController;

  bool _cameraReady = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _scanFinished = false;

  // Prevent multiple camera initialization calls.
  bool _isInitializingCamera = false;

  // Prevent the scan from being started twice.
  bool _scanStarted = false;

  Timer? _scanTimer;
  Timer? _countdownTimer;

  int _remainingSeconds = scanDurationSeconds;

  // ============================================================
  // LOCAL VIDEO
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

    _stopSensorMonitoring();

    final controller = _cameraController;

    _cameraController = null;

    controller?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    debugPrint(
      'App lifecycle changed: $state',
    );

    // ----------------------------------------------------------
    // IMPORTANT:
    //
    // NEVER dispose/reinitialize the camera while recording.
    // This was one of the causes of the scan getting stuck.
    // ----------------------------------------------------------

    if (_isRecording || _isProcessing) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    }

    if (state == AppLifecycleState.resumed) {
      if (!_scanFinished &&
          !_scanStarted &&
          !_isProcessing) {
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
    if (_isInitializingCamera) {
      debugPrint(
        'Camera initialization already running.',
      );

      return;
    }

    if (_isRecording ||
        _isProcessing ||
        _scanFinished ||
        _scanStarted) {
      debugPrint(
        'Camera initialization skipped.',
      );

      return;
    }

    _isInitializingCamera = true;

    try {
      debugPrint(
        'Initializing camera...',
      );

      await _disposeCamera();

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'No cameras available.',
        );
      }

      // --------------------------------------------------------
      // Prefer front camera for driver monitoring.
      // --------------------------------------------------------

      CameraDescription selectedCamera =
          cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection ==
            CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
      }

      debugPrint(
        'Selected camera: '
            '${selectedCamera.name}',
      );

      // --------------------------------------------------------
      // MEDIUM is deliberately used.
      //
      // Higher resolutions produce much larger MP4 files and
      // increase the chance of upload/reset problems on Render.
      // --------------------------------------------------------

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

      // --------------------------------------------------------
      // Start only ONCE.
      // --------------------------------------------------------

      if (!_scanStarted &&
          !_scanFinished &&
          !_isProcessing) {
        await _startSafetyScan();
      }
    } on CameraException catch (e) {
      debugPrint(
        'Camera initialization error: '
            '${e.code} - ${e.description}',
      );

      _cameraReady = false;

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

      if (mounted) {
        setState(() {
          _cameraReady = false;
        });

        _showError(
          'Unable to initialize the camera.',
        );
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  // ============================================================
  // START SAFETY SCAN
  // ============================================================

  Future<void> _startSafetyScan() async {
    final controller = _cameraController;

    if (controller == null) {
      debugPrint(
        'Cannot start scan: camera controller is null.',
      );

      return;
    }

    if (!controller.value.isInitialized) {
      debugPrint(
        'Cannot start scan: camera not initialized.',
      );

      return;
    }

    if (_isRecording ||
        _isProcessing ||
        _scanStarted ||
        _scanFinished) {
      return;
    }

    try {
      _scanStarted = true;

      _resetScanData();

      _startSensorMonitoring();

      debugPrint(
        'Starting $scanDurationSeconds second safety scan...',
      );

      // --------------------------------------------------------
      // START RECORDING
      // --------------------------------------------------------

      await controller.startVideoRecording();

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecording = true;

        _remainingSeconds =
            scanDurationSeconds;
      });

      // --------------------------------------------------------
      // COUNTDOWN
      // --------------------------------------------------------

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

      // --------------------------------------------------------
      // EXACTLY 5 SECONDS
      // --------------------------------------------------------

      _scanTimer?.cancel();

      _scanTimer = Timer(
        const Duration(seconds: scanDurationSeconds),
        _finishSafetyScan,
      );
    } on CameraException catch (e) {
      debugPrint(
        'Could not start recording: '
            '${e.code} - ${e.description}',
      );

      _scanStarted = false;

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

      _scanStarted = false;

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
  // FINISH SAFETY SCAN
  // ============================================================

  Future<void> _finishSafetyScan() async {
    if (!_isRecording ||
        _isProcessing ||
        _scanFinished) {
      return;
    }

    debugPrint(
      'Finishing safety scan...',
    );

    _scanTimer?.cancel();
    _countdownTimer?.cancel();

    _scanTimer = null;
    _countdownTimer = null;

    // Stop sensors BEFORE processing the video.
    _stopSensorMonitoring();

    final controller = _cameraController;

    if (controller == null) {
      debugPrint(
        'Cannot finish scan: camera controller is null.',
      );

      return;
    }

    if (!controller.value.isInitialized) {
      debugPrint(
        'Cannot finish scan: camera is not initialized.',
      );

      return;
    }

    if (!controller.value.isRecordingVideo) {
      debugPrint(
        'Camera is no longer recording.',
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
        'Stopping video recording...',
      );

      final XFile recordedFile =
      await controller.stopVideoRecording();

      debugPrint(
        'Camera returned file: '
            '${recordedFile.path}',
      );

      // ========================================================
      // STEP 2
      // IMPORTANT ANDROID FIX
      //
      // Give MediaRecorder time to finalize the MP4 metadata.
      //
      // This helps with:
      //
      // getMetaData returned -22
      //
      // ========================================================

      debugPrint(
        'Waiting for Android to finalize MP4...',
      );

      await Future.delayed(
        videoFinalizeDelay,
      );

      // ========================================================
      // STEP 3
      // SAVE LOCALLY
      // ========================================================

      final localPath =
      await _storeVideoLocally(
        recordedFile,
      );

      _localVideoPath = localPath;

      debugPrint(
        'Local video ready: $localPath',
      );

      // ========================================================
      // STEP 4
      // VERIFY VIDEO
      // ========================================================

      final bool validVideo =
      await _verifyLocalVideo(
        localPath,
      );

      if (!validVideo) {
        throw Exception(
          'Recorded video file is invalid or empty.',
        );
      }

      // ========================================================
      // STEP 5
      // CAMERA IS NO LONGER NEEDED
      //
      // Dispose it completely.
      //
      // DO NOT call _initializeCamera() afterwards.
      // ========================================================

      await _disposeCamera();

      // ========================================================
      // STEP 6
      // UPLOAD TO FASTAPI
      // ========================================================

      debugPrint(
        'Uploading local video to FastAPI...',
      );

      final fastApiResult =
      await _sendLocalVideoToFastAPI(
        localPath,
      );

      if (fastApiResult == null) {
        debugPrint(
          'FastAPI processing failed.',
        );

        // Keep local file for retry.

        if (mounted) {
          setState(() {
            _isProcessing = false;
          });

          _showError(
            'Safety analysis failed.\n'
                'The recorded scan was kept locally.',
          );
        }

        return;
      }

      _fastApiResult = fastApiResult;

      debugPrint(
        'FastAPI analysis completed successfully.',
      );

      // ========================================================
      // STEP 7
      // MOTION ANALYSIS
      // ========================================================

      final motionAnalysis =
      _buildMotionAnalysis();

      // ========================================================
      // STEP 8
      // SEND TO DJANGO
      // ========================================================

      await _sendResultToDjango(
        fastApiResult: fastApiResult,
        motionAnalysis: motionAnalysis,
      );

      // ========================================================
      // STEP 9
      // RISK
      // ========================================================

      final riskLevel =
      (fastApiResult['risk_level'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      debugPrint(
        'Final risk level: $riskLevel',
      );

      // ========================================================
      // DELETE VIDEO ONLY AFTER COMPLETE SUCCESS
      // ========================================================

      await _deleteLocalVideo();

      // ========================================================
      // CRITICAL
      // ========================================================

      if (riskLevel == 'critical') {
        _scanFinished = true;

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
      // NORMAL
      // ========================================================

      _scanFinished = true;

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Return to previous screen.
        Navigator.of(context).pop();
      }
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

        _showError(
          'Camera error while saving the scan.',
        );
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
          'An error occurred while processing the safety scan.',
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

    final String fileName =
        'safety_scan_$timestamp.mp4';

    final String localPath =
    path.join(
      scanDirectory.path,
      fileName,
    );

    debugPrint(
      'Copying recorded video...',
    );

    await recordedFile.saveTo(
      localPath,
    );

    final File localFile =
    File(localPath);

    if (!await localFile.exists()) {
      throw Exception(
        'Local video was not created.',
      );
    }

    final int fileSize =
    await localFile.length();

    debugPrint(
      'Local video size: '
          '$fileSize bytes',
    );

    if (fileSize < 1024) {
      throw Exception(
        'Video file is too small or corrupt.',
      );
    }

    return localPath;
  }

  // ============================================================
  // VERIFY LOCAL VIDEO
  // ============================================================

  Future<bool> _verifyLocalVideo(
      String localPath,
      ) async {
    try {
      final File file =
      File(localPath);

      if (!await file.exists()) {
        debugPrint(
          'Video verification failed: file missing.',
        );

        return false;
      }

      final int size =
      await file.length();

      debugPrint(
        'Video verification size: '
            '$size bytes',
      );

      if (size < 1024) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint(
        'Video verification error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // FASTAPI UPLOAD
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
          'Video does not exist.',
        );

        return null;
      }

      final int fileSize =
      await videoFile.length();

      debugPrint(
        'Uploading file: '
            '$localVideoPath',
      );

      debugPrint(
        'Upload size: '
            '$fileSize bytes',
      );

      final Uri uri =
      Uri.parse(fastApiUrl);

      final request =
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
      // IMPORTANT:
      //
      // FastAPI error previously said:
      //
      // body.file -> Field required
      //
      // Therefore the multipart field MUST be "file".
      // ========================================================

      final multipartFile =
      await http.MultipartFile.fromPath(
        'file',
        localVideoPath,
        filename:
        path.basename(localVideoPath),
      );

      request.files.add(
        multipartFile,
      );

      debugPrint(
        'Sending multipart request to FastAPI...',
      );

      // ========================================================
      // SEND WITH TIMEOUT
      //
      // Render can take a while to wake up/process the video.
      // ========================================================

      final streamedResponse =
      await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException(
            'FastAPI request timed out.',
          );
        },
      );

      final response =
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
      // SUCCESS
      // ========================================================

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        dynamic decoded;

        try {
          decoded =
              jsonDecode(response.body);
        } catch (e) {
          debugPrint(
            'FastAPI returned invalid JSON: $e',
          );

          return null;
        }

        if (decoded is Map) {
          return Map<String, dynamic>.from(
            decoded,
          );
        }

        debugPrint(
          'FastAPI response is not a JSON object.',
        );

        return null;
      }

      // ========================================================
      // VALIDATION ERROR
      // ========================================================

      if (response.statusCode == 422) {
        debugPrint(
          'FastAPI validation error: '
              '${response.body}',
        );

        return null;
      }

      // ========================================================
      // SERVER ERROR
      // ========================================================

      debugPrint(
        'FastAPI server error: '
            '${response.statusCode}',
      );

      return null;
    } on TimeoutException catch (e) {
      debugPrint(
        'FastAPI timeout: $e',
      );

      return null;
    } on SocketException catch (e) {
      debugPrint(
        'FastAPI socket error: $e',
      );

      return null;
    } on http.ClientException catch (e) {
      debugPrint(
        'FastAPI client error: $e',
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
    _stopSensorMonitoring();

    debugPrint(
      'Starting sensor monitoring...',
    );

    _accelerometerSubscription =
        userAccelerometerEventStream().listen(
              (event) {
            final timestamp =
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
            final timestamp =
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

  // ============================================================
  // STOP SENSOR MONITORING
  // ============================================================

  void _stopSensorMonitoring() {
    _accelerometerSubscription?.cancel();

    _gyroscopeSubscription?.cancel();

    _accelerometerSubscription = null;

    _gyroscopeSubscription = null;

    debugPrint(
      'Sensor monitoring stopped.',
    );
  }

  // ============================================================
  // BRAKING
  // ============================================================

  void _detectBraking(
      UserAccelerometerEvent event,
      ) {
    final now = DateTime.now();

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
    final now = DateTime.now();

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
      (data['x'] as num).toDouble();

      final double y =
      (data['y'] as num).toDouble();

      final double z =
      (data['z'] as num).toDouble();

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
      (data['x'] as num).toDouble();

      final double y =
      (data['y'] as num).toDouble();

      final double z =
      (data['z'] as num).toDouble();

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
  // DJANGO
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

        'motion_analysis':
        motionAnalysis,

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
        'Sending safety result to Django...',
      );

      final response =
      await http
          .post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      )
          .timeout(
        const Duration(
          seconds: 60,
        ),
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
    } on TimeoutException catch (e) {
      debugPrint(
        'Django timeout: $e',
      );
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
  }

  // ============================================================
  // ERROR
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
          duration:
          const Duration(seconds: 5),
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

      decoration:
      BoxDecoration(
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

            style:
            TextStyle(
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
              border:
              Border.all(
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
        return SizedBox(
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

              const Text(
                'Safety Scan in Progress',

                textAlign:
                TextAlign.center,

                style:
                TextStyle(
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

              Padding(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 28,
                ),

                child: Text(
                  _isProcessing
                      ? 'Analyzing your safety scan...'
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
              // COUNTDOWN
              // =================================================

              if (_isRecording)
                Text(
                  'Recording: '
                      '$_remainingSeconds s',

                  style:
                  const TextStyle(
                    fontSize: 14,
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
                    top: 16,
                  ),

                  child:
                  Column(
                    children: [
                      SizedBox(
                        width: 25,
                        height: 25,

                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),

                      SizedBox(
                        height: 10,
                      ),

                      Text(
                        'Uploading and analyzing...',
                        style:
                        TextStyle(
                          fontSize: 13,
                          color:
                          Color(
                            0xFF555967,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // =================================================
              // CAMERA PREVIEW
              //
              // Keep it effectively invisible as in your
              // original design.
              // =================================================

              if (_cameraReady &&
                  _cameraController !=
                      null &&
                  !_isProcessing)
                SizedBox(
                  width: 1,
                  height: 1,

                  child:
                  CameraPreview(
                    _cameraController!,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}