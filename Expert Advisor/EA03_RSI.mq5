//+------------------------------------------------------------------+
//|                                         Gemini_RSI_Trader.mq5   |
//|                                Copyright 2026, Algorithmic Trader|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini MQL5 Developer"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums untuk Lot Risk Mode
enum ENUM_RISK_MODE
  {
   RISK_MODE_PERCENT,  // Risk Percentage (% Account Balance)
   RISK_MODE_MONETARY  // Fixed Monetary Amount ($)
  };

//--- Input Parameters
input group "=== RSI Signal Settings ==="
input ENUM_TIMEFRAMES InpRSITimeframe = PERIOD_H1;  // RSI Timeframe
input int           InpRSIPeriod     = 14;         // RSI Period
input double        InpRSIBuyThresh  = 30.0;       // RSI Buy Threshold (Oversold)
input double        InpRSISellThresh = 70.0;       // RSI Sell Threshold (Overbought)

input group "=== Moving Average Filter ==="
input bool          InpUseMAFilter   = true;        // Enable MA Filter
input ENUM_TIMEFRAMES InpMATimeframe = PERIOD_D1;    // MA Timeframe
input int           InpMAPeriod      = 50;         // MA Period
input ENUM_MA_METHOD InpMAMethod     = MODE_SMA;    // MA Method

input group "=== Stop Loss & Take Profit ==="
input double        InpSLPercent     = 5.0;        // Stop Loss % of Open Price (0 = Disabled)
input double        InpTPPercent     = 1.0;        // Take Profit % of Open Price (0 = Disabled)

input group "=== Trailing Stop Settings ==="
input double        InpTrailTrigger  = 0.5;        // Trailing Trigger % Profit (0 = Disabled)
input double        InpTrailDistance = 0.1;        // Trailing Distance %
input double        InpTrailStep     = 0.05;       // Trailing Step %

input group "=== Risk & Capital Management ==="
input ENUM_RISK_MODE InpRiskMode     = RISK_MODE_PERCENT; // Risk Mode
input double        InpRiskValue     = 1.0;        // Risk Value (% Balance or $ Amount)

input group "=== System Settings ==="
input ulong         InpMagicNumber   = 888999;     // Unique Magic Number
input string        InpOrderComment  = "Gemini_RSI_EA"; // Order Comment

//--- Global Variables
CTrade         trade;
int            handleRSI;
int            handleMA;
bool           canBuyNext;
bool           canSellNext;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi RSI Indicator
   handleRSI = iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, PRICE_CLOSE);
   if(handleRSI == INVALID_HANDLE)
     {
      Print("Error: Gagal membuat handle RSI.");
      return(INIT_FAILED);
     }

   // Inisialisasi MA Indicator jika diaktifkan
   if(InpUseMAFilter)
     {
      handleMA = iMA(_Symbol, InpMATimeframe, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(handleMA == INVALID_HANDLE)
        {
         Print("Error: Gagal membuat handle Moving Average.");
         return(INIT_FAILED);
        }
     }

   canBuyNext = true;
   canSellNext = true;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleMA != INVALID_HANDLE) IndicatorRelease(handleMA);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Kelola Trailing Stop untuk posisi terbuka
   if(InpTrailTrigger > 0) ManageTrailingStop();

   // 2. Pembacaan nilai RSI dari Bar 1 (Closed Candle)
   double rsiValues[];
   ArraySetAsSeries(rsiValues, true);
   if(CopyBuffer(handleRSI, 0, 1, 2, rsiValues) < 2) return;

   double rsiBar1 = rsiValues[0];

   // 3. Update Re-entry Guard (Must Cross Level 50)
   if(rsiBar1 > 50.0) canBuyNext = true;
   if(rsiBar1 < 50.0) canSellNext = true;

   // 4. Jika sedang ada posisi terbuka, tidak buka order baru
   if(HasOpenPosition()) return;

   // 5. Pembacaan MA Filter dari Bar 1
   bool maBuyOK = true;
   bool maSellOK = true;

   if(InpUseMAFilter)
     {
      double maValues[];
      MqlRates rates[];
      ArraySetAsSeries(maValues, true);
      ArraySetAsSeries(rates, true);

      if(CopyBuffer(handleMA, 0, 1, 1, maValues) > 0 && CopyRates(_Symbol, InpMATimeframe, 1, 1, rates) > 0)
        {
         double closePriceBar1 = rates[0].close;
         maBuyOK  = (closePriceBar1 > maValues[0]);
         maSellOK = (closePriceBar1 < maValues[0]);
        }
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 6. Logika Sinyal BUY
   if(rsiBar1 < InpRSIBuyThresh && maBuyOK && canBuyNext)
     {
      double lot = CalculateLotSize(ask, InpSLPercent);
      double sl = (InpSLPercent > 0) ? ask * (1.0 - InpSLPercent / 100.0) : 0;
      double tp = (InpTPPercent > 0) ? ask * (1.0 + InpTPPercent / 100.0) : 0;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.Buy(lot, _Symbol, ask, sl, tp, InpOrderComment))
        {
         canBuyNext = false; // Kunci sampai RSI melintasi level 50 kembali
        }
     }

   // 7. Logika Sinyal SELL
   else if(rsiBar1 > InpRSISellThresh && maSellOK && canSellNext)
     {
      double lot = CalculateLotSize(bid, InpSLPercent);
      double sl = (InpSLPercent > 0) ? bid * (1.0 + InpSLPercent / 100.0) : 0;
      double tp = (InpTPPercent > 0) ? bid * (1.0 - InpTPPercent / 100.0) : 0;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.Sell(lot, _Symbol, bid, sl, tp, InpOrderComment))
        {
         canSellNext = false; // Kunci sampai RSI melintasi level 50 kembali
        }
     }
  }

//+------------------------------------------------------------------+
//| Perhitungan Ukuran Lot Dinamis Berdasarkan Risiko                |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPercent)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = 0;

   if(InpRiskMode == RISK_MODE_PERCENT)
      riskAmount = balance * (InpRiskValue / 100.0);
   else
      riskAmount = InpRiskValue;

   double lot = 0.01;

   if(slPercent > 0)
     {
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slPoints  = (slPercent / 100.0) * entryPrice / _Point;
      double lossPerLot = (slPoints * _Point / tickSize) * tickValue;

      if(lossPerLot > 0) lot = riskAmount / lossPerLot;
     }
   else
     {
      lot = (riskAmount / 1000.0) * 0.01; // Fallback dasar jika tanpa SL
     }

   // Validasi lot terhadap batas broker
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / stepLot) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| Kelola Trailing Stop Sesuai Persentase                            |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL    = PositionGetDouble(POSITION_SL);
         double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if(type == POSITION_TYPE_BUY)
           {
            double triggerPrice = openPrice * (1.0 + InpTrailTrigger / 100.0);
            if(currentPrice >= triggerPrice)
              {
               double newSL = currentPrice * (1.0 - InpTrailDistance / 100.0);
               double minStepPrice = currentSL * (1.0 + InpTrailStep / 100.0);

               if(newSL > currentSL && (currentSL == 0 || newSL >= minStepPrice))
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double triggerPrice = openPrice * (1.0 - InpTrailTrigger / 100.0);
            if(currentPrice <= triggerPrice)
              {
               double newSL = currentPrice * (1.0 + InpTrailDistance / 100.0);
               double minStepPrice = currentSL * (1.0 - InpTrailStep / 100.0);

               if((newSL < currentSL || currentSL == 0) && (currentSL == 0 || newSL <= minStepPrice))
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Memeriksa Posisi Terbuka Berdasarkan Symbol & Magic Number       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
