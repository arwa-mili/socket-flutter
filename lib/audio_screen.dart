import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'audio_service.dart';

class AudioScreen extends StatefulWidget {
  @override
  _AudioScreenState createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _suraController = TextEditingController();
  final TextEditingController _ayatBeginController = TextEditingController();
  final TextEditingController _ayatEndController = TextEditingController();
  final TextEditingController _wordBeginController = TextEditingController();
  final TextEditingController _wordEndController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = AudioService.defaultServerUrl;
    _suraController.text = '1';
    _ayatBeginController.text = '1';
    _ayatEndController.text = '7';
    _wordBeginController.text = '1';
    _wordEndController.text = '4';
  }

  @override
  void dispose() {
    _urlController.dispose();
    _suraController.dispose();
    _ayatBeginController.dispose();
    _ayatEndController.dispose();
    _wordBeginController.dispose();
    _wordEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Quran Audio Streaming'), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
      body: Consumer<AudioService>(
        builder: (context, audioService, child) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Server URL
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _urlController,
                      decoration: InputDecoration(labelText: 'WebSocket URL', border: OutlineInputBorder()),
                      enabled: !audioService.isConnected,
                      onChanged: (value) => audioService.setServerUrl(value),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // Quran info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Quran Verse Info', style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _numberInputField('Sura', _suraController, audioService.setSuraNumber, audioService.isConnected)),
                            SizedBox(width: 8),
                            Expanded(child: _numberInputField('Ayat Begin', _ayatBeginController, audioService.setAyatBegin, audioService.isConnected)),
                            SizedBox(width: 8),
                            Expanded(child: _numberInputField('Ayat End', _ayatEndController, audioService.setAyatEnd, audioService.isConnected)),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _numberInputField('Word Begin', _wordBeginController, audioService.setWordBegin, audioService.isConnected)),
                            SizedBox(width: 8),
                            Expanded(child: _numberInputField('Word End', _wordEndController, audioService.setWordEnd, audioService.isConnected)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // Status card
                Card(
                  color: audioService.isConnected ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(audioService.isConnected ? Icons.wifi : Icons.wifi_off, color: audioService.isConnected ? Colors.green : Colors.red),
                            SizedBox(width: 8),
                            Expanded(child: Text('Status: ${audioService.status}', style: Theme.of(context).textTheme.titleMedium)),
                          ],
                        ),
                        if (audioService.sessionId.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Text('Session: ${audioService.sessionId}'),
                          Text('Current: Sura ${audioService.suraNumber}, Ayat ${audioService.ayatBegin}-${audioService.ayatEnd}, Words ${audioService.wordBegin}-${audioService.wordEnd}'),
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
                    Expanded(child: ElevatedButton(onPressed: audioService.isConnected ? null : () => audioService.connect(), child: Text('Connect'))),
                    SizedBox(width: 8),
                    Expanded(child: ElevatedButton(onPressed: audioService.isConnected ? () => audioService.disconnect() : null, child: Text('Disconnect'))),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: audioService.isConnected && !audioService.isRecording ? () => audioService.startRecording() : null, child: Text('Start Recording'))),
                    SizedBox(width: 8),
                    Expanded(child: ElevatedButton(onPressed: audioService.isRecording ? () => audioService.stopRecording() : null, child: Text('Stop Recording'))),
                  ],
                ),
                SizedBox(height: 16),
                if (audioService.isRecording)
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                    child: Row(children: [Icon(Icons.fiber_manual_record, color: Colors.red), SizedBox(width: 8), Expanded(child: Text('Recording Sura ${audioService.suraNumber}, Ayat ${audioService.ayatBegin}-${audioService.ayatEnd}...', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))]),
                  ),
                SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Text('Activity Log', style: Theme.of(context).textTheme.titleMedium),
                              Spacer(),
                              IconButton(onPressed: audioService.clearMessages, icon: Icon(Icons.clear)),
                            ],
                          ),
                        ),
                        Divider(height: 1),
                        Expanded(child: ListView.builder(padding: EdgeInsets.all(8), itemCount: audioService.messages.length, itemBuilder: (context, index) => Text(audioService.messages[index], style: TextStyle(fontSize: 12, fontFamily: 'monospace')))),
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

  Widget _numberInputField(String label, TextEditingController controller, Function(int) onChange, bool disabled) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder()),
      keyboardType: TextInputType.number,
      enabled: !disabled,
      onChanged: (value) => onChange(int.tryParse(value) ?? 1),
    );
  }
}
