//+------------------------------------------------------------------+
//| Jammy ICT Suite：SMT 相关性背离 + 市场结构 + FVG + OB + 流动性      |
//|                 + 折价/溢价/OTE + Killzone + CRT                   |
//| 每根新K线重算一次（只用已收盘K线，不重绘），全部用图形对象绘制。       |
//+------------------------------------------------------------------+
#property copyright "Jammy"
#property version   "1.00"
#property description "Jammy ICT Suite v1.00：SMT / 结构(BOS·CHoCH) / FVG / OB / 流动性 / 折价溢价·OTE / Killzone / CRT"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| 参数                                                              |
//+------------------------------------------------------------------+
input group "=== 通用 ==="
input int    LookbackBars        = 400;   // 分析的K线数（越大越慢）
input int    SwingLen            = 3;     // 波段点：左右各多少根K线
input int    ATRPeriod           = 14;

input group "=== SMT 相关性背离 ==="
input bool   ShowSMT             = true;
input string SMTCandidates       = "XAGUSD,DXY,USDX,EURUSD,XPTUSD,US500"; // 候选品种（自动匹配经纪商后缀）
input int    CorrBars            = 120;   // 相关系数回看K线数（收益率相关）
input double MinAbsCorr          = 0.60;  // |相关系数| 至少多少才判 SMT
input int    SMTMaxPairs         = 6;     // 最多回看多少组相邻波段

input group "=== 市场结构 ==="
input bool   ShowStructure       = true;
input bool   ShowSwingPoints     = false;
input color  BullStructColor     = clrLimeGreen;
input color  BearStructColor     = clrTomato;

input group "=== FVG 公允价值缺口 ==="
input bool   ShowFVG             = true;
input double MinFVGATR           = 0.15;  // 缺口至少多少倍ATR
input bool   ShowFilledFVG       = false;
input color  BullFVGColor        = C'0,90,60';
input color  BearFVGColor        = C'100,30,40';

input group "=== Order Block 订单块 ==="
input bool   ShowOB              = true;
input int    MaxOB               = 4;     // 每个方向最多显示几个未失效OB
input color  BullOBColor         = C'20,70,120';
input color  BearOBColor         = C'110,60,10';

input group "=== 流动性 ==="
input bool   ShowLiquidity       = true;
input double EqualTolATR         = 0.10;  // 等高/等低容差（ATR倍数）
input bool   ShowSweeps          = true;

input group "=== 折价 / 溢价 / OTE ==="
input bool   ShowPremiumDiscount = true;

input group "=== Killzone（纽约时间） ==="
input bool   ShowKillzones       = true;
input int    KillzoneDays        = 3;
input bool   ShowMidnightOpen    = true;
input int    TesterServerGMTOffset = 2;   // 仅回测：服务器冬令时GMT偏移
input bool   TesterOffsetFollowsUSDST = true;

input group "=== CRT 蜡烛区间理论 ==="
input bool   ShowCRT             = true;
input ENUM_TIMEFRAMES CRT_TF     = PERIOD_H4; // CRT 高周期（H1/H4/D1）
input int    CRTLookback         = 6;     // 回看多少组高周期K线

input group "=== 提醒 ==="
input bool   AlertPopup          = true;
input bool   AlertPush           = false; // 推送到手机（需配置 MetaQuotes ID）
input bool   AlertOnSMT          = true;
input bool   AlertOnCRT          = true;
input bool   AlertOnCHoCH        = true;
input bool   AlertOnSweep        = false;
input int    AlertRecentBars     = 2;     // 只对最近几根K线内出现的信号提醒

//+------------------------------------------------------------------+
#define PFX "JICT_"

int      hATR=INVALID_HANDLE;
datetime g_lastBar=0;
int      g_serverOffset=0;
double   g_atr=0;

// 本周期数据（series：0=当前未收盘K线）
int      N=0;
datetime T[]; double O[],H[],L[],C[];

// 波段点（按时间从旧到新）
struct SWING { int idx; double price; datetime time; bool high; };
SWING g_sw[];

string g_smtSym="";
double g_smtCorr=0;
string g_corrTable="";
int    g_trend=0;
string g_lastEvent="";
string g_crtText="";
string g_alerted[];

//+------------------------------------------------------------------+
//| 时间：纽约夏令时（与 Jammy VWAP 指标同算法）                         |
//+------------------------------------------------------------------+
datetime MakeDate(int y,int m,int d) { MqlDateTime s; ZeroMemory(s); s.year=y; s.mon=m; s.day=d; return StructToTime(s); }
int DayOfWeek(datetime t) { return (int)(((long)t/86400+4)%7); }
int YearOf(datetime t) { MqlDateTime d; TimeToStruct(t,d); return d.year; }
datetime DayStart(datetime t) { return (datetime)((long)t-(long)t%86400); }
int NthSundayDay(int y,int m,int nth) { int dow=DayOfWeek(MakeDate(y,m,1)); return 1+((7-dow)%7)+(nth-1)*7; }

int NewYorkOffsetAtUTC(datetime utc)
{
   int y=YearOf(utc);
   datetime s=MakeDate(y,3,NthSundayDay(y,3,2))+7*3600;
   datetime e=MakeDate(y,11,NthSundayDay(y,11,1))+6*3600;
   return (utc>=s && utc<e) ? -4 : -5;
}
int NewYorkOffsetAtLocal(datetime local)
{
   int y=YearOf(local);
   datetime s=MakeDate(y,3,NthSundayDay(y,3,2))+2*3600;
   datetime e=MakeDate(y,11,NthSundayDay(y,11,1))+2*3600;
   return (local>=s && local<e) ? -4 : -5;
}
int ServerUtcOffsetSeconds()
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      int h=TesterServerGMTOffset;
      if(TesterOffsetFollowsUSDST && NewYorkOffsetAtUTC(TimeCurrent()-h*3600)==-4) h++;
      return h*3600;
   }
   datetime sv=TimeTradeServer(); if(sv<=0) sv=TimeCurrent();
   datetime utc=TimeGMT(); if(utc<=0 || sv<=0) return 0;
   return (int)MathRound((double)(sv-utc)/900.0)*900;
}
datetime ToNY(datetime server)   { datetime u=server-g_serverOffset; return u+NewYorkOffsetAtUTC(u)*3600; }
datetime FromNY(datetime nyLoc)  { return nyLoc-NewYorkOffsetAtLocal(nyLoc)*3600+g_serverOffset; }

//+------------------------------------------------------------------+
//| 绘图工具                                                          |
//+------------------------------------------------------------------+
datetime RightEdge() { return T[0]+PeriodSeconds()*10; }

void Rect(string name,datetime t1,double p1,datetime t2,double p2,color c,bool fill=true,int style=STYLE_SOLID)
{
   string n=PFX+name;
   ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_FILL,fill);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

void Seg(string name,datetime t1,double p1,datetime t2,double p2,color c,int style=STYLE_SOLID,int width=1)
{
   string n=PFX+name;
   ObjectCreate(0,n,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

void Txt(string name,datetime t,double p,string text,color c,int size=7,ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_LOWER)
{
   string n=PFX+name;
   ObjectCreate(0,n,OBJ_TEXT,0,t,p);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,n,OBJPROP_FONT,"Microsoft YaHei");
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

void Mark(string name,datetime t,double p,bool up,color c)
{
   string n=PFX+name;
   ObjectCreate(0,n,OBJ_ARROW,0,t,p);
   ObjectSetInteger(0,n,OBJPROP_ARROWCODE,up?233:234);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,up?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

//+------------------------------------------------------------------+
//| 提醒（同一事件只提醒一次）                                          |
//+------------------------------------------------------------------+
void Notify(string key,string msg,int barIdx)
{
   if(barIdx>MathMax(1,AlertRecentBars)) return;
   for(int i=0;i<ArraySize(g_alerted);i++) if(g_alerted[i]==key) return;
   int n=ArraySize(g_alerted); if(n>300) { ArrayRemove(g_alerted,0,100); n=ArraySize(g_alerted); }
   ArrayResize(g_alerted,n+1); g_alerted[n]=key;
   string full=_Symbol+" "+StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7)+"｜"+msg;
   if(AlertPopup) Alert(full);
   if(AlertPush) SendNotification(StringSubstr(full,0,250));
}

//+------------------------------------------------------------------+
//| 波段点                                                            |
//+------------------------------------------------------------------+
bool IsSwingHigh(int i) { for(int k=1;k<=SwingLen;k++) if(H[i]<=H[i-k] || H[i]<H[i+k]) return false; return true; }
bool IsSwingLow(int i)  { for(int k=1;k<=SwingLen;k++) if(L[i]>=L[i-k] || L[i]>L[i+k]) return false; return true; }

void BuildSwings()
{
   ArrayResize(g_sw,0);
   // i 从旧到新；i-SwingLen>=1 保证右侧K线都已收盘
   for(int i=N-1-SwingLen;i>=SwingLen+1;i--)
   {
      bool sh=IsSwingHigh(i), sl=IsSwingLow(i);
      if(sh) { int k=ArraySize(g_sw); ArrayResize(g_sw,k+1); g_sw[k].idx=i; g_sw[k].price=H[i]; g_sw[k].time=T[i]; g_sw[k].high=true; }
      if(sl) { int k=ArraySize(g_sw); ArrayResize(g_sw,k+1); g_sw[k].idx=i; g_sw[k].price=L[i]; g_sw[k].time=T[i]; g_sw[k].high=false; }
   }
   if(ShowSwingPoints)
      for(int k=0;k<ArraySize(g_sw);k++)
         Txt("SW"+IntegerToString(k),g_sw[k].time,g_sw[k].price,g_sw[k].high?"▼":"▲",clrSilver,7,g_sw[k].high?ANCHOR_LOWER:ANCHOR_UPPER);
}

//+------------------------------------------------------------------+
//| 市场结构 BOS / CHoCH + 订单块 + 扫流动性                            |
//+------------------------------------------------------------------+
struct OBZONE { datetime t; double top,bot; bool bull; bool dead; int bornIdx; };
OBZONE g_ob[];

bool Opposite(int i,bool bull) { return bull ? C[i]<O[i] : C[i]>O[i]; }

// OB = 推动段起点（波段低/高点）处最后一根反向K线：
// 先在波段点及其之前 SwingLen 根里找最近的一根反向K线，没有再往波段点之后找。
void AddOB(bool bull,int pivotIdx,int breakIdx,int bornIdx)
{
   int best=-1;
   for(int i=pivotIdx;i<=pivotIdx+SwingLen && i<N;i++) if(Opposite(i,bull)) { best=i; break; }
   if(best<0) for(int i=pivotIdx-1;i>breakIdx;i--) if(Opposite(i,bull)) { best=i; break; }
   if(best<0) return;
   int k=ArraySize(g_ob); ArrayResize(g_ob,k+1);
   g_ob[k].t=T[best]; g_ob[k].top=H[best]; g_ob[k].bot=L[best]; g_ob[k].bull=bull; g_ob[k].dead=false; g_ob[k].bornIdx=bornIdx;
}

void Structure()
{
   ArrayResize(g_ob,0);
   g_trend=0;
   int nsw=ArraySize(g_sw);
   int lastH=-1,lastL=-1;           // g_sw 下标
   bool hBroken=true,lBroken=true;
   int si=0;

   for(int i=N-1;i>=1;i--)           // 逐根已收盘K线，从旧到新
   {
      // 波段点在右侧 SwingLen 根收盘后才确认
      while(si<nsw && g_sw[si].idx-SwingLen>=i)
      {
         if(g_sw[si].high) { lastH=si; hBroken=false; } else { lastL=si; lBroken=false; }
         si++;
      }

      if(lastH>=0 && !hBroken)
      {
         double lv=g_sw[lastH].price;
         if(C[i]>lv)
         {
            hBroken=true;
            string kind=(g_trend<0?"CHoCH":"BOS");
            g_trend=1;
            if(ShowStructure)
            {
               Seg("BU"+IntegerToString(i),g_sw[lastH].time,lv,T[i],lv,BullStructColor,STYLE_DOT);
               Txt("BUt"+IntegerToString(i),T[i],lv,kind,BullStructColor,7,ANCHOR_RIGHT_LOWER);
            }
            if(kind=="CHoCH") { g_lastEvent="多头 CHoCH @ "+DoubleToString(lv,_Digits); if(AlertOnCHoCH) Notify("CHU"+IntegerToString((long)T[i]),"多头 CHoCH 结构转换",i); }
            if(ShowOB && lastL>=0) AddOB(true,g_sw[lastL].idx,i,i);
         }
         else if(ShowSweeps && H[i]>lv && C[i]<lv)
         {
            hBroken=true;   // 流动性被扫，该高点作废
            Mark("SWH"+IntegerToString(i),T[i],H[i],false,BearStructColor);
            Txt("SWHt"+IntegerToString(i),T[i],H[i],"扫BSL",BearStructColor,7,ANCHOR_LEFT_LOWER);
            if(AlertOnSweep) Notify("SWH"+IntegerToString((long)T[i]),"扫上方流动性(BSL)后收回",i);
         }
      }
      if(lastL>=0 && !lBroken)
      {
         double lv=g_sw[lastL].price;
         if(C[i]<lv)
         {
            lBroken=true;
            string kind=(g_trend>0?"CHoCH":"BOS");
            g_trend=-1;
            if(ShowStructure)
            {
               Seg("BD"+IntegerToString(i),g_sw[lastL].time,lv,T[i],lv,BearStructColor,STYLE_DOT);
               Txt("BDt"+IntegerToString(i),T[i],lv,kind,BearStructColor,7,ANCHOR_RIGHT_UPPER);
            }
            if(kind=="CHoCH") { g_lastEvent="空头 CHoCH @ "+DoubleToString(lv,_Digits); if(AlertOnCHoCH) Notify("CHD"+IntegerToString((long)T[i]),"空头 CHoCH 结构转换",i); }
            if(ShowOB && lastH>=0) AddOB(false,g_sw[lastH].idx,i,i);
         }
         else if(ShowSweeps && L[i]<lv && C[i]>lv)
         {
            lBroken=true;
            Mark("SWL"+IntegerToString(i),T[i],L[i],true,BullStructColor);
            Txt("SWLt"+IntegerToString(i),T[i],L[i],"扫SSL",BullStructColor,7,ANCHOR_LEFT_UPPER);
            if(AlertOnSweep) Notify("SWL"+IntegerToString((long)T[i]),"扫下方流动性(SSL)后收回",i);
         }
      }

      // 订单块失效：收盘穿过OB另一侧
      for(int k=0;k<ArraySize(g_ob);k++)
      {
         if(g_ob[k].dead || i>=g_ob[k].bornIdx) continue;
         if(g_ob[k].bull && C[i]<g_ob[k].bot) g_ob[k].dead=true;
         if(!g_ob[k].bull && C[i]>g_ob[k].top) g_ob[k].dead=true;
      }
   }

   if(ShowOB)
   {
      int nb=0,ns=0;
      for(int k=ArraySize(g_ob)-1;k>=0;k--)
      {
         if(g_ob[k].dead) continue;
         if(g_ob[k].bull && nb>=MaxOB) continue;
         if(!g_ob[k].bull && ns>=MaxOB) continue;
         if(g_ob[k].bull) nb++; else ns++;
         Rect("OB"+IntegerToString(k),g_ob[k].t,g_ob[k].top,RightEdge(),g_ob[k].bot,g_ob[k].bull?BullOBColor:BearOBColor);
         Txt("OBt"+IntegerToString(k),RightEdge(),g_ob[k].bull?g_ob[k].bot:g_ob[k].top,g_ob[k].bull?"多头OB":"空头OB",
             g_ob[k].bull?clrDeepSkyBlue:clrOrange,7,g_ob[k].bull?ANCHOR_RIGHT_UPPER:ANCHOR_RIGHT_LOWER);
      }
   }
}

//+------------------------------------------------------------------+
//| FVG                                                               |
//+------------------------------------------------------------------+
void FVG()
{
   if(!ShowFVG) return;
   double minGap=MinFVGATR*g_atr;
   for(int i=N-3;i>=1;i--)          // i=第三根（最新）K线，i+1=中间K线，i+2=第一根
   {
      bool bull=(L[i]>H[i+2] && L[i]-H[i+2]>=minGap);
      bool bear=(H[i]<L[i+2] && L[i+2]-H[i]>=minGap);
      if(!bull && !bear) continue;
      double top=bull?L[i]:L[i+2], bot=bull?H[i+2]:H[i];

      int filledAt=-1;
      for(int k=i-1;k>=1;k--)
         if((bull && L[k]<=bot) || (bear && H[k]>=top)) { filledAt=k; break; }
      if(filledAt>=0 && !ShowFilledFVG) continue;

      datetime t2=(filledAt>=0?T[filledAt]:RightEdge());
      Rect("FVG"+IntegerToString(i),T[i+1],top,t2,bot,bull?BullFVGColor:BearFVGColor);
      if(filledAt<0) Txt("FVGt"+IntegerToString(i),t2,bull?bot:top,bull?"FVG↑":"FVG↓",bull?clrMediumSeaGreen:clrIndianRed,7,bull?ANCHOR_RIGHT_UPPER:ANCHOR_RIGHT_LOWER);
   }
}

//+------------------------------------------------------------------+
//| 流动性：等高 / 等低                                                |
//+------------------------------------------------------------------+
void EqualHighsLows()
{
   if(!ShowLiquidity) return;
   double tol=EqualTolATR*g_atr;
   int lastH=-1,lastL=-1;
   for(int k=0;k<ArraySize(g_sw);k++)
   {
      if(g_sw[k].high)
      {
         if(lastH>=0 && MathAbs(g_sw[k].price-g_sw[lastH].price)<=tol)
         {
            double lv=MathMax(g_sw[k].price,g_sw[lastH].price);
            Seg("EQH"+IntegerToString(k),g_sw[lastH].time,lv,RightEdge(),lv,clrGold,STYLE_DASHDOT);
            Txt("EQHt"+IntegerToString(k),RightEdge(),lv,"EQH 买方流动性",clrGold,7,ANCHOR_RIGHT_LOWER);
         }
         lastH=k;
      }
      else
      {
         if(lastL>=0 && MathAbs(g_sw[k].price-g_sw[lastL].price)<=tol)
         {
            double lv=MathMin(g_sw[k].price,g_sw[lastL].price);
            Seg("EQL"+IntegerToString(k),g_sw[lastL].time,lv,RightEdge(),lv,clrGold,STYLE_DASHDOT);
            Txt("EQLt"+IntegerToString(k),RightEdge(),lv,"EQL 卖方流动性",clrGold,7,ANCHOR_RIGHT_UPPER);
         }
         lastL=k;
      }
   }
}

//+------------------------------------------------------------------+
//| 折价 / 溢价 / OTE（最近一段波段区间）                               |
//+------------------------------------------------------------------+
void PremiumDiscount()
{
   if(!ShowPremiumDiscount) return;
   int hi=-1,lo=-1;
   for(int k=ArraySize(g_sw)-1;k>=0 && (hi<0 || lo<0);k--)
   {
      if(g_sw[k].high && hi<0) hi=k;
      if(!g_sw[k].high && lo<0) lo=k;
   }
   if(hi<0 || lo<0) return;
   double top=g_sw[hi].price, bot=g_sw[lo].price;
   if(top<=bot) return;
   datetime t1=(g_sw[hi].time<g_sw[lo].time?g_sw[hi].time:g_sw[lo].time), t2=RightEdge();
   double eq=(top+bot)/2.0;
   bool upLeg=(g_sw[lo].time<g_sw[hi].time);   // 先低后高 = 上涨段，在折价区找多

   Seg("EQ",t1,eq,t2,eq,clrSilver,STYLE_DASH);
   Txt("EQt",t2,eq,"EQ 50%",clrSilver,7,ANCHOR_RIGHT_LOWER);
   Seg("RH",t1,top,t2,top,clrDimGray,STYLE_DOT);
   Seg("RL",t1,bot,t2,bot,clrDimGray,STYLE_DOT);
   Txt("PRt",t2,top,"溢价区",clrIndianRed,7,ANCHOR_RIGHT_UPPER);
   Txt("DSt",t2,bot,"折价区",clrMediumSeaGreen,7,ANCHOR_RIGHT_LOWER);

   double r=top-bot;
   double o1=upLeg?top-0.62*r:bot+0.62*r, o2=upLeg?top-0.79*r:bot+0.79*r;
   Rect("OTE",t1,o1,t2,o2,upLeg?C'0,60,40':C'70,25,30');
   Txt("OTEt",t2,(o1+o2)/2,upLeg?"OTE 多 62-79%":"OTE 空 62-79%",upLeg?clrMediumSeaGreen:clrIndianRed,7,ANCHOR_RIGHT);
}

//+------------------------------------------------------------------+
//| Killzone + 纽约午夜开盘价                                          |
//+------------------------------------------------------------------+
void KillzoneBox(string id,datetime nyDay,int h1,int m1,int h2,int m2,color c,string label)
{
   datetime s=FromNY(nyDay+h1*3600+m1*60);
   datetime e=FromNY(nyDay+h2*3600+m2*60);
   if(h2<h1) e=FromNY(nyDay+86400+h2*3600+m2*60);
   if(s>T[0]) return;
   datetime eEnd=(e<T[0]?e:T[0]);
   int is=iBarShift(_Symbol,_Period,s,false), ie=iBarShift(_Symbol,_Period,eEnd,false);
   if(is<0 || ie<0 || is<ie || is>=N) return;
   int kh=iHighest(_Symbol,_Period,MODE_HIGH,is-ie+1,ie), kl=iLowest(_Symbol,_Period,MODE_LOW,is-ie+1,ie);
   if(kh<0 || kl<0) return;
   double hi=iHigh(_Symbol,_Period,kh), lo=iLow(_Symbol,_Period,kl);
   Rect("KZ"+id,s,hi,e,lo,c,false,STYLE_DOT);
   Txt("KZt"+id,s,hi,label,c,7,ANCHOR_LEFT_LOWER);
}

void Killzones()
{
   if(!ShowKillzones && !ShowMidnightOpen) return;
   if(PeriodSeconds()>PeriodSeconds(PERIOD_H1)) return;   // 只在 H1 及以下显示
   datetime nyNow=ToNY(T[0]);
   datetime nyToday=DayStart(nyNow);
   for(int d=0;d<MathMax(1,KillzoneDays);d++)
   {
      datetime day=nyToday-d*86400;
      int dow=DayOfWeek(day);
      if(dow==0 || dow==6) continue;
      string id=IntegerToString((long)day);
      if(ShowKillzones)
      {
         KillzoneBox("A"+id,day-86400,20,0,0,0,clrMediumPurple,"亚洲");
         KillzoneBox("L"+id,day,2,0,5,0,clrDodgerBlue,"伦敦 KZ");
         KillzoneBox("N"+id,day,7,0,10,0,clrOrange,"纽约AM KZ");
         KillzoneBox("P"+id,day,13,30,16,0,clrGoldenrod,"纽约PM");
      }
      if(ShowMidnightOpen)
      {
         datetime mo=FromNY(day);
         int sh=iBarShift(_Symbol,_Period,mo,false);
         if(sh>=0 && sh<N && MathAbs((long)(T[sh]-mo))<PeriodSeconds())
         {
            datetime end=(d==0?RightEdge():FromNY(day+17*3600));
            Seg("MO"+id,T[sh],O[sh],end,O[sh],clrWhite,STYLE_DASH);
            Txt("MOt"+id,end,O[sh],"纽约午夜开盘",clrWhite,7,ANCHOR_RIGHT_LOWER);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CRT：高周期前一根K线区间被扫后收回                                   |
//+------------------------------------------------------------------+
void CRT()
{
   g_crtText="";
   if(!ShowCRT || PeriodSeconds(CRT_TF)<=PeriodSeconds()) { if(ShowCRT) g_crtText="CRT 需高于当前周期"; return; }
   MqlRates r[]; ArraySetAsSeries(r,true);
   int got=CopyRates(_Symbol,CRT_TF,0,CRTLookback+2,r);
   if(got<3) return;

   for(int j=MathMin(CRTLookback,got-2);j>=0;j--)
   {
      // C1=r[j+1]（区间K线）  C2=r[j]（扫区间的K线，j=0 为进行中）
      double h1=r[j+1].high, l1=r[j+1].low, mid=(h1+l1)/2;
      datetime t1=r[j+1].time, t2=r[j].time+PeriodSeconds(CRT_TF);
      bool live=(j==0);
      double c2close=r[j].close;
      if(live)   // 进行中的高周期K线：用本周期最新已收盘K线的收盘价判断
      {
         c2close=C[1];
      }

      bool bear=(r[j].high>h1 && c2close<h1 && c2close>l1);   // 扫高点收回 → 目标区间低点
      bool bull=(r[j].low<l1  && c2close>l1 && c2close<h1);   // 扫低点收回 → 目标区间高点
      if(!bear && !bull) continue;

      string id=IntegerToString((long)t1);
      color c=bear?clrTomato:clrLimeGreen;
      Rect("CRT"+id,t1,h1,t2,l1,c,false,STYLE_SOLID);
      Seg("CRTm"+id,t1,mid,t2,mid,c,STYLE_DOT);
      string label=StringFormat("CRT%s %s｜目标 %s",bear?"空":"多",live?"(进行中)":"",
                                DoubleToString(bear?l1:h1,_Digits));
      Txt("CRTt"+id,t1,bear?h1:l1,label,c,8,bear?ANCHOR_LEFT_LOWER:ANCHOR_LEFT_UPPER);
      if(j<=1)
      {
         g_crtText=StringFormat("%s %s：扫%s %s 后收回，目标 50%% %s / 区间%s %s",
                   StringSubstr(EnumToString(CRT_TF),7),bear?"空":"多",bear?"前高":"前低",DoubleToString(bear?h1:l1,_Digits),
                   DoubleToString(mid,_Digits),bear?"低":"高",DoubleToString(bear?l1:h1,_Digits));
         if(AlertOnCRT) Notify("CRT"+id+(bear?"S":"B"),"CRT"+(bear?"空":"多")+"："+g_crtText,1);
      }
   }
}

//+------------------------------------------------------------------+
//| SMT：相关品种选择 + 波段背离                                        |
//+------------------------------------------------------------------+
string FindBrokerSymbol(string base)
{
   if(SymbolSelect(base,true) && SymbolInfoInteger(base,SYMBOL_SELECT)) return base;
   int n=SymbolsTotal(false);
   for(int i=0;i<n;i++)
   {
      string s=SymbolName(i,false);
      if(StringFind(s,base)==0 && StringLen(s)<=StringLen(base)+4) { SymbolSelect(s,true); return s; }
   }
   return "";
}

// 收益率相关系数（同时间对齐）
double Correlation(string sym,int bars)
{
   double a[],b[]; int n=0;
   ArrayResize(a,bars); ArrayResize(b,bars);
   for(int i=1;i<=bars && i+1<N;i++)
   {
      int s1=iBarShift(sym,_Period,T[i],true), s2=iBarShift(sym,_Period,T[i+1],true);
      if(s1<0 || s2<0) continue;
      double c1=iClose(sym,_Period,s1), c2=iClose(sym,_Period,s2);
      if(c1<=0 || c2<=0 || C[i+1]<=0) continue;
      a[n]=C[i]/C[i+1]-1.0; b[n]=c1/c2-1.0; n++;
   }
   if(n<20) return 0.0;
   double ma=0,mb=0; for(int i=0;i<n;i++){ ma+=a[i]; mb+=b[i]; } ma/=n; mb/=n;
   double sab=0,saa=0,sbb=0;
   for(int i=0;i<n;i++){ double da=a[i]-ma, db=b[i]-mb; sab+=da*db; saa+=da*da; sbb+=db*db; }
   if(saa<=0 || sbb<=0) return 0.0;
   return sab/MathSqrt(saa*sbb);
}

void PickSMTSymbol()
{
   g_smtSym=""; g_smtCorr=0; g_corrTable="";
   string parts[]; int n=StringSplit(SMTCandidates,',',parts);
   for(int i=0;i<n;i++)
   {
      string base=parts[i]; StringTrimLeft(base); StringTrimRight(base);
      if(base=="") continue;
      string s=FindBrokerSymbol(base);
      if(s=="" || s==_Symbol) continue;
      double r=Correlation(s,CorrBars);
      g_corrTable+=StringFormat("%s %+.2f  ",s,r);
      if(MathAbs(r)>MathAbs(g_smtCorr)) { g_smtCorr=r; g_smtSym=s; }
   }
}

// 对方品种在某个时间附近（±SwingLen根）的最高/最低
bool OtherExtreme(string sym,datetime t,bool wantHigh,double &v)
{
   int sh=iBarShift(sym,_Period,t,false);
   if(sh<0) return false;
   int from=MathMax(0,sh-SwingLen), cnt=2*SwingLen+1;
   int k=wantHigh?iHighest(sym,_Period,MODE_HIGH,cnt,from):iLowest(sym,_Period,MODE_LOW,cnt,from);
   if(k<0) return false;
   v=wantHigh?iHigh(sym,_Period,k):iLow(sym,_Period,k);
   return v>0;
}

void SMT()
{
   if(!ShowSMT) return;
   PickSMTSymbol();
   if(g_smtSym=="" || MathAbs(g_smtCorr)<MinAbsCorr) return;
   bool inverse=(g_smtCorr<0);   // 负相关（如美元指数）：我方高点对应对方低点

   for(int pass=0;pass<2;pass++)
   {
      bool highs=(pass==0);
      int idx[]; ArrayResize(idx,0);
      for(int k=0;k<ArraySize(g_sw);k++) if(g_sw[k].high==highs) { int n=ArraySize(idx); ArrayResize(idx,n+1); idx[n]=k; }
      int cnt=ArraySize(idx);
      for(int p=MathMax(1,cnt-SMTMaxPairs);p<cnt;p++)
      {
         SWING a=g_sw[idx[p-1]], b=g_sw[idx[p]];
         bool otherHigh=(highs!=inverse);
         double oa,ob;
         if(!OtherExtreme(g_smtSym,a.time,otherHigh,oa) || !OtherExtreme(g_smtSym,b.time,otherHigh,ob)) continue;

         // 把对方换算成"与我方同向"的比较：负相关时对方方向取反
         bool meHigher=(b.price>a.price), meLower=(b.price<a.price);
         bool otHigher=inverse?(ob<oa):(ob>oa), otLower=inverse?(ob>oa):(ob<oa);

         bool smt=false;
         if(highs) smt=(meHigher && !otHigher) || (otHigher && !meHigher);   // 一方创新高、另一方没有
         else      smt=(meLower && !otLower)   || (otLower && !meLower);     // 一方创新低、另一方没有
         if(!smt) continue;

         string id=IntegerToString((long)b.time);
         color c=highs?clrOrangeRed:clrSpringGreen;
         Seg("SMT"+id,a.time,a.price,b.time,b.price,c,STYLE_SOLID,2);
         Txt("SMTt"+id,b.time,b.price,StringFormat("SMT%s vs %s",highs?"空":"多",g_smtSym),c,8,highs?ANCHOR_LEFT_LOWER:ANCHOR_LEFT_UPPER);
         if(AlertOnSMT) Notify("SMT"+id+(highs?"H":"L"),StringFormat("SMT%s背离（对比 %s，相关 %.2f）",highs?"空":"多",g_smtSym,g_smtCorr),b.idx-SwingLen);
      }
   }
}

//+------------------------------------------------------------------+
//| 面板                                                              |
//+------------------------------------------------------------------+
void Panel()
{
   string trend=(g_trend>0?"多头结构":(g_trend<0?"空头结构":"未定"));
   string smt=(g_smtSym==""?"无可用相关品种":StringFormat("%s 相关 %.2f%s",g_smtSym,g_smtCorr,
               MathAbs(g_smtCorr)<MinAbsCorr?"（不足，未判SMT）":(g_smtCorr<0?"（负相关）":"")));
   Comment(StringFormat("Jammy ICT Suite｜%s %s\n结构：%s｜最近：%s\nSMT：%s\n相关：%s\nCRT：%s",
           _Symbol,StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7),
           trend,g_lastEvent==""?"--":g_lastEvent,smt,g_corrTable,g_crtText==""?"--":g_crtText));
}

//+------------------------------------------------------------------+
int OnInit()
{
   hATR=iATR(_Symbol,_Period,ATRPeriod);
   if(hATR==INVALID_HANDLE) return INIT_FAILED;
   IndicatorSetString(INDICATOR_SHORTNAME,"Jammy ICT Suite");
   g_lastBar=0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,PFX);
   Comment("");
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<SwingLen*2+10) return 0;
   ArraySetAsSeries(time,true);
   if(time[0]==g_lastBar && prev_calculated>0) return rates_total;   // 每根新K线算一次

   double a[]; ArraySetAsSeries(a,true);
   if(CopyBuffer(hATR,0,1,1,a)<1) return 0;
   g_atr=a[0];

   N=MathMin(rates_total,MathMax(50,LookbackBars));
   ArraySetAsSeries(T,true); ArraySetAsSeries(O,true); ArraySetAsSeries(H,true); ArraySetAsSeries(L,true); ArraySetAsSeries(C,true);
   if(CopyTime(_Symbol,_Period,0,N,T)<N || CopyOpen(_Symbol,_Period,0,N,O)<N || CopyHigh(_Symbol,_Period,0,N,H)<N ||
      CopyLow(_Symbol,_Period,0,N,L)<N || CopyClose(_Symbol,_Period,0,N,C)<N) return 0;

   g_lastBar=time[0];
   g_serverOffset=ServerUtcOffsetSeconds();

   ObjectsDeleteAll(0,PFX);
   BuildSwings();
   Killzones();
   PremiumDiscount();
   FVG();
   EqualHighsLows();
   Structure();
   CRT();
   SMT();
   Panel();
   ChartRedraw();
   return rates_total;
}
