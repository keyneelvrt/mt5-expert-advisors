//+------------------------------------------------------------------+
//|                                           SilverBulletEA_YT.mq5  |
//|                                 Created based on René Balke Video|
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Class untuk Menyimpan dan Menggambar Fair Value Gap (FVG)
class CFairValueGap : public CObject
  {
public:
   int      direction; // 1 = Up (Bullish), -1 = Down (Bearish)
   datetime time;
   double   high;
   double   low;

   void Draw(datetime timeStart, datetime timeEnd)
     {
      string fvgName = "SilverBullet_FVG_" + TimeToString(time);
      ObjectCreate(0, fvgName, OBJ_RECTANGLE, 0, time, low, timeStart, high);
      ObjectSetInteger(0, fvgName, OBJPROP_FILL, true);
      ObjectSetInteger(0, fvgName, OBJPROP_COLOR, clrLightGray);

      string tradeArea = "SilverBullet_Trade_" + TimeToString(time);
      ObjectCreate(0, tradeArea, OBJ_RECTANGLE, 0, timeStart, low, timeEnd, high);
      ObjectSetInteger(0, tradeArea, OBJPROP_FILL, true);
      ObjectSetInteger(0, tradeArea, OBJPROP_COLOR, clrGray);
     }

   void DrawTradeLevels(datetime timeStart, datetime timeEnd, double tp, double sl)
     {
      string tpName = "SilverBullet_TP_" + TimeToString(time);
      ObjectCreate(0, tpName, OBJ_RECTANGLE, 0, timeStart, (direction > 0 ? high : low), timeEnd, tp);
      ObjectSetInteger(0, tpName, OBJPROP_FILL, true);
      ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrLightGreen);

      string slName = "SilverBullet_SL_" + TimeToString(time);
      ObjectCreate(0, slName, OBJ_RECTANGLE, 0, timeStart, (direction > 0 ? low : high), timeEnd, sl);
      ObjectSetInteger(0, slName, OBJPROP_FILL, true);
      ObjectSetInteger(0, slName, OBJPROP_COLOR, clrOrange);
     }
  };

//--- Input Parameters
input group "=== Trade Settings ==="
input double          InpLots             = 0.0;     // Fixed Lot (Isi 0 jika pakai Risk %)
input double          InpRiskPercent      = 0.5;     // Risk per Trade (%)
input double          InpMinTpPoints      = 150;     // Minimum TP (Points)
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5; // Timeframe Pencarian FVG
input ulong           InpMagicNumber      = 777123;

input group "=== Session Time Settings ==="
input int             InpStartHour        = 3;       // Start Hour (New York / Session Time)
input int             InpEndHour          = 4;       // End Hour

//--- Global Variables
CTrade         trade;
CFairValueGap *fvg = NULL;
int            lastDay = -1;

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
   ObjectsDeleteAll(0, "SilverBullet");
   if(CheckPointer(fvg) != POINTER_INVALID)
      delete fvg;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   MqlDateTime structTime;
   TimeToStruct(TimeCurrent(), structTime);

   // Tentukan Waktu Mulai & Selesai Jendela Silver Bullet
   structTime.sec = 0;
   structTime.min = 0;
   
   structTime.hour = InpStartHour;
   datetime timeStart = StructToTime(structTime);
   
   structTime.hour = InpEndHour;
   datetime timeEnd = StructToTime(structTime);

   datetime now = TimeCurrent();

   // 1. FILTER WAKTU SESI (Trading Window)
   if(now >= timeStart && now <= timeEnd)
     {
      // Hanya eksekusi 1 pencarian per hari
      if(lastDay != structTime.day_of_year)
        {
         if(CheckPointer(fvg) != POINTER_INVALID)
           {
            delete fvg;
            fvg = NULL;
           }

         // Scan 100 candle ke belakang di timeframe internal untuk mencari FVG
         for(int i = 1; i < 100; i++)
           {
            double low0  = iLow(_Symbol, InpTimeframe, i);
            double high2 = iHigh(_Symbol, InpTimeframe, i + 2);

            // Bullish FVG
            if((low0 - high2) > InpMinTpPoints * _Point)
              {
               fvg = new CFairValueGap();
               fvg.direction = 1;
               fvg.time      = iTime(_Symbol, InpTimeframe, i + 1);
               fvg.high      = low0;
               fvg.low       = high2;
               break;
              }

            double high0 = iHigh(_Symbol, InpTimeframe, i);
            double low2  = iLow(_Symbol, InpTimeframe, i + 2);

            // Bearish FVG
            if((low2 - high0) > InpMinTpPoints * _Point)
              {
               fvg = new CFairValueGap();
               fvg.direction = -1;
               fvg.time      = iTime(_Symbol, InpTimeframe, i + 1);
               fvg.high      = low2;
               fvg.low       = high0;
               break;
              }
           }

         // Jika FVG Ditemukan, Validasi apakah harga sudah terlanjur menembus FVG
         if(CheckPointer(fvg) != POINTER_INVALID)
           {
            if(fvg.direction == 1)
              {
               int lowestIdx = iLowest(_Symbol, InpTimeframe, MODE_LOW, 10, 0);
               if(iLow(_Symbol, InpTimeframe, lowestIdx) <= fvg.low)
                 {
                  delete fvg;
                  fvg = NULL;
                 }
               else
                 {
                  fvg.Draw(timeStart, timeEnd);
                  lastDay = structTime.day_of_year;
                 }
              }
            else if(fvg.direction == -1)
              {
               int highestIdx = iHighest(_Symbol, InpTimeframe, MODE_HIGH, 10, 0);
               if(iHigh(_Symbol, InpTimeframe, highestIdx) >= fvg.high)
                 {
                  delete fvg;
                  fvg = NULL;
                 }
               else
                 {
                  fvg.Draw(timeStart, timeEnd);
                  lastDay = structTime.day_of_year;
                 }
              }
           }
        }
     }

   // 2. LOGIKA ENTRY TRADE SAAT HARGA RETEST FVG
   if(CheckPointer(fvg) != POINTER_INVALID)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // --- BUY SETUP ---
      if(fvg.direction == 1 && ask <= fvg.high)
        {
         int highIdx = iHighest(_Symbol, InpTimeframe, MODE_HIGH, 20, 0);
         double tp   = iHigh(_Symbol, InpTimeframe, highIdx);
         
         int lowIdx  = iLowest(_Symbol, InpTimeframe, MODE_LOW, 5, 0);
         double sl   = iLow(_Symbol, InpTimeframe, lowIdx);

         if((tp - ask) >= InpMinTpPoints * _Point)
           {
            double lots = (InpLots > 0) ? InpLots : CalculateLots(ask - sl);
            if(lots > 0)
              {
               fvg.DrawTradeLevels(timeStart, timeEnd, tp, sl);
               trade.Buy(lots, _Symbol, ask, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "ICT_SilverBullet_Buy");
              }
           }
         // Hapus FVG agar tidak terjadi multiple trade di hari yang sama
         delete fvg;
         fvg = NULL;
        }
      // --- SELL SETUP ---
      else if(fvg.direction == -1 && bid >= fvg.low)
        {
         int lowIdx  = iLowest(_Symbol, InpTimeframe, MODE_LOW, 20, 0);
         double tp   = iLow(_Symbol, InpTimeframe, lowIdx);

         int highIdx = iHighest(_Symbol, InpTimeframe, MODE_HIGH, 5, 0);
         double sl   = iHigh(_Symbol, InpTimeframe, highIdx);

         if((bid - tp) >= InpMinTpPoints * _Point)
           {
            double lots = (InpLots > 0) ? InpLots : CalculateLots(sl - bid);
            if(lots > 0)
              {
               fvg.DrawTradeLevels(timeStart, timeEnd, tp, sl);
               trade.Sell(lots, _Symbol, bid, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), "ICT_SilverBullet_Sell");
              }
           }
         delete fvg;
         fvg = NULL;
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Kalkulasi Variable Lot Size berdasarkan Risk %           |
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
