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

  // Buffer pour accumuler les données audio
  List<int> _audioBuffer = [];
  static const int _targetChunkDurationMs = 500; // 0.5 seconde
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bytesPerSample = 2; // 16-bit PCM
  static const int _targetChunkSize = (_sampleRate * _channels * _bytesPerSample * _targetChunkDurationMs) ~/ 1000;

  // ✅ NOUVEAU: Suivre le timing précis
  DateTime? _lastChunkSentTime;
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
            // ✅ NOUVEAU: Vérifier la durée attendue par le serveur
            final expectedDuration = data['expected_chunk_duration_ms'];
            if (expectedDuration != null) {
              _addMessage('Server expects chunks every ${expectedDuration}ms');
            }
            break;
          case 'chunk_processed':
            final sequence = data['sequence'];
            final size = data['size'];
            final actualDuration = data['actual_duration_ms'];
            final expectedDuration = data['expected_duration_ms'];
            
            String durationInfo = '';
            if (actualDuration != null && expectedDuration != null) {
              durationInfo = ' (${actualDuration.toStringAsFixed(1)}ms vs ${expectedDuration}ms expected)';
            }
            
            _addMessage('Chunk $sequence processed ($size bytes)$durationInfo');
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

      // Réinitialiser le buffer et les timings
      _audioBuffer.clear();
      _lastChunkSentTime = null;
      _recordingStartTime = DateTime.now();

      // Utiliser startStream() pour obtenir les données audio en temps réel
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

      // Écouter le stream audio réel
      _audioStreamSubscription = stream.listen(
        (audioData) {
          _processAudioData(audioData);
        },
        onError: (error) {
          _updateStatus('Audio stream error: $error');
          stopRecording();
        },
        onDone: () {
          _updateStatus('Audio stream ended');
        },
      );

      // ✅ AMÉLIORATION: Timer plus précis avec compensation de dérive
      _startPreciseTimer();

    } catch (e) {
      _updateStatus('Failed to start recording: $e');
    }

    notifyListeners();
  }

  // ✅ NOUVEAU: Timer plus précis pour éviter la dérive temporelle
  void _startPreciseTimer() {
    final startTime = DateTime.now();
    int expectedChunks = 0;
    
    _recordingTimer = Timer.periodic(Duration(milliseconds: 50000), (timer) {
      if (!_isRecording || !_isConnected) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final elapsedMs = now.difference(startTime).inMilliseconds;
      final shouldHaveSentChunks = (elapsedMs / _targetChunkDurationMs).floor();
      
      // Envoyer les chunks manqués pour rattraper le timing
      while (expectedChunks < shouldHaveSentChunks) {
        _sendBufferedAudioChunk();
        expectedChunks++;
      }
    });
  }

  // Traiter les données audio reçues du stream
  void _processAudioData(Uint8List audioData) {
    if (!_isRecording || !_isConnected) return;

    // Ajouter les nouvelles données au buffer
    _audioBuffer.addAll(audioData);
  }

  // ✅ AMÉLIORATION: Envoyer les données audio avec meilleur contrôle de taille
  Future<void> _sendBufferedAudioChunk() async {
    if (!_isRecording || !_isConnected) return;

    try {
      final now = DateTime.now();
      
      // ✅ AMÉLIORATION: Envoyer même si le buffer est plus petit que la taille cible
      // pour maintenir le timing régulier
      if (_audioBuffer.isEmpty) {
        // Si pas de données, envoyer un chunk de silence
        final silenceChunk = Uint8List(_targetChunkSize);
        _channel!.sink.add(silenceChunk);
        _chunksSent++;
        _addMessage('Sent silence chunk ${_chunksSent} (${silenceChunk.length} bytes)');
      } else {
        // Prendre toutes les données disponibles ou la taille cible
        final chunkSize = _audioBuffer.length > _targetChunkSize ? _targetChunkSize : _audioBuffer.length;
        final chunkData = Uint8List.fromList(_audioBuffer.take(chunkSize).toList());
        
        // Si le chunk est plus petit que la taille cible, le compléter avec du silence
        Uint8List finalChunk;
        if (chunkData.length < _targetChunkSize) {
          finalChunk = Uint8List(_targetChunkSize);
          finalChunk.setRange(0, chunkData.length, chunkData);
          // Le reste reste à zéro (silence)
        } else {
          finalChunk = chunkData;
        }
        
        // Retirer les données envoyées du buffer
        final dataToRemove = chunkData.length;
        if (_audioBuffer.length >= dataToRemove) {
          _audioBuffer.removeRange(0, dataToRemove);
        } else {
          _audioBuffer.clear();
        }

        // Envoyer les données audio
        _channel!.sink.add(finalChunk);
        _chunksSent++;
        
        // ✅ NOUVEAU: Calculer le timing réel
        String timingInfo = '';
        if (_lastChunkSentTime != null) {
          final actualInterval = now.difference(_lastChunkSentTime!).inMilliseconds;
          timingInfo = ' (interval: ${actualInterval}ms)';
        }
        
        _addMessage('Sent audio chunk ${_chunksSent} (${finalChunk.length} bytes)$timingInfo');
      }
      
      _lastChunkSentTime = now;
      
    } catch (e) {
      _addMessage('Error sending audio chunk: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      _updateStatus('Stopping recording...');

      // Arrêter le timer
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Arrêter l'écoute du stream audio
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // Arrêter l'enregistrement
      await _recorder.stop();

      // Envoyer les dernières données du buffer s'il en reste
      if (_audioBuffer.isNotEmpty) {
        final remainingData = Uint8List.fromList(_audioBuffer);
        _channel!.sink.add(remainingData);
        _chunksSent++;
        _addMessage('Sent final chunk ${_chunksSent} (${remainingData.length} bytes)');
      }

      // Vider le buffer
      _audioBuffer.clear();

      _isRecording = false;
      
      // ✅ NOUVEAU: Afficher les statistiques de timing
      if (_recordingStartTime != null) {
        final totalDuration = DateTime.now().difference(_recordingStartTime!);
        final expectedChunks = (totalDuration.inMilliseconds / _targetChunkDurationMs).round();
        _updateStatus('Recording stopped - Sent: $_chunksSent chunks, Expected: $expectedChunks chunks');
      } else {
        _updateStatus('Recording stopped - Total chunks sent: $_chunksSent');
      }
    } catch (e) {
      _updateStatus('Error stopping recording: $e');
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