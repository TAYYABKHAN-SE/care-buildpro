import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saved Counter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Saved Counter'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const String _counterKey = 'saved_counter';
  int _counter = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  Future<void> _loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCounter = prefs.getInt(_counterKey) ?? 0;

    if (!mounted) return;
    setState(() {
      _counter = savedCounter;
      _isLoading = false;
    });
  }

  Future<void> _incrementCounter() async {
    final newValue = _counter + 1;
    setState(() {
      _counter = newValue;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_counterKey, newValue);
  }

  Future<void> _resetCounter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_counterKey, 0);

    if (!mounted) return;
    setState(() {
      _counter = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Reset counter',
            onPressed: _isLoading ? null : _resetCounter,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Your saved number is:'),
                  const SizedBox(height: 12),
                  Text(
                    '$_counter',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'This number is saved on this device and should remain '
                      'after you close and reopen the app.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _incrementCounter,
        tooltip: 'Increase and save',
        child: const Icon(Icons.add),
      ),
    );
  }
}
