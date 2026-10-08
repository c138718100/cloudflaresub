#property copyright "Jammy"
#property version   "1.00"
#property description "Jammy VWAP PA 全自动EA v1.00"
#property description "震荡：VWAP ±2σ 极值 + PA反转形态 + 震荡指标确认，TP回到 VWAP 0~0.5σ"
#property description "趋势：回踩 VWAP 0~0.5σ 边缘 + PA形态 + 震荡指标确认，顺势做"

#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| 参数                                                              |
//+------------------------------------------------------------------+
enum VWAP_MODE
{
   VWAP_DAILY=0,          // 经纪商服务器 00:00
   VWAP_WEEKLY=1,
   VWAP_MONTHLY=2,
   VWAP_CME_NY_1800=3,    // 纽约 18:00（CME/Globex）
   VWAP_NY_MIDNIGHT=5     // 纽约 00:00
};

input group "=== VWAP（与图上 Jammy VWAP 指标保持同一模式） ==="
input VWAP_MODE       VwapMode            = VWAP_CME_NY_1800;
input ENUM_TIMEFRAMES SignalTF            = PERIOD_CURRENT; // 信号周期（建议 M5~M15）
input bool            UseHLC3             = true;
input int             MinSessionBars      = 12;   // 交易日开盘后至少多少根K线才交易（σ稳定后）
input int             TesterServerGMTOffset = 2;  // 仅回测：服务器冬令时 GMT 偏移（回测里TimeGMT不可靠）
input bool            TesterOffsetFollowsUSDST = true; // 仅回测：服务器随美国夏令时 +1 小时

input group "=== 行情分类（震荡 / 趋势） ==="
input int    ADXPeriod            = 14;
input double RangeADXMax          = 22.0; // ADX 低于此值才算震荡
input double TrendADXMin          = 25.0; // ADX 高于此值才算趋势
input int    SlopeBars            = 12;   // VWAP 斜率回看K线数
input double RangeSlopeMaxSigma   = 0.30; // 震荡：VWAP 斜率绝对值 < 此值×σ
input double TrendSlopeMinSigma   = 0.50; // 趋势：VWAP 斜率 > 此值×σ

input group "=== 震荡：VWAP 极值反转 ==="
input bool   EnableRangeTrades    = true;
input double RangeEntrySigma      = 2.0;  // 形态极值需触及 ±此σ
input bool   RangeRequireCloseInside = true; // 信号K线须收回 ±2σ 以内（确认拒绝）
input double RangeTPSigma         = 0.5;  // TP = VWAP ±此σ（0=VWAP中线，0.5=核心区边缘）
input bool   RangeDynamicTP       = true; // 每根新K线让TP跟随最新VWAP

input group "=== 趋势：回踩 0~0.5σ 边缘 ==="
input bool   EnableTrendTrades    = true;
input double PullbackTolSigma     = 0.15; // 回踩到 +0.5σ 上方多少σ以内也算触及
input double PullbackMaxBelowSigma= 0.30; // 回踩穿过 VWAP 最多多少σ（再深视为趋势失败）
input double TrendTPSigma         = 2.0;  // TP = VWAP ±此σ（顺势目标）

input group "=== PA 价格行为形态（至少命中一种） ==="
input bool   UsePinBar            = true;
input double PinWickBodyRatio     = 2.0;  // 影线 ≥ 实体 × 此倍数
input double PinWickRangePct      = 0.55; // 影线 ≥ K线振幅 × 此比例
input bool   UseEngulfing         = true; // 吞没
input bool   UseStar              = true; // 早晨之星 / 黄昏之星
input double MinPatternBarATR     = 0.30; // 形态K线振幅 ≥ 此倍ATR（过滤小十字星）

input group "=== 震荡指标综合确认（RSI / Stochastic / CCI） ==="
input int    MinOscConfirm        = 2;    // 3个里至少几个确认
input int    RSIPeriod            = 14;
input double RSIHigh              = 70.0;
input double RSILow               = 30.0;
input double TrendRSIMin          = 40.0; // 趋势回踩：RSI 回落但不跌破此值（多）
input double TrendRSIMax          = 60.0; // 趋势回踩：RSI 反弹但不突破此值（空）
input int    StochK               = 14;
input int    StochD               = 3;
input int    StochSlowing         = 3;
input double StochHigh            = 80.0;
input double StochLow             = 20.0;
input int    CCIPeriod            = 20;
input double CCILevel             = 100.0;

input group "=== 止损 / 止盈 / 持仓管理 ==="
input int    ATRPeriod            = 14;
input double SLBufferATR          = 0.25; // SL = 形态极值外 + 此倍ATR
input double MaxSLATR             = 2.5;  // 止损超过此倍ATR不做
input int    MinSLPoints          = 150;  // 最小止损距离(点)
input double MinRR                = 1.0;  // 盈亏比低于此值不做
input double BreakEvenR           = 1.0;  // 浮盈达到此R后推保本（0=关闭）
input int    MaxHoldBars          = 48;   // 持仓超过此K线数平仓（0=关闭）
input bool   ExitRangeOnTrendAgainst = true; // 震荡单遇反向趋势成立时平仓

input group "=== 资金与风控 ==="
input double RiskPercent          = 0.5;  // 每笔风险 = 净值 × %
input double RiskUSD              = 0.0;  // >0 时改用固定金额
input double CommissionPerLotRT   = 7.0;  // 每手往返佣金（计入风险与保本）
input double MaxLots              = 1.0;
input int    MaxSpreadPoints      = 60;
input int    MaxTradesPerDay      = 6;
input double DailyMaxLossPct      = 2.0;  // 当日亏损(已实现+浮动)达到余额%后停止开仓（0=关闭）
input int    MaxConsecLosses      = 3;    // 当日连亏N笔后停止（0=关闭）
input int    CooldownBarsAfterLoss= 3;    // 亏损后冷却K线数
input int    TradeStartHour       = 1;    // 服务器时间，允许开仓的起始小时
input int    TradeEndHour         = 23;   // 服务器时间，允许开仓的结束小时（不含）
input bool   FridayCloseEnable    = true;
input int    FridayCloseHour      = 22;   // 周五此小时(服务器)后平仓并停止开仓

input group "=== 其它 ==="
input long   MagicNumber          = 26100801;
input int    SlippagePoints       = 30;
input bool   DrawSignals          = true;

//+------------------------------------------------------------------+
//| 运行状态                                                          |
//+------------------------------------------------------------------+
enum REGIME { REG_NONE=0, REG_RANGE=1, REG_UP=2, REG_DOWN=3 };

#define TAG_RANGE "VPA-RNG"
#define TAG_TREND "VPA-TRD"
#define OBJ_PREFIX "VPA_"

ENUM_TIMEFRAMES g_tf;
int hRSI=INVALID_HANDLE,hSto=INVALID_HANDLE,hCCI=INVALID_HANDLE,hADX=INVALID_HANDLE,hATR=INVALID_HANDLE;

datetime g_lastBar=0;
int      g_serverOffset=0;

// 当前交易日 VWAP（按时间正序，最后一个元素 = 已收盘的 shift 1）
MqlRates g_r[];
double   g_vw[],g_sd[];
int      g_n=0;

// 指标（series：[0]=shift1）
double rsi[],stK[],stD[],cci[];
double g_adx=0,g_pdi=0,g_mdi=0,g_atr=0;

REGIME g_regime=REG_NONE;
double g_slopeSigma=0,g_z1=0;
string g_status="初始化";

// 当日统计
int    g_dayTrades=0,g_dayConsecLoss=0;
double g_dayRealized=0;
datetime g_lastLossTime=0;

//+------------------------------------------------------------------+
//| 时间 / 交易日锚点（与 Jammy VWAP 指标同一套算法）                   |
//+------------------------------------------------------------------+
datetime MakeDate(int year,int month,int day)
{
   MqlDateTime s; ZeroMemory(s);
   s.year=year; s.mon=month; s.day=day;
   return StructToTime(s);
}

int DayOfWeek(datetime t) { return (int)(((long)t/86400+4)%7); }

int NthSundayDay(int year,int month,int nth)
{
   int dow=DayOfWeek(MakeDate(year,month,1));
   return 1+((7-dow)%7)+(nth-1)*7;
}

int      g_dstYear=0;
datetime g_dstStartLocal=0,g_dstEndLocal=0,g_dstStartUTC=0,g_dstEndUTC=0;

void EnsureDstYear(int year)
{
   if(year==g_dstYear) return;
   g_dstYear=year;
   g_dstStartLocal=MakeDate(year,3,NthSundayDay(year,3,2))+2*3600;
   g_dstEndLocal  =MakeDate(year,11,NthSundayDay(year,11,1))+2*3600;
   g_dstStartUTC  =g_dstStartLocal+5*3600;
   g_dstEndUTC    =g_dstEndLocal+4*3600;
}

int YearOf(datetime t) { MqlDateTime d; TimeToStruct(t,d); return d.year; }

int NewYorkOffsetAtUTC(datetime utc)
{
   EnsureDstYear(YearOf(utc));
   return (utc>=g_dstStartUTC && utc<g_dstEndUTC) ? -4 : -5;
}

int NewYorkOffsetAtLocal(datetime nyLocal)
{
   EnsureDstYear(YearOf(nyLocal));
   return (nyLocal>=g_dstStartLocal && nyLocal<g_dstEndLocal) ? -4 : -5;
}

int ServerUtcOffsetSeconds(datetime serverTime)
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      // 回测中 TimeGMT() 不反映真实时差，改用参数。
      int h=TesterServerGMTOffset;
      if(TesterOffsetFollowsUSDST && NewYorkOffsetAtUTC(serverTime-h*3600)==-4) h++;
      return h*3600;
   }
   datetime server=TimeTradeServer();
   if(server<=0) server=TimeCurrent();
   datetime utc=TimeGMT();
   if(utc<=0 || server<=0) return 0;
   return (int)MathRound((double)(server-utc)/900.0)*900;
}

datetime NewYorkSessionAnchor(datetime brokerTime,int anchorHour)
{
   datetime utc=brokerTime-g_serverOffset;
   datetime nyClock=utc+NewYorkOffsetAtUTC(utc)*3600;
   datetime localAnchor=(datetime)((long)nyClock-(long)nyClock%86400+anchorHour*3600);
   if(anchorHour==18 && nyClock<localAnchor) localAnchor-=86400;
   return localAnchor-NewYorkOffsetAtLocal(localAnchor)*3600+g_serverOffset;
}

datetime PeriodAnchor(datetime t)
{
   datetime day0=(datetime)((long)t-(long)t%86400);
   if(VwapMode==VWAP_DAILY)   return day0;
   if(VwapMode==VWAP_WEEKLY)  return day0-((DayOfWeek(day0)+6)%7)*86400;
   if(VwapMode==VWAP_MONTHLY) { MqlDateTime d; TimeToStruct(t,d); return MakeDate(d.year,d.mon,1); }
   if(VwapMode==VWAP_NY_MIDNIGHT) return NewYorkSessionAnchor(t,0);
   return NewYorkSessionAnchor(t,18);
}

//+------------------------------------------------------------------+
//| VWAP / σ（只用已收盘K线，信号不重绘）                               |
//+------------------------------------------------------------------+
bool BuildSessionVWAP()
{
   g_n=0;
   datetime t1=iTime(_Symbol,g_tf,1);
   if(t1<=0) return false;
   datetime anchor=PeriodAnchor(t1);

   ArraySetAsSeries(g_r,false);
   int n=CopyRates(_Symbol,g_tf,anchor,t1,g_r);
   if(n<=0) return false;

   ArrayResize(g_vw,n); ArrayResize(g_sd,n);
   double sV=0,sPV=0,sP2V=0;
   for(int i=0;i<n;i++)
   {
      double p=UseHLC3?(g_r[i].high+g_r[i].low+g_r[i].close)/3.0:g_r[i].close;
      double v=(double)g_r[i].tick_volume; if(v<=0) v=1.0;
      sV+=v; sPV+=p*v; sP2V+=p*p*v;
      double vw=sPV/sV;
      double var=sP2V/sV-vw*vw; if(var<0) var=0;
      g_vw[i]=vw; g_sd[i]=MathSqrt(var);
   }
   g_n=n;
   return true;
}

double VW(int s) { int i=g_n-s; return (i>=0 && i<g_n) ? g_vw[i] : 0.0; }
double SD(int s) { int i=g_n-s; return (i>=0 && i<g_n) ? g_sd[i] : 0.0; }
bool   BarAt(int s,MqlRates &b) { int i=g_n-s; if(i<0 || i>=g_n) return false; b=g_r[i]; return true; }

//+------------------------------------------------------------------+
//| 指标读取                                                          |
//+------------------------------------------------------------------+
bool ReadIndicators()
{
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(stK,true); ArraySetAsSeries(stD,true); ArraySetAsSeries(cci,true);
   double a[],p[],m[],t[];
   ArraySetAsSeries(a,true); ArraySetAsSeries(p,true); ArraySetAsSeries(m,true); ArraySetAsSeries(t,true);

   if(CopyBuffer(hRSI,0,1,5,rsi)<5) return false;
   if(CopyBuffer(hSto,0,1,3,stK)<3 || CopyBuffer(hSto,1,1,3,stD)<3) return false;
   if(CopyBuffer(hCCI,0,1,3,cci)<3) return false;
   if(CopyBuffer(hADX,0,1,1,a)<1 || CopyBuffer(hADX,1,1,1,p)<1 || CopyBuffer(hADX,2,1,1,m)<1) return false;
   if(CopyBuffer(hATR,0,1,1,t)<1) return false;
   g_adx=a[0]; g_pdi=p[0]; g_mdi=m[0]; g_atr=t[0];
   return g_atr>0;
}

double MaxOf(const double &x[],int n) { double r=-DBL_MAX; for(int i=0;i<n && i<ArraySize(x);i++) r=MathMax(r,x[i]); return r; }
double MinOf(const double &x[],int n) { double r= DBL_MAX; for(int i=0;i<n && i<ArraySize(x);i++) r=MathMin(r,x[i]); return r; }

//+------------------------------------------------------------------+
//| 行情分类                                                          |
//+------------------------------------------------------------------+
REGIME ClassifyRegime()
{
   g_slopeSigma=0; g_z1=0;
   double sd=SD(1);
   if(sd<=0) return REG_NONE;
   int back=MathMin(MathMax(1,SlopeBars),g_n-1);
   if(back<1) return REG_NONE;
   g_slopeSigma=(VW(1)-VW(1+back))/sd;
   MqlRates b1; BarAt(1,b1);
   g_z1=(b1.close-VW(1))/sd;

   if(g_adx<RangeADXMax && MathAbs(g_slopeSigma)<RangeSlopeMaxSigma) return REG_RANGE;
   if(g_adx>TrendADXMin && g_slopeSigma> TrendSlopeMinSigma && g_pdi>g_mdi && b1.close>VW(1)) return REG_UP;
   if(g_adx>TrendADXMin && g_slopeSigma<-TrendSlopeMinSigma && g_mdi>g_pdi && b1.close<VW(1)) return REG_DOWN;
   return REG_NONE;
}

string RegimeText(REGIME r)
{
   if(r==REG_RANGE) return "震荡";
   if(r==REG_UP)    return "上升趋势";
   if(r==REG_DOWN)  return "下降趋势";
   return "过渡/不交易";
}

//+------------------------------------------------------------------+
//| PA 价格行为形态（全部基于已收盘K线）                                |
//+------------------------------------------------------------------+
bool BigEnough(const MqlRates &b) { return (b.high-b.low)>=MinPatternBarATR*g_atr; }

bool BullPin(const MqlRates &b)
{
   double rng=b.high-b.low; if(rng<=0 || !BigEnough(b)) return false;
   double body=MathAbs(b.close-b.open);
   double lw=MathMin(b.open,b.close)-b.low;
   double uw=b.high-MathMax(b.open,b.close);
   return lw>=PinWickBodyRatio*MathMax(body,_Point) && lw>=PinWickRangePct*rng && uw<=0.25*rng;
}

bool BearPin(const MqlRates &b)
{
   double rng=b.high-b.low; if(rng<=0 || !BigEnough(b)) return false;
   double body=MathAbs(b.close-b.open);
   double uw=b.high-MathMax(b.open,b.close);
   double lw=MathMin(b.open,b.close)-b.low;
   return uw>=PinWickBodyRatio*MathMax(body,_Point) && uw>=PinWickRangePct*rng && lw<=0.25*rng;
}

bool BullEngulf(const MqlRates &b1,const MqlRates &b2)
{
   return b2.close<b2.open && b1.close>b1.open &&
          b1.close>=b2.open && b1.open<=b2.close &&
          (b1.close-b1.open)>=(b2.open-b2.close) && BigEnough(b1);
}

bool BearEngulf(const MqlRates &b1,const MqlRates &b2)
{
   return b2.close>b2.open && b1.close<b1.open &&
          b1.close<=b2.open && b1.open>=b2.close &&
          (b1.open-b1.close)>=(b2.close-b2.open) && BigEnough(b1);
}

bool MorningStar(const MqlRates &b1,const MqlRates &b2,const MqlRates &b3)
{
   double body3=b3.open-b3.close;
   if(body3<=0 || body3<0.5*(b3.high-b3.low) || !BigEnough(b3)) return false;
   if(MathAbs(b2.close-b2.open)>0.3*body3) return false;
   return b1.close>b1.open && b1.close>=(b3.open+b3.close)*0.5;
}

bool EveningStar(const MqlRates &b1,const MqlRates &b2,const MqlRates &b3)
{
   double body3=b3.close-b3.open;
   if(body3<=0 || body3<0.5*(b3.high-b3.low) || !BigEnough(b3)) return false;
   if(MathAbs(b2.close-b2.open)>0.3*body3) return false;
   return b1.close<b1.open && b1.close<=(b3.open+b3.close)*0.5;
}

// 找看涨形态：返回形态名和形态最低点（止损参考）
bool FindBullPA(string &name,double &ext)
{
   MqlRates b1,b2,b3;
   if(!BarAt(1,b1) || !BarAt(2,b2)) return false;
   bool has3=BarAt(3,b3);
   if(UsePinBar && BullPin(b1))                 { name="看涨Pin Bar"; ext=b1.low; return true; }
   if(UseEngulfing && BullEngulf(b1,b2))        { name="看涨吞没";   ext=MathMin(b1.low,b2.low); return true; }
   if(UseStar && has3 && MorningStar(b1,b2,b3)) { name="早晨之星";   ext=MathMin(b1.low,MathMin(b2.low,b3.low)); return true; }
   return false;
}

bool FindBearPA(string &name,double &ext)
{
   MqlRates b1,b2,b3;
   if(!BarAt(1,b1) || !BarAt(2,b2)) return false;
   bool has3=BarAt(3,b3);
   if(UsePinBar && BearPin(b1))                 { name="看跌Pin Bar"; ext=b1.high; return true; }
   if(UseEngulfing && BearEngulf(b1,b2))        { name="看跌吞没";   ext=MathMax(b1.high,b2.high); return true; }
   if(UseStar && has3 && EveningStar(b1,b2,b3)) { name="黄昏之星";   ext=MathMax(b1.high,MathMax(b2.high,b3.high)); return true; }
   return false;
}

//+------------------------------------------------------------------+
//| 震荡指标综合确认                                                   |
//+------------------------------------------------------------------+
// 震荡做空：超买后拐头
int OscRangeSell()
{
   int c=0;
   if(MaxOf(rsi,3)>=RSIHigh && rsi[0]<rsi[1]) c++;
   if(MaxOf(stK,3)>=StochHigh && stK[0]<stD[0] && stK[0]<stK[1]) c++;
   if(MaxOf(cci,3)>=CCILevel && cci[0]<cci[1]) c++;
   return c;
}

// 震荡做多：超卖后拐头
int OscRangeBuy()
{
   int c=0;
   if(MinOf(rsi,3)<=RSILow && rsi[0]>rsi[1]) c++;
   if(MinOf(stK,3)<=StochLow && stK[0]>stD[0] && stK[0]>stK[1]) c++;
   if(MinOf(cci,3)<=-CCILevel && cci[0]>cci[1]) c++;
   return c;
}

// 顺势做多：回调降温但未转弱，再次拐头向上
int OscTrendBuy()
{
   int c=0;
   if(rsi[0]>=TrendRSIMin && rsi[0]>rsi[1] && MinOf(rsi,5)>=TrendRSIMin-5) c++;
   if(stK[0]>stD[0] && stK[1]<=stD[1] && MinOf(stK,3)<=50) c++;
   if(cci[0]>cci[1] && MinOf(cci,3)<=0) c++;
   return c;
}

// 顺势做空：反弹降温但未转强，再次拐头向下
int OscTrendSell()
{
   int c=0;
   if(rsi[0]<=TrendRSIMax && rsi[0]<rsi[1] && MaxOf(rsi,5)<=TrendRSIMax+5) c++;
   if(stK[0]<stD[0] && stK[1]>=stD[1] && MaxOf(stK,3)>=50) c++;
   if(cci[0]<cci[1] && MaxOf(cci,3)>=0) c++;
   return c;
}

//+------------------------------------------------------------------+
//| 当日统计 / 风控                                                   |
//+------------------------------------------------------------------+
datetime ServerDayStart() { datetime t=TimeCurrent(); return (datetime)((long)t-(long)t%86400); }

void RefreshDayStats()
{
   g_dayTrades=0; g_dayRealized=0; g_dayConsecLoss=0;
   if(!HistorySelect(ServerDayStart(),TimeCurrent()+60)) return;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(d,DEAL_MAGIC)!=MagicNumber) continue;
      long en=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(en==DEAL_ENTRY_IN) { g_dayTrades++; continue; }
      if(en!=DEAL_ENTRY_OUT && en!=DEAL_ENTRY_OUT_BY) continue;
      double pl=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+
                HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
      g_dayRealized+=pl;
      if(pl<0) { g_dayConsecLoss++; g_lastLossTime=(datetime)HistoryDealGetInteger(d,DEAL_TIME); }
      else g_dayConsecLoss=0;
   }
   // 开仓佣金记在 IN 成交上，同样计入当日盈亏
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(d,DEAL_MAGIC)!=MagicNumber) continue;
      if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN)
         g_dayRealized+=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
   }
}

double FloatingPnL()
{
   double pl=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      pl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

int MyPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==MagicNumber) n++;
   }
   return n;
}

bool IsFridayCloseTime()
{
   if(!FridayCloseEnable) return false;
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   return d.day_of_week==5 && d.hour>=FridayCloseHour;
}

// 返回空串=允许开仓，否则为拒绝原因
string EntryBlockReason()
{
   MqlTick k; if(!SymbolInfoTick(_Symbol,k)) return "无报价";
   if((k.ask-k.bid)/_Point>MaxSpreadPoints) return StringFormat("点差%.0f过大",(k.ask-k.bid)/_Point);

   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   if(d.hour<TradeStartHour || d.hour>=TradeEndHour) return "不在交易时段";
   if(IsFridayCloseTime()) return "周五收盘前停止开仓";
   if(g_n<MinSessionBars) return StringFormat("交易日开盘不足%d根K线，σ未稳定",MinSessionBars);

   if(MaxTradesPerDay>0 && g_dayTrades>=MaxTradesPerDay) return "今日交易次数已满";
   if(MaxConsecLosses>0 && g_dayConsecLoss>=MaxConsecLosses) return StringFormat("今日连亏%d笔，停止",g_dayConsecLoss);
   if(DailyMaxLossPct>0)
   {
      double base=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayRealized; // 约等于今日开盘余额
      double day=g_dayRealized+FloatingPnL();
      if(base>0 && day<=-base*DailyMaxLossPct/100.0) return StringFormat("今日亏损%.2f达到上限",-day);
   }
   if(CooldownBarsAfterLoss>0 && g_lastLossTime>0 &&
      TimeCurrent()-g_lastLossTime<(datetime)CooldownBarsAfterLoss*PeriodSeconds(g_tf))
      return "亏损后冷却中";
   return "";
}

//+------------------------------------------------------------------+
//| 下单                                                              |
//+------------------------------------------------------------------+
double MoneyPerPointPerLot()
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0 || tv<=0) return 0;
   return tv*_Point/ts;
}

double LotsForRisk(ENUM_ORDER_TYPE type,double entry,double sl)
{
   double money=(RiskUSD>0 ? RiskUSD : AccountInfoDouble(ACCOUNT_EQUITY)*RiskPercent/100.0);
   double p=0;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,p)) return 0;
   double perLot=MathAbs(p)+MathMax(0.0,CommissionPerLotRT);
   if(perLot<=0) return 0;

   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); if(st<=0) st=mn;
   double lots=MathFloor(money/perLot/st+1e-8)*st;
   lots=MathMin(lots,MathMin(mx,MaxLots));
   if(lots<mn-1e-12) return 0;   // 风险不够最小手数时不做，绝不向上取整
   int vd=(st<0.01?3:2);
   return NormalizeDouble(lots,vd);
}

double StopsGap()
{
   long s=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long f=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(s,f)*_Point;
}

void DrawSignal(bool buy,string text)
{
   if(!DrawSignals) return;
   MqlRates b1; if(!BarAt(1,b1)) return;
   string nm=OBJ_PREFIX+(buy?"B_":"S_")+IntegerToString((long)b1.time);
   ObjectCreate(0,nm,buy?OBJ_ARROW_BUY:OBJ_ARROW_SELL,0,b1.time,buy?b1.low:b1.high);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,buy?clrLime:clrRed);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,text);
}

// 统一入口：校验止损/止盈/盈亏比后市价开仓
bool TryOpen(bool buy,double ext,double tp,string tag,string why)
{
   MqlTick k; if(!SymbolInfoTick(_Symbol,k)) return false;
   double entry=buy?k.ask:k.bid;
   double buf=SLBufferATR*g_atr;
   double sl=buy?ext-buf:ext+buf;

   double minDist=MathMax(MinSLPoints*_Point,StopsGap()+_Point);
   if(buy && entry-sl<minDist) sl=entry-minDist;
   if(!buy && sl-entry<minDist) sl=entry+minDist;

   double risk=MathAbs(entry-sl);
   double reward=buy?tp-entry:entry-tp;
   if(reward<=StopsGap()) { g_status=why+"｜价格已到目标区，放弃"; return false; }
   if(risk>MaxSLATR*g_atr) { g_status=why+StringFormat("｜止损%.1fATR过大，放弃",risk/g_atr); return false; }
   if(reward/risk<MinRR) { g_status=why+StringFormat("｜盈亏比%.2f<%.2f，放弃",reward/risk,MinRR); return false; }

   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   double lots=LotsForRisk(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,entry,sl);
   if(lots<=0) { g_status=why+"｜风险金额不足最小手数，放弃"; return false; }

   bool ok=buy ? trade.Buy(lots,_Symbol,0,sl,tp,tag) : trade.Sell(lots,_Symbol,0,sl,tp,tag);
   if(ok)
   {
      g_status=StringFormat("%s｜%s %.2f手 SL %.*f TP %.*f RR %.2f",why,buy?"买入":"卖出",lots,_Digits,sl,_Digits,tp,reward/risk);
      DrawSignal(buy,g_status);
   }
   else
      g_status=why+"｜下单失败 retcode="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription();
   Print("VPA ",g_status);
   return ok;
}

//+------------------------------------------------------------------+
//| 信号                                                              |
//+------------------------------------------------------------------+
void CheckRangeSignals()
{
   double vw=VW(1),sd=SD(1);
   MqlRates b1; BarAt(1,b1);
   string pa; double ext;

   // 上沿极值 → 做空
   if(FindBearPA(pa,ext) && (ext-vw)/sd>=RangeEntrySigma &&
      (!RangeRequireCloseInside || b1.close<vw+RangeEntrySigma*sd))
   {
      int oc=OscRangeSell();
      string why=StringFormat("震荡做空：+%.1fσ极值 %s｜指标确认%d/3",(ext-vw)/sd,pa,oc);
      if(oc>=MinOscConfirm) { TryOpen(false,ext,vw+RangeTPSigma*sd,TAG_RANGE,why); return; }
      g_status=why+"（不足，放弃）";
   }

   // 下沿极值 → 做多
   if(FindBullPA(pa,ext) && (vw-ext)/sd>=RangeEntrySigma &&
      (!RangeRequireCloseInside || b1.close>vw-RangeEntrySigma*sd))
   {
      int oc=OscRangeBuy();
      string why=StringFormat("震荡做多：-%.1fσ极值 %s｜指标确认%d/3",(vw-ext)/sd,pa,oc);
      if(oc>=MinOscConfirm) { TryOpen(true,ext,vw-RangeTPSigma*sd,TAG_RANGE,why); return; }
      g_status=why+"（不足，放弃）";
   }
}

void CheckTrendSignals()
{
   double vw=VW(1),sd=SD(1);
   MqlRates b1; BarAt(1,b1);
   string pa; double ext;

   if(g_regime==REG_UP && FindBullPA(pa,ext))
   {
      double z=(ext-vw)/sd;   // 形态低点所在σ位置
      if(z<=0.5+PullbackTolSigma && z>=-PullbackMaxBelowSigma && b1.close>=vw)
      {
         int oc=OscTrendBuy();
         string why=StringFormat("顺势做多：回踩%.2fσ %s｜指标确认%d/3",z,pa,oc);
         if(oc>=MinOscConfirm) { TryOpen(true,ext,vw+TrendTPSigma*sd,TAG_TREND,why); return; }
         g_status=why+"（不足，放弃）";
      }
   }

   if(g_regime==REG_DOWN && FindBearPA(pa,ext))
   {
      double z=(ext-vw)/sd;   // 形态高点所在σ位置
      if(z>=-0.5-PullbackTolSigma && z<=PullbackMaxBelowSigma && b1.close<=vw)
      {
         int oc=OscTrendSell();
         string why=StringFormat("顺势做空：反弹%.2fσ %s｜指标确认%d/3",z,pa,oc);
         if(oc>=MinOscConfirm) { TryOpen(false,ext,vw-TrendTPSigma*sd,TAG_TREND,why); return; }
         g_status=why+"（不足，放弃）";
      }
   }
}

//+------------------------------------------------------------------+
//| 持仓管理（每根新K线）                                              |
//+------------------------------------------------------------------+
void ClosePos(ulong ticket,string why)
{
   if(trade.PositionClose(ticket,SlippagePoints)) Print("VPA 平仓 ",ticket,"：",why);
   g_status="平仓："+why;
}

void ManagePositions()
{
   bool vwOk=(g_n>=2 && SD(1)>0);
   double vw=VW(1),sd=SD(1);
   double gap=StopsGap();
   double mpp=MoneyPerPointPerLot();
   int barSec=PeriodSeconds(g_tf);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      bool isRange=(StringFind(PositionGetString(POSITION_COMMENT),TAG_RANGE)==0);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double cur=buy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);

      if(IsFridayCloseTime()) { ClosePos(t,"周五收盘前平仓"); continue; }

      if(MaxHoldBars>0 && barSec>0 && TimeCurrent()-opened>=(datetime)MaxHoldBars*barSec)
      { ClosePos(t,StringFormat("持仓超过%d根K线",MaxHoldBars)); continue; }

      if(isRange && ExitRangeOnTrendAgainst &&
         ((buy && g_regime==REG_DOWN) || (!buy && g_regime==REG_UP)))
      { ClosePos(t,"震荡单遇反向趋势成立"); continue; }

      // 震荡单：TP 跟随最新 VWAP 核心区；已越过目标则直接平仓
      if(isRange && RangeDynamicTP && vwOk)
      {
         double nt=NormalizeDouble(buy?vw-RangeTPSigma*sd:vw+RangeTPSigma*sd,_Digits);
         if((buy && cur>=nt) || (!buy && cur<=nt)) { ClosePos(t,"已回到VWAP核心区"); continue; }
         if(MathAbs(nt-tp)>=10*_Point && MathAbs(cur-nt)>gap)
         {
            if(trade.PositionModify(t,sl,nt)) tp=nt;
         }
      }

      // 推保本：只在SL仍处亏损侧时计算初始R
      bool slLossSide=(sl>0 && (buy?sl<open:sl>open));
      if(BreakEvenR>0 && slLossSide)
      {
         double R=MathAbs(open-sl);
         double move=buy?cur-open:open-cur;
         if(R>0 && move>=BreakEvenR*R)
         {
            double costPts=(mpp>0 ? CommissionPerLotRT/mpp : 0)+10;
            double be=NormalizeDouble(buy?open+costPts*_Point:open-costPts*_Point,_Digits);
            if((buy && cur-be>gap) || (!buy && be-cur>gap))
               if(trade.PositionModify(t,be,tp)) Print("VPA 推保本 ",t," SL→",DoubleToString(be,_Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 面板                                                              |
//+------------------------------------------------------------------+
void ShowPanel(string block)
{
   string mode=(VwapMode==VWAP_CME_NY_1800?"CME 18:00":(VwapMode==VWAP_NY_MIDNIGHT?"纽约00:00":
               (VwapMode==VWAP_DAILY?"服务器日":(VwapMode==VWAP_WEEKLY?"周":"月"))));
   Comment(StringFormat(
      "Jammy VWAP PA 全自动 EA v1.00｜%s｜VWAP %s\n"
      "行情：%s｜ADX %.1f｜VWAP斜率 %.2fσ｜收盘位置 %.2fσ\n"
      "VWAP %.*f｜σ %.*f｜ATR %.*f｜本交易日K线 %d\n"
      "今日：开仓 %d/%d｜已实现 %.2f｜浮动 %.2f｜连亏 %d\n"
      "开仓许可：%s\n"
      "最近：%s",
      EnumToString(g_tf),mode,
      RegimeText(g_regime),g_adx,g_slopeSigma,g_z1,
      _Digits,VW(1),_Digits,SD(1),_Digits,g_atr,g_n,
      g_dayTrades,MaxTradesPerDay,g_dayRealized,FloatingPnL(),g_dayConsecLoss,
      block==""?"允许":block,
      g_status));
}

//+------------------------------------------------------------------+
//| 生命周期                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   g_tf=(SignalTF==PERIOD_CURRENT?(ENUM_TIMEFRAMES)_Period:SignalTF);
   hRSI=iRSI(_Symbol,g_tf,RSIPeriod,PRICE_CLOSE);
   hSto=iStochastic(_Symbol,g_tf,StochK,StochD,StochSlowing,MODE_SMA,STO_LOWHIGH);
   hCCI=iCCI(_Symbol,g_tf,CCIPeriod,PRICE_TYPICAL);
   hADX=iADX(_Symbol,g_tf,ADXPeriod);
   hATR=iATR(_Symbol,g_tf,ATRPeriod);
   if(hRSI==INVALID_HANDLE || hSto==INVALID_HANDLE || hCCI==INVALID_HANDLE || hADX==INVALID_HANDLE || hATR==INVALID_HANDLE)
   {
      Print("VPA 指标句柄创建失败");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_lastBar=0;
   g_status="等待新K线";
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI); IndicatorRelease(hSto); IndicatorRelease(hCCI);
   IndicatorRelease(hADX); IndicatorRelease(hATR);
   Comment("");
   if(reason==REASON_REMOVE) ObjectsDeleteAll(0,OBJ_PREFIX);
}

void OnTick()
{
   // 只在信号周期新K线开盘时运行一次：信号全部来自已收盘K线，不重绘。
   datetime bar=iTime(_Symbol,g_tf,0);
   if(bar<=0 || bar==g_lastBar) return;
   g_lastBar=bar;

   g_serverOffset=ServerUtcOffsetSeconds(TimeCurrent());
   RefreshDayStats();

   bool ready=BuildSessionVWAP() && ReadIndicators() && g_n>=2 && SD(1)>0;
   g_regime=ready?ClassifyRegime():REG_NONE;

   ManagePositions();

   string block=ready?EntryBlockReason():"VWAP/指标数据未就绪";
   if(block=="" && MyPositions()==0)
   {
      if(g_regime==REG_RANGE && EnableRangeTrades) CheckRangeSignals();
      else if((g_regime==REG_UP || g_regime==REG_DOWN) && EnableTrendTrades) CheckTrendSignals();
   }
   ShowPanel(block);
}
