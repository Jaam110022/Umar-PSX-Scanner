// lib/main.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const UmarPsxScannerApp());
}

// --- CONFIGURE: set your serverless proxy (Vercel) URL here ---
const String proxyBase = 'https://<YOUR-VERCEL-PROJECT>.vercel.app'; // replace

class UmarPsxScannerApp extends StatelessWidget {
  const UmarPsxScannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umar PSX Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F1A),
        cardColor: const Color(0xFF0F1724),
        primaryColor: Colors.greenAccent,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white70)),
      ),
      home: const DashboardPage(),
    );
  }
}

class Signal {
  final String ticker;
  final String side;
  final double entry, tp, sl, score;
  Signal(this.ticker, this.side, this.entry, this.tp, this.sl, this.score);
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loading = true;
  String status = 'Starting...';
  List<Signal> buys = [];
  List<Signal> sells = [];
  List<String> tickers = ['OGDC','PSO','HBL','UBL','ENGRO','LUCK','TRG','SYS','PPL','MCB'];
  // For chart demo
  List<FlSpot> demoSpots = [];

  @override
  void initState() {
    super.initState();
    _initDemoSpots();
    _startScan();
  }

  void _initDemoSpots(){
    demoSpots = List.generate(20, (i) => FlSpot(i.toDouble(), 80 + Random().nextDouble()*40));
  }

  Future<void> _startScan() async {
    setState((){ loading = true; status = 'Scanning tickers...'; buys.clear(); sells.clear(); });
    for (int i=0;i<tickers.length;i++){
      final t = tickers[i];
      setState(() => status = 'Scanning ${i+1}/${tickers.length}: $t');
      try {
        final ohlc = await _fetchOHLC(t);
        final s = _analyze(t, ohlc);
        if (s != null){
          if (s.side == 'BUY') buys.add(s); else sells.add(s);
        }
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    buys.sort((a,b)=>b.score.compareTo(a.score));
    sells.sort((a,b)=>b.score.compareTo(a.score));
    setState((){ loading = false; status = 'Done — Buys:${buys.length} Sells:${sells.length}'; });
  }

  // Fetch via proxy. If proxy not configured or fails, return null and analyzer uses demo.
  Future<Map<String,List<double>>?> _fetchOHLC(String ticker) async {
    try {
      if (proxyBase.contains('<YOUR-VERCEL')) return null; // proxy not configured
      final url = Uri.parse('$proxyBase/api/quote?ticker=$ticker');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body);
      if (j['ok'] != true) return null;
      final close = List<double>.from((j['close'] as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      final high  = List<double>.from((j['high']  as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      final low   = List<double>.from((j['low']   as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      final valid = <int>[];
      for (int k=0;k<close.length;k++) if (!close[k].isNaN) valid.add(k);
      if (valid.length < 30) return null;
      final filteredClose = valid.map((i)=>close[i]).toList();
      final filteredHigh  = valid.map((i)=>high[i]).toList();
      final filteredLow   = valid.map((i)=>low[i]).toList();
      return {'close':filteredClose, 'high':filteredHigh, 'low':filteredLow};
    } catch (e){
      return null;
    }
  }

  // indicators: ema, rsi, atr (same safe logic)
  List<double> _ema(List<double> v, int p){
    if (v.isEmpty) return [];
    final res = List<double>.filled(v.length, 0.0);
    final k = 2/(p+1);
    res[0] = v[0];
    for (int i=1;i<v.length;i++) res[i] = v[i]*k + res[i-1]*(1-k);
    return res;
  }

  List<double> _rsi(List<double> v, int p){
    if (v.length <= p) return [];
    final deltas = <double>[];
    for (int i=1;i<v.length;i++) deltas.add(v[i]-v[i-1]);
    final ups = deltas.map((d)=> d>0?d:0).toList();
    final downs = deltas.map((d)=> d<0?-d:0).toList();
    final au = _ema(ups, p);
    final ad = _ema(downs, p);
    if (au.isEmpty || ad.isEmpty) return [];
    final len = min(au.length, ad.length);
    final out = <double>[];
    for (int i=0;i<len;i++){
      final rs = ad[i]==0 ? 100.0 : au[i]/ad[i];
      out.add(100 - (100/(1+rs)));
    }
    return out;
  }

  List<double> _atr(List<double> high, List<double> low, List<double> close, int p){
    final trs = <double>[];
    for (int i=1;i<close.length;i++){
      final tr = [ (high[i]-low[i]).abs(), (high[i]-close[i-1]).abs(), (low[i]-close[i-1]).abs()].reduce(max);
      trs.add(tr);
    }
    final res = <double>[];
    double sum = 0;
    for (int i=0;i<trs.length;i++){
      sum += trs[i];
      if (i>=p) sum -= trs[i-p];
      res.add(sum / min(i+1, p));
    }
    return res;
  }

  // analyzer returns Signal or null. If ohlc==null use demo random generator
  Signal? _analyze(String ticker, Map<String,List<double>>? ohlc){
    try {
      List<double> close, high, low;
      if (ohlc==null){
        // demo
        close = List.generate(60, (i)=> 100 + sin(i/5)*8 + Random().nextDouble()*4);
        high = close.map((c)=> c + Random().nextDouble()*2).toList();
        low = close.map((c)=> c - Random().nextDouble()*2).toList();
      } else {
        close = ohlc['close']!;
        high = ohlc['high']!;
        low = ohlc['low']!;
      }
      if (close.length < 30) return null;
      final ema9 = _ema(close, 9);
      final ema21 = _ema(close, 21);
      final rsilist = _rsi(close, 14);
      final atrlist = _atr(high, low, close, 10);
      if (ema9.isEmpty || ema21.isEmpty || rsilist.isEmpty || atrlist.isEmpty) return null;
      final last = close.last;
      final e9 = ema9.last, e21 = ema21.last;
      final rsi = rsilist.last, atrv = atrlist.last;
      final gapPct = ((e9 - e21).abs() / e21) * 100;
      // Buy condition
      if (e9 > e21 && rsi > 45 && rsi < 75 && gapPct > 0.03){
        final entry = last;
        final tp = entry + 2*atrv;
        final sl = entry - 1*atrv;
        final score = gapPct + (rsi - 50);
        return Signal(ticker, 'BUY', entry, tp, sl, score);
      }
      // Sell
      if (e9 < e21 && rsi < 55 && rsi > 25 && gapPct > 0.03){
        final entry = last;
        final tp = entry - 2*atrv;
        final sl = entry + 1*atrv;
        final score = gapPct + (50 - rsi);
        return Signal(ticker, 'SELL', entry, tp, sl, score);
      }
      return null;
    } catch (e){
      return null;
    }
  }

  // UI widgets
  Widget _summaryCard(String title, int count, Color color, IconData icon){
    return Card(
      margin: const EdgeInsets.all(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical:12,horizontal:14),
        width: double.infinity,
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width:12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Text('$count', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w800))
            ])
          ],
        ),
      ),
    );
  }

  Widget _miniChart(){
    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show:false),
          titlesData: FlTitlesData(show:false),
          borderData: FlBorderData(show:false),
          lineBarsData: [
            LineChartBarData(
              spots: demoSpots,
              isCurved: true,
              dotData: FlDotData(show:false),
              color: Colors.greenAccent,
              barWidth: 2
            )
          ]
        ),
      ),
    );
  }

  Widget _signalTile(Signal s){
    final color = s.side == 'BUY' ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal:12, vertical:6),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Text(s.ticker, style: const TextStyle(fontSize:11, color: Colors.white))),
        title: Text('${s.ticker} — ${s.side}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        subtitle: Text('Entry: ${s.entry.toStringAsFixed(2)}  TP: ${s.tp.toStringAsFixed(2)}  SL: ${s.sl.toStringAsFixed(2)}'),
        trailing: Text(s.score.toStringAsFixed(1), style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Umar PSX Scanner'),
        actions: [
          IconButton(onPressed: _startScan, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical:10,horizontal:8),
        child: Column(
          children: [
            // summary row
            Row(children: [
              Expanded(child: _summaryCard('Top Buys', buys.length, Colors.greenAccent, Icons.trending_up)),
              Expanded(child: _summaryCard('Top Sells', sells.length, Colors.redAccent, Icons.trending_down)),
            ]),
            const SizedBox(height:8),
            // mini chart + stats
            Card(child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                  Text('Market Snapshot', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('1H', style: TextStyle(color: Colors.white60))
                ]),
                const SizedBox(height:8),
                _miniChart(),
              ]),
            )),
            const SizedBox(height:6),
            // signals list (scroll)
            Expanded(
              child: loading ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(), const SizedBox(height:8), Text(status)])) :
              RefreshIndicator(
                onRefresh: () async { await _startScan(); },
                child: ListView(
                  children: [
                    const SizedBox(height:6),
                    const Padding(padding: EdgeInsets.symmetric(horizontal:12), child: Text('Top Buys', style: TextStyle(fontWeight: FontWeight.bold))),
                    ...buys.map(_signalTile),
                    const Divider(),
                    const Padding(padding: EdgeInsets.symmetric(horizontal:12), child: Text('Top Sells', style: TextStyle(fontWeight: FontWeight.bold))),
                    ...sells.map(_signalTile),
                    const SizedBox(height:20),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
