# WLED Audio Sender - Web Deployment Guide

This guide explains how to deploy the WLED Audio Sender web application.

## Building the Web App

1. Build the release version:
```bash
flutter build web --release
```

The built files will be in `build/web/` directory.

## Serving the Web App

### Option 1: Python HTTP Server (Quick Testing)

```bash
cd build/web
python3 -m http.server 8080
```

Then open http://localhost:8080 in your browser.

### Option 2: Node.js HTTP Server

```bash
cd build/web
npx http-server -p 8080
```

Then open http://localhost:8080 in your browser.

### Option 3: Deploy to Web Hosting

Upload the contents of `build/web/` to any static web hosting service:
- GitHub Pages
- Netlify
- Vercel
- Firebase Hosting
- AWS S3 + CloudFront
- etc.

## Browser Requirements

- Modern browsers with Web Audio API support:
  - Chrome 70+
  - Firefox 65+
  - Safari 14+
  - Edge 79+

## HTTPS Requirement

**Important:** Modern browsers require HTTPS (or localhost) to access the microphone. 

If deploying to a server:
- Use a reverse proxy with SSL (nginx, Apache)
- Use a hosting service that provides SSL (most modern services do)
- Use a service like Cloudflare for SSL

## Web Platform Limitations

### UDP Multicast Not Available

Web browsers cannot send UDP multicast packets due to security restrictions. The web version handles this by:

1. **Default Behavior**: Audio capture and visualization work, but UDP packets are not sent
2. **WebSocket Relay Option** (Advanced): Set up a WebSocket server that relays to UDP

### Setting up WebSocket Relay (Optional)

If you need actual UDP transmission from the web app:

1. Set up a WebSocket relay server that receives messages and forwards them as UDP
2. Build the web app with the relay URL:
```bash
flutter build web --dart-define=WS_RELAY_URL=wss://your-relay-server.com/wled
```

Example relay server concept (Node.js):
```javascript
const WebSocket = require('ws');
const dgram = require('dgram');

const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', (ws) => {
  const udpSocket = dgram.createSocket('udp4');
  
  ws.on('message', (message) => {
    const payload = JSON.parse(message);
    const buffer = Buffer.from(payload.data);
    udpSocket.send(buffer, payload.port, payload.address);
  });
  
  ws.on('close', () => {
    udpSocket.close();
  });
});
```

## Granting Microphone Permissions

When you first open the web app:
1. Click the microphone button to start recording
2. Your browser will prompt for microphone access
3. Click "Allow" to grant permission

If you accidentally deny permission:
- Chrome: Click the lock icon in the address bar → Site settings → Microphone
- Firefox: Click the lock icon → Clear permissions
- Safari: Safari menu → Settings → Websites → Microphone

## Testing Locally

```bash
# Run in Chrome
flutter run -d chrome

# Run in Chrome with release mode
flutter run -d chrome --release
```

## Troubleshooting

### Microphone Not Working
- Check browser console for errors
- Ensure HTTPS or localhost is being used
- Verify microphone permissions are granted
- Check that no other app is using the microphone

### App Not Loading
- Check browser console for errors
- Ensure all files from `build/web/` are served
- Verify MIME types are correct (server configuration)

### Performance Issues
- Use release build (`flutter build web --release`)
- Enable tree shaking (enabled by default in release mode)
- Consider using `--web-renderer html` or `--web-renderer canvaskit` based on your needs
