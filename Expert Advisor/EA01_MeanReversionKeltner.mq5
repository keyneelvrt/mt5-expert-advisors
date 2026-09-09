//+------------------------------------------------------------------+
//|                                     KeltnerChannelEA_YT.mq5      |
//|                                Created based on René Balke Video |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Input Parameters (Persis Sesuai Video)
input group "=== Trade Settings ==="
input double   Lots         = 0.1;
input double   TpPoints     = 500;
input double   SlPoints     = 2000;
input ulong    Magic        = 112314;

input group "=== Keltner Channel Settings ==="
input ENUM_TIMEFRAMES Timeframe      = PERIOD_H1;
input int            K_EmaPeriod    = 20;
input int            K_AtrPeriod    = 10;
input double         K_AtrMultiplier= 2.0;

//--- Global Variables
CTrade   trade;
int      handleKeltner;
datetime timeStamp;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(Magic);

   // Memanggil Keltner Channel bawaan dari folder "free indicators" MT5
   handleKeltner = iCustom(_Symbol, Timeframe, "free indicators/Keltner Channel.ex5", 
                           K_EmaPeriod, K_AtrPeriod, K_AtrMultiplier, false);

   if(handleKeltner == INVALID_HANDLE)
     {
      Print("Error: Gagal menginisialisasi Keltner Channel Indicator!");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handleKeltner != INVALID_HANDLE)
      IndicatorRelease(handleKeltner);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. New Bar Filter (Hanya jalan 1x di awal candle baru)
   datetime currentTime = iTime(_Symbol, Timeframe, 0);
   if(timeStamp == currentTime)
      return;
   
   timeStamp = currentTime;

   // 2. Mengambil Buffer Keltner Channel
   // Buffer 0 = Upper Line, Buffer 1 = Middle Line, Buffer 2 = Lower Line
   double kUp[], kDown[];
   ArraySetAsSeries(kUp, true);
   ArraySetAsSeries(kDown, true);

   if(CopyBuffer(handleKeltner, 0, 1, 2, kUp) < 2) return;   // Upper Keltner (Bar 1 & 2)
   if(CopyBuffer(handleKeltner, 2, 1, 2, kDown) < 2) return; // Lower Keltner (Bar 1 & 2)

   // 3. Mengambil Harga Close Bar Sebelumnya
   double close1 = iClose(_Symbol, Timeframe, 1); // Close bar kemarin
   double close2 = iClose(_Symbol, Timeframe, 2); // Close bar 2 hari lalu

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- STRATEGI MEAN REVERSION (RETEST / GO BACK INSIDE CHANNEL) ---

   // 4. Signal SELL:
   // Bar 2 close di luar (di atas Upper Channel), Bar 1 close kembali masuk ke dalam channel
   if(close2 > kUp[1] && close1 < kUp[0])
     {
      double sl = bid + (SlPoints * _Point);
      double tp = bid - (TpPoints * _Point);

      if(trade.Sell(Lots, _Symbol, bid, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "Keltner_Sell"))
        {
         Print(__FUNCTION__, " > Sell Order Executed!");
        }
     }

   // 5. Signal BUY:
   // Bar 2 close di luar (di bawah Lower Channel), Bar 1 close kembali masuk ke dalam channel
   if(close2 < kDown[1] && close1 > kDown[0])
     {
      double sl = ask - (SlPoints * _Point);
      double tp = ask + (TpPoints * _Point);

      if(trade.Buy(Lots, _Symbol, ask, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "Keltner_Buy"))
        {
         Print(__FUNCTION__, " > Buy Order Executed!");
        }
     }
  }
//+------------------------------------------------------------------+
