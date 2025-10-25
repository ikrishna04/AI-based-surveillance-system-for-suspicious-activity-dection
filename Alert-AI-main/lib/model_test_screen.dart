import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_recognize/detail_screen.dart';
import 'package:image_recognize/login_screen.dart';
import 'package:image_recognize/profile_screen.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart' show rootBundle;

class Detection {
  final String label;
  final double confidence;
  final DateTime timestamp;
  final Uint8List thumbnail;

  Detection({
    required this.label,
    required this.confidence,
    required this.timestamp,
    required this.thumbnail,
  });
}

class ModelTestScreen extends StatefulWidget {
  const ModelTestScreen({super.key});

  @override
  _ModelTestScreenState createState() => _ModelTestScreenState();
}

class _ModelTestScreenState extends State<ModelTestScreen> {
  late Interpreter _interpreter;
  List<String> _labels = [];
  File? _video;
  VideoPlayerController? _videoController;
  String _predictedLabel = ' ';
  bool _isModelLoaded = false;
  double confidenceThreshold = 0.7; // Adjust this threshold as needed
  bool _isProcessing = false;
  Timer? _videoProcessingTimer;
  bool _isVideoPlaying = false;

  // For post-processing (moving average)
  final List<double> _confidenceScores = [];
  final List<String> _predictedLabels = [];
  final List<Detection> _detectionHistory = [];
  String? _fcmToken;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadLabels();
    _getFCMToken();
    requestNotificationPermissions();
    _initializeNotifications();
  }

  Future<void> requestNotificationPermissions() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _getFCMToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    try {
      // Request permission for notifications
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // Get the FCM token
        String? token = await messaging.getToken();
        setState(() {
          _fcmToken = token;
        });

        print("FCM Token: $_fcmToken");
      } else {
        print("User declined or has not accepted permissions");
      }
    } catch (e) {
      print("ssssssssss $e");
    }
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void showLocalNotification(String label, double confidence) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_importance_channel', // Ensure this matches your existing channel ID
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Detection Alert!',
      'Detected: $label with ${(confidence * 100).toStringAsFixed(1)}% confidence',
      platformChannelSpecifics,
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _videoProcessingTimer?.cancel();
    _interpreter.close();
    super.dispose();
  }

  Future<void> _processVideoFrame(img.Image frame) async {
    if (!_isModelLoaded) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      List<double> inputArray = await _processImageData(frame);

      var reshapedInput = inputArray.reshape([1, 224, 224, 3]);

      var outputShape = _interpreter.getOutputTensor(0).shape;
      var outputBuffer =
          List<double>.filled(outputShape.reduce((a, b) => a * b), 0)
              .reshape(outputShape);

      _interpreter.run(reshapedInput, outputBuffer);

      List<double> outputArray = outputBuffer[0];
      int maxIndex = 0;
      double maxValue = outputArray[0];

      for (int i = 1; i < outputArray.length; i++) {
        if (outputArray[i] > maxValue) {
          maxValue = outputArray[i];
          maxIndex = i;
        }
      }

      // Update prediction with moving average
      if (maxIndex < _labels.length) {
        _updatePrediction(_labels[maxIndex], maxValue);
      }
    } catch (e) {
      print('Error processing video frame: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed: Input shape mismatch or other error: $e"),
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _updatePrediction(String label, double confidence) async {
    // Add new prediction to tracking lists
    _confidenceScores.add(confidence);
    _predictedLabels.add(label);

    // Keep only last 10 predictions for smooth transitions
    if (_confidenceScores.length > 10) {
      _confidenceScores.removeAt(0);
      _predictedLabels.removeAt(0);
    }

    // Calculate average confidence
    double avgConfidence =
        _confidenceScores.reduce((a, b) => a + b) / _confidenceScores.length;

    // Find most frequent label in recent predictions
    Map<String, int> labelCounts = {};
    for (String label in _predictedLabels) {
      labelCounts[label] = (labelCounts[label] ?? 0) + 1;
    }

    String mostCommonLabel =
        labelCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    // Update UI with prediction
    setState(() {
      if (avgConfidence > confidenceThreshold) {
        _predictedLabel =
            "$mostCommonLabel (${(avgConfidence * 100).toStringAsFixed(1)}%)";

        // For very high confidence predictions (>90%), save with thumbnail
        if (avgConfidence > 0.90 && _video != null) {
          _saveHighConfidenceDetection(mostCommonLabel, avgConfidence);
        }
      } else {
        _predictedLabel = "Unknown";
      }
    });
  }

  Future<void> _saveHighConfidenceDetection(
      String label, double confidence) async {
    try {
      if (_video == null) return;

      // Check if the label already exists in the detection history
      bool labelExists =
          _detectionHistory.any((detection) => detection.label == label);

      if (!labelExists) {
        final thumbnail = await VideoThumbnail.thumbnailData(
          video: _video!.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 256,
          maxHeight: 256,
          quality: 85,
          timeMs: (_videoController?.value.position.inMilliseconds ??
              0), // Capture current frame
        );

        if (thumbnail != null) {
          setState(() {
            _detectionHistory.add(Detection(
              label: label,
              confidence: confidence,
              timestamp: DateTime.now(),
              thumbnail: thumbnail,
            ));
          });

// Show local notification when detection occurs
          showLocalNotification(label, confidence);
        }
      }
    } catch (e) {
      print('Error saving high confidence detection: $e');
    }
  }

  // Update the UI only if confidence is above the threshold

  Future<void> _pickVideo() async {
    final pickedFile =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _video = File(pickedFile.path);
    });

    _initializeVideoController();
  }

  Future<void> _initializeVideoController() async {
    if (_video == null) return;

    _videoController = VideoPlayerController.file(_video!);
    try {
      await _videoController!.initialize();
      if (!mounted) return;

      setState(() {});

      _videoController!.play();
      _isVideoPlaying = true;
      _startVideoProcessing();
    } catch (e) {
      print('Failed to initialize video controller: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to load video: $e"),
        ),
      );
    }
  }

  void _startVideoProcessing() {
    const frameInterval = Duration(milliseconds: 300);
    _videoProcessingTimer = Timer.periodic(frameInterval, (timer) async {
      if (_videoController!.value.isPlaying && !_isProcessing) {
        await _captureAndProcessFrame();
      } else if (!_videoController!.value.isPlaying) {
        timer.cancel();
      }
    });
  }

  Future<void> _captureAndProcessFrame() async {
    if (_video == null) return;

    final thumbnail = await VideoThumbnail.thumbnailData(
      video: _video!.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 224,
      quality: 50,
    );

    if (thumbnail != null) {
      final img.Image? image = img.decodeImage(thumbnail);
      if (image != null) {
        await _processVideoFrame(image);
      }
    }
  }

  Future<List<double>> _processImageData(img.Image image) async {
    try {
      final img.Image resizedImage =
          img.copyResize(image, width: 224, height: 224);

      var inputArray = Float32List(224 * 224 * 3);

      for (int i = 0; i < resizedImage.height; i++) {
        for (int j = 0; j < resizedImage.width; j++) {
          int pixel = resizedImage.getPixel(j, i);
          inputArray[(i * resizedImage.width + j) * 3] =
              img.getRed(pixel) / 255.0;
          inputArray[(i * resizedImage.width + j) * 3 + 1] =
              img.getGreen(pixel) / 255.0;
          inputArray[(i * resizedImage.width + j) * 3 + 2] =
              img.getBlue(pixel) / 255.0;
        }
      }

      return inputArray;
    } catch (e) {
      print('Error processing image data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed: Input shape or other error: $e"),
        ),
      );
      rethrow;
    }
  }

  void _loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/model_unquant.tflite',
          options: options);

      var inputShape = _interpreter.getInputTensor(0).shape;
      var outputShape = _interpreter.getOutputTensor(0).shape;

      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text("output  $outputShape,  $inputShape"),
      //   ),
      // );

      setState(() {
        _isModelLoaded = true;
      });
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  void _loadLabels() async {
    try {
      final labelData = await rootBundle.loadString('assets/labels.txt');
      setState(() {
        _labels = labelData
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      });
    } catch (e) {
      print('Failed to load labels: $e');
    }
  }

  void _togglePlayPause() {
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
      setState(() {
        _isVideoPlaying = false;
      });
    } else {
      _videoController!.play();
      setState(() {
        _isVideoPlaying = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        automaticallyImplyLeading: false,
        title: Text(
          'Alert AI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case "Account":
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AccountsScreen(),
                    ),
                  );
                  break;

                case "LogOut":
                  _showLogoutConfirmationDialog(context);
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: "Account",
                  child: Text("Account"),
                ),
                PopupMenuItem<String>(
                  value: "LogOut",
                  child: Text(
                    "LogOut",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      backgroundColor: Colors.blueGrey[900],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blueGrey[800],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _videoController != null &&
                          _videoController!.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        )
                      : Container(
                          color: Colors.blueGrey[700],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.video_library,
                                  color: Colors.tealAccent,
                                  size: 48,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No Video Selected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              SizedBox(height: 20),
              AnimatedContainer(
                duration: Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[800],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.assessment,
                      color: Colors.tealAccent,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Action: $_predictedLabel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickVideo,
                    icon: Icon(Icons.video_library, color: Colors.white),
                    label: Text(
                      'Pick Video',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_videoController != null)
                    ElevatedButton.icon(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      label: Text(
                        _isVideoPlaying ? 'Pause' : 'Play',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
              if (_isProcessing)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.blueGrey[700],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                  ),
                ),
              if (_detectionHistory.isNotEmpty) ...[
                SizedBox(height: 20),
                Text(
                  'Recent Detected Items',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: _detectionHistory.length,
                  itemBuilder: (context, index) {
                    // final detection = _detectionHistory[index];
                    // Sort the list by timestamp in descending order
                    final sortedHistory = _detectionHistory
                      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
                    final detection = sortedHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey[800],
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    DetailsScreen(detectionHistory: detection),
                              ),
                            );
                          },
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                detection.thumbnail,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                            title: Text(
                              "${detection.label} Detected",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Confidence: ${(detection.confidence * 100).toStringAsFixed(1)}%\n'
                              '${_formatTime(detection.timestamp)}',
                              style: TextStyle(color: Colors.white70),
                            ),
                            trailing: Icon(
                              Icons.check_circle,
                              color: Colors.tealAccent,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _showLogoutConfirmationDialog(BuildContext context) async {
  bool shouldLogout = await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.blueGrey[800],
        title: Text(
          "LogOut ?",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to log out?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          Container(
            decoration: BoxDecoration(
              color: Colors.blueGrey[800],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                "Cancel",
                style: TextStyle(color: Colors.tealAccent),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.blueGrey[800],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(true); // Close the dialog and confirm logout
              },
              child: Text(
                "Logout",
                style:
                    TextStyle(color: Colors.redAccent), // Logout button color
              ),
            ),
          ),
        ],
      );
    },
  );

  if (shouldLogout) {
    // Only navigate after the dialog is dismissed
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(), // Your Login screen widget
      ),
    );
  }
}

String _formatTime(DateTime timestamp) {
  // Format the time to 12-hour format with AM/PM
  int hour = timestamp.hour % 12;
  String period = timestamp.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} $period';
}
