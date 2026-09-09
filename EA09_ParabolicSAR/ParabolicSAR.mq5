//+------------------------------------------------------------------+
//|                                         Parabolic_SAR_Scalper.mq5|
//|                                  Parabolic SAR Scalping Strategy |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//--- Input Parameters
input group "=== Trade Settings ==="
input double   InpLotSize         = 0.1;       // Lot Volume
input int      InpStopLossPoints  = 200;       // Stop Loss (Points)
input int      InpTakeProfitPoints= 300;       // Take Profit (Points)
input ulong    InpMagicNumber     = 112233;    // Magic Number

input group "=== Indicator Settings ==="
input ENUM_TIMEFRAMES InpTimeframe= PERIOD_H1; // Timeframe Analisis
input double   InpSARStep         = 0.02;      // Parabolic SAR Step
input double   InpSARMaximum      = 0.2;       // Parabolic SAR Maximum

//--- Global Variables
CTrade         trade;
int            g_handleSAR        = INVALID_HANDLE;
int            g_barsTotal        = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Inisialisasi Handle Parabolic SAR
   g_handleSAR = iSAR(_Symbol, InpTimeframe, InpSARStep, InpSARMaximum);
   if(g_handleSAR == INVALID_HANDLE)
     {
      Print("Gagal membuat handle Parabolic SAR!");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Hapus handle dari memori saat EA dilepas
   if(g_handleSAR != INVALID_HANDLE)
      IndicatorRelease(g_handleSAR);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Filter: Hanya jalankan 1 kali per perubahan Bar (Mencegah Multiple Trade)
   int bars = iBars(_Symbol, InpTimeframe);
   if(bars == g_barsTotal || bars == 0) return;

   // 2. Ambil nilai buffer Parabolic SAR untuk 2 bar terakhir (Index 0 & 1)
   double sarValues[];
   ArraySetAsSeries(sarValues, true);
   if(CopyBuffer(g_handleSAR, 0, 0, 2, sarValues) < 2) return;

   // 3. Ambil data High dan Low candle untuk pembacaan sinyal
   double highCurrent  = iHigh(_Symbol, InpTimeframe, 0);
   double lowCurrent   = iLow(_Symbol, InpTimeframe, 0);
   double highPrevious = iHigh(_Symbol, InpTimeframe, 1);
   double lowPrevious  = iLow(_Symbol, InpTimeframe, 1);

   // Update total bar setelah data berhasil dibaca
   g_barsTotal = bars;

   // 4. Deteksi Sinyal Perubahan Arah Parabolic SAR
   
   // Buy Signal: Titik SAR pindah dari Atas High (Bar 1) ke Bawah Low (Bar 0)
   bool buySignal  = (sarValues[1] > highPrevious) && (sarValues[0] < lowCurrent);
   
   // Sell Signal: Titik SAR pindah dari Bawah Low (Bar 1) ke Atas High (Bar 0)
   bool sellSignal = (sarValues[1] < lowPrevious) && (sarValues[0] > highCurrent);

   // 5. Eksekusi Order
   if(buySignal)
     {
      double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slPrice  = (InpStopLossPoints > 0)   ? NormalizeDouble(askPrice - (InpStopLossPoints * _Point), _Digits) : 0;
      double tpPrice  = (InpTakeProfitPoints > 0) ? NormalizeDouble(askPrice + (InpTakeProfitPoints * _Point), _Digits) : 0;

      trade.Buy(InpLotSize, _Symbol, askPrice, slPrice, tpPrice, "SAR_Scalp_Buy");
      Print("Buy Executed at: ", askPrice);
     }
   else if(sellSignal)
     {
      double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slPrice  = (InpStopLossPoints > 0)   ? NormalizeDouble(bidPrice + (InpStopLossPoints * _Point), _Digits) : 0;
      double tpPrice  = (InpTakeProfitPoints > 0) ? NormalizeDouble(bidPrice - (InpTakeProfitPoints * _Point), _Digits) : 0;

      trade.Sell(InpLotSize, _Symbol, bidPrice, slPrice, tpPrice, "SAR_Scalp_Sell");
      Print("Sell Executed at: ", bidPrice);
     }
  }
//+------------------------------------------------------------------+
