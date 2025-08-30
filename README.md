# Audio Streaming Flutter App

A Flutter mobile application for real-time audio streaming to a FastAPI WebSocket server.

## Features

- Real-time audio recording and streaming
- WebSocket communication with server
- MP3 chunk processing and storage
- Live activity log
- Connection management
- Permission handling

## Setup

1. **Install Flutter**: Make sure you have Flutter SDK installed
2. **Get dependencies**:
   ```bash
   flutter pub get
   ```

3. **Configure server URL**: 
   - For Android emulator: `ws://10.0.2.2:8000/ws/audio?token=flutter`
   - For real device: `ws://YOUR_SERVER_IP:8000/ws/audio?token=flutter`

## Running the App

### Android Emulator
```bash
flutter run
```

### Real Device
1. Enable USB debugging on your Android device
2. Connect via USB
3. Run: `flutter run`

## Permissions

The app requires the following permissions:
- `RECORD_AUDIO` - For microphone access
- `INTERNET` - For WebSocket communication
- `ACCESS_NETWORK_STATE` - For network status

## Usage

1. **Connect to Server**:
   - Enter the WebSocket URL
   - Tap "Connect"
   - Wait for connection confirmation

2. **Start Recording**:
   - Tap "Start Recording"
   - Grant microphone permission if prompted
   - Audio will be streamed in real-time

3. **Monitor Activity**:
   - View connection status
   - Check chunks sent counter
   - Read activity log for detailed information

## Server Configuration

Make sure your FastAPI server is running and accessible:
- Server should listen on `0.0.0.0:8000`
- WebSocket endpoint: `/ws/audio`
- CORS should be enabled for mobile access

## Troubleshooting

### Connection Issues
- Check server URL format
- Ensure server is running and accessible
- Verify network connectivity

### Recording Issues
- Grant microphone permission
- Check device audio settings
- Ensure app has necessary permissions

### Android Emulator Network
- Use `10.0.2.2` instead of `localhost` for server IP
- Enable internet access in emulator settings

## Development Notes

- Audio is currently simulated with sine wave for testing
- Real audio recording can be implemented using the `record` package
- WebSocket messages are logged for debugging
- Session IDs are automatically generated

## Dependencies

- `record`: Audio recording
- `permission_handler`: Runtime permissions
- `web_socket_channel`: WebSocket communication
- `provider`: State management
- `http`: HTTP requests

