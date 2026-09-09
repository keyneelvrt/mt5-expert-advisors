//+------------------------------------------------------------------+
//|                                              RangeBreakoutEA.mq5 |
//|                                Copyright 2026, René Balke (Repl) |
//|                                  https://www.mql5.com (MT5 EA)   |
//+------------------------------------------------------------------+
#property copyright "Based on René Balke Range Breakout EA v1.40"
#property link      "https://www.mql5.com"
#property version   "1.40"
#property strict

#include <Trade\Trade.mqh>

//--- Enums untuk Pilihan Input
enum ENUM_VOLUME_MODE {
   VOLUME_FIXED,     // Fixed Lots
   VOLUME_MANAGED,   // Managed (Lot per X Capital)
   VOLUME_PERCENT,   // Risk % of Balance
   VOLUME_MONEY      // Risk Cash ($)
};

enum ENUM_CALC_MODE {
   CALC_OFF,         // Off / Disabled
   CALC_FACTOR,      // Factor of Range
   CALC_PERCENT,     // % of Price / Range
   CALC_POINTS       // Absolute Points
};

enum ENUM_TSL_MODE {
   TSL_OFF,          // Disabled
   TSL_PERCENT,      // Percentage
   TSL_POINTS        // Points
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- 1. VOLUME SETTINGS
input group "=== 1. Volume Settings ==="
input ENUM_VOLUME_MODE InpVolumeMode   = VOLUME_PERCENT; // Volume Mode
input double           InpFixedLots     = 0.1;            // Fixed Lot Size
input double           InpLotPerCapital = 0.01;           // Lot per X Capital
input double           InpCapitalUnit   = 1000.0;         // Capital Unit ($/€)
input double           InpRiskPercent   = 1.0;            // Risk Percentage (%)
input double           InpRiskMoney     = 50.0;           // Risk Money ($)

//--- 2. ORDER BUFFER & SL/TP
input group "=== 2. Order Buffer & SL/TP Settings ==="
input int              InpBufferPoints  = 20;             // Buffer Points above/below range
input ENUM_CALC_MODE   InpTPMode        = CALC_POINTS;    // Take Profit Mode
input double           InpTPValue       = 500.0;          // Take Profit Value
input ENUM_CALC_MODE   InpSLMode        = CALC_FACTOR;    // Stop Loss Mode
input double           InpSLValue       = 1.0;            // Stop Loss Value (Factor 1.0 = Opposite Range)

//--- 3. TIME SETTINGS
input group "=== 3. Time Settings ==="
input int              InpRangeStartHour = 0;             // Range Start Hour (0-23)
input int              InpRangeStartMin  = 0;             // Range Start Minute (0-59)
input int              InpRangeEndHour   = 8;             // Range End Hour (0-23)
input int              InpRangeEndMin    = 30;            // Range End Minute (0-59)
input int              InpDeleteHour     = 14;            // Delete Pending Orders Hour
input int              InpDeleteMin      = 0;             // Delete Pending Orders Min
input int              InpCloseHour      = 18;            // Close Positions Hour
input int              InpCloseMin       = 0;             // Close Positions Min
input bool             InpClosePositions = true;          // Close positions at End Time?

//--- 4. TRAILING STOP & BREAK EVEN
input group "=== 4. Trailing Stop & Break Even ==="
input ENUM_TSL_MODE   InpTSLMode        = TSL_PERCENT;    // TSL Mode
input double           InpBETrigger      = 0.5;            // BE Trigger Value (% or Points)
input double           InpBEBuffer       = 0.05;           // BE Buffer Value (% or Points)
input double           InpTSLTrigger     = 0.5;            // TSL Trigger Value
input double           InpTSLDistance    = 0.2;            // TSL Distance Value
input double           InpTSLStep        = 0.05;           // TSL Step Value

//--- 5. TRADE FREQUENCY & FILTERS
input group "=== 5. Trade Frequency & Filters ==="
input int              InpMaxBuyTrades   = 1;              // Max Buy Trades per Day
input int              InpMaxSellTrades  = 1;              // Max Sell Trades per Day
input int              InpMaxTotalTrades = 2;              // Max Total Trades per Day
input double           InpMinRangePoints = 0;              // Min Range Size (Points)
input double           InpMaxRangePoints = 99999;          // Max Range Size (Points)

//--- 6. SYSTEM SETTINGS
input group "=== 6. System Settings ==="
input color            InpRangeColor     = clrBlue;        // Chart Comment/Range Color
input string           InpOrderComment   = "RangeBreakout"; // Order Comment
input ulong            InpMagicNumber    = 123456;         // Magic Number
input bool             InpShowComment    = true;           // Show Chart Comment
input bool             InpDebugMode      = false;          // Debug Mode

//--- Global Variables
CTrade         trade;
datetime       g_last_day = 0;
double         g_range_high = 0.0;
double         g_range_low  = 0.0;
bool           g_orders_placed = false;
int            g_today_buys = 0;
int            g_today_sells = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Reset harian saat berganti hari
   datetime today = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if(today != g_last_day)
   {
      g_last_day = today;
      g_range_high = 0.0;
      g_range_low = 0.0;
      g_orders_placed = false;
      g_today_buys = 0;
      g_today_sells = 0;
   }

   int current_time_sec = dt.hour * 3600 + dt.min * 60 + dt.sec;
   int range_start_sec  = InpRangeStartHour * 3600 + InpRangeStartMin * 60;
   int range_end_sec    = InpRangeEndHour * 3600 + InpRangeEndMin * 60;
   int delete_sec       = InpDeleteHour * 3600 + InpDeleteMin * 60;
   int close_sec        = InpCloseHour * 3600 + InpCloseMin * 60;

   // 1. HITUNG HIGH & LOW RANGE (Gunakan data 1-menit)
   if(current_time_sec >= range_start_sec && current_time_sec <= range_end_sec)
   {
      double high = iHigh(_Symbol, PERIOD_M1, 0);
      double low  = iLow(_Symbol, PERIOD_M1, 0);
      
      if(g_range_high == 0.0 || high > g_range_high) g_range_high = high;
      if(g_range_low == 0.0  || low < g_range_low)   g_range_low  = low;
      
      if(InpShowComment)
      {
         Comment("--- Range Breakout EA ---\nBuilding Range...\nHigh: ", g_range_high, "\nLow: ", g_range_low);
      }
      return;
   }

   // 2. PASANG PENDING ORDER SETELAH RANGE SELESAI
   if(current_time_sec > range_end_sec && current_time_sec < delete_sec && !g_orders_placed)
   {
      double range_size_pts = (g_range_high - g_range_low) / _Point;
      
      // Cek Filter Ukuran Range
      if(range_size_pts >= InpMinRangePoints && range_size_pts <= InpMaxRangePoints)
      {
         PlaceBreakoutOrders();
      }
      else if(InpDebugMode)
      {
         Print("Range size out of bounds: ", range_size_pts, " points.");
      }
      
      g_orders_placed = true; // Mark order telah diproses hari ini
   }

   // 3. HAPUS PENDING ORDER JIKA MELEWATI DELETE TIME
   if(current_time_sec >= delete_sec && current_time_sec < close_sec)
   {
      DeletePendingOrders();
   }

   // 4. TUTUP POSISI JIKA DIATUR CLOSE TIME
   if(InpClosePositions && current_time_sec >= close_sec)
   {
      CloseAllPositions();
      DeletePendingOrders();
   }

   // 5. MANAJEMEN TRAILING STOP & BREAK EVEN
   ManageTrailingStop();
}

//+------------------------------------------------------------------+
//| PASANG BUY STOP & SELL STOP                                      |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
   double point = _Point;
   double range_size = g_range_high - g_range_low;
   
   double buy_price  = g_range_high + (InpBufferPoints * point);
   double sell_price = g_range_low - (InpBufferPoints * point);
   
   // Hitung SL dan TP untuk Buy
   double buy_sl = CalculateSL(buy_price, g_range_high, g_range_low, range_size, true);
   double buy_tp = CalculateTP(buy_price, g_range_high, range_size, true);
   
   // Hitung SL dan TP untuk Sell
   double sell_sl = CalculateSL(sell_price, g_range_high, g_range_low, range_size, false);
   double sell_tp = CalculateTP(sell_price, g_range_low, range_size, false);

   // Hitung Lot Size
   double buy_lot  = CalculateLot(buy_price, buy_sl);
   double sell_lot = CalculateLot(sell_price, sell_sl);

   // Pasang Buy Order jika kuota mencukupi
   if(g_today_buys < InpMaxBuyTrades && (g_today_buys + g_today_sells) < InpMaxTotalTrades)
   {
      if(trade.BuyStop(buy_lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, InpOrderComment))
         g_today_buys++;
   }

   // Pasang Sell Order jika kuota mencukupi
   if(g_today_sells < InpMaxSellTrades && (g_today_buys + g_today_sells) < InpMaxTotalTrades)
   {
      if(trade.SellStop(sell_lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, InpOrderComment))
         g_today_sells++;
   }
}

//+------------------------------------------------------------------+
//| KALKULASI UKURAN LOT                                            |
//+------------------------------------------------------------------+
double CalculateLot(double entry_price, double sl_price)
{
   double lot = InpFixedLots;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   switch(InpVolumeMode)
   {
      case VOLUME_FIXED:
         lot = InpFixedLots;
         break;
         
      case VOLUME_MANAGED:
         lot = MathFloor(balance / InpCapitalUnit) * InpLotPerCapital;
         break;
         
      case VOLUME_PERCENT:
         if(sl_price > 0)
         {
            double risk_amount = balance * (InpRiskPercent / 100.0);
            double sl_distance = MathAbs(entry_price - sl_price);
            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            if(sl_distance > 0 && tick_size > 0)
               lot = risk_amount / ((sl_distance / tick_size) * tick_value);
         }
         break;
         
      case VOLUME_MONEY:
         if(sl_price > 0)
         {
            double sl_distance = MathAbs(entry_price - sl_price);
            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            if(sl_distance > 0 && tick_size > 0)
               lot = InpRiskMoney / ((sl_distance / tick_size) * tick_value);
         }
         break;
   }

   // Normalisasi Lot
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = MathFloor(lot / step_lot) * step_lot;
   return lot;
}

//+------------------------------------------------------------------+
//| KALKULASI STOP LOSS                                              |
//+------------------------------------------------------------------+
double CalculateSL(double entry_price, double high, double low, double range_size, bool is_buy)
{
   if(InpSLMode == CALC_OFF) return 0.0;

   double sl = 0.0;
   if(InpSLMode == CALC_FACTOR)
   {
      // Default: 1.0 Factor berarti SL di sisi berlawanan dari range
      sl = is_buy ? (entry_price - (range_size * InpSLValue)) : (entry_price + (range_size * InpSLValue));
   }
   else if(InpSLMode == CALC_PERCENT)
   {
      sl = is_buy ? (entry_price * (1.0 - InpSLValue/100.0)) : (entry_price * (1.0 + InpSLValue/100.0));
   }
   else if(InpSLMode == CALC_POINTS)
   {
      sl = is_buy ? (entry_price - InpSLValue * _Point) : (entry_price + InpSLValue * _Point);
   }
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| KALKULASI TAKE PROFIT                                            |
//+------------------------------------------------------------------+
double CalculateTP(double entry_price, double base_range_price, double range_size, bool is_buy)
{
   if(InpTPMode == CALC_OFF) return 0.0;

   double tp = 0.0;
   if(InpTPMode == CALC_FACTOR)
   {
      tp = is_buy ? (entry_price + (range_size * InpTPValue)) : (entry_price - (range_size * InpTPValue));
   }
   else if(InpTPMode == CALC_PERCENT)
   {
      tp = is_buy ? (entry_price * (1.0 + InpTPValue/100.0)) : (entry_price * (1.0 - InpTPValue/100.0));
   }
   else if(InpTPMode == CALC_POINTS)
   {
      tp = is_buy ? (entry_price + InpTPValue * _Point) : (entry_price - InpTPValue * _Point);
   }
   return NormalizeDouble(tp, _Digits);
}

//+------------------------------------------------------------------+
//| HAPUS PENDING ORDERS                                             |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         trade.OrderDelete(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| TUTUP SEMUA POSISI TERBUKA                                       |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| MANAJEMEN BREAK EVEN & TRAILING STOP                             |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(InpTSLMode == TSL_OFF) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         ulong  ticket     = PositionGetInteger(POSITION_TICKET);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool   is_buy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

         double current_price = is_buy ? bid : ask;
         double profit_dist   = is_buy ? (current_price - open_price) : (open_price - current_price);

         // Break Even & Trailing Trigger Calculation
         double trigger_dist  = (InpTSLMode == TSL_PERCENT) ? (open_price * InpTSLTrigger / 100.0) : (InpTSLTrigger * _Point);
         double tsl_distance   = (InpTSLMode == TSL_PERCENT) ? (open_price * InpTSLDistance / 100.0) : (InpTSLDistance * _Point);
         double tsl_step       = (InpTSLMode == TSL_PERCENT) ? (open_price * InpTSLStep / 100.0)     : (InpTSLStep * _Point);

         if(profit_dist >= trigger_dist)
         {
            double new_sl = is_buy ? (current_price - tsl_distance) : (current_price + tsl_distance);

            // Cek Step Modification
            if(is_buy)
            {
               if(new_sl > current_sl + tsl_step)
                  trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
            }
            else
            {
               if(current_sl == 0 || new_sl < current_sl - tsl_step)
                  trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}
