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
        title: 'Velocímetro ESP32',
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.blue,
        ),
        home: const SpeedometerScreen(),
      ),
    );
  }
}


class MyAppState extends ChangeNotifier {
  var stateMsg = "Bluetooth no está disponible en este dispositivo";

  void changeBluetoothStateMsg(String msg){
    stateMsg = msg;
  }
}

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});// Definir los UUIDs del servicio y cracterísticas. Deben coincidir con los del microcontrolador.
  final String SERVICE_UUID = "dc9a0000-bebf-4d11-8235-01878bbec7fe";
  final String WRITE_CHARACTERISTIC_UUID = "dc9a0100-bebf-4d11-8235-01878bbec7fe";
  final String SPEED_CHARACTERISTIC_UUID = "dc9a0200-bebf-4d11-8235-01878bbec7fe";
  final String AVG_SPEED_UUID ="dc9a0201-bebf-4d11-8235-01878bbec7fe";
  final String TOTAL_DISTANCE_UUID ="dc9a0202-bebf-4d11-8235-01878bbec7fe";
  final String TEMPERATURE_UUID ="dc9a0203-bebf-4d11-8235-01878bbec7fe";

  @override
  _SpeedometerScreenState createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  // Variables relacionadas con Bluetooth
  BluetoothDevice? connectedDevice;
  List<ScanResult> scanResults = [];
  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<BluetoothConnectionState>? deviceStateSubscription;
  BluetoothCharacteristic? writeCharacteristic;
  StreamSubscription<List<int>>? characteristicSubscription;
  StreamSubscription<List<int>>? avgSpeedSubscription;
  StreamSubscription<List<int>>? distanceSubscription;
  StreamSubscription<List<int>>? temperatureSubscription;

  double wheelDiameter = 50.0; // Diámetro de rueda en centímetros
  double currentSpeed = 0.0; // Velocidad actual en km/h
  double avgSpeed = 0.0; // Velocidad media en km/h
  double totalDistance = 0.0; // Distancia total recorrida en km/h
  double currentTemp = 0.0; // Temperatura actual en Celsius
  Stopwatch chrono = Stopwatch(); // Cronómetro

  bool isConnecting = false;
  bool isScanning = false;
  bool isTraining = false;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Velocímetro ESP32'),
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

  // Construye la Card que contiene la información del dispositivo conectado, o de su escaneo.
  Card buildConnectBox() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: connectedDevice != null
            ? ListTile(
          title: Text(
            'Conectado a: ${connectedDevice!.platformName}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dispositivos disponibles:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            isConnecting? const Center(child: CircularProgressIndicator())
                : scanResults.isEmpty? const Text('No se encontró dispositivos')
                : ListView.builder(
              shrinkWrap: true,
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                ScanResult result = scanResults[index];
                return ListTile(
                  title: Text(result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : 'Dispositivo desconocido'),
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
                label: Text(isScanning ? 'Escaneando...' : 'Escanear'),
                onPressed: isScanning ? null : startScan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Construye el elemento Expanded que contiene las tarjetas de mediciones y el botón de entrenamiento
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

          //Botón de entrenamiento
          ElevatedButton(
            onPressed: () {
              toggleTraining();
            },
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
        ])

    );
  }

  // Una función para construir una Card de medidas, como la de velocidad.
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

  // Activa o desactiva el modo de entrenamiento, incluido el cambio de estado que conlleva.
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
    // Inicializa el adaptador de BLE, que empieza a escanear
    initBleAdapter();
  }

  @override
  void dispose() {
    // Limpiar todas las suscripciones
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
          title: const Text('Ajustes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              const Text('Diámetro de rueda (centímetros):'),
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
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  double newDiameter = double.parse(auxDiameter);
                  setState(() {
                    wheelDiameter = newDiameter;
                  });
                } catch (e) {
                  showStatusAlert(context, "Error leyendo diámetro: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Valor de diámetro no válido")),
                  );
                }
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }


  /// /// /// /// /// /// /// /// /// /// ///
  ///           MÉTODOS BLUETOOTH         ///
  /// /// /// /// /// /// /// /// /// /// ///
  // Función para inicializar el adaptador de Bluetooth LE
  Future<void> initBleAdapter() async {
    try {
      // Comprobar si Bluetooth está disponible
      if (await FlutterBluePlus.isSupported == false) {
        showStatusAlert(context, "Bluetooth no está disponible en este dispositivo");
        return;
      }

      // Comprobar si Bluetooth está encendido
      if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
        showStatusAlert(context, "Bluetooth está apagado");
        // En Android, podemos pedir al usuario que encienda Bluetooth
        await FlutterBluePlus.turnOn();
      }

      // Ahora que hemos comprobado que Bluetooth está encendido, podemos emepzar a escanear
      startScan();
    } catch (e) {
      showStatusAlert(context, "Error inicializando Bluetooth: $e");
    }
  }

  // Función para escanear dispositivos Bluetooth
  void startScan() async {
    if (isScanning) return;

    setState(() {
      scanResults = [];
      isScanning = true;
    });

    // Cancelar suscripciones existentes para empezar un nuevo escaneo
    scanSubscription?.cancel();

    try {
      scanSubscription = FlutterBluePlus.scanResults.listen(
              (results) {
            setState(() {
              scanResults = results;
            });
          },
          onError: (e) {
            showStatusAlert(context, "Error de escaneo: $e");
            setState(() {
              isScanning = false;
            });
          }
      );

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      // Tras el timeout del escaneo actualizamos el estado de la aplicación
      setState(() {
        isScanning = false;
      });
    } catch (e) {
      showStatusAlert(context, "Error empezando el escaneo: $e");
      setState(() {
        isScanning = false;
      });
    }
  }

  // Función para conectar con un dispositivo
  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
    });

    // Dejar de escanear
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      showStatusAlert(context, "Error parando el escaneo: $e");
    }

    try {
      // Conectar con el dispositivo
      await device.connect();

      // Configurar el estado de la suscripción del dispositivo
      deviceStateSubscription = device.connectionState.listen(
              (state) {
            if (state == BluetoothConnectionState.disconnected) {
              setState(() {
                connectedDevice = null;
                currentSpeed = 0.0;
                isConnecting = false;
              });
              startScan(); // Volver a empezar a escanear dispositivos
            }
          },
          onError: (e) {
            showStatusAlert(context, "Error de estado de conexión: $e");
            setState(() {
              isConnecting = false;
            });
            startScan();
          }
      );

      List<BluetoothService> services = await device.discoverServices();
      bool foundWrite = false;
      bool foundNotify = false;

      // Comprobar los servicios Bluetooth para encontrar los servicios y características que buscamos
      for (BluetoothService service in services) {
        // Comprobar si este es el servicio que buscamos
        if (service.uuid.toString() == widget.SERVICE_UUID) {
          // Encontrar cada característica utilizada
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            // Comprobar si esta es la carcaterística de escritura
            if (characteristic.uuid.toString() == widget.WRITE_CHARACTERISTIC_UUID) {
              writeCharacteristic = characteristic;
              foundWrite = true;
            }

            // Comprobar si esta es la carcaterística de velocidad
            if (characteristic.uuid.toString() == widget.SPEED_CHARACTERISTIC_UUID) {
              foundNotify = true;
              // Activar las notificaciones
              await characteristic.setNotifyValue(true);

              // Empezar a escuchar las notificaciones de velocidad
              characteristicSubscription = characteristic.onValueReceived.listen((value) {
                    if (value.isNotEmpty) {
                      // Diseccionar los datos recibidos de la ESP32
                      try {
                        final speedString = String.fromCharCodes(value);
                        final speedValue = double.parse(speedString);
                        setState(() {
                          currentSpeed = speedValue;
                        });
                      } catch (e) {
                        showStatusAlert(context, "Error leyendo datos de velocidad: $e");
                      }
                    }
                  },
                  onError: (e) {
                    showStatusAlert(context, "Error de Característica de notificación: $e");
                  }
              );
            }

            // Comprobar si esta es la carcaterística de velocidad media
            if (characteristic.uuid.toString() == widget.AVG_SPEED_UUID) {
              await characteristic.setNotifyValue(true);

              characteristicSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  try {
                    final avgspeedString = String.fromCharCodes(value);
                    final avgspeedValue = double.parse(avgspeedString);
                    setState(() {
                      avgSpeed = avgspeedValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error leyendo datos de velocidad media: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Error de Característica de notificación: $e");
                  }
              );
            }

            // Comprobar si esta es la carcaterística de distancia total
            if (characteristic.uuid.toString() == widget.TOTAL_DISTANCE_UUID) {
              await characteristic.setNotifyValue(true);

              distanceSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  try {
                    final distanceString = String.fromCharCodes(value);
                    final distanceValue = double.parse(distanceString);
                    setState(() {
                      totalDistance = distanceValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error leyendo datos de distancia: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Error de Característica de notificación: $e");
                  }
              );
            }

            // Comprobar si esta es la característica de temperatura
            if (characteristic.uuid.toString() == widget.TEMPERATURE_UUID) {
              await characteristic.setNotifyValue(true);

              temperatureSubscription = characteristic.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  try {
                    final tempString = String.fromCharCodes(value);
                    final tempValue = double.parse(tempString);
                    setState(() {
                      currentTemp = tempValue;
                    });
                  } catch (e) {
                    showStatusAlert(context, "Error leyendo datos de temperatura: $e");
                  }
                }
              },
                  onError: (e) {
                    showStatusAlert(context, "Error de Característica de notificación: $e");
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
      showStatusAlert(context, 'Error conectando al dispositivo: $e');
      setState(() {
        isConnecting = false;
      });
      startScan(); // Volver a empezar a escanear dispositivos
    }
  }

  // Desconectar del dispositivo
  Future<void> disconnectFromDevice() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        showStatusAlert(context, "Error en la desconexión: $e");
      }

      setState(() {
        connectedDevice = null;
        currentSpeed = 0.0;
      });

      startScan(); // Volver a empezar a escanear dispositivos
    }
  }

}
