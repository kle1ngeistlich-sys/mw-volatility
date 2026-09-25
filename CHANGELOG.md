# CHANGELOG - MW Volatility

## V1.4 - 2026-09-25 (ATR%)
- Neu: zeigt die TOP 10 der gesamten Marktuebersicht (hoechste ATR%) statt der ersten 10 der Liste.
- Neu: `Re-rank top 10 every X minutes` (Default 5). Rangfolge wird im 5-ms-Budget je Sekunde gemessen.
- Symbole, die in den Top 10 bleiben, behalten Platz und Farbe; nur Auf-/Absteiger wechseln.
- Fehlt einem Symbol beim Ranking noch die Historie, wird nach 30 s erneut gerankt.
- Legende: Statuszeile "Top 10 of N | next ranking in X min" bzw. "Ranking i/N ...".

## V1.3 - 2026-09-25 (ATR%)
- Fix leeres Fenster (V1.2 auf BTCUSD M2 im Echtgeld-Terminal): OnInit lief nie, der BTCUSD-Thread war ueberlastet
  (VolumeDeltaCandles meldete 3 s Rueckstand, avg 47 ms statt 4 ms je Aufruf).
- Symbol wird nur noch nach neuem Kurs (SYMBOL_TIME_MSC) neu gerechnet statt jede Sekunde alle 10.
- Rechenzeit je Aufruf auf 15 ms gedeckelt, Rest reihum im naechsten Timer-Takt.
- Legende/Labels nur bei Aenderung neu zeichnen; Lastbericht alle 5 min im Experten-Log.

## V1.2 - 2026-09-24 (ATR%)
- Label-Groesse als Auswahlliste statt Zahl: Tiny (6) / Small (7) / Medium (8, Default) / Normal (10).

## V1.1 - 2026-09-24 (nur ATR%-Fassung)
- Neu: optionale Symbol-Labels am Ende jeder Linie (`Show symbol labels at line ends`, Default an,
  Schriftgroesse einstellbar). Farbe = Linienfarbe, verankert links an der letzten Kerze.
- Weiterentwickelt wird nur noch die ATR%-Fassung; die Perzentil-Fassung bleibt auf V1.0.

## V1.0 - 2026-09-24
Erste Auslieferung, zwei Indikatoren aus einer Quelle (Schalter `VOL_PERCENTILE`):
- `MW_Volatility_Percentile_V1.0` - Perzentil-Rang der ATR gegen die eigenen letzten N Bars, 0-100, Level 20/80.
- `MW_Volatility_ATRPct_V1.0` - ATR in % vom Schlusskurs, direkt zwischen Symbolen vergleichbar.

Gemeinsam:
- Symbole ausschliesslich aus der Marktuebersicht (`SymbolsTotal(true)` / `SymbolName(i,true)`);
  kein `SymbolSelect`, die Marktuebersicht wird nie veraendert.
- Max. 10 Linien, ueberzaehlige Symbole als "+N not shown" in der Legende.
- Rechen-TF waehlbar (Default Chart-TF, alle TFs inkl. M2/M10); Zuordnung per Zeit, nicht per Index.
- ATR = SMA der True Range (wie MT5-iATR).
- Legende oben links (Ecke waehlbar), sortiert nach aktuellem Wert, Chart-Symbol mit dicker Linie und Pfeil.
- Fehlende Historie: Nachladen, Anzeige "loading...", kein Fehler.
- Timer 1 s fuer Live-Werte fremder Symbole, Market-Watch-Scan alle 5 s.
- Max bars to calculate (Default 1000), Quelldaten je Symbol auf 50.000 Bars gedeckelt.
- Lizenzbausteine blanko, Instanz-Praefix, Branding t.me/Liquidity_Laboratory.
