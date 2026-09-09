//+------------------------------------------------------------------+
//|                                     TurnaroundTuesday_YT.mq5     |
//|                                  Created based on René Balke EA  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Input Parameters
input group "=== Trade Settings ==="
input double            InpLots              = 0.0;     // Fixed Lot (Isi 0 jika ingin pakai Risk %)
input double            InpRiskPercent       = 0.5;     // Risk per Trade (%)
input double            InpStopLossPercent   = 5.0;     // Emergency Stop Loss (% dari Harga)
input ulong             InpMagicNumber       = 999333;

input group "=== Session & Time Settings ==="
input ENUM_TIMEFRAMES   InpTimeframe         = PERIOD_M1; // Base execution timeframe
input int               InpTimeOpenHour      = 22;      // Open Hour (Monday)
input int               InpTimeOpenMinute    = 55;      // Open Minute
input int               InpTimeCloseHour     = 22;      // Close Hour (Tuesday)
input int               InpTimeCloseMinute   = 55;      // Close Minute
input int               InpDayOpen           = 1;       // 1 = Monday
input int               InpDayClose          = 2;       // 2 = Tuesday

input group "=== Moving Average Filter ==="
input bool              InpUseMAFilter       = true;    // Use MA Filter
input ENUM_TIMEFRAMES   InpMATimeframe       = PERIOD_D1; // MA Timeframe
input int               InpMAPeriods         = 24;      // MA Period
input ENUM_MA_METHOD    InpMAMethod          = MODE_SMA; // MA Method
input ENUM_APPLIED_PRICE InpMAAppliedPrice   = PRICE_CLOSE; // Applied Price

//--- Global Variables
CTrade                  trade;
int                     g_handleMA           = INVALID_HANDLE;
int                     g_barsTotal          = 0;
int                     g_lastDay            = -1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi Handle Moving Average
   if(InpUseMAFilter)
     {
      g_handleMA = iMA(_Symbol, InpMATimeframe, InpMAPeriods, 0, InpMAMethod, InpMAAppliedPrice);
      if(g_handleMA == INVALID_HANDLE)
        {
         Print("Error initializing MA Handle");
         return(INIT_FAILED);
        }
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handleMA != INVALID_HANDLE)
      IndicatorRelease(g_handleMA);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Hanya jalankan logika sekali per bar pada timeframe M1
   int bars = iBars(_Symbol, InpTimeframe);
   if(bars == g_barsTotal) return;
   g_barsTotal = bars;

   // Persiapan struktur waktu saat ini
   MqlDateTime dt;
   datetime currentTime = TimeCurrent();
   TimeToStruct(currentTime, dt);

   // 1. CEK CLOSING POSITION (Selasa Malam @ 22:55)
   if(dt.day_of_week == InpDayClose)
     {
      dt.hour   = InpTimeCloseHour;
      dt.min    = InpTimeCloseMinute;
      dt.sec    = 0;
      datetime timeClose = StructToTime(dt);

      if(currentTime >= timeClose)
        {
         CloseAllPositions();
        }
     }

   // 2. CEK OPENING POSITION (Senin Malam @ 22:55)
   if(dt.day_of_week == InpDayOpen && g_lastDay != dt.day_of_year)
     {
      dt.hour   = InpTimeOpenHour;
      dt.min    = InpTimeOpenMinute;
      dt.sec    = 0;
      datetime timeOpen = StructToTime(dt);

      if(currentTime >= timeOpen)
        {
         double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         bool maCondition = true;

         // Cek apakah harga berada di bawah Moving Average Daily
         if(InpUseMAFilter && g_handleMA != INVALID_HANDLE)
           {
            double maVal[];
            ArraySetAsSeries(maVal, true);
            if(CopyBuffer(g_handleMA, 0, 0, 1, maVal) > 0)
              {
               if(bidPrice >= maVal[0])
                  maCondition = false; // Batal entry jika harga tidak di bawah MA
              }
           }

         // Eksekusi Buy jika semua kondisi terpenuhi
         if(maCondition && PositionsTotal() == 0)
           {
            double slDistance = askPrice * (InpStopLossPercent / 100.0);
            double slPrice    = NormalizeDouble(askPrice - slDistance, _Digits);

            double lotSize    = (InpLots > 0) ? InpLots : CalculateLots(slDistance);

            if(lotSize > 0)
              {
               if(trade.Buy(lotSize, _Symbol, askPrice, slPrice, 0.0, "Turnaround_Tuesday_Buy"))
                 {
                  Print("Turnaround Tuesday Order Opened Successfully.");
                  g_lastDay = dt.day_of_year; // Mencegah re-entry pada hari yang sama
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Menutup Semua Posisi Terbuka                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            trade.PositionClose(ticket);
            Print("Turnaround Tuesday Position Closed.");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Kalkulasi Dynamic Lot Size Berdasarkan Risk %             |
//+------------------------------------------------------------------+
double CalculateLots(double slDistance)
  {
   if(slDistance <= 0) return 0.01;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0) return 0.01;

   double moneyPerLot = (slDistance / tickSize) * tickValue;
   if(moneyPerLot == 0) return 0.01;

   double lots = NormalizeDouble(riskMoney / moneyPerLot, 2);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   return MathMin(MathMax(lots, minLot), maxLot);
  }
//+------------------------------------------------------------------+
