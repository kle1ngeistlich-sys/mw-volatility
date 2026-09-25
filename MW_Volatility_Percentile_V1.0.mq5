//+------------------------------------------------------------------+
//|                            MW_Volatility_Percentile_V1.0.mq5     |
//|                                  Copyright 2026 P. Paarsch       |
//|                              https://t.me/Liquidity_Laboratory   |
//|                                                                  |
//| One volatility line per symbol of the Market Watch (max. 10),    |
//| drawn in its own indicator window.                               |
//|                                                                  |
//| Symbol source: ONLY the symbols the user selected in the Market  |
//| Watch - SymbolsTotal(true) / SymbolName(i, true). The indicator  |
//| never calls SymbolSelect() and never reads the full broker list, |
//| so the Market Watch stays exactly as the user left it.           |
//|                                                                  |
//| Two builds from one source, switched by one define:              |
//|  VOL_PERCENTILE defined = ATR percentile rank 0..100             |
//|  VOL_PERCENTILE absent  = ATR in percent of the close price       |
//+------------------------------------------------------------------+
#define VOL_PERCENTILE                  // remove for the ATR% build

#property copyright   "Copyright 2026 P. Paarsch"
#property link        "https://t.me/Liquidity_Laboratory"
#property version     "1.00"
#property description "Volatility of every Market Watch symbol in one window (max. 10 lines)."
#property description "Reads only the symbols you selected - the Market Watch is never changed."
#property description "t.me/Liquidity_Laboratory"
#property indicator_separate_window
#property indicator_buffers 10
#property indicator_plots   10

#ifdef VOL_PERCENTILE
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_level1  20
#property indicator_level2  80
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#endif

//--- default palette, blue first; changeable per slot in the Colors tab
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDarkOrange
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMagenta
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrForestGreen
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrGoldenrod
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrDarkTurquoise
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrBlueViolet
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrSienna
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrGray

//+------------------------------------------------------------------+
//| LICENSE - blank by default. 0 = unbound, far date = no expiry.   |
//+------------------------------------------------------------------+
#define LIC_ACCOUNT   0                 // 0 = unbound
#define LIC_ACCOUNT2  0                 // 0 = unused
#define LIC_EXPIRY    D'2099.12.31'     // last valid day

#ifdef VOL_PERCENTILE
#define IND_NAME   "MW Volatility Percentile"
#define OBJ_FAMILY "MWVP_"
#else
#define IND_NAME   "MW Volatility ATR%"
#define OBJ_FAMILY "MWVA_"
#endif
#define IND_VER    "1.0"
#define MAX_SLOTS  10
#define MW_SCAN_SEC 5                   // Market Watch re-scan interval
#define MAX_SRC_BARS 50000              // cap of source bars per symbol (low TF on high chart TF)

//==================================================================
//  INPUTS
//==================================================================
input group "Calculation"
input ENUM_TIMEFRAMES InpTF       = PERIOD_CURRENT; // Timeframe (Current = chart)
input int             InpATRPeriod = 14;            // ATR period
#ifdef VOL_PERCENTILE
input int             InpLookback  = 100;           // Percentile lookback (bars)
input double          InpLevelLow  = 20;            // Lower level
input double          InpLevelHigh = 80;            // Upper level
#endif
input int             InpMaxBars   = 1000;          // Max bars to calculate (0 = all)

input group "Display"
input bool             InpHighlightChart = true;              // Highlight chart symbol (thick line)
input int              InpLineWidth      = 1;                 // Line width
input int              InpHighlightWidth = 3;                 // Line width of chart symbol
input ENUM_BASE_CORNER InpLegendCorner   = CORNER_LEFT_UPPER; // Legend corner
input int              InpLegendFont     = 9;                 // Legend font size
input bool             InpShowBranding   = true;              // Show branding

//==================================================================
//  GLOBALS
//==================================================================
double B0[], B1[], B2[], B3[], B4[], B5[], B6[], B7[], B8[], B9[];

string          g_pfx;                  // object prefix of this instance
ENUM_TIMEFRAMES g_tf;                   // calculation timeframe
int             g_warm;                 // source bars needed before the first value
string          g_sym[MAX_SLOTS];       // symbol per slot ("" = unused)
bool            g_ready[MAX_SLOTS];     // slot fully calculated
double          g_cur[MAX_SLOTS];       // value at the last chart bar
int             g_used    = 0;          // occupied slots
int             g_skipped = 0;          // Market Watch symbols beyond MAX_SLOTS
string          g_mwKey   = "";         // joined symbol list of the last scan
datetime        g_t[];                  // chart bar times (non-series)
int             g_rates   = 0;          // rates_total of the last OnCalculate
int             g_drawFrom = 0;         // first chart bar that gets values
ulong           g_lastScan = 0;         // GetTickCount64 of the last scan

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- license
   long acc = AccountInfoInteger(ACCOUNT_LOGIN);
   if((LIC_ACCOUNT != 0 || LIC_ACCOUNT2 != 0) &&
      acc != (long)LIC_ACCOUNT && acc != (long)LIC_ACCOUNT2)
     {
      string m = StringFormat("%s: this build is not licensed for account %I64d.", IND_NAME, acc);
      Print(m); Alert(m);
      return(INIT_FAILED);
     }
   datetime now = (TimeCurrent() > TimeGMT()) ? TimeCurrent() : TimeGMT();
   if(now > LIC_EXPIRY + 86399)
     {
      string m = StringFormat("%s: this version expired on %s.", IND_NAME,
                              TimeToString(LIC_EXPIRY, TIME_DATE));
      Print(m); Alert(m);
      return(INIT_FAILED);
     }

   if(InpATRPeriod < 1)
     {
      Print(IND_NAME, ": ATR period must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }
#ifdef VOL_PERCENTILE
   if(InpLookback < 2)
     {
      Print(IND_NAME, ": percentile lookback must be >= 2.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_warm = InpATRPeriod + InpLookback + 1;
#else
   g_warm = InpATRPeriod + 1;
#endif

   //--- unique prefix per instance: MT5 loads the new instance BEFORE it
   //--- removes the old one on a timeframe change
   g_pfx = OBJ_FAMILY + IntegerToString((long)(GetTickCount64() % 100000000)) + "_" +
           IntegerToString((long)(GetMicrosecondCount() % 1000000)) + "_";
   //--- remove leftovers of other instances (templates, crashes)
   for(int n = ObjectsTotal(0, -1, -1) - 1; n >= 0; n--)
     {
      string on = ObjectName(0, n, -1, -1);
      if(StringFind(on, OBJ_FAMILY) == 0 && StringFind(on, g_pfx) != 0)
         ObjectDelete(0, on);
     }

   g_tf = (InpTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTF;

   SetIndexBuffer(0, B0, INDICATOR_DATA);
   SetIndexBuffer(1, B1, INDICATOR_DATA);
   SetIndexBuffer(2, B2, INDICATOR_DATA);
   SetIndexBuffer(3, B3, INDICATOR_DATA);
   SetIndexBuffer(4, B4, INDICATOR_DATA);
   SetIndexBuffer(5, B5, INDICATOR_DATA);
   SetIndexBuffer(6, B6, INDICATOR_DATA);
   SetIndexBuffer(7, B7, INDICATOR_DATA);
   SetIndexBuffer(8, B8, INDICATOR_DATA);
   SetIndexBuffer(9, B9, INDICATOR_DATA);
   for(int k = 0; k < MAX_SLOTS; k++)
     {
      PlotIndexSetDouble(k, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      g_sym[k]   = "";
      g_ready[k] = false;
      g_cur[k]   = EMPTY_VALUE;
     }

#ifdef VOL_PERCENTILE
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("%s V%s (%s, ATR %d, LB %d)",
                      IND_NAME, IND_VER, TfName(g_tf), InpATRPeriod, InpLookback));
   IndicatorSetInteger(INDICATOR_DIGITS, 1);
   IndicatorSetInteger(INDICATOR_LEVELS, 2);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, InpLevelLow);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, InpLevelHigh);
#else
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("%s V%s (%s, ATR %d)",
                      IND_NAME, IND_VER, TfName(g_tf), InpATRPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, 3);
#endif

   ScanMarketWatch();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, g_pfx);          // own instance only
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2) return(0);

   bool full = (prev_calculated == 0 || rates_total - prev_calculated > 1 ||
                rates_total < g_rates);
   if(full)
     {
      ArrayResize(g_t, rates_total);
      ArrayCopy(g_t, time, 0, 0, rates_total);
      g_rates    = rates_total;
      g_drawFrom = (InpMaxBars > 0 && rates_total > InpMaxBars) ? rates_total - InpMaxBars : 0;
      for(int k = 0; k < MAX_SLOTS; k++)
        {
         ClearSlot(k);
         g_ready[k] = false;
         PlotIndexSetInteger(k, PLOT_DRAW_BEGIN, g_drawFrom);
        }
     }
   else if(rates_total != g_rates)
     {
      //--- one new chart bar
      ArrayResize(g_t, rates_total);
      g_t[rates_total - 2] = time[rates_total - 2];
      g_t[rates_total - 1] = time[rates_total - 1];
      g_rates = rates_total;
      for(int k = 0; k < g_used; k++) SetVal(k, rates_total - 1, EMPTY_VALUE);
     }
   else
      return(rates_total);              // plain tick: the timer does the work

   UpdateAll(true);
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Timer: live update of all slots, Market Watch re-scan, legend.   |
//| Ticks of foreign symbols never reach OnCalculate, so the live    |
//| values come from here (once per second).                         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(GetTickCount64() - g_lastScan >= MW_SCAN_SEC * 1000)
      ScanMarketWatch();
   if(g_rates > 0)
      UpdateAll(false);
  }

//==================================================================
//  MARKET WATCH
//==================================================================
//--- reads the Market Watch selection; changes nothing in it
void ScanMarketWatch()
  {
   g_lastScan = GetTickCount64();
   int total = SymbolsTotal(true);      // true = Market Watch only
   string list[];
   ArrayResize(list, 0);
   string key = "";
   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, true);   // true = Market Watch only
      if(s == "") continue;
      int n = ArraySize(list);
      ArrayResize(list, n + 1);
      list[n] = s;
      key += s + ";";
     }
   if(key == g_mwKey) return;
   g_mwKey = key;

   int cnt   = ArraySize(list);
   g_used    = MathMin(cnt, MAX_SLOTS);
   g_skipped = cnt - g_used;
   for(int k = 0; k < MAX_SLOTS; k++)
     {
      string s = (k < g_used) ? list[k] : "";
      if(s != g_sym[k])
        {
         g_sym[k]   = s;
         g_ready[k] = false;
         g_cur[k]   = EMPTY_VALUE;
         ClearSlot(k);
        }
      if(s == "")
        {
         PlotIndexSetInteger(k, PLOT_DRAW_TYPE, DRAW_NONE);
         PlotIndexSetInteger(k, PLOT_SHOW_DATA, false);
         PlotIndexSetString(k, PLOT_LABEL, "unused");
        }
      else
        {
         bool hl = InpHighlightChart && s == _Symbol;
         PlotIndexSetInteger(k, PLOT_DRAW_TYPE, DRAW_LINE);
         PlotIndexSetInteger(k, PLOT_SHOW_DATA, true);
         PlotIndexSetInteger(k, PLOT_LINE_WIDTH, hl ? InpHighlightWidth : InpLineWidth);
         PlotIndexSetString(k, PLOT_LABEL, s);
        }
     }
   PrintFormat("%s: %d Market Watch symbol(s), %d shown%s", IND_NAME, cnt, g_used,
               g_skipped > 0 ? StringFormat(", %d not shown (limit %d)", g_skipped, MAX_SLOTS) : "");
  }

//==================================================================
//  CALCULATION
//==================================================================
void UpdateAll(const bool newBar)
  {
   if(g_rates < 2) return;
   for(int k = 0; k < g_used; k++)
     {
      if(g_sym[k] == "") continue;
      if(!g_ready[k])
         g_ready[k] = ComputeSlot(k, g_drawFrom);
      else
         ComputeSlot(k, MathMax(g_drawFrom, g_rates - (newBar ? 2 : 1)));
     }
   DrawLegend();
   DrawBranding();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Fills chart bars [fromBar .. g_rates-1] of one slot.             |
//| Returns false while the symbol history is not available yet -    |
//| the timer simply tries again, no error is raised.                |
//+------------------------------------------------------------------+
bool ComputeSlot(const int k, const int fromBar)
  {
   string s = g_sym[k];
   int avail = Bars(s, g_tf);           // also starts the history download
   if(avail <= g_warm) return(false);

   //--- source bars from the first chart bar to be filled up to now
   int shift = iBarShift(s, g_tf, g_t[fromBar], false);
   if(shift < 0) shift = avail - 1;
   int need = MathMin(MathMin(shift + 1 + g_warm, avail), MAX_SRC_BARS);

   MqlRates r[];
   int n = CopyRates(s, g_tf, 0, need, r);   // r[0] = oldest
   if(n <= g_warm) return(false);

   //--- ATR as SMA of the true range (same definition as MT5's iATR)
   double atr[];
   ArrayResize(atr, n);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
     {
      double tr = (i == 0) ? r[i].high - r[i].low
                  : MathMax(r[i].high, r[i-1].close) - MathMin(r[i].low, r[i-1].close);
      atr[i] = EMPTY_VALUE;
      if(i == 0) continue;              // first TR has no previous close
      sum += tr;
      if(i > InpATRPeriod)
        {
         double old = MathMax(r[i-InpATRPeriod].high, r[i-InpATRPeriod-1].close) -
                      MathMin(r[i-InpATRPeriod].low,  r[i-InpATRPeriod-1].close);
         sum -= old;
        }
      if(i >= InpATRPeriod) atr[i] = sum / InpATRPeriod;
     }

   //--- volatility value per source bar
   double val[];
   ArrayResize(val, n);
   for(int i = 0; i < n; i++) val[i] = EMPTY_VALUE;
#ifdef VOL_PERCENTILE
   for(int i = InpATRPeriod + InpLookback; i < n; i++)
     {
      //--- percentile rank of the current ATR against the previous N values;
      //--- ties count half, so a completely flat ATR reads 50
      double less = 0.0, eq = 0.0;
      for(int j = i - InpLookback; j < i; j++)
        {
         if(atr[j] < atr[i])       less += 1.0;
         else if(atr[j] == atr[i]) eq   += 1.0;
        }
      val[i] = (less + 0.5 * eq) / InpLookback * 100.0;
     }
#else
   for(int i = InpATRPeriod; i < n; i++)
      if(r[i].close > 0.0) val[i] = atr[i] / r[i].close * 100.0;
#endif

   //--- map onto chart bars by time: a chart bar takes the last source bar
   //--- that opened before the chart bar closed (works for any TF ratio)
   int chartSec = PeriodSeconds(_Period);
   int p = 0;
   for(int b = fromBar; b < g_rates; b++)
     {
      datetime tEnd = g_t[b] + chartSec;
      while(p + 1 < n && r[p+1].time < tEnd) p++;
      double v = (r[p].time < tEnd) ? val[p] : EMPTY_VALUE;
      SetVal(k, b, v);
     }
   g_cur[k] = GetVal(k, g_rates - 1);
   return(true);
  }

//==================================================================
//  BUFFER ACCESS (indicator buffers cannot live in an array)
//==================================================================
void SetVal(const int k, const int i, const double v)
  {
   switch(k)
     {
      case 0: B0[i] = v; break;
      case 1: B1[i] = v; break;
      case 2: B2[i] = v; break;
      case 3: B3[i] = v; break;
      case 4: B4[i] = v; break;
      case 5: B5[i] = v; break;
      case 6: B6[i] = v; break;
      case 7: B7[i] = v; break;
      case 8: B8[i] = v; break;
      case 9: B9[i] = v; break;
     }
  }

double GetVal(const int k, const int i)
  {
   switch(k)
     {
      case 0: return(B0[i]);
      case 1: return(B1[i]);
      case 2: return(B2[i]);
      case 3: return(B3[i]);
      case 4: return(B4[i]);
      case 5: return(B5[i]);
      case 6: return(B6[i]);
      case 7: return(B7[i]);
      case 8: return(B8[i]);
      case 9: return(B9[i]);
     }
   return(EMPTY_VALUE);
  }

void ClearSlot(const int k)
  {
   switch(k)
     {
      case 0: ArrayInitialize(B0, EMPTY_VALUE); break;
      case 1: ArrayInitialize(B1, EMPTY_VALUE); break;
      case 2: ArrayInitialize(B2, EMPTY_VALUE); break;
      case 3: ArrayInitialize(B3, EMPTY_VALUE); break;
      case 4: ArrayInitialize(B4, EMPTY_VALUE); break;
      case 5: ArrayInitialize(B5, EMPTY_VALUE); break;
      case 6: ArrayInitialize(B6, EMPTY_VALUE); break;
      case 7: ArrayInitialize(B7, EMPTY_VALUE); break;
      case 8: ArrayInitialize(B8, EMPTY_VALUE); break;
      case 9: ArrayInitialize(B9, EMPTY_VALUE); break;
     }
  }

//==================================================================
//  LEGEND (sorted: highest volatility on top)
//==================================================================
void DrawLegend()
  {
   int win = ChartWindowFind();
   if(win < 0) return;

   //--- order of slots by current value, descending; loading ones last
   int ord[MAX_SLOTS];
   int cnt = 0;
   for(int k = 0; k < g_used; k++) ord[cnt++] = k;
   for(int a = 1; a < cnt; a++)
     {
      int key = ord[a];
      double kv = SortKey(key);
      int b = a - 1;
      while(b >= 0 && SortKey(ord[b]) < kv) { ord[b+1] = ord[b]; b--; }
      ord[b+1] = key;
     }

   string txt[MAX_SLOTS + 2];
   color  col[MAX_SLOTS + 2];
   int lines = 0;
   for(int n = 0; n < cnt; n++)
     {
      int k = ord[n];
      string v;
      if(!g_ready[k] || g_cur[k] == EMPTY_VALUE) v = "loading...";
#ifdef VOL_PERCENTILE
      else v = StringFormat("%5.1f", g_cur[k]);
#else
      else v = StringFormat("%.3f %%", g_cur[k]);
#endif
      txt[lines] = StringFormat("%s %-12s %s", (g_sym[k] == _Symbol ? "\x25BA" : "\x25A0"),
                                g_sym[k], v);
      col[lines] = (color)PlotIndexGetInteger(k, PLOT_LINE_COLOR);
      lines++;
     }
   if(g_used == 0)
     {
      txt[lines] = "Market Watch is empty";
      col[lines] = clrOrangeRed;
      lines++;
     }
   if(g_skipped > 0)
     {
      txt[lines] = StringFormat("+%d not shown (limit %d)", g_skipped, MAX_SLOTS);
      col[lines] = clrGray;
      lines++;
     }

   int corner = (int)InpLegendCorner;
   bool lower = (corner == CORNER_LEFT_LOWER || corner == CORNER_RIGHT_LOWER);
   int step   = InpLegendFont + 7;
   int baseY  = lower ? ((corner == CORNER_RIGHT_LOWER && InpShowBranding) ? 40 : 6) : 6;
   for(int n = 0; n < MAX_SLOTS + 2; n++)
     {
      string name = g_pfx + "leg" + IntegerToString(n);
      if(n >= lines) { ObjectDelete(0, name); continue; }
      int y = lower ? baseY + (lines - 1 - n) * step : baseY + n * step;
      SetLabel(name, win, txt[n], corner, 8, y, col[n], InpLegendFont);
     }
  }

double SortKey(const int k)
  {
   return((!g_ready[k] || g_cur[k] == EMPTY_VALUE) ? -DBL_MAX : g_cur[k]);
  }

//==================================================================
//  BRANDING
//==================================================================
void DrawBranding()
  {
   string au = g_pfx + "Author";
   string ch = g_pfx + "Channel";
   int win = ChartWindowFind();
   if(!InpShowBranding || win < 0)
     {
      ObjectDelete(0, au);
      ObjectDelete(0, ch);
      return;
     }
   SetLabel(au, win, "P. Paarsch 2026",           CORNER_RIGHT_LOWER, 8, 21, clrGray, 7);
   SetLabel(ch, win, "t.me/Liquidity_Laboratory", CORNER_RIGHT_LOWER, 8, 8,  clrGray, 7);
   ObjectSetString(0, au, OBJPROP_TOOLTIP, "https://t.me/Liquidity_Laboratory");
   ObjectSetString(0, ch, OBJPROP_TOOLTIP, "https://t.me/Liquidity_Laboratory");
  }

//==================================================================
//  HELPERS
//==================================================================
void SetLabel(const string name, const int win, const string text, const int corner,
              const int x, const int y, const color c, const int size)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, win, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER;
   if(corner == CORNER_RIGHT_UPPER) anc = ANCHOR_RIGHT_UPPER;
   if(corner == CORNER_LEFT_LOWER)  anc = ANCHOR_LEFT_LOWER;
   if(corner == CORNER_RIGHT_LOWER) anc = ANCHOR_RIGHT_LOWER;
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   return(StringSubstr(EnumToString(tf), 7));   // "PERIOD_M10" -> "M10"
  }
//+------------------------------------------------------------------+
