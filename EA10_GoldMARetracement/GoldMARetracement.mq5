//+------------------------------------------------------------------+
//|                                     Gold_MA_Retracement_EA.mq5   |
//|                                  Gold MA Retracement Strategy    |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Input Parameters
input group "=== Trade Settings ==="
input double          InpLots               = 0.0;     // Fixed Lot (Isi 0 jika ingin pakai Risk %)
input double          InpRiskPercent        = 0.5;     // Risk per Trade (%)
input double          InpRetracementPercent = 0.5;     // Retracement Level (%)
input double          InpSlPercent          = 0.5;     // Stop Loss (%)
input ulong           InpMagicNumber        = 101010;  // Magic Number

input group "=== Strategy Parameters ==="
input ENUM_TIMEFRAMES   InpTimeframe        = PERIOD_D1; // Timeframe D1
input int               InpMAPeriods        = 100;       // MA Period (100)
input ENUM_MA_METHOD    InpMAMethod         = MODE_SMA;  // MA Method
input ENUM_APPLIED_PRICE InpMAAppliedPrice  = PRICE_CLOSE; // Applied Price

//--- Global Variables
CTrade   trade;
int      g_handleMA = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi Handle Moving Average (100 D1)
   g_handleMA = iMA(_Symbol, InpTimeframe, InpMAPeriods, 0, InpMAMethod, InpMAAppliedPrice);
   if(g_handleMA == INVALID_HANDLE)
     {
      Print("Gagal membuat handle Moving Average!");
      return(INIT_FAILED);
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
   // 1. Pembacaan Indikator MA
   double maVal[];
   ArraySetAsSeries(maVal, true);
   if(CopyBuffer(g_handleMA, 0, 0, 1, maVal) <= 0) return;

   // 2. Data Harga Candle D1 & Harga Realtime Saat Ini
   double close1 = iClose(_Symbol, InpTimeframe, 1);
   double open0  = iOpen(_Symbol, InpTimeframe, 0);
   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(open0 == 0 || curBid == 0) return;

   // 3. Filter Tren & Kondisi Retracement
   bool isUptrend     = (close1 > maVal[0]);
   bool isRetracement = (curBid <= (open0 - (InpRetracementPercent * open0 / 100.0)));

   // 4. Filter Eksekusi: Maksimal 1 Trade per Hari
   static datetime lastTradeDay = 0;
   datetime curDay = iTime(_Symbol, InpTimeframe, 0);

   // 5. Eksekusi Buy Order
   if(isUptrend && isRetracement && PositionsTotal() == 0 && lastTradeDay != curDay)
     {
      double askPrice   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDistance = askPrice * (InpSlPercent / 100.0);
      double slPrice    = NormalizeDouble(askPrice - slDistance, _Digits);

      double lotSize = (InpLots > 0) ? InpLots : CalculateLots(slDistance);

      if(lotSize > 0)
        {
         if(trade.Buy(lotSize, _Symbol, askPrice, slPrice, 0.0, "Gold_MA_Retracement_Buy"))
           {
            lastTradeDay = curDay; // Mengunci agar tidak membuka order ganda pada hari yang sama
            Print("Buy Order Berhasil Dieksekusi pada Harga: ", askPrice);
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
