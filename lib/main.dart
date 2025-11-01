import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const UmarPsxScanner());
}

class UmarPsxScanner extends StatelessWidget {
  const UmarPsxScanner({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umar PSX Scanner',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
      ),
      home: const PsxHomePage(),
    );
  }
}

class PsxHomePage extends StatefulWidget {
  const PsxHomePage({super.key});

  @override
  State<PsxHomePage> createState() => _PsxHomePageState();
}

class _PsxHomePageState extends State<PsxHomePage> {
  final List<String> stocks = [
    'OGDC', 'HBL', 'ENGRO', 'PSO', 'TRG', 'LUCK', 'EFERT', 'SYS', 'UBL', 'FFC'
  ];

  List<Map<String, dynamic>> scanResults = [];

  void scanStocks() {
    final random = Random();
    scanResults = stocks.map((s) {
      double price = 100 + random.nextDouble() * 100;
      double rsi = random.nextDouble() * 100;
      double volume = 100000 + random.nextDouble() * 900000;
      double trend = random.nextDouble() * 100;

      String signal = (rsi < 30 && trend > 60) ? "BUY" : (rsi > 70 && trend < 40) ? "SELL" : "HOLD";
      double tp = price * (signal == "BUY" ? 1.05 : signal == "SELL" ? 0.95 : 1.0);
      double sl = price * (signal == "BUY" ? 0.97 : signal == "SELL" ? 1.03 : 1.0);

      return {
        'symbol': s,
        'price': price.toStringAsFixed(2),
        'rsi': rsi.toStringAsFixed(1),
        'trend': trend.toStringAsFixed(1),
        'signal': signal,
        'tp': tp.toStringAsFixed(2),
        'sl': sl.toStringAsFixed(2),
      };
    }).toList();

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    scanStocks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Umar PSX Scanner"),
        centerTitle: true,
        backgroundColor: Colors.greenAccent.withOpacity(0.2),
      ),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (context, index) {
          final s = scanResults[index];
          Color sigColor = s['signal'] == "BUY"
              ? Colors.greenAccent
              : s['signal'] == "SELL"
                  ? Colors.redAccent
                  : Colors.grey;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.black54,
            child: ListTile(
              title: Text(
                "${s['symbol']} — ${s['signal']}",
                style: TextStyle(color: sigColor, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "Price: ${s['price']} | RSI: ${s['rsi']} | Trend: ${s['trend']}\nTP: ${s['tp']} | SL: ${s['sl']}",
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        child: const Icon(Icons.refresh, color: Colors.black),
        onPressed: scanStocks,
      ),
    );
  }
}
