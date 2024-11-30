import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MQTT LED Control',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MQTTApp(),
    );
  }
}

class MQTTApp extends StatefulWidget {
  @override
  _MQTTAppState createState() => _MQTTAppState();
}

class _MQTTAppState extends State<MQTTApp> {
  mqtt.MqttClient? _mqttClient;
  bool _isLedOn = false;

  @override
  void initState() {
    super.initState();
    _connectToMQTT();
  }

  // Load certificates from the assets
  Future<String> loadAsset(String assetPath) async {
    return await rootBundle.loadString(assetPath);
  }

  Future<void> _connectToMQTT() async {
    final client = mqtt.MqttClient('aehnkcy6nec1e-ats.iot.eu-central-1.amazonaws.com', '');
    client.port = 8883;
    client.secure = true;

    // Load certificates
    final String caCert = await loadAsset('assets/AmazonRootCA1.pem');
    final String cert = await loadAsset('assets/device-cert.pem');
    final String key = await loadAsset('assets/device-private-key.pem');

    // Write certificates to local files
    final directory = await getApplicationDocumentsDirectory();
    final caCertPath = '${directory.path}/AmazonRootCA1.pem';
    final certPath = '${directory.path}/device-cert.pem';
    final keyPath = '${directory.path}/device-private-key.pem';

    await File(caCertPath).writeAsString(caCert);
    await File(certPath).writeAsString(cert);
    await File(keyPath).writeAsString(key);

    // Set the security context for the connection
    final securityContext = SecurityContext.defaultContext;
    securityContext.setTrustedCertificates(caCertPath);
    securityContext.useCertificateChain(certPath);
    securityContext.usePrivateKey(keyPath);

    client.onConnected = onConnected;
    client.onDisconnected = onDisconnected;
    client.onSubscribed = onSubscribed;

    // Set up the connection message with necessary credentials
    final connMessage = mqtt.MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean()
        .withWillTopic('hello')
        .withWillMessage('Connection lost'.codeUnits)
        .withWillQos(mqtt.MqttQos.atLeastOnce);

    client.connectionMessage = connMessage;

    try {
      await client.connect(securityContext);
      print('Connected to MQTT broker');
      _mqttClient = client;

      // Subscribe to the "hello" topic
      _mqttClient?.subscribe('hello', mqtt.MqttQos.atLeastOnce);

      // Listen for incoming messages
      _mqttClient?.updates?.listen((List<mqtt.MqttReceivedMessage> c) {
        final message = c[0].payload as mqtt.MqttPublishMessage;
        final payload = mqtt.MqttPublishPayload.bytesToStringAsString(message.payload.message);
        print('Received message: $payload');
      });

    } catch (e) {
      print('Error connecting to MQTT broker: $e');
    }
  }

  // Handle connection event
  void onConnected() {
    print('Connected to the broker');
  }

  // Handle disconnection event
  void onDisconnected() {
    print('Disconnected from the broker');
  }

  // Handle subscription event
  void onSubscribed(String topic) {
    print('Subscribed to topic: $topic');
  }

  // Send message to the "hello" topic
  Future<void> _sendLedCommand(String command) async {
    if (_mqttClient?.connectionStatus!.state == mqtt.MqttConnectionState.connected) {
      final builder = mqtt.MqttClientPayloadBuilder();
      builder.addString(command);
      _mqttClient?.publishMessage('hello', mqtt.MqttQos.atLeastOnce, builder.payload!);
      print('Sent message: $command');
    }
  }

  // Toggle the LED state
  void _toggleLed() {
    setState(() {
      _isLedOn = !_isLedOn;
    });

    // Send the appropriate command to turn the LED on or off
    _sendLedCommand(_isLedOn ? 'ledon' : 'ledoff');
  }

  @override
  void dispose() {
    _mqttClient?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MQTT LED Control'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _toggleLed,
          child: Text(_isLedOn ? 'Turn LED Off' : 'Turn LED On'),
        ),
      ),
    );
  }
}
