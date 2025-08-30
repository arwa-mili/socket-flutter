import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'audio_service.dart';

class AudioScreen extends StatefulWidget {
  @override
  _AudioScreenState createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  final TextEditingController _urlController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _urlController.text = AudioService.defaultServerUrl;
  }
  
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Audio Streaming'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AudioService>(
        builder: (context, audioService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Server URL input
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server Configuration',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: 8),
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: 'WebSocket URL',
                            hintText: 'ws://your-server:8000/ws/audio?token=flutter',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !audioService.isConnected,
                          onChanged: (value) {
                            audioService.setServerUrl(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Connection status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              audioService.isConnected 
                                ? Icons.wifi 
                                : Icons.wifi_off,
                              color: audioService.isConnected 
                                ? Colors.green 
                                : Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Status: ${audioService.status}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        if (audioService.sessionId.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Text('Session: ${audioService.sessionId}'),
                          Text('Chunks sent: ${audioService.chunksSent}'),
                        ],
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Control buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: audioService.isConnected 
                          ? null 
                          : () => audioService.connect(),
                        icon: Icon(Icons.link),
                        label: Text('Connect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: audioService.isConnected 
                          ? () => audioService.disconnect()
                          : null,
                        icon: Icon(Icons.link_off),
                        label: Text('Disconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Recording controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: audioService.isConnected && !audioService.isRecording
                          ? () => audioService.startRecording()
                          : null,
                        icon: Icon(Icons.mic),
                        label: Text('Start Recording'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: audioService.isRecording
                          ? () => audioService.stopRecording()
                          : null,
                        icon: Icon(Icons.stop),
                        label: Text('Stop Recording'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Recording indicator
                if (audioService.isRecording)
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.fiber_manual_record, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Recording in progress...',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                SizedBox(height: 16),
                
                // Messages log
                Expanded(
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Text(
                                'Activity Log',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Spacer(),
                              IconButton(
                                onPressed: () {
                                  // Clear messages
                                  audioService.messages.clear();
                                },
                                icon: Icon(Icons.clear),
                                tooltip: 'Clear log',
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.all(8),
                            itemCount: audioService.messages.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  audioService.messages[index],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

