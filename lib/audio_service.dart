import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService extends ChangeNotifier {
  static const String defaultServerUrl = 'ws://192.168.1.32:8000/ws/audio?token=flutter';

  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordingTimer;
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  bool _isConnected = false;
  bool _isRecording = false;
  String _sessionId = '';
  String _serverUrl = defaultServerUrl;
  String _status = 'Disconnected';
  List<String> _messages = [];
  int _chunksSent = 0;

  List<int> _audioBuffer = [];
  static const int _targetChunkDurationMs = 4000; // 0.4 second
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bytesPerSample = 2; 
  static const int _targetChunkSize = (_sampleRate * _channels * _bytesPerSample * _targetChunkDurationMs) ~/ 1000;

  DateTime? _recordingStartTime;

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
    if (_messages.length > 50) _messages.removeLast();
    notifyListeners();
  }

  void _updateStatus(String status) {
    _status = status;
    _addMessage(status);
    notifyListeners();
  }

  Future<bool> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    return micStatus == PermissionStatus.granted;
  }

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _updateStatus('Connecting to server...');
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

      _channel!.stream.listen(
        (message) => _handleServerMessage(message),
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

      final metadata = {
        'type': 'meta',
        'session_id': _sessionId,
        'sample_rate': _sampleRate,
        'channels': _channels,
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
    if (_isRecording) await stopRecording();
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
    if (!await _requestPermissions()) {
      _updateStatus('Microphone permission denied');
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _updateStatus('No recording permission');
        return;
      }

      _updateStatus('Starting recording...');
      _audioBuffer.clear();
      _recordingStartTime = DateTime.now();

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channels,
        ),
      );

      _isRecording = true;
      _chunksSent = 0;
      _updateStatus('Recording started - sending chunks every ${_targetChunkDurationMs}ms');

      _audioStreamSubscription = stream.listen(
        (audioData) => _audioBuffer.addAll(audioData),
        onError: (error) {
          _updateStatus('Audio stream error: $error');
          stopRecording();
        },
        onDone: () => _updateStatus('Audio stream ended'),
      );

      _startChunkTimer();

    } catch (e) {
      _updateStatus('Failed to start recording: $e');
    }

    notifyListeners();
  }

  void _startChunkTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(
      Duration(milliseconds: _targetChunkDurationMs),
      (_) {
        if (!_isRecording || !_isConnected) return;
        _sendBufferedAudioChunk();
      },
    );
  }

  Future<void> _sendBufferedAudioChunk() async {
    if (!_isConnected) return;

    try {
      Uint8List chunk;

      if (_audioBuffer.isEmpty) {
        chunk = Uint8List(_targetChunkSize); 
      } else {
        final takeSize = min(_audioBuffer.length, _targetChunkSize);
        chunk = Uint8List(_targetChunkSize);
        chunk.setRange(0, takeSize, _audioBuffer);
        _audioBuffer.removeRange(0, takeSize);
      }

      _channel!.sink.add(chunk);
      _chunksSent++;
      _addMessage('Sent audio chunk $_chunksSent (${chunk.length} bytes)');
    } catch (e) {
      _addMessage('Error sending audio chunk: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _recorder.stop();

    if (_audioBuffer.isNotEmpty) {
      final remainingData = Uint8List.fromList(_audioBuffer);
      _channel!.sink.add(remainingData);
      _chunksSent++;
      _addMessage('Sent final chunk $_chunksSent (${remainingData.length} bytes)');
      _audioBuffer.clear();
    }

    _isRecording = false;

    if (_recordingStartTime != null) {
      final totalDuration = DateTime.now().difference(_recordingStartTime!);
      _updateStatus('Recording stopped - Sent: $_chunksSent chunks, Duration: ${totalDuration.inMilliseconds}ms');
    } else {
      _updateStatus('Recording stopped - Total chunks sent: $_chunksSent');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioStreamSubscription?.cancel();
    _recorder.dispose();
    _channel?.sink.close();
    super.dispose();
  }
}
