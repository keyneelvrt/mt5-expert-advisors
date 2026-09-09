//+------------------------------------------------------------------+
//|                                   Claude_MA_Crossover_EA.mq5     |
//|                                 Generated based on Video Concept |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Enums untuk Lot Management
enum ENUM_LOT_TYPE
  {
   LOT_FIXED,   // Fixed Lot Size
   LOT_RISK     // Risk in Money Amount ($)
  };

//--- Input Parameters (Sesuai Spesifikasi Transkrip Video)
input group "=== Trade Settings ==="
input ENUM_LOT_TYPE InpLotType     = LOT_RISK;    // Lot Calculation Type
input double        InpFixedLot    = 0.01;        // Fixed Lot Size
input double        InpRiskMoney   = 100.0;       // Risk Amount in Money ($)
input ulong         InpMagicNumber = 123456;      // Magic Number

input group "=== Stop Loss & Take Profit (In Points) ==="
input double        InpStopLoss    = 200;         // Stop Loss (Points, 0 = Disabled)
input double        InpTakeProfit  = 400;         // Take Profit (Points, 0 = Disabled)
input double        InpTrailingStop= 100;         // Trailing Stop Distance (Points, 0 = Disabled)

input group "=== Fast Moving Average Settings ==="
input int                  InpFastMAPeriod = 10;           // Fast MA Period
input int                  InpFastMAShift  = 0;            // Fast MA Shift
input ENUM_MA_METHOD       InpFastMAMethod = MODE_SMA;     // Fast MA Method
input ENUM_APPLIED_PRICE   InpFastMAPrice  = PRICE_CLOSE;  // Fast MA Applied Price

input group "=== Slow Moving Average Settings ==="
input int                  InpSlowMAPeriod = 20;           // Slow MA Period
input int                  InpSlowMAShift  = 0;            // Slow MA Shift
input ENUM_MA_METHOD       InpSlowMAMethod = MODE_SMA;     // Slow MA Method
input ENUM_APPLIED_PRICE   InpSlowMAPrice  = PRICE_CLOSE;  // Slow MA Applied Price

//--- Global Variables
CTrade         trade;
int            handleFastMA;
int            handleSlowMA;
datetime       lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Set Magic Number untuk isolasi transaksi
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi Handles Indikator MA
   handleFastMA = iMA(_Symbol, _Period, InpFastMAPeriod, InpFastMAShift, InpFastMAMethod, InpFastMAPrice);
   handleSlowMA = iMA(_Symbol, _Period, InpSlowMAPeriod, InpSlowMAShift, InpSlowMAMethod, InpSlowMAPrice);

   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE)
     {
      Print("Error: Gagal menginisialisasi indikator Moving Average.");
      return(INIT_FAILED);
     }

   lastBarTime = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleFastMA != INVALID_HANDLE) IndicatorRelease(handleFastMA);
   if(handleSlowMA != INVALID_HANDLE) IndicatorRelease(handleSlowMA);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Trailing Stop dijalankan pada setiap tick
   if(InpTrailingStop > 0)
      ApplyTrailingStop();

   // 2. Filter Bar Baru (Logika Entry/Cross hanya dieksekusi saat bar ditutup)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
      return;

   // Pembacaan Nilai MA untuk Bar 1 (tertutup) dan Bar 2
   double fastMA[];
   double slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(handleFastMA, 0, 1, 2, fastMA) < 2 ||
      CopyBuffer(handleSlowMA, 0, 1, 2, slowMA) < 2)
      return;

   // 3. Deteksi Crossover
   bool buySignal  = (fastMA[1] > slowMA[1]) && (fastMA[0] <= slowMA[0]); // Fast MA memotong Slow MA ke atas
   bool sellSignal = (fastMA[1] < slowMA[1]) && (fastMA[0] >= slowMA[0]); // Fast MA memotong Slow MA ke bawah

   if(buySignal)
     {
      lastBarTime = currentBarTime;
      ClosePositions(POSITION_TYPE_SELL); // Tutup posisi berlawanan (Sell) jika ada

      if(!HasOpenPosition(POSITION_TYPE_BUY))
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl  = (InpStopLoss > 0) ? ask - (InpStopLoss * _Point) : 0;
         double tp  = (InpTakeProfit > 0) ? ask + (InpTakeProfit * _Point) : 0;
         double lot = CalculateLotSize(InpStopLoss);

         trade.Buy(lot, _Symbol, ask, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "MA_Cross_Buy");
        }
     }
   else if(sellSignal)
     {
      lastBarTime = currentBarTime;
      ClosePositions(POSITION_TYPE_BUY); // Tutup posisi berlawanan (Buy) jika ada

      if(!HasOpenPosition(POSITION_TYPE_SELL))
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl  = (InpStopLoss > 0) ? bid + (InpStopLoss * _Point) : 0;
         double tp  = (InpTakeProfit > 0) ? bid - (InpTakeProfit * _Point) : 0;
         double lot = CalculateLotSize(InpStopLoss);

         trade.Sell(lot, _Symbol, bid, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "MA_Cross_Sell");
        }
     }
  }

//+------------------------------------------------------------------+
//| Perhitungan Ukuran Lot Sesuai Risiko $ Nominal                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
  {
   if(InpLotType == LOT_FIXED)
      return InpFixedLot;

   double lot = InpFixedLot;
   if(slPoints > 0)
     {
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lossPerLot = (slPoints * _Point / tickSize) * tickValue;

      if(lossPerLot > 0)
         lot = InpRiskMoney / lossPerLot;
     }

   // Penyesuaian ke batas lot instrumen broker
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / stepLot) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| Menutup Posisi Berdasarkan Tipe Posisi                            |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE posType)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetInteger(POSITION_TYPE) == posType)
        {
         trade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Memeriksa Apakah Ada Posisi Aktif                                |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE posType)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetInteger(POSITION_TYPE) == posType)
        {
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Logika Trailing Stop Berbasis Points                             |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
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

         if(type == POSITION_TYPE_BUY)
           {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(bid - openPrice > InpTrailingStop * _Point)
              {
               double newSL = bid - (InpTrailingStop * _Point);
               if(newSL > currentSL + _Point)
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(openPrice - ask > InpTrailingStop * _Point)
              {
               double newSL = ask + (InpTrailingStop * _Point);
               if(newSL < currentSL - _Point || currentSL == 0)
                 {
                  trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
