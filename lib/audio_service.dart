import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math'; 
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService extends ChangeNotifier {
  static const String defaultServerUrl = 'ws://192.168.1.26:8000/ws/audio?token=flutter';

  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordingTimer;

  bool _isConnected = false;
  bool _isRecording = false;
  String _sessionId = '';
  String _serverUrl = defaultServerUrl;
  String _status = 'Disconnected';
  List<String> _messages = [];
  int _chunksSent = 0;

  // Getters
  bool get isConnected => _isConnected;
  bool get isRecording => _isRecording;
  String get sessionId => _sessionId;
  String get serverUrl => _serverUrl;
  String get status => _status;
  List<String> get messages => _messages;
  int get chunksSent => _chunksSent;

  void setServerUrl(String url) {
    _serverUrl = url;
    notifyListeners();
  }

  void _addMessage(String message) {
    _messages.insert(0, '${DateTime.now().toString().substring(11, 19)}: $message');
    if (_messages.length > 50) {
      _messages.removeLast();
    }
    notifyListeners();
  }

  void _updateStatus(String status) {
    _status = status;
    _addMessage(status);
    notifyListeners();
  }

  Future<bool> _requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    return microphoneStatus == PermissionStatus.granted;
  }

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _updateStatus('Connecting to server...');

      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

      // Listen for messages
      _channel!.stream.listen(
        (message) {
          _handleServerMessage(message);
        },
        onError: (error) {
          _updateStatus('WebSocket error: $error');
          _disconnect();
        },
        onDone: () {
          _updateStatus('Connection closed by server');
          _disconnect();
        },
      );

      _isConnected = true;
      _sessionId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
      _chunksSent = 0;

      // Send metadata
      final metadata = {
        'type': 'meta',
        'session_id': _sessionId,
        'sample_rate': 16000,
        'channels': 1,
      };

      _channel!.sink.add(jsonEncode(metadata));
      _updateStatus('Connected! Session: $_sessionId');
    } catch (e) {
      _updateStatus('Connection failed: $e');
      _disconnect();
    }
  }

  void _handleServerMessage(dynamic message) {
    try {
      if (message is String) {
        final data = jsonDecode(message);
        final type = data['type'];

        switch (type) {
          case 'connection_established':
            _addMessage('Server: ${data['message']}');
            break;
          case 'meta_ack':
            _addMessage('Metadata acknowledged');
            break;
          case 'chunk_processed':
            final sequence = data['sequence'];
            final size = data['size'];
            _addMessage('Chunk $sequence processed ($size bytes)');
            break;
          case 'error':
            _addMessage('Server error: ${data['message']}');
            break;
          default:
            _addMessage('Server: $message');
        }
      }
    } catch (e) {
      _addMessage('Failed to parse server message: $e');
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_isRecording) {
      await stopRecording();
    }

    _updateStatus('Disconnecting...');
    _disconnect();
    _updateStatus('Disconnected');
  }

  Future<void> startRecording() async {
    if (!_isConnected) {
      _updateStatus('Not connected to server');
      return;
    }

    if (_isRecording) return;

    // Request permissions
    if (!await _requestPermissions()) {
      _updateStatus('Microphone permission denied');
      return;
    }

    try {
      // Check if recorder is available
      if (!await _recorder.hasPermission()) {
        _updateStatus('No recording permission');
        return;
      }

      _updateStatus('Starting recording...');

      // ✅ Added required path parameter
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '/tmp/recording.wav', // required for new API
      );

      _isRecording = true;
      _chunksSent = 0;
      _updateStatus('Recording started');

      // Start streaming timer (send chunks every 100ms)
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        _sendAudioChunk();
      });
    } catch (e) {
      _updateStatus('Failed to start recording: $e');
    }

    notifyListeners();
  }

  Future<void> _sendAudioChunk() async {
    if (!_isRecording || !_isConnected) return;

    try {
      // Simulated audio data
      final chunkSize = 1600; // 100ms at 16kHz mono 16-bit
      final audioData = Uint8List(chunkSize * 2); // 16-bit samples

      // Generate sine wave
      final frequency = 440.0; // A4 note
      final sampleRate = 16000.0;

      for (int i = 0; i < chunkSize; i++) {
        final time = (_chunksSent * chunkSize + i) / sampleRate;
        // ✅ Use sin() from dart:math instead of .sin()
        final amplitude = (16384 * (0.1 * sin(2 * pi * frequency * time))).round();

        // Convert to 16-bit little-endian
        audioData[i * 2] = amplitude & 0xFF;
        audioData[i * 2 + 1] = (amplitude >> 8) & 0xFF;
      }

      // Send binary data
      _channel!.sink.add(audioData);
      _chunksSent++;
    } catch (e) {
      _addMessage('Error sending audio chunk: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;

      await _recorder.stop();
      _isRecording = false;
      _updateStatus('Recording stopped');
    } catch (e) {
      _updateStatus('Error stopping recording: $e');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _channel?.sink.close();
    super.dispose();
  }
}