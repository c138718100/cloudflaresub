#property copyright "Jammy"
#property version   "2.00"
#property description "Jammy VWAP PA 全自动EA v2.00：周VWAP定格局 + 周一高低点清扫定偏见 + 日内双VWAP(CME 18:00 / 纽约0点)执行"
#property description "震荡/趋势全部按VWAP斜率区分；进场必须有PA形态 + RSI/Stochastic/CCI综合确认"

#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| 参数                                                              |
//+------------------------------------------------------------------+
input group "=== 周线层：周VWAP格局（CME周开盘 纽约周日18:00） ==="
input ENUM_TIMEFRAMES WeekTF              = PERIOD_H1; // 周内分析周期（只允许 M15~H1）
input int    WeekSlopeBars                = 12;   // 周VWAP斜率回看K线数
input double WeekTrendSlopeSigma          = 0.30; // 周VWAP斜率 > 此值×周σ = 周趋势
input double WeekRangeSlopeSigma          = 0.15; // 周VWAP斜率绝对值 < 此值×周σ = 周震荡
input bool   AllowBiasInWeekTransition    = true; // 周格局处于过渡时，是否仍按清扫偏见交易

input group "=== 周一高低点清扫 → 本周偏见 ==="
input int    SweepMinPoints               = 30;   // 超过周一高/低点至少多少点才算清扫
input int    SweepLastSession             = 2;    // 最晚第几个交易日确认偏见（1=周二 2=周三）
input bool   EnableBreakoutBias           = true; // 连续收盘站稳周一高/低点外 = 突破偏见（需与周趋势同向）
input int    BreakoutAcceptBars           = 2;    // 站稳需要连续几根周内K线收在外侧
input int    LastTradeSession             = 3;    // 最晚第几个交易日还开仓（3=周四 4=周五）

input group "=== 日内层：M5 双VWAP（CME 18:00 + 纽约 00:00） ==="
input ENUM_TIMEFRAMES ExecTF              = PERIOD_M5;
input int    IntradaySlopeBars            = 12;   // 日内VWAP斜率回看K线数（12根M5=1小时）
input double IntraTrendSlopeSigma         = 0.30; // 两条日内VWAP斜率都 > 此值×σ 且与偏见同向 = 日内趋势
input double IntraRangeSlopeSigma         = 0.15; // 两条日内VWAP斜率都 < 此值×σ = 日内震荡
input int    LondonOpenDelayMinutes       = 30;   // 伦敦开盘(08:00伦敦时间，自动夏令时)后再等多少分钟
input int    TradeEndNYHour               = 15;   // 纽约时间此小时后不再开新仓
input int    CloseAtNYHour                = 16;   // 纽约时间此小时平掉所有持仓（0=关闭）

input group "=== 日内趋势：回踩 0~0.5σ 边缘 ==="
input bool   EnableTrendTrades            = true;
input double PullbackTolSigma             = 0.15;
input double PullbackMaxBelowSigma        = 0.30; // 回踩穿过VWAP最多多少σ
input double TrendTPSigma                 = 2.0;

input group "=== 日内震荡：±2σ 极值反转（只做偏见方向） ==="
input bool   EnableRangeTrades            = true;
input double RangeEntrySigma              = 2.0;
input bool   RangeRequireCloseInside      = true;
input double RangeTPSigma                 = 0.5;  // TP = VWAP ±此σ（0~0.5核心区）
input bool   RangeDynamicTP               = true;

input group "=== PA 价格行为形态 ==="
input bool   UsePinBar                    = true;
input double PinWickBodyRatio             = 2.0;
input double PinWickRangePct              = 0.55;
input bool   UseEngulfing                 = true;
input bool   UseStar                      = true;
input double MinPatternBarATR             = 0.30;

input group "=== 震荡指标综合确认（RSI / Stochastic / CCI） ==="
input int    MinOscConfirm                = 2;
input int    RSIPeriod                    = 14;
input double RSIHigh                      = 70.0;
input double RSILow                       = 30.0;
input double TrendRSIMin                  = 40.0;
input double TrendRSIMax                  = 60.0;
input int    StochK                       = 14;
input int    StochD                       = 3;
input int    StochSlowing                 = 3;
input double StochHigh                    = 80.0;
input double StochLow                     = 20.0;
input int    CCIPeriod                    = 20;
input double CCILevel                     = 100.0;

input group "=== 止损 / 止盈 / 持仓管理 ==="
input int    ATRPeriod                    = 14;
input double SLBufferATR                  = 0.25;
input double MaxSLATR                     = 2.5;
input int    MinSLPoints                  = 150;
input double MinRR                        = 1.0;
input double BreakEvenR                   = 1.0;
input int    MaxHoldBars                  = 48;

input group "=== 资金与风控 ==="
input double RiskPercent                  = 0.5;
input double RiskUSD                      = 0.0;
input double CommissionPerLotRT           = 7.0;
input double MaxLots                      = 1.0;
input int    MaxSpreadPoints              = 60;
input int    MaxTradesPerDay              = 3;
input double DailyMaxLossPct              = 2.0;
input int    MaxConsecLosses              = 2;
input int    CooldownBarsAfterLoss        = 6;

input group "=== 时间 / 其它 ==="
input int    TesterServerGMTOffset        = 2;    // 仅回测：服务器冬令时GMT偏移
input bool   TesterOffsetFollowsUSDST     = true; // 仅回测：服务器随美国夏令时 +1
input long   MagicNumber                  = 26100802;
input int    SlippagePoints               = 30;
input bool   DrawSignals                  = true;
input bool   DrawMondayRange              = true;

//+------------------------------------------------------------------+
//| 时间工具：纽约 / 伦敦夏令时、CME交易日                              |
//+------------------------------------------------------------------+
int g_serverOffset=0;

datetime MakeDate(int year,int month,int day)
{
   if(month>12) { year++; month-=12; }
   MqlDateTime s; ZeroMemory(s);
   s.year=year; s.mon=month; s.day=day;
   return StructToTime(s);
}
int DayOfWeek(datetime t) { return (int)(((long)t/86400+4)%7); }   // 0=周日
int YearOf(datetime t)    { MqlDateTime d; TimeToStruct(t,d); return d.year; }
datetime DayStart(datetime t) { return (datetime)((long)t-(long)t%86400); }

int NthSundayDay(int year,int month,int nth)
{
   int dow=DayOfWeek(MakeDate(year,month,1));
   return 1+((7-dow)%7)+(nth-1)*7;
}
datetime LastSunday(int year,int month)       // 该月最后一个周日 00:00
{
   datetime next1=MakeDate(year,month+1,1);
   int dow=DayOfWeek(next1);
   return next1-(dow==0?7:dow)*86400;
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
int NewYorkOffsetAtUTC(datetime utc)     { EnsureDstYear(YearOf(utc));     return (utc>=g_dstStartUTC && utc<g_dstEndUTC) ? -4 : -5; }
int NewYorkOffsetAtLocal(datetime local) { EnsureDstYear(YearOf(local));   return (local>=g_dstStartLocal && local<g_dstEndLocal) ? -4 : -5; }

int ServerUtcOffsetSeconds(datetime serverTime)
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      int h=TesterServerGMTOffset;
      if(TesterOffsetFollowsUSDST && NewYorkOffsetAtUTC(serverTime-h*3600)==-4) h++;
      return h*3600;
   }
   datetime server=TimeTradeServer(); if(server<=0) server=TimeCurrent();
   datetime utc=TimeGMT();
   if(utc<=0 || server<=0) return 0;
   return (int)MathRound((double)(server-utc)/900.0)*900;
}

datetime ToNYLocal(datetime serverT) { datetime utc=serverT-g_serverOffset; return utc+NewYorkOffsetAtUTC(utc)*3600; }
datetime FromNYLocal(datetime nyLocal) { return nyLocal-NewYorkOffsetAtLocal(nyLocal)*3600+g_serverOffset; }
int NYHour(datetime serverT) { return (int)(((long)ToNYLocal(serverT)%86400)/3600); }

// 最近一次纽约 anchorHour 点（服务器时间）
datetime NewYorkSessionAnchor(datetime serverT,int anchorHour)
{
   datetime ny=ToNYLocal(serverT);
   datetime local=DayStart(ny)+anchorHour*3600;
   if(ny<local) local-=86400;
   return FromNYLocal(local);
}

datetime CmeSessionStart(datetime t) { return NewYorkSessionAnchor(t,18); }
datetime NYMidnight(datetime t)      { return NewYorkSessionAnchor(t,0); }

// CME 周开盘：本周的纽约周日 18:00
datetime WeeklyAnchor(datetime t)
{
   datetime ny=ToNYLocal(CmeSessionStart(t));
   return FromNYLocal(ny-DayOfWeek(ny)*86400);
}

// 本周第几个CME交易日：0=周一(周日18:00开) 1=周二 2=周三 3=周四 4=周五
int SessionIndex(datetime t)
{
   return (int)MathRound((double)(CmeSessionStart(t)-WeeklyAnchor(t))/86400.0);
}

// 伦敦 08:00 开盘（英国夏令时：3月最后周日 ~ 10月最后周日 01:00 UTC）
datetime LondonOpenServer(datetime serverT)
{
   datetime utc=serverT-g_serverOffset;
   datetime day0=DayStart(utc);
   int y=YearOf(utc);
   datetime bstStart=LastSunday(y,3)+3600, bstEnd=LastSunday(y,10)+3600;
   bool bst=(day0+8*3600>=bstStart && day0+8*3600<bstEnd);
   return day0+(bst?7:8)*3600+g_serverOffset;
}

string SessionName(int idx)
{
   string n[5]={"周一","周二","周三","周四","周五"};
   return (idx>=0 && idx<5) ? n[idx] : "周末";
}

//+------------------------------------------------------------------+
//| VWAP 计算（只用已收盘K线）                                         |
//+------------------------------------------------------------------+
class CVwap
{
public:
   MqlRates r[];
   double   vw[],sd[];
   int      n;

   CVwap() { n=0; }

   bool Build(ENUM_TIMEFRAMES tf,datetime anchor)
   {
      n=0;
      datetime t1=iTime(_Symbol,tf,1);
      if(t1<=0 || anchor<=0 || anchor>t1) return false;
      ArraySetAsSeries(r,false);
      int c=CopyRates(_Symbol,tf,anchor,t1,r);
      if(c<=0) return false;
      ArrayResize(vw,c); ArrayResize(sd,c);
      double sV=0,sPV=0,sP2V=0;
      for(int i=0;i<c;i++)
      {
         double p=(r[i].high+r[i].low+r[i].close)/3.0;
         double v=(double)r[i].tick_volume; if(v<=0) v=1.0;
         sV+=v; sPV+=p*v; sP2V+=p*p*v;
         double m=sPV/sV, var=sP2V/sV-m*m; if(var<0) var=0;
         vw[i]=m; sd[i]=MathSqrt(var);
      }
      n=c;
      return true;
   }
   double VW(int s) { int i=n-s; return (i>=0 && i<n) ? vw[i] : 0.0; }
   double SD(int s) { int i=n-s; return (i>=0 && i<n) ? sd[i] : 0.0; }
   bool   Bar(int s,MqlRates &b) { int i=n-s; if(i<0 || i>=n) return false; b=r[i]; return true; }
   bool   Ready(int minBars) { return n>=minBars && SD(1)>0; }
   // VWAP 在 bars 根K线内的移动，以当前σ为单位
   double SlopeSigma(int bars)
   {
      int b=MathMin(MathMax(1,bars),n-1);
      if(b<1 || SD(1)<=0) return 0.0;
      return (VW(1)-VW(1+b))/SD(1);
   }
};

CVwap g_week,g_cme,g_ny;

//+------------------------------------------------------------------+
//| 运行状态                                                          |
//+------------------------------------------------------------------+
enum WEEK_STATE { WK_NONE=0, WK_RANGE=1, WK_UP=2, WK_DOWN=3 };

#define TAG_RANGE "VPA-RNG-"
#define TAG_TREND "VPA-TRD-"
#define OBJ_PREFIX "VPA2_"

ENUM_TIMEFRAMES g_weekTF,g_execTF;
int hRSI=INVALID_HANDLE,hSto=INVALID_HANDLE,hCCI=INVALID_HANDLE,hATR=INVALID_HANDLE;
double rsi[],stK[],stD[],cci[];
double g_atr=0;

datetime g_lastBar=0;
string   g_status="初始化";

WEEK_STATE g_weekState=WK_NONE;
double g_weekSlope=0;
int    g_sessionIdx=-1;
double g_monHigh=0,g_monLow=0;
int    g_bias=0;                 // +1 多 / -1 空 / 0 无
string g_biasText="等待";
double g_slopeCme=0,g_slopeNy=0;
string g_intraText="";

int    g_dayTrades=0,g_dayConsecLoss=0;
double g_dayRealized=0;
datetime g_lastLossTime=0;

//+------------------------------------------------------------------+
//| 周线层：周VWAP格局                                                 |
//+------------------------------------------------------------------+
WEEK_STATE ClassifyWeek()
{
   g_weekSlope=0;
   if(!g_week.Ready(3)) return WK_NONE;
   g_weekSlope=g_week.SlopeSigma(WeekSlopeBars);
   MqlRates b; g_week.Bar(1,b);
   double vw=g_week.VW(1);
   if(MathAbs(g_weekSlope)<WeekRangeSlopeSigma) return WK_RANGE;
   if(g_weekSlope> WeekTrendSlopeSigma && b.close>vw) return WK_UP;
   if(g_weekSlope<-WeekTrendSlopeSigma && b.close<vw) return WK_DOWN;
   return WK_NONE;
}

string WeekText(WEEK_STATE w)
{
   if(w==WK_RANGE) return "周震荡";
   if(w==WK_UP)    return "周上升趋势";
   if(w==WK_DOWN)  return "周下降趋势";
   return "周过渡";
}

//+------------------------------------------------------------------+
//| 周一高低点 + 周二/周三清扫 → 本周偏见（每次从头重算，重启不丢）       |
//+------------------------------------------------------------------+
void DrawMonday(datetime wa,datetime monEnd)
{
   if(!DrawMondayRange || g_monHigh<=0) return;
   string nm=OBJ_PREFIX+"MON_"+IntegerToString((long)wa);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE,0,wa,g_monHigh,monEnd,g_monLow);
   ObjectSetDouble(0,nm,OBJPROP_PRICE,0,g_monHigh);
   ObjectSetDouble(0,nm,OBJPROP_PRICE,1,g_monLow);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clrSlateGray);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,nm,OBJPROP_FILL,false);
   ObjectSetInteger(0,nm,OBJPROP_BACK,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}

void ResolveWeeklyBias()
{
   g_bias=0; g_monHigh=0; g_monLow=0;
   if(g_week.n<=0) { g_biasText="周数据未就绪"; return; }

   datetime wa=WeeklyAnchor(g_week.r[g_week.n-1].time);
   datetime monEnd=wa+86400;
   datetime sweepEnd=wa+(SweepLastSession+1)*86400;
   double tol=SweepMinPoints*_Point;

   double hi=0,lo=DBL_MAX;
   for(int i=0;i<g_week.n;i++)
      if(g_week.r[i].time<monEnd) { hi=MathMax(hi,g_week.r[i].high); lo=MathMin(lo,g_week.r[i].low); }
   if(hi<=0 || lo==DBL_MAX) { g_biasText="周一数据未就绪"; return; }
   g_monHigh=hi; g_monLow=lo;
   DrawMonday(wa,monEnd);

   int bias=0; string how="";
   int aboveRun=0,belowRun=0;
   for(int i=0;i<g_week.n;i++)
   {
      MqlRates b=g_week.r[i];
      if(b.time<monEnd || b.time>=sweepEnd) continue;

      bool bearSweep=(b.high>hi+tol && b.close<hi);   // 扫周一高点后收回 → 偏空
      bool bullSweep=(b.low<lo-tol && b.close>lo);    // 扫周一低点后收回 → 偏多
      aboveRun=(b.close>hi+tol ? aboveRun+1 : 0);
      belowRun=(b.close<lo-tol ? belowRun+1 : 0);
      bool bullBreak=EnableBreakoutBias && aboveRun>=MathMax(1,BreakoutAcceptBars) && g_weekState==WK_UP;
      bool bearBreak=EnableBreakoutBias && belowRun>=MathMax(1,BreakoutAcceptBars) && g_weekState==WK_DOWN;

      int nb=0; string nh="";
      if(bearSweep && bullSweep) { bias=0; how="同一根K线双向清扫，本周不交易"; break; }
      if(bearSweep)      { nb=-1; nh="扫周一高点后收回"; }
      else if(bullSweep) { nb=+1; nh="扫周一低点后收回"; }
      else if(bullBreak) { nb=+1; nh="站稳周一高点上方"; }
      else if(bearBreak) { nb=-1; nh="站稳周一低点下方"; }
      if(nb==0) continue;

      if(bias==0) { bias=nb; how=nh+" @"+TimeToString(b.time,TIME_DATE|TIME_MINUTES); }
      else if(nb==-bias) { bias=0; how="出现反向清扫，偏见作废，本周不交易"; break; }
   }

   if(bias!=0)
   {
      bool conflict=(g_weekState==WK_UP && bias<0) || (g_weekState==WK_DOWN && bias>0);
      if(conflict) { g_biasText=(bias>0?"多":"空")+string("（")+how+"）与"+WeekText(g_weekState)+"冲突，不交易"; return; }
      if(g_weekState==WK_NONE && !AllowBiasInWeekTransition) { g_biasText="周格局过渡，不交易"; return; }
      g_bias=bias;
      g_biasText=(bias>0?"偏多":"偏空")+string("｜")+how;
      return;
   }
   g_biasText=(how!="" ? how : (g_sessionIdx<=SweepLastSession ? "等待清扫周一高/低点" : "截至确认日未出现清扫，本周不交易"));
}

//+------------------------------------------------------------------+
//| 指标                                                              |
//+------------------------------------------------------------------+
bool ReadIndicators()
{
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(stK,true); ArraySetAsSeries(stD,true); ArraySetAsSeries(cci,true);
   double t[]; ArraySetAsSeries(t,true);
   if(CopyBuffer(hRSI,0,1,5,rsi)<5) return false;
   if(CopyBuffer(hSto,0,1,3,stK)<3 || CopyBuffer(hSto,1,1,3,stD)<3) return false;
   if(CopyBuffer(hCCI,0,1,3,cci)<3) return false;
   if(CopyBuffer(hATR,0,1,1,t)<1) return false;
   g_atr=t[0];
   return g_atr>0;
}
double MaxOf(const double &x[],int n) { double r=-DBL_MAX; for(int i=0;i<n && i<ArraySize(x);i++) r=MathMax(r,x[i]); return r; }
double MinOf(const double &x[],int n) { double r= DBL_MAX; for(int i=0;i<n && i<ArraySize(x);i++) r=MathMin(r,x[i]); return r; }

int OscRangeSell() { int c=0; if(MaxOf(rsi,3)>=RSIHigh && rsi[0]<rsi[1]) c++; if(MaxOf(stK,3)>=StochHigh && stK[0]<stD[0] && stK[0]<stK[1]) c++; if(MaxOf(cci,3)>=CCILevel && cci[0]<cci[1]) c++; return c; }
int OscRangeBuy()  { int c=0; if(MinOf(rsi,3)<=RSILow && rsi[0]>rsi[1]) c++; if(MinOf(stK,3)<=StochLow && stK[0]>stD[0] && stK[0]>stK[1]) c++; if(MinOf(cci,3)<=-CCILevel && cci[0]>cci[1]) c++; return c; }
int OscTrendBuy()  { int c=0; if(rsi[0]>=TrendRSIMin && rsi[0]>rsi[1] && MinOf(rsi,5)>=TrendRSIMin-5) c++; if(stK[0]>stD[0] && stK[1]<=stD[1] && MinOf(stK,3)<=50) c++; if(cci[0]>cci[1] && MinOf(cci,3)<=0) c++; return c; }
int OscTrendSell() { int c=0; if(rsi[0]<=TrendRSIMax && rsi[0]<rsi[1] && MaxOf(rsi,5)<=TrendRSIMax+5) c++; if(stK[0]<stD[0] && stK[1]>=stD[1] && MaxOf(stK,3)>=50) c++; if(cci[0]<cci[1] && MaxOf(cci,3)>=0) c++; return c; }

//+------------------------------------------------------------------+
//| PA 形态（M5 已收盘K线）                                            |
//+------------------------------------------------------------------+
bool BigEnough(const MqlRates &b) { return (b.high-b.low)>=MinPatternBarATR*g_atr; }
bool BullPin(const MqlRates &b)
{
   double rng=b.high-b.low; if(rng<=0 || !BigEnough(b)) return false;
   double body=MathAbs(b.close-b.open), lw=MathMin(b.open,b.close)-b.low, uw=b.high-MathMax(b.open,b.close);
   return lw>=PinWickBodyRatio*MathMax(body,_Point) && lw>=PinWickRangePct*rng && uw<=0.25*rng;
}
bool BearPin(const MqlRates &b)
{
   double rng=b.high-b.low; if(rng<=0 || !BigEnough(b)) return false;
   double body=MathAbs(b.close-b.open), uw=b.high-MathMax(b.open,b.close), lw=MathMin(b.open,b.close)-b.low;
   return uw>=PinWickBodyRatio*MathMax(body,_Point) && uw>=PinWickRangePct*rng && lw<=0.25*rng;
}
bool BullEngulf(const MqlRates &b1,const MqlRates &b2)
{ return b2.close<b2.open && b1.close>b1.open && b1.close>=b2.open && b1.open<=b2.close && (b1.close-b1.open)>=(b2.open-b2.close) && BigEnough(b1); }
bool BearEngulf(const MqlRates &b1,const MqlRates &b2)
{ return b2.close>b2.open && b1.close<b1.open && b1.close<=b2.open && b1.open>=b2.close && (b1.open-b1.close)>=(b2.close-b2.open) && BigEnough(b1); }
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

// PA 一律取自 CME 交易日的M5K线（CME 18:00 起，包含纽约0点之后的全部K线）
bool FindBullPA(string &name,double &ext)
{
   MqlRates b1,b2,b3;
   if(!g_cme.Bar(1,b1) || !g_cme.Bar(2,b2)) return false;
   bool has3=g_cme.Bar(3,b3);
   if(UsePinBar && BullPin(b1))                 { name="看涨Pin Bar"; ext=b1.low; return true; }
   if(UseEngulfing && BullEngulf(b1,b2))        { name="看涨吞没";   ext=MathMin(b1.low,b2.low); return true; }
   if(UseStar && has3 && MorningStar(b1,b2,b3)) { name="早晨之星";   ext=MathMin(b1.low,MathMin(b2.low,b3.low)); return true; }
   return false;
}
bool FindBearPA(string &name,double &ext)
{
   MqlRates b1,b2,b3;
   if(!g_cme.Bar(1,b1) || !g_cme.Bar(2,b2)) return false;
   bool has3=g_cme.Bar(3,b3);
   if(UsePinBar && BearPin(b1))                 { name="看跌Pin Bar"; ext=b1.high; return true; }
   if(UseEngulfing && BearEngulf(b1,b2))        { name="看跌吞没";   ext=MathMax(b1.high,b2.high); return true; }
   if(UseStar && has3 && EveningStar(b1,b2,b3)) { name="黄昏之星";   ext=MathMax(b1.high,MathMax(b2.high,b3.high)); return true; }
   return false;
}

//+------------------------------------------------------------------+
//| 当日统计 / 风控                                                   |
//+------------------------------------------------------------------+
void RefreshDayStats()
{
   g_dayTrades=0; g_dayRealized=0; g_dayConsecLoss=0;
   if(!HistorySelect(CmeSessionStart(TimeCurrent()),TimeCurrent()+60)) return;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(d,DEAL_MAGIC)!=MagicNumber) continue;
      long en=HistoryDealGetInteger(d,DEAL_ENTRY);
      double cost=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
      if(en==DEAL_ENTRY_IN) { g_dayTrades++; g_dayRealized+=cost; continue; }
      if(en!=DEAL_ENTRY_OUT && en!=DEAL_ENTRY_OUT_BY) continue;
      double pl=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+cost;
      g_dayRealized+=pl;
      if(pl<0) { g_dayConsecLoss++; g_lastLossTime=(datetime)HistoryDealGetInteger(d,DEAL_TIME); }
      else g_dayConsecLoss=0;
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

// 空串=允许开仓
string EntryBlockReason()
{
   datetime now=TimeCurrent();
   if(g_sessionIdx<=0) return SessionName(g_sessionIdx)+"不开单（周一只收集周VWAP数据）";
   if(g_sessionIdx>LastTradeSession) return SessionName(g_sessionIdx)+"不在开仓日";
   if(g_bias==0) return "本周无偏见："+g_biasText;

   datetime lo=LondonOpenServer(now)+LondonOpenDelayMinutes*60;
   if(now<lo) return "等待伦敦开盘 "+TimeToString(lo,TIME_MINUTES)+"(服务器)";
   int nyh=NYHour(now);
   if(nyh>=TradeEndNYHour) return StringFormat("纽约%d点后不开新仓",TradeEndNYHour);

   MqlTick k; if(!SymbolInfoTick(_Symbol,k)) return "无报价";
   if((k.ask-k.bid)/_Point>MaxSpreadPoints) return StringFormat("点差%.0f过大",(k.ask-k.bid)/_Point);

   if(MaxTradesPerDay>0 && g_dayTrades>=MaxTradesPerDay) return "今日开仓次数已满";
   if(MaxConsecLosses>0 && g_dayConsecLoss>=MaxConsecLosses) return StringFormat("今日连亏%d笔，停止",g_dayConsecLoss);
   if(DailyMaxLossPct>0)
   {
      double base=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayRealized;
      double day=g_dayRealized+FloatingPnL();
      if(base>0 && day<=-base*DailyMaxLossPct/100.0) return StringFormat("今日亏损%.2f达上限",-day);
   }
   if(CooldownBarsAfterLoss>0 && g_lastLossTime>0 &&
      now-g_lastLossTime<(datetime)CooldownBarsAfterLoss*PeriodSeconds(g_execTF)) return "亏损后冷却中";
   return "";
}

//+------------------------------------------------------------------+
//| 下单                                                              |
//+------------------------------------------------------------------+
double MoneyPerPointPerLot()
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE), tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   return (ts>0 && tv>0) ? tv*_Point/ts : 0.0;
}

double LotsForRisk(ENUM_ORDER_TYPE type,double entry,double sl)
{
   double money=(RiskUSD>0 ? RiskUSD : AccountInfoDouble(ACCOUNT_EQUITY)*RiskPercent/100.0);
   double p=0; if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,p)) return 0;
   double perLot=MathAbs(p)+MathMax(0.0,CommissionPerLotRT);
   if(perLot<=0) return 0;
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); if(st<=0) st=mn;
   double lots=MathFloor(money/perLot/st+1e-8)*st;
   lots=MathMin(lots,MathMin(mx,MaxLots));
   if(lots<mn-1e-12) return 0;
   return NormalizeDouble(lots,(st<0.01?3:2));
}

double StopsGap()
{
   return (double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
}

void DrawSignal(bool buy,string text)
{
   if(!DrawSignals) return;
   MqlRates b1; if(!g_cme.Bar(1,b1)) return;
   string nm=OBJ_PREFIX+(buy?"B_":"S_")+IntegerToString((long)b1.time);
   ObjectCreate(0,nm,buy?OBJ_ARROW_BUY:OBJ_ARROW_SELL,0,b1.time,buy?b1.low:b1.high);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,buy?clrLime:clrRed);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,text);
}

bool TryOpen(bool buy,double ext,double tp,string tag,string why)
{
   MqlTick k; if(!SymbolInfoTick(_Symbol,k)) return false;
   double entry=buy?k.ask:k.bid;
   double sl=buy?ext-SLBufferATR*g_atr:ext+SLBufferATR*g_atr;
   double minDist=MathMax(MinSLPoints*_Point,StopsGap()+_Point);
   if(buy && entry-sl<minDist) sl=entry-minDist;
   if(!buy && sl-entry<minDist) sl=entry+minDist;

   double risk=MathAbs(entry-sl), reward=buy?tp-entry:entry-tp;
   if(reward<=StopsGap())  { g_status=why+"｜价格已到目标区，放弃"; return false; }
   if(risk>MaxSLATR*g_atr) { g_status=why+StringFormat("｜止损%.1fATR过大，放弃",risk/g_atr); return false; }
   if(reward/risk<MinRR)   { g_status=why+StringFormat("｜盈亏比%.2f<%.2f，放弃",reward/risk,MinRR); return false; }

   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   double lots=LotsForRisk(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,entry,sl);
   if(lots<=0) { g_status=why+"｜风险金额不足最小手数，放弃"; return false; }

   bool ok=buy?trade.Buy(lots,_Symbol,0,sl,tp,tag):trade.Sell(lots,_Symbol,0,sl,tp,tag);
   if(ok)
   {
      g_status=StringFormat("%s｜%s %.2f手 SL %.*f TP %.*f RR %.2f",why,buy?"买入":"卖出",lots,_Digits,sl,_Digits,tp,reward/risk);
      DrawSignal(buy,g_status);
   }
   else g_status=why+"｜下单失败 retcode="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription();
   Print("VPA2 ",g_status);
   return ok;
}

//+------------------------------------------------------------------+
//| 日内信号（方向只能是本周偏见方向）                                  |
//+------------------------------------------------------------------+
// 日内趋势回踩：src 为触发的那条VWAP（C=CME 18:00，N=纽约0点）
bool TrendPullback(CVwap &v,string src)
{
   double vw=v.VW(1),sd=v.SD(1); if(sd<=0) return false;
   MqlRates b1; if(!g_cme.Bar(1,b1)) return false;
   string pa; double ext;
   string vn=(src=="C"?"CME VWAP":"纽约0点VWAP");

   if(g_bias>0 && FindBullPA(pa,ext))
   {
      double z=(ext-vw)/sd;
      if(z<=0.5+PullbackTolSigma && z>=-PullbackMaxBelowSigma && b1.close>=vw)
      {
         int oc=OscTrendBuy();
         string why=StringFormat("日内趋势做多：回踩%s %.2fσ %s｜指标%d/3",vn,z,pa,oc);
         if(oc>=MinOscConfirm) return TryOpen(true,ext,vw+TrendTPSigma*sd,TAG_TREND+src,why);
         g_status=why+"（确认不足）";
      }
   }
   if(g_bias<0 && FindBearPA(pa,ext))
   {
      double z=(ext-vw)/sd;
      if(z>=-0.5-PullbackTolSigma && z<=PullbackMaxBelowSigma && b1.close<=vw)
      {
         int oc=OscTrendSell();
         string why=StringFormat("日内趋势做空：反弹%s %.2fσ %s｜指标%d/3",vn,z,pa,oc);
         if(oc>=MinOscConfirm) return TryOpen(false,ext,vw-TrendTPSigma*sd,TAG_TREND+src,why);
         g_status=why+"（确认不足）";
      }
   }
   return false;
}

// 日内震荡极值反转：只做偏见方向（偏空只做+2σ，偏多只做-2σ）
bool RangeFade(CVwap &v,string src)
{
   double vw=v.VW(1),sd=v.SD(1); if(sd<=0) return false;
   MqlRates b1; if(!g_cme.Bar(1,b1)) return false;
   string pa; double ext;
   string vn=(src=="C"?"CME VWAP":"纽约0点VWAP");

   if(g_bias<0 && FindBearPA(pa,ext) && (ext-vw)/sd>=RangeEntrySigma &&
      (!RangeRequireCloseInside || b1.close<vw+RangeEntrySigma*sd))
   {
      int oc=OscRangeSell();
      string why=StringFormat("日内震荡做空：%s +%.1fσ %s｜指标%d/3",vn,(ext-vw)/sd,pa,oc);
      if(oc>=MinOscConfirm) return TryOpen(false,ext,vw+RangeTPSigma*sd,TAG_RANGE+src,why);
      g_status=why+"（确认不足）";
   }
   if(g_bias>0 && FindBullPA(pa,ext) && (vw-ext)/sd>=RangeEntrySigma &&
      (!RangeRequireCloseInside || b1.close>vw-RangeEntrySigma*sd))
   {
      int oc=OscRangeBuy();
      string why=StringFormat("日内震荡做多：%s -%.1fσ %s｜指标%d/3",vn,(vw-ext)/sd,pa,oc);
      if(oc>=MinOscConfirm) return TryOpen(true,ext,vw-RangeTPSigma*sd,TAG_RANGE+src,why);
      g_status=why+"（确认不足）";
   }
   return false;
}

void CheckIntradaySignals()
{
   if(!g_cme.Ready(IntradaySlopeBars+1) || !g_ny.Ready(IntradaySlopeBars+1))
   { g_intraText="日内VWAP数据不足"; return; }

   g_slopeCme=g_cme.SlopeSigma(IntradaySlopeBars);
   g_slopeNy =g_ny.SlopeSigma(IntradaySlopeBars);

   double th=IntraTrendSlopeSigma*(g_bias>0?1:-1);
   bool trend=(g_bias>0 ? (g_slopeCme>th && g_slopeNy>th) : (g_slopeCme<th && g_slopeNy<th));
   bool flat =(MathAbs(g_slopeCme)<IntraRangeSlopeSigma && MathAbs(g_slopeNy)<IntraRangeSlopeSigma);

   if(trend)
   {
      g_intraText="日内趋势与偏见同向";
      if(EnableTrendTrades && !TrendPullback(g_ny,"N")) TrendPullback(g_cme,"C");
   }
   else if(flat)
   {
      g_intraText="日内震荡（只做偏见方向的极值反转）";
      if(EnableRangeTrades && !RangeFade(g_cme,"C")) RangeFade(g_ny,"N");
   }
   else g_intraText="等待日内VWAP走出与偏见同向的趋势";
}

//+------------------------------------------------------------------+
//| 持仓管理                                                          |
//+------------------------------------------------------------------+
void ClosePos(ulong t,string why)
{
   if(trade.PositionClose(t,SlippagePoints)) Print("VPA2 平仓 ",t,"：",why);
   g_status="平仓："+why;
}

void ManagePositions()
{
   datetime now=TimeCurrent();
   int nyh=NYHour(now);
   bool closeTime=(CloseAtNYHour>0 && nyh>=CloseAtNYHour && nyh<18);
   double gap=StopsGap(), mpp=MoneyPerPointPerLot();
   int barSec=PeriodSeconds(g_execTF);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      string cmt=PositionGetString(POSITION_COMMENT);
      bool isRange=(StringFind(cmt,TAG_RANGE)==0);
      double open=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double cur=buy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);

      if(closeTime) { ClosePos(t,StringFormat("纽约%d点日内平仓",CloseAtNYHour)); continue; }
      if(MaxHoldBars>0 && now-opened>=(datetime)MaxHoldBars*barSec) { ClosePos(t,StringFormat("持仓超过%d根K线",MaxHoldBars)); continue; }
      if(g_bias!=0 && ((buy && g_bias<0) || (!buy && g_bias>0))) { ClosePos(t,"本周偏见已反转"); continue; }

      // 震荡单：TP 跟随触发它的那条 VWAP 的 0~0.5σ 核心区
      if(isRange && RangeDynamicTP)
      {
         bool useNy=(StringFind(cmt,TAG_RANGE+"N")==0);
         double vw=useNy?g_ny.VW(1):g_cme.VW(1), sd=useNy?g_ny.SD(1):g_cme.SD(1);
         if(sd>0)
         {
            double nt=NormalizeDouble(buy?vw-RangeTPSigma*sd:vw+RangeTPSigma*sd,_Digits);
            if((buy && cur>=nt) || (!buy && cur<=nt)) { ClosePos(t,"已回到VWAP核心区"); continue; }
            if(MathAbs(nt-tp)>=10*_Point && MathAbs(cur-nt)>gap && trade.PositionModify(t,sl,nt)) tp=nt;
         }
      }

      // 推保本（SL仍在亏损侧时）
      if(BreakEvenR>0 && sl>0 && (buy?sl<open:sl>open))
      {
         double R=MathAbs(open-sl), move=buy?cur-open:open-cur;
         if(R>0 && move>=BreakEvenR*R)
         {
            double costPts=(mpp>0?CommissionPerLotRT/mpp:0)+10;
            double be=NormalizeDouble(buy?open+costPts*_Point:open-costPts*_Point,_Digits);
            if((buy && cur-be>gap) || (!buy && be-cur>gap)) trade.PositionModify(t,be,tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 面板                                                              |
//+------------------------------------------------------------------+
void ShowPanel(string block)
{
   datetime now=TimeCurrent();
   Comment(StringFormat(
      "Jammy VWAP PA 全自动 EA v2.00｜执行 %s｜周内 %s\n"
      "【周】%s｜周VWAP斜率 %.2fσ｜%s｜周一高 %.*f 低 %.*f\n"
      "【偏见】%s\n"
      "【日内】CME VWAP 斜率 %.2fσ｜纽约0点 VWAP 斜率 %.2fσ｜%s\n"
      "纽约时间 %02d点｜伦敦开盘(服务器) %s\n"
      "今日：开仓 %d/%d｜已实现 %.2f｜浮动 %.2f｜连亏 %d\n"
      "开仓许可：%s\n"
      "最近：%s",
      EnumToString(g_execTF),EnumToString(g_weekTF),
      WeekText(g_weekState),g_weekSlope,SessionName(g_sessionIdx),_Digits,g_monHigh,_Digits,g_monLow,
      g_biasText,
      g_slopeCme,g_slopeNy,g_intraText,
      NYHour(now),TimeToString(LondonOpenServer(now),TIME_MINUTES),
      g_dayTrades,MaxTradesPerDay,g_dayRealized,FloatingPnL(),g_dayConsecLoss,
      block==""?"允许":block,
      g_status));
}

//+------------------------------------------------------------------+
//| 生命周期                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // 周内分析周期限定 M15~H1
   g_weekTF=WeekTF;
   if(PeriodSeconds(g_weekTF)<PeriodSeconds(PERIOD_M15)) g_weekTF=PERIOD_M15;
   if(PeriodSeconds(g_weekTF)>PeriodSeconds(PERIOD_H1))  g_weekTF=PERIOD_H1;
   g_execTF=ExecTF;

   hRSI=iRSI(_Symbol,g_execTF,RSIPeriod,PRICE_CLOSE);
   hSto=iStochastic(_Symbol,g_execTF,StochK,StochD,StochSlowing,MODE_SMA,STO_LOWHIGH);
   hCCI=iCCI(_Symbol,g_execTF,CCIPeriod,PRICE_TYPICAL);
   hATR=iATR(_Symbol,g_execTF,ATRPeriod);
   if(hRSI==INVALID_HANDLE || hSto==INVALID_HANDLE || hCCI==INVALID_HANDLE || hATR==INVALID_HANDLE)
   { Print("VPA2 指标句柄创建失败"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_lastBar=0;
   g_status="等待新K线";
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI); IndicatorRelease(hSto); IndicatorRelease(hCCI); IndicatorRelease(hATR);
   Comment("");
   if(reason==REASON_REMOVE) ObjectsDeleteAll(0,OBJ_PREFIX);
}

void OnTick()
{
   // 每根 M5 新K线开盘运行一次，信号全部来自已收盘K线
   datetime bar=iTime(_Symbol,g_execTF,0);
   if(bar<=0 || bar==g_lastBar) return;
   g_lastBar=bar;

   datetime now=TimeCurrent();
   g_serverOffset=ServerUtcOffsetSeconds(now);
   g_sessionIdx=SessionIndex(now);

   // 周线层
   g_week.Build(g_weekTF,WeeklyAnchor(now));
   g_weekState=ClassifyWeek();
   ResolveWeeklyBias();

   // 日内层：两条日内VWAP
   g_cme.Build(g_execTF,CmeSessionStart(now));
   g_ny.Build(g_execTF,NYMidnight(now));
   bool indOk=ReadIndicators();

   RefreshDayStats();
   ManagePositions();

   string block=indOk?EntryBlockReason():"指标数据未就绪";
   g_intraText="";
   if(block=="" && MyPositions()==0) CheckIntradaySignals();
   ShowPanel(block);
}
