//+------------------------------------------------------------------+
//|                                                 Fisherman_EA.mq5 |
//|                                Copyright 2026, Rene / MQL5 Style |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Fisherman EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_LOT_MODE
  {
   LOT_MODE_FIXED,   // Fixed Lot
   LOT_MODE_MANAGED, // Managed Lot (per $1,000 Balance)
   LOT_MODE_PERCENT  // Risk Percent (% Balance)
  };

//--- Input Parameters
input group "=== Volume Settings ==="
input ENUM_LOT_MODE InpLotMode      = LOT_MODE_MANAGED; // Lot Management Mode
input double        InpFixedLot     = 0.01;             // Fixed Lot Size
input double        InpManagedStep  = 1000.0;           // Account Step for Managed Lot (e.g. 1000)
input double        InpRiskPercent  = 1.0;              // Risk Percent (%)

input group "=== Order Settings ==="
input ENUM_TIMEFRAMES InpSignalTF   = PERIOD_D1;        // Timeframe for Signals (Bar Retracement)
input double        InpRetracePct   = 0.5;              // Retracement Percent (%)
input double        InpTPPercent    = 1.0;              // Take Profit Percent (0 = Disabled)
input double        InpSLPercent    = 0.5;              // Stop Loss Percent (0 = Disabled)

input group "=== Time Close Settings ==="
input bool          InpUseTimeClose = true;             // Enable Time Close
input int           InpCloseHour    = 22;               // Close Hour (0-23)
input int           InpCloseMinute  = 0;                // Close Minute (0-59)

input group "=== Break Even & Trailing Settings ==="
input double        InpBETriggerPct = 0.3;              // Break Even Trigger Percent (0 = Disabled)
input int           InpBEBufferPts  = 10;               // Break Even Buffer Points
input double        InpTrailPct     = 0.2;              // Trailing Stop Percent (0 = Disabled)

input group "=== Direction & Filters ==="
input bool          InpAllowBuy     = true;             // Allow Buy Trades
input bool          InpAllowSell    = true;             // Allow Sell Trades

input group "=== Moving Average Filter ==="
input bool          InpUseMA        = true;             // Enable MA Filter
input ENUM_TIMEFRAMES InpMATimeframe= PERIOD_D1;        // MA Timeframe
input int           InpMAPeriod     = 200;              // MA Period
input ENUM_MA_METHOD InpMAMethod    = MODE_SMA;         // MA Method
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;      // MA Applied Price

input group "=== RSI Filter ==="
input bool          InpUseRSI       = true;             // Enable RSI Filter
input ENUM_TIMEFRAMES InpRSITimeframe= PERIOD_H4;       // RSI Timeframe
input int           InpRSIPeriod    = 14;               // RSI Period
input ENUM_APPLIED_PRICE InpRSIPrice= PRICE_CLOSE;      // RSI Applied Price
input double        InpRSILevel     = 40.0;             // RSI Level (e.g. 40 -> Buy < 40, Sell > 60)

input group "=== System Settings ==="
input string        InpOrderComment = "Fisherman EA";   // Order Comment
input ulong         InpMagicNumber  = 123456;           // Magic Number
input color         InpCommentColor = clrYellow;        // Chart Comment Color
input bool          InpShowComment  = true;             // Show On-Screen Comment

//--- Global Variables
CTrade         trade;
int            handleMA;
int            handleRSI;
datetime       lastTradeBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi Indicator MA
   if(InpUseMA)
     {
      handleMA = iMA(_Symbol, InpMATimeframe, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
      if(handleMA == INVALID_HANDLE)
        {
         Print("Gagal menginisialisasi indikator MA!");
         return(INIT_FAILED);
        }
     }

   // Inisialisasi Indicator RSI
   if(InpUseRSI)
     {
      handleRSI = iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, InpRSIPrice);
      if(handleRSI == INVALID_HANDLE)
        {
         Print("Gagal menginisialisasi indikator RSI!");
         return(INIT_FAILED);
        }
     }

   lastTradeBarTime = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleMA != INVALID_HANDLE) IndicatorRelease(handleMA);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Eksekusi Time-based Close jika diaktifkan
   if(InpUseTimeClose)
     {
      CheckTimeClose();
     }

   // 2. Eksekusi Break Even dan Trailing Stop
   ManagePositions();

   // 3. Tampilkan Komentar di Chart
   if(InpShowComment)
     {
      UpdateComment();
     }

   // 4. Cek apakah sudah ada posisi aktif dengan Magic Number ini
   if(HasOpenPosition()) return;

   // 5. Cek Kondisi Signal & Filter
   bool maBuyOK = true, maSellOK = true;
   if(InpUseMA) CheckMAFilter(maBuyOK, maSellOK);

   bool rsiBuyOK = true, rsiSellOK = true;
   if(InpUseRSI) CheckRSIFilter(rsiBuyOK, rsiSellOK);

   // Filter Arah
   bool canBuy  = InpAllowBuy && maBuyOK && rsiBuyOK;
   bool canSell = InpAllowSell && maSellOK && rsiSellOK;

   if(!canBuy && !canSell) return;

   // 6. Cek Retracement pada Candle Aktif Signal Timeframe
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, 1, rates) < 1) return;

   datetime currentBarTime = rates[0].time;
   if(currentBarTime == lastTradeBarTime) return; // Maksimal 1 trade per bar signal

   double openPrice = rates[0].open;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Hitung Retracement
   // Drop/Retracement untuk BUY (Harga turun dari Open)
   double dropPct = (openPrice - ask) / openPrice * 100.0;
   // Rise/Retracement untuk SELL (Harga naik dari Open)
   double risePct = (bid - openPrice) / openPrice * 100.0;

   // 7. Eksekusi Perintah Trade
   if(canBuy && dropPct >= InpRetracePct)
     {
      double lot = CalculateLotSize(InpSLPercent);
      double sl = (InpSLPercent > 0) ? ask * (1.0 - InpSLPercent / 100.0) : 0;
      double tp = (InpTPPercent > 0) ? ask * (1.0 + InpTPPercent / 100.0) : 0;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.Buy(lot, _Symbol, ask, sl, tp, InpOrderComment))
        {
         lastTradeBarTime = currentBarTime;
        }
     }
   else if(canSell && risePct >= InpRetracePct)
     {
      double lot = CalculateLotSize(InpSLPercent);
      double sl = (InpSLPercent > 0) ? bid * (1.0 + InpSLPercent / 100.0) : 0;
      double tp = (InpTPPercent > 0) ? bid * (1.0 - InpTPPercent / 100.0) : 0;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.Sell(lot, _Symbol, bid, sl, tp, InpOrderComment))
        {
         lastTradeBarTime = currentBarTime;
        }
     }
  }

//+------------------------------------------------------------------+
//| Cek Filter Moving Average (Diambil dari Bar 1 yang sudah tertutup)|
//+------------------------------------------------------------------+
void CheckMAFilter(bool &buyAllowed, bool &sellAllowed)
  {
   buyAllowed = false;
   sellAllowed = false;

   double maVal[];
   MqlRates rates[];
   ArraySetAsSeries(maVal, true);
   ArraySetAsSeries(rates, true);

   if(CopyBuffer(handleMA, 0, 1, 1, maVal) > 0 && CopyRates(_Symbol, InpMATimeframe, 1, 1, rates) > 0)
     {
      double closeBar1 = rates[0].close;
      if(closeBar1 > maVal[0]) buyAllowed = true;
      if(closeBar1 < maVal[0]) sellAllowed = true;
     }
  }

//+------------------------------------------------------------------+
//| Cek Filter RSI (Diambil dari Bar 1 yang sudah tertutup)          |
//+------------------------------------------------------------------+
void CheckRSIFilter(bool &buyAllowed, bool &sellAllowed)
  {
   buyAllowed = false;
   sellAllowed = false;

   double rsiVal[];
   ArraySetAsSeries(rsiVal, true);

   if(CopyBuffer(handleRSI, 0, 1, 1, rsiVal) > 0)
     {
      double lowerLevel = InpRSILevel;
      double upperLevel = 100.0 - InpRSILevel;

      if(rsiVal[0] < lowerLevel) buyAllowed = true;
      if(rsiVal[0] > upperLevel) sellAllowed = true;
     }
  }

//+------------------------------------------------------------------+
//| Perhitungan Ukuran Lot                                           |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPercent)
  {
   double lot = InpFixedLot;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpLotMode == LOT_MODE_MANAGED)
     {
      lot = (balance / InpManagedStep) * InpFixedLot;
     }
   else if(InpLotMode == LOT_MODE_PERCENT)
     {
      double riskAmount = balance * (InpRiskPercent / 100.0);
      if(slPercent > 0)
        {
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double slPoints = (slPercent / 100.0) * SymbolInfoDouble(_Symbol, SYMBOL_ASK) / _Point;
         double lossPerLot = (slPoints * _Point / tickSize) * tickValue;

         if(lossPerLot > 0) lot = riskAmount / lossPerLot;
        }
     }

   // Normalisasi ukuran Lot sesuai aturan Broker
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / stepLot) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| Manajemen Break Even & Trailing Stop                             |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         // 1. Break Even
         if(InpBETriggerPct > 0)
           {
            if(type == POSITION_TYPE_BUY)
              {
               double beTriggerPrice = openPrice * (1.0 + InpBETriggerPct / 100.0);
               double targetSL = openPrice + (InpBEBufferPts * _Point);

               if(currentPrice >= beTriggerPrice && (currentSL < targetSL || currentSL == 0))
                 {
                  trade.PositionModify(ticket, NormalizeDouble(targetSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double beTriggerPrice = openPrice * (1.0 - InpBETriggerPct / 100.0);
               double targetSL = openPrice - (InpBEBufferPts * _Point);

               if(currentPrice <= beTriggerPrice && (currentSL > targetSL || currentSL == 0))
                 {
                  trade.PositionModify(ticket, NormalizeDouble(targetSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }

         // 2. Trailing Stop
         if(InpTrailPct > 0)
           {
            if(type == POSITION_TYPE_BUY)
              {
               double newSL = currentPrice * (1.0 - InpTrailPct / 100.0);
               if(newSL > currentSL + (_Point * 10)) // Geser jika ada peningkatan minimal
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double newSL = currentPrice * (1.0 + InpTrailPct / 100.0);
               if(newSL < currentSL - (_Point * 10) || currentSL == 0)
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Cek Penutupan Posisi Berdasarkan Waktu (Time Close)              |
//+------------------------------------------------------------------+
void CheckTimeClose()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.hour == InpCloseHour && dt.min >= InpCloseMinute)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Cek apakah ada posisi terbuka aktif                             |
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
//| Update Informasi di Kiri Atas Chart                              |
//+------------------------------------------------------------------+
void UpdateComment()
  {
   bool maBuyOK = true, maSellOK = true;
   if(InpUseMA) CheckMAFilter(maBuyOK, maSellOK);

   bool rsiBuyOK = true, rsiSellOK = true;
   if(InpUseRSI) CheckRSIFilter(rsiBuyOK, rsiSellOK);

   string msg = "=== Fisherman EA Status ===\n";
   msg += "MA Filter: " + (InpUseMA ? (maBuyOK ? "BUY ALLOWED" : (maSellOK ? "SELL ALLOWED" : "NEUTRAL")) : "DISABLED") + "\n";
   msg += "RSI Filter: " + (InpUseRSI ? (rsiBuyOK ? "BUY ALLOWED" : (rsiSellOK ? "SELL ALLOWED" : "NEUTRAL")) : "DISABLED") + "\n";
   msg += "Buy Status: " + ((InpAllowBuy && maBuyOK && rsiBuyOK) ? "ACTIVE" : "BLOCKED") + "\n";
   msg += "Sell Status: " + ((InpAllowSell && maSellOK && rsiSellOK) ? "ACTIVE" : "BLOCKED") + "\n";

   Comment(msg);
  }
//+------------------------------------------------------------------+
