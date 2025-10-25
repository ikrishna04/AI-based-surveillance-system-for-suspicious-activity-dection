import 'package:flutter/material.dart';
import 'dart:typed_data';

class DetailsScreen extends StatelessWidget {
  final detectionHistory;

  const DetailsScreen({super.key, required this.detectionHistory});

  String _formatTime(DateTime timestamp) {
    // Format the time to 12-hour format with AM/PM
    int hour = timestamp.hour % 12;
    String period = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detection Details'),
        backgroundColor: Colors.teal[700],
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueGrey[900]!, Colors.teal[300]!],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Hero(
                  tag: 'detection-thumbnail',
                  child: Material(
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: detectionHistory.thumbnail.isNotEmpty
                          ? Image.memory(
                              detectionHistory.thumbnail,
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 150,
                              height: 150,
                              color: Colors.teal[800],
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                "${detectionHistory.label} Detected",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Confidence: ${(detectionHistory.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Time: ${_formatTime(detectionHistory.timestamp)}',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 20),
              Divider(color: Colors.white38),
              SizedBox(height: 20),
              Text(
                'Additional Information',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    _buildInfoCard('Location', 'Unknown'),
                    _buildInfoCard('Device', 'Pixel 6'),
                    _buildInfoCard('Model Version', 'v1.2.3'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Card(
      color: Colors.teal[700],
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.tealAccent,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
