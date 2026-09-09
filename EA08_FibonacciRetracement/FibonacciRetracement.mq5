//+------------------------------------------------------------------+
//|                                                  FiboTrader.mq5  |
//|                                  Created based on René Balke EA  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Input Parameters
input group "=== Trade Settings ==="
input double   InpLots              = 0.0;     // Fixed Lot (Isi 0 jika ingin pakai Risk %)
input double   InpRiskPercent       = 0.5;     // Risk per Trade (%)
input double   InpRetracementLevel  = 61.8;    // Retracement Level (%)
input int      InpSlPoints          = 1000;    // Stop Loss (Points)
input int      InpTpPoints          = 1500;    // Take Profit (Points)
input int      InpExpirationHours   = 15;      // Expiration (Hours)
input ulong    InpMagicNumber       = 555888;

//--- Global Variables
CTrade         trade;
string         g_fiboObjectName     = "FiboRetracement_Rene";
int            g_barsTotal          = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, g_fiboObjectName);
  }

//+------------------------------------------------------------------+
//| Fungsi Kalkulasi Dynamic Lot Size Berdasarkan Risk %              |
//| (dipindah ke atas OnTick supaya sudah "dikenal" saat dipanggil)   |
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Hitung jumlah bar daily untuk deteksi pergantian hari
   int bars = iBars(_Symbol, PERIOD_D1);
   if(bars == 0) return;

   if(g_barsTotal != bars)
     {
      // Pastikan eksekusi dilakukan setelah pasar buka (5 menit pasca midnight)
      if(TimeCurrent() < StringToTime("00:05")) return;

      g_barsTotal = bars;

      // 1. Hapus Objek Fibonacci Lama
      ObjectDelete(0, g_fiboObjectName);

      // 2. Ambil Data Candle Daily Sebelumnya (Shift 1)
      double openPrev  = iOpen(_Symbol, PERIOD_D1, 1);
      double closePrev = iClose(_Symbol, PERIOD_D1, 1);
      double highPrev  = iHigh(_Symbol, PERIOD_D1, 1);
      double lowPrev   = iLow(_Symbol, PERIOD_D1, 1);

      datetime timeStart = iTime(_Symbol, PERIOD_D1, 1);
      datetime timeEnd   = iTime(_Symbol, PERIOD_D1, 0) - 1;

      // 3. Buat Objek Visual Fibonacci Retracement di Chart
      bool isBullish = (closePrev > openPrev);

      if(isBullish)
         ObjectCreate(0, g_fiboObjectName, OBJ_FIBO, 0, timeStart, lowPrev, timeEnd, highPrev);
      else
         ObjectCreate(0, g_fiboObjectName, OBJ_FIBO, 0, timeStart, highPrev, timeEnd, lowPrev);

      // Format Tampilan Garis Fibonacci (Warna Hitam)
      ObjectSetInteger(0, g_fiboObjectName, OBJPROP_COLOR, clrBlack);
      int levelsCount = (int)ObjectGetInteger(0, g_fiboObjectName, OBJPROP_LEVELS);
      for(int i = 0; i < levelsCount; i++)
        {
         // FIX: nama konstanta yang benar adalah OBJPROP_LEVELCOLOR (tanpa underscore)
         ObjectSetInteger(0, g_fiboObjectName, OBJPROP_LEVELCOLOR, i, clrBlack);
        }

      // 4. Kalkulasi Entry Price berdasarkan Level Retracement
      double entryPrice = 0.0;
      double slPrice    = 0.0;
      double tpPrice    = 0.0;

      if(isBullish)
        {
         // Bullish Day -> Pasang BUY LIMIT pada level retracement
         entryPrice = highPrev - ((highPrev - lowPrev) * (InpRetracementLevel / 100.0));
         entryPrice = NormalizeDouble(entryPrice, _Digits);

         slPrice = NormalizeDouble(entryPrice - (InpSlPoints * _Point), _Digits);
         tpPrice = NormalizeDouble(entryPrice + (InpTpPoints * _Point), _Digits);

         double lotSize = (InpLots > 0) ? InpLots : CalculateLots(entryPrice - slPrice);
         datetime expiration = iTime(_Symbol, PERIOD_D1, 0) + (InpExpirationHours * PeriodSeconds(PERIOD_H1));

         if(lotSize > 0)
           {
            trade.BuyLimit(lotSize, entryPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expiration, "Fibo_Buy_Limit");
            Print("Buy Limit Order Sent at: ", entryPrice);
           }
        }
      else
        {
         // Bearish Day -> Pasang SELL LIMIT pada level retracement
         entryPrice = lowPrev + ((highPrev - lowPrev) * (InpRetracementLevel / 100.0));
         entryPrice = NormalizeDouble(entryPrice, _Digits);

         slPrice = NormalizeDouble(entryPrice + (InpSlPoints * _Point), _Digits);
         tpPrice = NormalizeDouble(entryPrice - (InpTpPoints * _Point), _Digits);

         double lotSize = (InpLots > 0) ? InpLots : CalculateLots(slPrice - entryPrice);
         datetime expiration = iTime(_Symbol, PERIOD_D1, 0) + (InpExpirationHours * PeriodSeconds(PERIOD_H1));

         if(lotSize > 0)
           {
            trade.SellLimit(lotSize, entryPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expiration, "Fibo_Sell_Limit");
            Print("Sell Limit Order Sent at: ", entryPrice);
           }
        }
     }
  }
//+------------------------------------------------------------------+
