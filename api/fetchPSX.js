// api/fetchPSX.js
// Vercel / serverless handler. Simple proxy + in-memory cache.
// Deploy to Vercel (Project -> Add -> Import Git Repository) OR any Node server.
// Endpoints:
//  - GET /api/list             -> returns built-in tickers list (JSON)
//  - GET /api/quote?ticker=OGDC -> returns OHLC & latest quote (from Yahoo) cached

const TICKERS = [
  // minimal example; you can replace with full list later or keep server-side CSV
  "OGDC","PSO","HBL","UBL","ENGRO","LUCK","TRG","SYS","PPL","MCB",
  "NML","PRL","MARI","KEL","KAPCO","PTC","SEARL","SHEL","SNGP","SNGPL"
];

const CACHE_TTL = 30 * 1000; // 30s cache

const cache = new Map(); // key -> {ts, data}

function setCache(key, data) {
  cache.set(key, { ts: Date.now(), data });
}
function getCache(key) {
  const v = cache.get(key);
  if (!v) return null;
  if (Date.now() - v.ts > CACHE_TTL) {
    cache.delete(key);
    return null;
  }
  return v.data;
}

module.exports = async (req, res) => {
  try {
    const url = new URL(req.url, `https://${req.headers.host}`);
    const pathname = url.pathname || req.url;

    // Allow CORS for your Flutter Web during testing
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.statusCode = 204;
      return res.end();
    }

    if (pathname.endsWith('/api/list')) {
      return res.json({ ok: true, tickers: TICKERS });
    }

    if (pathname.endsWith('/api/quote')) {
      const ticker = url.searchParams.get('ticker') || '';
      if (!ticker) return res.status(400).json({ ok: false, error: 'ticker required' });

      const cacheKey = `quote:${ticker.toUpperCase()}`;
      const cached = getCache(cacheKey);
      if (cached) return res.json({ ok: true, source: 'cache', ...cached });

      // Fetch 60m data from Yahoo Finance v8 chart API
      // Note: For PSX tickers you may need to try symbol variants; try with .KS or no suffix
      const symbolCandidates = [ticker, `${ticker}.KS`, `${ticker}.PAK`, `${ticker}.PK`];
      let body = null;
      for (const s of symbolCandidates) {
        try {
          const period2 = Math.floor(Date.now() / 1000);
          const period1 = period2 - (10 * 24 * 3600); // 10 days
          const qurl = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(s)}?period1=${period1}&period2=${period2}&interval=60m`;
          const r = await fetch(qurl, { method: 'GET' });
          if (!r.ok) continue;
          const j = await r.json();
          if (j?.chart?.result && j.chart.result.length > 0) {
            body = j.chart.result[0];
            break;
          }
        } catch (e) {
          // try next candidate
        }
      }

      if (!body) {
        return res.status(502).json({ ok: false, error: 'no-data', ticker });
      }

      // parse indicator arrays
      const quote = (body.indicators && body.indicators.quote && body.indicators.quote[0]) || {};
      const timestamps = body.timestamp || [];
      const close = (quote.close || []).map(v => v === null ? null : Number(v));
      const high = (quote.high || []).map(v => v === null ? null : Number(v));
      const low = (quote.low || []).map(v => v === null ? null : Number(v));
      const open = (quote.open || []).map(v => v === null ? null : Number(v));
      const result = { ticker: ticker.toUpperCase(), timestamps, open, high, low, close };

      setCache(cacheKey, result);
      return res.json({ ok: true, source: 'yahoo', ...result });
    }

    // default
    return res.status(404).json({ ok: false, error: 'unknown endpoint' });
  } catch (err) {
    console.error(err);
    res.statusCode = 500;
    return res.json({ ok: false, error: err.message || 'server error' });
  }
};
