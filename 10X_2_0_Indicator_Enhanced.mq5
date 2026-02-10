//+------------------------------------------------------------------+
//|                                    10X_2_0_Indicator_Enhanced.mq5 |
//|                                       10X 2.0 Enhanced Indicator  |
//|                          Shows historical signals with all filters |
//+------------------------------------------------------------------+
#property copyright "10X 2.0 Enhanced"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//--- Plot 1: Valid BUY signals (BIG arrows)
#property indicator_label1  "BUY Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  5

//--- Plot 2: Valid SELL signals (BIG arrows)
#property indicator_label2  "SELL Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  5

//--- Plot 3: Filtered BUY signals (small arrows)
#property indicator_label3  "Filtered BUY"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrDarkGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Plot 4: Filtered SELL signals (small arrows)
#property indicator_label4  "Filtered SELL"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMaroon
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "══════ Signal Settings ══════"
input int      Lookback = 5;                    // Lookback Period
input bool     RequireLowestHighest = false;    // Require LOWEST low / HIGHEST high
input double   MinCandleBodyRatio = 0.3;        // Min body/range ratio
input int      SignalExpiryBars = 3;            // Entry Zone Width in bars (0=default 5)

input group "══════ Display Settings ══════"
input bool     ShowFilteredSignals = true;      // Show Filtered Signals (smaller arrows)
input bool     ShowFilterReasons = false;       // Show Filter Reasons (MTF_1/3, TIME, etc)
input bool     ShowScoreLabels = false;         // Show Score Labels
input bool     ShowEntryZones = true;           // Show Entry Zone Boxes
input bool     ShowStatsPanel = true;           // Show Statistics Panel
input int      MaxBarsToCalculate = 1000;       // Max Bars (0=all)
input int      SignalBufferPips = 5;            // SL Buffer (pips)
input double   RiskRewardRatio = 2.0;           // Risk:Reward Ratio

input group "══════ TREND FILTER (MTF) ══════"
input bool     UseTrendFilter = true;           // Enable Trend Filter
input int      TrendEMA_Period = 50;            // EMA Period
input ENUM_APPLIED_PRICE TrendEMA_Price = PRICE_CLOSE;
input bool     UseMTFTrend = true;              // Use Multi-Timeframe
input ENUM_TIMEFRAMES MTF_TF1 = PERIOD_H4;      // MTF Timeframe 1
input ENUM_TIMEFRAMES MTF_TF2 = PERIOD_H8;      // MTF Timeframe 2
input ENUM_TIMEFRAMES MTF_TF3 = PERIOD_H12;     // MTF Timeframe 3
input int      MinTFAlignment = 1;              // Min TF Alignment (1-3)
input bool     RequireCurrentTFAlign = false;   // Current TF must align

input group "══════ VOLATILITY FILTER ══════"
input bool     UseVolatilityFilter = false;     // Enable Volatility Filter
input int      ATR_Period = 14;                 // ATR Period
input double   MinATR_Multiplier = 0.5;         // Min ATR Multiplier
input double   MaxATR_Multiplier = 3.0;         // Max ATR Multiplier
input int      ATR_Average_Period = 50;         // ATR Average Period

input group "══════ TIME FILTER ══════"
input bool     UseTimeFilter = false;           // Enable Time Filter
input int      TradingStartHour = 7;            // Start Hour
input int      TradingEndHour = 20;             // End Hour

input group "══════ SIGNAL QUALITY ══════"
input int      MinSignalScore = 50;             // Min Signal Score

input group "══════ Colors ══════"
input color    BuyColor = clrLime;              // Valid BUY Color
input color    SellColor = clrRed;              // Valid SELL Color
input color    FilteredBuyColor = C'0,100,0';   // Filtered BUY Color
input color    FilteredSellColor = C'139,0,0';  // Filtered SELL Color
input color    BuyZoneColor = C'0,80,0';        // BUY Zone Color
input color    SellZoneColor = C'80,0,0';       // SELL Zone Color
input color    PanelBgColor = C'20,20,35';      // Panel Background

//+------------------------------------------------------------------+
//| Indicator Buffers                                                 |
//+------------------------------------------------------------------+
double BuySignalBuffer[];
double SellSignalBuffer[];
double FilteredBuyBuffer[];
double FilteredSellBuffer[];

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int emaHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int emaHandle_TF1 = INVALID_HANDLE;
int emaHandle_TF2 = INVALID_HANDLE;
int emaHandle_TF3 = INVALID_HANDLE;

string objPrefix = "10X_";
int totalSignals = 0;
int filteredSignals = 0;
int validBuySignals = 0;
int validSellSignals = 0;

double pipValue = 0.0001;
string spreadUnit = "pips";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate inputs (Fix #10)
   if(Lookback < 1)
   {
      Print("Error: Lookback Period must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(TrendEMA_Period < 1)
   {
      Print("Error: EMA Period must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(UseVolatilityFilter && ATR_Period < 1)
   {
      Print("Error: ATR Period must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(RiskRewardRatio <= 0)
   {
      Print("Error: Risk:Reward Ratio must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MinTFAlignment < 0 || MinTFAlignment > 3)
   {
      Print("Error: Min TF Alignment must be between 0 and 3");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MinSignalScore > 100)
      Print("Warning: Min Signal Score > 100, no signals will pass");
   if(UseTimeFilter && TradingStartHour >= TradingEndHour)
      Print("Warning: Start Hour >= End Hour, time filter may not work for overnight sessions");

   //--- Set indicator buffers
   SetIndexBuffer(0, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, FilteredBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, FilteredSellBuffer, INDICATOR_DATA);

   //--- Set arrow codes - using cleaner wingdings
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Down arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 158);  // Small circle for filtered
   PlotIndexSetInteger(3, PLOT_ARROW, 158);  // Small circle for filtered

   //--- Set colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, BuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, SellColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, FilteredBuyColor);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, FilteredSellColor);

   //--- Set empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Create indicator handles
   if(UseTrendFilter)
   {
      emaHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, TrendEMA_Price);
      if(emaHandle == INVALID_HANDLE)
      {
         Print("Failed to create EMA indicator");
         return(INIT_FAILED);
      }

      if(UseMTFTrend)
      {
         //--- Validate MTF timeframes are higher than chart timeframe (Fix #8)
         int currentPeriodSec = PeriodSeconds(_Period);
         if(PeriodSeconds(MTF_TF1) <= currentPeriodSec ||
            PeriodSeconds(MTF_TF2) <= currentPeriodSec ||
            PeriodSeconds(MTF_TF3) <= currentPeriodSec)
         {
            Print("Warning: MTF timeframes should be higher than chart timeframe (", GetTimeframeName(_Period), ")");
         }

         emaHandle_TF1 = iMA(_Symbol, MTF_TF1, TrendEMA_Period, 0, MODE_EMA, TrendEMA_Price);
         emaHandle_TF2 = iMA(_Symbol, MTF_TF2, TrendEMA_Period, 0, MODE_EMA, TrendEMA_Price);
         emaHandle_TF3 = iMA(_Symbol, MTF_TF3, TrendEMA_Period, 0, MODE_EMA, TrendEMA_Price);

         if(emaHandle_TF1 == INVALID_HANDLE || emaHandle_TF2 == INVALID_HANDLE || emaHandle_TF3 == INVALID_HANDLE)
         {
            Print("Failed to create MTF EMA indicators");
            return(INIT_FAILED);
         }
      }
   }

   if(UseVolatilityFilter)
   {
      atrHandle = iATR(_Symbol, _Period, ATR_Period);
      if(atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR indicator");
         return(INIT_FAILED);
      }
   }

   //--- Detect instrument type
   DetectInstrumentType();

   //--- Create stats panel
   if(ShowStatsPanel)
      CreateStatsPanel();

   //--- Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "10X 2.0 Enhanced");

   Print("===================================================");
   Print("10X 2.0 Enhanced Indicator v2.0");
   Print("   MTF: ", GetTimeframeName(MTF_TF1), "/", GetTimeframeName(MTF_TF2), "/", GetTimeframeName(MTF_TF3));
   Print("   Min Alignment: ", MinTFAlignment, "/3");
   Print("===================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaHandle_TF1 != INVALID_HANDLE) IndicatorRelease(emaHandle_TF1);
   if(emaHandle_TF2 != INVALID_HANDLE) IndicatorRelease(emaHandle_TF2);
   if(emaHandle_TF3 != INVALID_HANDLE) IndicatorRelease(emaHandle_TF3);

   ObjectsDeleteAll(0, objPrefix);

   Print("===================================================");
   Print("10X 2.0 Final Statistics:");
   Print("   Valid BUY:  ", validBuySignals);
   Print("   Valid SELL: ", validSellSignals);
   Print("   Filtered:   ", filteredSignals);
   Print("===================================================");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   if(rates_total < Lookback + 10)
      return(0);

   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   ArraySetAsSeries(FilteredBuyBuffer, true);
   ArraySetAsSeries(FilteredSellBuffer, true);

   int limit;
   if(prev_calculated == 0)
   {
      limit = (MaxBarsToCalculate > 0) ? MathMin(MaxBarsToCalculate, rates_total - Lookback - 2) : rates_total - Lookback - 2;

      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      ArrayInitialize(FilteredBuyBuffer, EMPTY_VALUE);
      ArrayInitialize(FilteredSellBuffer, EMPTY_VALUE);

      ObjectsDeleteAll(0, objPrefix + "zone_");
      ObjectsDeleteAll(0, objPrefix + "lbl_");
      ObjectsDeleteAll(0, objPrefix + "flt_");  // Fix #2: clean up filter labels too
   }
   else
   {
      limit = rates_total - prev_calculated + 1;
   }

   for(int i = limit; i >= 1; i--)
   {
      if(i + Lookback >= rates_total)
         continue;

      CheckSignal(i, open, high, low, close, time);
   }

   //--- Fix #1: Recount signals from buffers to avoid accumulation on tick updates
   totalSignals = 0;
   filteredSignals = 0;
   validBuySignals = 0;
   validSellSignals = 0;
   int countLimit = (MaxBarsToCalculate > 0) ? MathMin(MaxBarsToCalculate, rates_total - Lookback - 2) : rates_total - Lookback - 2;
   for(int c = 1; c <= countLimit; c++)
   {
      if(BuySignalBuffer[c] != EMPTY_VALUE) { validBuySignals++; totalSignals++; }
      if(SellSignalBuffer[c] != EMPTY_VALUE) { validSellSignals++; totalSignals++; }
      if(FilteredBuyBuffer[c] != EMPTY_VALUE) { filteredSignals++; totalSignals++; }
      if(FilteredSellBuffer[c] != EMPTY_VALUE) { filteredSignals++; totalSignals++; }
   }

   //--- Update stats panel
   if(ShowStatsPanel)
      UpdateStatsPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Check for signal at bar index                                     |
//+------------------------------------------------------------------+
void CheckSignal(int i, const double &open[], const double &high[],
                 const double &low[], const double &close[], const datetime &time[])
{
   bool isBullish = close[i] > open[i];
   bool isBearish = close[i] < open[i];

   double candleRange = high[i] - low[i];
   if(candleRange <= 0)
      return;

   double candleBody = MathAbs(close[i] - open[i]);
   double bodyRatio = candleBody / candleRange;

   //--- Fix #6: Enforce MinCandleBodyRatio as a hard filter
   if(bodyRatio < MinCandleBodyRatio)
      return;

   double closeFromLow = close[i] - low[i];
   double closeFromHigh = high[i] - close[i];
   bool upperQuarterClose = closeFromLow >= (0.75 * candleRange);
   bool lowerQuarterClose = closeFromHigh >= (0.75 * candleRange);

   bool makingLowerLow = false;
   bool makingHigherHigh = false;

   if(RequireLowestHighest)
   {
      makingLowerLow = true;
      makingHigherHigh = true;
      for(int j = 1; j <= Lookback; j++)
      {
         if(low[i] >= low[i + j]) makingLowerLow = false;
         if(high[i] <= high[i + j]) makingHigherHigh = false;
      }
   }
   else
   {
      for(int j = 1; j <= Lookback; j++)
      {
         if(low[i] < low[i + j]) { makingLowerLow = true; break; }
      }
      for(int j = 1; j <= Lookback; j++)
      {
         if(high[i] > high[i + j]) { makingHigherHigh = true; break; }
      }
   }

   //--- BUY SIGNAL
   if(isBullish && makingLowerLow && upperQuarterClose)
   {
      // Fix #1: counters removed, recount from buffers in OnCalculate
      int score = CalculateSignalScore("BUY", i, open, high, low, close, bodyRatio, time[i]);
      string filterResult = CheckAllFilters("BUY", close[i], time[i]);

      if(filterResult == "PASS" && score >= MinSignalScore)
      {
         BuySignalBuffer[i] = low[i] - (candleRange * 0.5);

         if(ShowEntryZones)
            DrawEntryZone(i, "BUY", high[i], low[i], time[i], score);

         if(ShowScoreLabels)
            CreateScoreLabel(i, "BUY", score, time[i], low[i] - (candleRange * 0.8));
      }
      else
      {
         if(ShowFilteredSignals)
         {
            FilteredBuyBuffer[i] = low[i] - (candleRange * 0.3);

            // Show filter reason label
            if(ShowFilterReasons)
               CreateFilterLabel(i, "BUY", filterResult, score, time[i], low[i] - (candleRange * 0.6));
         }
      }
   }

   //--- SELL SIGNAL
   if(isBearish && makingHigherHigh && lowerQuarterClose)
   {
      int score = CalculateSignalScore("SELL", i, open, high, low, close, bodyRatio, time[i]);
      string filterResult = CheckAllFilters("SELL", close[i], time[i]);

      if(filterResult == "PASS" && score >= MinSignalScore)
      {
         SellSignalBuffer[i] = high[i] + (candleRange * 0.5);

         if(ShowEntryZones)
            DrawEntryZone(i, "SELL", high[i], low[i], time[i], score);

         if(ShowScoreLabels)
            CreateScoreLabel(i, "SELL", score, time[i], high[i] + (candleRange * 0.8));
      }
      else
      {
         if(ShowFilteredSignals)
         {
            FilteredSellBuffer[i] = high[i] + (candleRange * 0.3);

            // Show filter reason label
            if(ShowFilterReasons)
               CreateFilterLabel(i, "SELL", filterResult, score, time[i], high[i] + (candleRange * 0.6));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw entry zone box                                               |
//+------------------------------------------------------------------+
void DrawEntryZone(int barIndex, string signalType, double signalHigh,
                   double signalLow, datetime signalTime, int score)
{
   double buffer = SignalBufferPips * pipValue;
   double entryPrice = (signalHigh + signalLow) / 2.0;
   double stopLoss, takeProfit, riskPoints;

   if(signalType == "BUY")
   {
      stopLoss = signalLow - buffer;
      riskPoints = entryPrice - stopLoss;
      takeProfit = entryPrice + (riskPoints * RiskRewardRatio);
   }
   else
   {
      stopLoss = signalHigh + buffer;
      riskPoints = stopLoss - entryPrice;
      takeProfit = entryPrice - (riskPoints * RiskRewardRatio);
   }

   //--- Zone extends for SignalExpiryBars (or 5 if no width set)
   int zoneBars = (SignalExpiryBars > 0) ? SignalExpiryBars : 5;
   datetime endTime = signalTime + PeriodSeconds() * zoneBars;
   color zoneColor = (signalType == "BUY") ? BuyZoneColor : SellZoneColor;  // Fix #4: use input colors

   //--- Draw TP zone (translucent)
   // Fix #12: include signalType in object names to avoid collision
   string tpName = objPrefix + "zone_tp_" + signalType + "_" + IntegerToString(signalTime);
   double tpTop = (signalType == "BUY") ? takeProfit : entryPrice;
   double tpBot = (signalType == "BUY") ? entryPrice : takeProfit;

   ObjectCreate(0, tpName, OBJ_RECTANGLE, 0, signalTime, tpTop, endTime, tpBot);
   ObjectSetInteger(0, tpName, OBJPROP_COLOR, zoneColor);  // Fix #4: use zoneColor
   ObjectSetInteger(0, tpName, OBJPROP_FILL, true);
   ObjectSetInteger(0, tpName, OBJPROP_BACK, true);
   ObjectSetInteger(0, tpName, OBJPROP_SELECTABLE, false);

   //--- Draw SL zone
   string slName = objPrefix + "zone_sl_" + signalType + "_" + IntegerToString(signalTime);
   double slTop = (signalType == "BUY") ? entryPrice : stopLoss;
   double slBot = (signalType == "BUY") ? stopLoss : entryPrice;

   ObjectCreate(0, slName, OBJ_RECTANGLE, 0, signalTime, slTop, endTime, slBot);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, C'60,30,0');
   ObjectSetInteger(0, slName, OBJPROP_FILL, true);
   ObjectSetInteger(0, slName, OBJPROP_BACK, true);
   ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);

   //--- Entry line
   string entryName = objPrefix + "zone_entry_" + signalType + "_" + IntegerToString(signalTime);
   ObjectCreate(0, entryName, OBJ_TREND, 0, signalTime, entryPrice, endTime, entryPrice);
   ObjectSetInteger(0, entryName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, entryName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, entryName, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Create score label (only if enabled)                              |
//+------------------------------------------------------------------+
void CreateScoreLabel(int barIndex, string signalType, int score,
                      datetime signalTime, double price)
{
   // Fix #12: include signalType in object name
   string name = objPrefix + "lbl_" + signalType + "_" + IntegerToString(signalTime);
   string text = IntegerToString(score);
   color textColor = (signalType == "BUY") ? BuyColor : SellColor;

   ObjectCreate(0, name, OBJ_TEXT, 0, signalTime, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
}

//+------------------------------------------------------------------+
//| Create filter reason label (for filtered signals)                 |
//+------------------------------------------------------------------+
void CreateFilterLabel(int barIndex, string signalType, string filterReason,
                       int score, datetime signalTime, double price)
{
   string name = objPrefix + "flt_" + IntegerToString(signalTime) + "_" + signalType;
   string text = IntegerToString(score) + " [" + filterReason + "]";
   color textColor = (signalType == "BUY") ? FilteredBuyColor : FilteredSellColor;

   ObjectCreate(0, name, OBJ_TEXT, 0, signalTime, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
}

//+------------------------------------------------------------------+
//| Calculate signal score                                            |
//+------------------------------------------------------------------+
int CalculateSignalScore(string signalType, int barIndex,
                         const double &open[], const double &high[],
                         const double &low[], const double &close[],
                         double bodyRatio, datetime signalTime)
{
   int score = 50;

   if(bodyRatio >= 0.6) score += 15;
   else if(bodyRatio >= MinCandleBodyRatio) score += 10;

   double range = high[barIndex] - low[barIndex];
   if(signalType == "BUY")
   {
      double closeRatio = (close[barIndex] - low[barIndex]) / range;
      if(closeRatio >= 0.9) score += 15;
      else if(closeRatio >= 0.8) score += 10;
   }
   else
   {
      double closeRatio = (high[barIndex] - close[barIndex]) / range;
      if(closeRatio >= 0.9) score += 15;
      else if(closeRatio >= 0.8) score += 10;
   }

   if(UseTrendFilter && UseMTFTrend)
   {
      int bullCount = 0, bearCount = 0;
      GetMTFTrendAtTime(signalTime, bullCount, bearCount);
      int alignedCount = (signalType == "BUY") ? bullCount : bearCount;
      if(alignedCount == 3) score += 20;
      else if(alignedCount == 2) score += 10;
   }

   return MathMin(100, MathMax(0, score));
}

//+------------------------------------------------------------------+
//| Check all filters                                                 |
//+------------------------------------------------------------------+
string CheckAllFilters(string signalType, double signalClose, datetime signalTime)
{
   //--- Time Filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(signalTime, dt);
      if(dt.hour < TradingStartHour || dt.hour >= TradingEndHour)
         return "TIME";
   }

   //--- Volatility Filter
   if(UseVolatilityFilter && atrHandle != INVALID_HANDLE)
   {
      int barShift = iBarShift(_Symbol, _Period, signalTime);

      double atrValues[];
      ArraySetAsSeries(atrValues, true);
      if(CopyBuffer(atrHandle, 0, barShift, ATR_Average_Period + 5, atrValues) > ATR_Average_Period)
      {
         double currentATR = atrValues[0];
         //--- Fix #7: exclude current bar from its own average
         double avgATR = 0;
         for(int j = 1; j <= ATR_Average_Period; j++)
            avgATR += atrValues[j];
         avgATR /= ATR_Average_Period;

         if(avgATR > 0)
         {
            double ratio = currentATR / avgATR;
            if(ratio < MinATR_Multiplier) return "VOL_LOW";
            if(ratio > MaxATR_Multiplier) return "VOL_HIGH";
         }
      }
   }

   //--- MTF Trend Filter
   if(UseTrendFilter && UseMTFTrend)
   {
      int bullCount = 0, bearCount = 0;
      GetMTFTrendAtTime(signalTime, bullCount, bearCount);
      int alignedCount = (signalType == "BUY") ? bullCount : bearCount;
      if(alignedCount < MinTFAlignment)
         return "MTF_" + IntegerToString(alignedCount) + "/3";
   }

   //--- Current TF Trend Filter
   if(UseTrendFilter && RequireCurrentTFAlign && emaHandle != INVALID_HANDLE)
   {
      int barShift = iBarShift(_Symbol, _Period, signalTime);

      double emaValues[];
      ArraySetAsSeries(emaValues, true);
      if(CopyBuffer(emaHandle, 0, barShift, 3, emaValues) >= 2)
      {
         bool bullish = signalClose > emaValues[0];
         if(signalType == "BUY" && !bullish) return "TREND";
         if(signalType == "SELL" && bullish) return "TREND";
      }
   }

   return "PASS";
}

//+------------------------------------------------------------------+
//| Get MTF Trend at specific time (for historical analysis)         |
//+------------------------------------------------------------------+
void GetMTFTrendAtTime(datetime signalTime, int &bullCount, int &bearCount)
{
   bullCount = 0;
   bearCount = 0;

   string trend1 = GetTrendDirectionAtTime(emaHandle_TF1, MTF_TF1, signalTime);
   string trend2 = GetTrendDirectionAtTime(emaHandle_TF2, MTF_TF2, signalTime);
   string trend3 = GetTrendDirectionAtTime(emaHandle_TF3, MTF_TF3, signalTime);

   if(trend1 == "BULL") bullCount++;
   else if(trend1 == "BEAR") bearCount++;

   if(trend2 == "BULL") bullCount++;
   else if(trend2 == "BEAR") bearCount++;

   if(trend3 == "BULL") bullCount++;
   else if(trend3 == "BEAR") bearCount++;
}

//+------------------------------------------------------------------+
//| Get trend direction at specific time for a timeframe             |
//+------------------------------------------------------------------+
string GetTrendDirectionAtTime(int handle, ENUM_TIMEFRAMES tf, datetime signalTime)
{
   if(handle == INVALID_HANDLE)
      return "N/A";

   // Find the bar index on the higher timeframe that corresponds to signalTime
   int barShift = iBarShift(_Symbol, tf, signalTime);
   if(barShift < 0)
      return "N/A";

   //--- Fix #9: use completed bar to avoid look-ahead bias on forming HTF bar
   if(barShift == 0)
      barShift = 1;

   double emaValues[];
   ArraySetAsSeries(emaValues, true);

   if(CopyBuffer(handle, 0, barShift, 3, emaValues) < 2)
      return "N/A";

   // Get close price at that time on the higher timeframe
   double closePrice = iClose(_Symbol, tf, barShift);
   if(closePrice <= 0 || emaValues[0] <= 0)
      return "N/A";

   if(closePrice > emaValues[0])
      return "BULL";
   else if(closePrice < emaValues[0])
      return "BEAR";
   else
      return "FLAT";
}

//+------------------------------------------------------------------+
//| Create statistics panel                                           |
//+------------------------------------------------------------------+
void CreateStatsPanel()
{
   int xOffset = 10;
   int yOffset = 50;
   int panelWidth = 220;
   int panelHeight = 280;
   int lineHeight = 22;
   int labelX = xOffset + 15;
   int valueX = xOffset + 120;

   //--- Background
   string bgName = objPrefix + "panel_bg";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, xOffset);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, yOffset);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, PanelBgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'60,60,80');

   int y = yOffset + 15;

   //--- Title
   CreatePanelLabel("title", "10X 2.0 SIGNALS", labelX, y, clrGold, 11);
   y += lineHeight + 10;

   //--- Signal Stats Section Header
   CreatePanelLabel("stats_hdr", "-- SIGNALS --", labelX, y, C'100,100,120', 9);
   y += lineHeight;

   CreatePanelLabel("buy_lbl", "Valid BUY:", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("buy_val", "0", valueX, y, BuyColor, 9);
   y += lineHeight;

   CreatePanelLabel("sell_lbl", "Valid SELL:", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("sell_val", "0", valueX, y, SellColor, 9);
   y += lineHeight;

   CreatePanelLabel("filt_lbl", "Filtered:", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("filt_val", "0", valueX, y, clrOrange, 9);
   y += lineHeight;

   CreatePanelLabel("rate_lbl", "Pass Rate:", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("rate_val", "—", valueX, y, clrWhite, 9);
   y += lineHeight + 15;

   //--- MTF Trend Section Header
   CreatePanelLabel("mtf_hdr", "-- MTF TREND --", labelX, y, C'100,100,120', 9);
   y += lineHeight;

   CreatePanelLabel("tf1_lbl", GetTimeframeName(MTF_TF1) + ":", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("tf1_val", "—", labelX + 45, y, clrGray, 9);
   y += lineHeight;

   CreatePanelLabel("tf2_lbl", GetTimeframeName(MTF_TF2) + ":", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("tf2_val", "—", labelX + 45, y, clrGray, 9);
   y += lineHeight;

   CreatePanelLabel("tf3_lbl", GetTimeframeName(MTF_TF3) + ":", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("tf3_val", "—", labelX + 45, y, clrGray, 9);
   y += lineHeight + 10;

   //--- Alignment display (larger, centered)
   CreatePanelLabel("align_lbl", "Alignment:", labelX, y, C'140,140,140', 9);
   CreatePanelLabel("align_val", "— of 3", valueX, y, clrWhite, 10);
}

//+------------------------------------------------------------------+
//| Create panel label helper                                         |
//+------------------------------------------------------------------+
void CreatePanelLabel(string id, string text, int x, int y, color clr, int fontSize)
{
   string name = objPrefix + "panel_" + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
}

//+------------------------------------------------------------------+
//| Update statistics panel                                           |
//+------------------------------------------------------------------+
void UpdateStatsPanel()
{
   //--- Update signal stats
   ObjectSetString(0, objPrefix + "panel_buy_val", OBJPROP_TEXT, IntegerToString(validBuySignals));
   ObjectSetString(0, objPrefix + "panel_sell_val", OBJPROP_TEXT, IntegerToString(validSellSignals));
   ObjectSetString(0, objPrefix + "panel_filt_val", OBJPROP_TEXT, IntegerToString(filteredSignals));

   int totalValid = validBuySignals + validSellSignals;
   if(totalSignals > 0)
   {
      double passRate = (double)totalValid / totalSignals * 100.0;
      ObjectSetString(0, objPrefix + "panel_rate_val", OBJPROP_TEXT, DoubleToString(passRate, 1) + "%");
   }

   //--- Update MTF Trend Display
   if(UseTrendFilter && UseMTFTrend)
   {
      int bullCount = 0, bearCount = 0;

      //--- Get current trend for each TF
      string trend1 = GetCurrentTrend(emaHandle_TF1, MTF_TF1);
      string trend2 = GetCurrentTrend(emaHandle_TF2, MTF_TF2);
      string trend3 = GetCurrentTrend(emaHandle_TF3, MTF_TF3);

      //--- Update TF1
      color clr1 = (trend1 == "BULL") ? clrLime : (trend1 == "BEAR") ? clrRed : clrGray;
      string txt1 = (trend1 == "BULL") ? "BULL" : (trend1 == "BEAR") ? "BEAR" : "— N/A";
      ObjectSetString(0, objPrefix + "panel_tf1_val", OBJPROP_TEXT, txt1);
      ObjectSetInteger(0, objPrefix + "panel_tf1_val", OBJPROP_COLOR, clr1);
      if(trend1 == "BULL") bullCount++;
      else if(trend1 == "BEAR") bearCount++;

      //--- Update TF2
      color clr2 = (trend2 == "BULL") ? clrLime : (trend2 == "BEAR") ? clrRed : clrGray;
      string txt2 = (trend2 == "BULL") ? "BULL" : (trend2 == "BEAR") ? "BEAR" : "— N/A";
      ObjectSetString(0, objPrefix + "panel_tf2_val", OBJPROP_TEXT, txt2);
      ObjectSetInteger(0, objPrefix + "panel_tf2_val", OBJPROP_COLOR, clr2);
      if(trend2 == "BULL") bullCount++;
      else if(trend2 == "BEAR") bearCount++;

      //--- Update TF3
      color clr3 = (trend3 == "BULL") ? clrLime : (trend3 == "BEAR") ? clrRed : clrGray;
      string txt3 = (trend3 == "BULL") ? "BULL" : (trend3 == "BEAR") ? "BEAR" : "— N/A";
      ObjectSetString(0, objPrefix + "panel_tf3_val", OBJPROP_TEXT, txt3);
      ObjectSetInteger(0, objPrefix + "panel_tf3_val", OBJPROP_COLOR, clr3);
      if(trend3 == "BULL") bullCount++;
      else if(trend3 == "BEAR") bearCount++;

      //--- Update alignment display
      int maxCount = MathMax(bullCount, bearCount);
      string alignText = IntegerToString(maxCount) + " of 3";
      color alignColor = clrGray;

      if(maxCount == 3)
         alignColor = (bullCount == 3) ? clrLime : clrRed;
      else if(maxCount == 2)
         alignColor = (bullCount == 2) ? clrLimeGreen : clrOrangeRed;
      else if(maxCount == 1)
         alignColor = clrOrange;
      else
         alignColor = clrGray;

      //--- Add direction indicator
      if(bullCount > bearCount)
         alignText = IntegerToString(bullCount) + " of 3";
      else if(bearCount > bullCount)
         alignText = IntegerToString(bearCount) + " of 3";
      else if(bullCount == bearCount && bullCount > 0)
         alignText = IntegerToString(bullCount) + " of 3";

      ObjectSetString(0, objPrefix + "panel_align_val", OBJPROP_TEXT, alignText);
      ObjectSetInteger(0, objPrefix + "panel_align_val", OBJPROP_COLOR, alignColor);
   }
}

//+------------------------------------------------------------------+
//| Get current trend for a timeframe                                 |
//+------------------------------------------------------------------+
string GetCurrentTrend(int handle, ENUM_TIMEFRAMES tf)
{
   if(handle == INVALID_HANDLE)
      return "N/A";

   double emaValues[];
   ArraySetAsSeries(emaValues, true);

   if(CopyBuffer(handle, 0, 0, 3, emaValues) < 2)
      return "N/A";

   double closePrice = iClose(_Symbol, tf, 1);
   if(closePrice <= 0 || emaValues[1] <= 0)
      return "N/A";

   if(closePrice > emaValues[1])
      return "BULL";
   else if(closePrice < emaValues[1])
      return "BEAR";
   else
      return "FLAT";
}

//+------------------------------------------------------------------+
//| Detect instrument type                                            |
//+------------------------------------------------------------------+
void DetectInstrumentType()
{
   string symbol = _Symbol;
   string symbolUpper = symbol;
   StringToUpper(symbolUpper);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(StringFind(symbolUpper, "XAU") >= 0 || StringFind(symbolUpper, "GOLD") >= 0)
   {
      pipValue = 0.1;
      spreadUnit = "cents";
   }
   else if(StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0)
   {
      pipValue = 0.01;
      spreadUnit = "cents";
   }
   else if(StringFind(symbolUpper, "JPY") >= 0)
   {
      pipValue = 0.01;
      spreadUnit = "pips";
   }
   else if(digits == 5 || digits == 4)
   {
      //--- Fix #3: 4-digit pairs also use 0.0001 pip value
      pipValue = 0.0001;
      spreadUnit = "pips";
   }
   else
   {
      pipValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
      spreadUnit = "points";
   }
}

//+------------------------------------------------------------------+
//| Get timeframe name                                                |
//+------------------------------------------------------------------+
string GetTimeframeName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
   }
}
//+------------------------------------------------------------------+
