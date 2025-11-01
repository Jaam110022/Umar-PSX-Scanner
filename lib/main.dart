// lib/main.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const UmarPsxScannerApp());
}

const proxyBase = 'https://<YOUR-VERCEL-PROJECT>.vercel.app'; // <- REPLACE THIS

class UmarPsxScannerApp extends StatelessWidget {
  const UmarPsxScannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umar PSX Scanner',
      theme: ThemeData.dark(),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Signal {
  final String ticker;
  final String side;
  final double entry, tp, sl, score;
  Signal(this.ticker, this.side, this.entry, this.tp, this.sl, this.score);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> tickers = [];
  bool loading = true;
  String status = '';
  List<Signal> buys = [];
  List<Signal> sells = [];

  @override
  void initState() {
    super.initState();
    _initAndScan();
  }

  Future<void> _initAndScan() async {
    setState(() { loading = true; status = 'Loading tickers...'; });
    try {
      // fetch tickers from proxy
      final r = await http.get(Uri.parse('$proxyBase/api/list')).timeout(const Duration(seconds:10));
      final j = jsonDecode(r.body);
      if (j['ok'] == true && j['tickers'] != null) {
        tickers = List<String>.from(j['tickers']);
      } else {
        // fallback small list
        tickers = ['OGDC','PSO','HBL','UBL','ENGRO','LUCK','TRG','SYS','PPL','MCB'];
      }
    } catch (e) {
      tickers = ['OGDC','PSO','HBL','UBL','ENGRO','LUCK','TRG','SYS','PPL','MCB'];
    }

    await _scanTickers();
  }

  Future<void> _scanTickers() async {
    buys.clear(); sells.clear();
    for (int i=0;i<tickers.length;i++) {
      final t = tickers[i];
      setState(() { status = 'Scanning ${i+1}/${tickers.length}: $t'; });
      try {
        final q = await fetchOHLC(t);
        if (q == null) continue;
        final s = analyzeTicker(t, q);
        if (s != null) {
          if (s.side == 'BUY') buys.add(s); else sells.add(s);
        }
        // polite delay
        await Future.delayed(const Duration(milliseconds:600));
      } catch (_) {}
    }

    buys.sort((a,b)=>b.score.compareTo(a.score));
    sells.sort((a,b)=>b.score.compareTo(a.score));

    setState(() {
      loading = false;
      buys = buys.take(10).toList();
      sells = sells.take(10).toList();
      status = 'Done - Buys:${buys.length} Sells:${sells.length}';
    });
  }

  Future<Map<String,List<double>>?> fetchOHLC(String ticker) async {
    try {
      final r = await http.get(Uri.parse('$proxyBase/api/quote?ticker=$ticker')).timeout(const Duration(seconds:12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      if (j['ok'] != true) return null;
      final close = List<double>.from((j['close'] as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      final high  = List<double>.from((j['high']  as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      final low   = List<double>.from((j['low']   as List).map((e)=> e==null ? double.nan : (e as num).toDouble()));
      // align/filter NAs - keep last 50 valid
      final validIdx = <int>[];
      for (int i=0;i<close.length;i++) if (!close[i].isNaN) validIdx.add(i);
      if (validIdx.length < 30) return null;
      final filteredClose = validIdx.map((i)=>close[i]).toList();
      final filteredHigh  = validIdx.map((i)=>high[i]).toList();
      final filteredLow   = validIdx.map((i)=>low[i]).toList();
      return {'close': filteredClose, 'high': filteredHigh, 'low': filteredLow};
    } catch (e) {
      return null;
    }
  }

  // indicators (same logic explained earlier)
  List<double> ema(List<double> v, int p) {
    if (v.isEmpty) return [];
    final out = List<double>.filled(v.length, 0.0);
    final k = 2/(p+1);
    out[0] = v[0];
    for (int i=1;i<v.length;i++) out[i] = v[i]*k + out[i-1]*(1-k);
    return out;
  }

  List<double> rsi(List<double> v, int p) {
    if (v.length <= p) return [];
    final deltas = <double>[];
    for (int i=1;i<v.length;i++) deltas.add(v[i]-v[i-1]);
    final ups = deltas.map((d)=> d>0?d:0).toList();
    final downs = deltas.map((d)=> d<0?-d:0).toList();
    final au = ema(ups, p);
    final ad = ema(downs, p);
    if (au.isEmpty || ad.isEmpty) return [];
    final len = min(au.length, ad.length);
    final res = <double>[];
    for (int i=0;i<len;i++){
      final rs = ad[i]==0 ? 100.0 : au[i]/ad[i];
      res.add(100 - (100/(1+rs)));
    }
    return res;
  }

  List<double> atr(List<double> high, List<double> low, List<double> close, int p) {
    final trs = <double>[];
    for (int i=1;i<close.length;i++){
      final tr = [
        (high[i]-low[i]).abs(),
        (high[i]-close[i-1]).abs(),
        (low[i]-close[i-1]).abs()
      ].reduce(max);
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

  Signal? analyzeTicker(String ticker, Map<String,List<double>> ohlc) {
    try {
      final close = ohlc['close']!;
      final high = ohlc['high']!;
      final low  = ohlc['low']!;
      if (close.length < 30) return null;
      final ema9 = ema(close,9);
      final ema21 = ema(close,21);
      final rsilist = rsi(close,14);
      final atrlist = atr(high,low,close,10);
      if (ema9.isEmpty || ema21.isEmpty || rsilist.isEmpty || atrlist.isEmpty) return null;
      final last = close.last;
      final ema9v = ema9.last;
      final ema21v = ema21.last;
      final rsiv = rsilist.last;
      final atrv = atrlist.last;

      // Trend strength: relative EMA gap
      final gapPct = ((ema9v - ema21v).abs() / ema21v) * 100;

      // Volume spike proxy: NOT AVAILABLE from Yahoo quote; skip or add later if server returns volume

      // Buy condition
      if (ema9v > ema21v && rsiv > 45 && rsiv < 75 && gapPct > 0.05) {
        final entry = last;
        final tp = entry + 2 * atrv;
        final sl = entry - 1 * atrv;
        final score = gapPct + (rsiv - 50);
        return Signal(ticker,'BUY',entry,tp,sl,score);
      }

      // Sell condition
      if (ema9v < ema21v && rsiv < 55 && rsiv > 25 && gapPct > 0.05) {
        final entry = last;
        final tp = entry - 2 * atrv;
        final sl = entry + 1 * atrv;
        final score = gapPct + (50 - rsiv);
        return Signal(ticker,'SELL',entry,tp,sl,score);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Widget cardFor(Signal s) {
    final color = s.side == 'BUY' ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.symmetric(vertical:6,horizontal:12),
      child: ListTile(
        leading: CircleAvatar(child: Text(s.ticker, style: const TextStyle(fontSize:10))),
        title: Text('${s.ticker} — ${s.side}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        subtitle: Text('Entry: ${s.entry.toStringAsFixed(2)} TP: ${s.tp.toStringAsFixed(2)} SL: ${s.sl.toStringAsFixed(2)}'),
        trailing: Text(s.score.toStringAsFixed(1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Umar PSX Scanner'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _scanTickers)
        ],
      ),
      body: loading ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(), const SizedBox(height:8), Text(status)])) :
      SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height:8),
            const Text('Top Buys', style: TextStyle(fontSize:18,fontWeight: FontWeight.bold)),
            ...buys.map(cardFor),
            const Divider(),
            const Text('Top Sells', style: TextStyle(fontSize:18,fontWeight: FontWeight.bold)),
            ...sells.map(cardFor),
            const SizedBox(height:30),
          ],
        ),
      ),
    );
  }
}
