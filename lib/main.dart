import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';

import 'package:status_alert/status_alert.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'ESP32 Speedometer',
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.blue,
        ),
        home: const SpeedometerScreen(),
      ),
    );
  }
}


//TODO: Ver si ponemos algo más en esta clase. Probablemente las suscripciones y conexiones.
class MyAppState extends ChangeNotifier {
  var stateMsg = "Bluetooth is not available on this device";

  void changeBluetoothStateMsg(String msg){
    stateMsg = msg;
  }
}

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({Key? key}) : super(key: key);

  @override
  _SpeedometerScreenState createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  // Bluetooth related variables
  BluetoothDevice? connectedDevice;
  List<ScanResult> scanResults = [];
  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<BluetoothConnectionState>? deviceStateSubscription;
  BluetoothCharacteristic? writeCharacteristic;
  StreamSubscription<List<int>>? characteristicSubscription;
  //StreamSubscription<List<int>>? timeSubscription;
  StreamSubscription<List<int>>? avgSpeedSubscription;
  StreamSubscription<List<int>>? distanceSubscription;
  StreamSubscription<List<int>>? temperatureSubscription;

  // App state variables
  final int DISCONNECTED_STATE = 0;
  final int NOT_TRAINING_STATE = 1;
  final int TRAINING_STATE = 2;
  double wheelDiameter = 50.0; // Diámetro de rueda en centímetros
  double currentSpeed = 0.0; // Velocidad actual en km/h
  double avgSpeed = 0.0; // Velocidad media en km/h
  double totalDistance = 0.0; // Distancia total recorrida en km/h
  double currentTemp = 0.0; // Temperatura actual en Celsius
  Stopwatch chrono = Stopwatch(); // Cronómetro

  bool isConnecting = false;
  bool isScanning = false;
  bool isTraining = false;

  // Define UUIDs for the service and characteristics
  // Posible nueva: dc9a393d-bebf-4d11-8235-01878bbec7fe
  final String SERVICE_UUID        = "4fafc201-0000-459e-8fcc-c5c9c331914b";
  final String WRITE_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String NOTIFY_CHARACTERISTIC_UUID = "cba1d466-344c-4be3-ab3f-189f80d751a2";
  final String AVG_SPEED_UUID="4fafc201-0001-459e-8fcc-c5c9c331914b";
  final String TOTAL_DISTANCE_UUID="4fafc201-0002-459e-8fcc-c5c9c331914b";
  final String TEMPERATURE_UUID="4fafc201-0003-459e-8fcc-c5c9c331914b";
  final String TOTAL_TIME_UUID="4fafc201-0004-459e-8fcc-c5c9c331914b";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Speedometer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: openSettingsDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // CONNECT_BOX
            buildConnectBox(),
            const SizedBox(height: 16.0),
            // MEASURE_BOX
            buildMeasureBox(),
          ],
        ),
      ),
    );
  }

  Card buildConnectBox() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: connectedDevice != null
            ? ListTile(
          title: Text(
            'Connected to: ${connectedDevice!.platformName}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Devices:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            isConnecting? const Center(child: CircularProgressIndicator())
                : scanResults.isEmpty? const Text('No devices found')
                : ListView.builder(
              shrinkWrap: true,
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                ScanResult result = scanResults[index];
                return ListTile(
                  title: Text(result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : 'Unknown Device'),
                  subtitle: Text(result.device.remoteId.toString()),
                  onTap: () => connectToDevice(result.device),
                );
              },
            ),
            const SizedBox(height: 8.0),
            Center(
              child: ElevatedButton.icon(
                icon: isScanning
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.refresh),
                label: Text(isScanning ? 'Scanning...' : 'Scan'),
                onPressed: isScanning ? null : startScan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Expanded buildMeasureBox() {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Caja de Velocidad
          Expanded(
            child:buildMeasurementCard("Velocidad", currentSpeed.toStringAsFixed(1), 'km/h', isTraining, true),
          ),


          // Cajas de medidas adicionales
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
            TableRow(
              children: [
                buildMeasurementCard("Veloc. media", avgSpeed.toStringAsFixed(1), 'km/h', isTraining, false),
                buildMeasurementCard("Distancia total", totalDistance.toStringAsFixed(1), 'km', isTraining, false),
              ],
            ),

            TableRow(
              children: [
                buildMeasurementCard("Temperatura", currentTemp.toStringAsFixed(1), 'ºC', (connectedDevice!=null), false),
                buildMeasurementCard("Tiempo entren.", chrono.elapsed.toString().substring(0,7), 'h', isTraining, false),
              ],
            )],
          ),

          //TODO: Botón de entrenamiento
          //Button
          // icon: isTraining ? icon.pause : icon.start
          // (ver el título del icono, y ver para poner la caja en gris cuando no esté conectado)
          // onPressed: (método. pedir confirmación para parar o iniciar?)
          ElevatedButton(
            onPressed: () {
              toggleTraining();
            },
            //TODO: Ver si hay que modificar el estilo
            style: ElevatedButton.styleFrom(
                backgroundColor:isTraining? Colors.redAccent:  connectedDevice==null? Colors.grey[400]: Colors.green[200],
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold)),
            child: Column(
              children:[
                isTraining? const Icon(Icons.stop): const Icon(Icons.play_arrow),
                isTraining? const Text('Terminar entrenamiento'): const Text('Empezar entrenamiento'),
              ]
            ),
          ),

          // TODO: Botón extra para reiniciar?? o que no se pause y en vez de eso se reinicie?
        ])

    );
  }

  // Un método para construir una Card de medidas, como la de velocidad.
  // Si está conectado, saldrá azul. Si no, saldrá gris.
  Card buildMeasurementCard(String measureName, String measureValue, String measureUnits, bool isActive, bool bigFont) {
    return Card(
            color: isActive ? Colors.blue : Colors.grey[300],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        measureValue,
                        style: TextStyle(
                          fontSize: bigFont? 72.0 : 40.0,
                          fontWeight: bigFont? FontWeight.bold: FontWeight.normal,
                          color: isActive ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width:10),
                      Text(
                        measureUnits,
                        style: TextStyle(
                          fontSize: bigFont? 24.0: 18.0,
                          color: isActive ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      ]),

                  const SizedBox(width:10),

                  Text(
                    measureName,
                    style: TextStyle(
                      fontSize: bigFont? 24.0: 18.0,
                      color: isActive ? Colors.white : Colors.grey[600],
                    ),
                  )
                ],
              ),
            ),
          );
  }

  // TODO: Hacer una función real
  Future<void> toggleTraining() async {
    if (connectedDevice != null && writeCharacteristic != null) {
      try {
        if(isTraining){
          // Para parar mandamos STOP y que haga una comprobación en el código. Si es STOP para, si es un valor empieza.
          List<int> bytes = utf8.encode("STOP");
          await writeCharacteristic!.write(bytes);

          setState(() {
            isTraining = false;
          });
          chrono.stop();
        }
        else {
          List<int> bytes = utf8.encode(wheelDiameter.toString());
          await writeCharacteristic!.write(bytes);

          setState(() {
            isTraining = true;
          });
          chrono.start();
        }
      } catch (e) {
        showStatusAlert(context, 'Error mandando señal al microcontrolador: $e');
      }
    }


  }


  @override
  void initState() {
    super.initState();
    // Initialize the Bluetooth adapter and start scanning
    initBleAdapter();
  }

  @override
  void dispose() {
    // Clean up all subscriptions
    scanSubscription?.cancel();
    deviceStateSubscription?.cancel();
    characteristicSubscription?.cancel();
    super.dispose();
  }

  void showStatusAlert(BuildContext context, String msg) {
    StatusAlert.show(
      context,
      duration: const Duration(seconds: 2),
      subtitle: msg,
    );
  }

  // Abrir diálogo de configuraciones. Por ahora solo se configura el diámetro.
  void openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String auxDiameter = wheelDiameter.toString();
        return AlertDialog(
          title: const Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              const Text('Wheel Diameter (centimeters):'),
              TextFormField(
                initialValue: wheelDiameter.toString(),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    auxDiameter = value;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  double newDiameter = double.parse(auxDiameter);
                  setState(() {
                    wheelDiameter = newDiameter;
                  });
                } catch (e) {
                  showStatusAlert(context, "Error parsing diameter: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid diameter value")),
                  );
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  /// /// /// /// /// /// /// /// /// /// ///
  ///           MÉTODOS BLUETOOTH         ///
  /// /// /// /// /// /// /// /// /// /// ///
  // Initialize the Bluetooth adapter
  Future<void> initBleAdapter() async {
    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        showStatusAlert(context, "Bluetooth is not available on this device");
        return;
      }

      // Check if Bluetooth is turned on
      if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
        showStatusAlert(context, "Bluetooth is turned off");
        // On Android, we can ask the user to turn on Bluetooth
        await FlutterBluePlus.turnOn();
      }

      // Now we can start scanning
      startScan();
    } catch (e) {
      showStatusAlert(context, "Error initializing Bluetooth: $e");
    }
  }

  // Start scanning for Bluetooth devices
  void startScan() async {
    if (isScanning) return;

    setState(() {
      scanResults = [];
      isScanning = true;
    });

    // Cancel any existing subscriptions
    scanSubscription?.cancel();

    try {
      // Start scanning
      scanSubscription = FlutterBluePlus.scanResults.listen(
              (results) {
            setState(() {
              scanResults = results;
            });
          },
          onError: (e) {
            showStatusAlert(context, "Scan error: $e");
            setState(() {
              isScanning = false;
            });
          }
      );

      // Start the scan
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      // After the scan timeout, update the state
      setState(() {
        isScanning = false;
      });
    } catch (e) {
      showStatusAlert(context, "Error starting scan: $e");
      setState(() {
        isScanning = false;
      });
    }
  }

  // Connect to a device
  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
    });

    // Stop scanning
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      showStatusAlert(context, "Error stopping scan: $e");
    }

    try {
      // Connect to the device
      await device.connect();

      // Set up device state subscription
      deviceStateSubscription = device.connectionState.listen(
              (state) {
            if (state == BluetoothConnectionState.disconnected) {
              // Device disconnected
              setState(() {
                connectedDevice = null;
                currentSpeed = 0.0;
                isConnecting = false;
              });
              startScan(); // Restart scanning for devices
            }
          },
          onError: (e) {
            showStatusAlert(context, "Connection state error: $e");
            setState(() {
              isConnecting = false;
            });
            startScan();
          }
      );

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      bool foundWrite = false;
      bool foundNotify = false;

      // Find the appropriate service and characteristics
      for (BluetoothService service in services) {
        // Check if this is the service we're looking for
        if (service.uuid.toString() == SERVICE_UUID) {
          // Find the write characteristic
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            // Check if this is the write characteristic
            if (characteristic.uuid.toString() == WRITE_CHARACTERISTIC_UUID) {
              writeCharacteristic = characteristic;
              foundWrite = true;
            }

            // Check if this is the notify characteristic
            if (characteristic.uuid.toString() == NOTIFY_CHARACTERISTIC_UUID) {
              foundNotify = true;
              // Set up notification
              await characteristic.setNotifyValue(true);

              // Listen for notifications (speed data)
              characteristicSubscription = characteristic.onValueReceived.listen((value) {
                    if (value.isNotEmpty) {
                      // Parse the speed data from the ESP32
                      try {
                        final speedString = String.fromCharCodes(value);
                        final speedValue = double.parse(speedString);
                        setState(() {
                          currentSpeed = speedValue;
                        });
                      } catch (e) {
                        showStatusAlert(context, "Error parsing speed data: $e");
                      }
                    }
                  },
                  onError: (e) {
                    showStatusAlert(context, "Characteristic notification error: $e");
                  }
              );
            }

            // Check if this is the notify characteristic
            if (characteristic.uuid.toString() == AVG_SPEED_UUID) {
              // Set up notification
              await characteristic.setNotifyValue(true);

              // Listen for notifications (speed data)
              characteristicSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  // Parse the speed data from the ESP32
                  try {
                    final avgspeedString = String.fromCharCodes(value);
                    final avgspeedValue = double.parse(avgspeedString);
                    setState(() {
                      avgSpeed = avgspeedValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error parsing speed data: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Characteristic notification error: $e");
                  }
              );
            }

            // Check if this is the notify characteristic
            if (characteristic.uuid.toString() == TOTAL_DISTANCE_UUID) {
              // Set up notification
              await characteristic.setNotifyValue(true);

              // Listen for notifications (speed data)
              distanceSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  // Parse the speed data from the ESP32
                  try {
                    final distanceString = String.fromCharCodes(value);
                    final distanceValue = double.parse(distanceString);
                    setState(() {
                      totalDistance = distanceValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error parsing distance data: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Characteristic notification error: $e");
                  }
              );
            }

            // Check if this is the temperature characteristic
            if (characteristic.uuid.toString() == TEMPERATURE_UUID) {
              // Set up notification
              await characteristic.setNotifyValue(true);

              // Listen for notifications (speed data)
              temperatureSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  // Parse the speed data from the ESP32
                  try {
                    final tempString = String.fromCharCodes(value);
                    final tempValue = double.parse(tempString);
                    setState(() {
                      currentTemp = tempValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error parsing temperature data: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Characteristic notification error: $e");
                  }
              );
            }

            }
        }
      }

      if (!foundWrite) showStatusAlert(context, 'Error: Write Characteristic UUID not found.');
      if (!foundNotify) showStatusAlert(context, 'Error: Notify Characteristic UUID not found.');

      setState(() {
        connectedDevice = device;
        isConnecting = false;
      });

    } catch (e) {
      showStatusAlert(context, 'Error connecting to device: $e');
      setState(() {
        isConnecting = false;
      });
      startScan(); // Restart scanning for devices
    }
  }

  //TODO: DEPRECATED
  // Send wheel diameter to ESP32
  Future<void> sendWheelDiameter() async {
    if (connectedDevice != null && writeCharacteristic != null) {
      try {
        // Convert wheel diameter to bytes and send
        List<int> bytes = utf8.encode(wheelDiameter.toString());
        await writeCharacteristic!.write(bytes);
      } catch (e) {
        showStatusAlert(context, 'Error sending wheel diameter: $e');
      }
    }
  }

  // Disconnect from device
  Future<void> disconnectFromDevice() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        showStatusAlert(context, "Error disconnecting: $e");
      }

      setState(() {
        connectedDevice = null;
        currentSpeed = 0.0;
      });

      startScan(); // Restart scanning for devices
    }
  }

}
