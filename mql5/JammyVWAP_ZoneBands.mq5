#property copyright "Jammy"
#property version   "1.63"
#property indicator_chart_window
#property indicator_buffers 21
#property indicator_plots   14

enum VWAP_MODE
{
   VWAP_DAILY=0,          // 经纪商服务器 00:00
   VWAP_WEEKLY=1,
   VWAP_MONTHLY=2,
   VWAP_CME_NY_1800=3,   // 纽约 18:00（CME/Globex）
   VWAP_NY_MIDNIGHT=5,   // 纽约 00:00，自动处理美东夏令时/冬令时
   VWAP_FREE_ANCHOR=4
};

input VWAP_MODE Mode=VWAP_DAILY;
input datetime FreeAnchor=D'2026.10.01 00:00';
input bool UseHLC3=true;
input int  MaxBars=0;                 // 最多计算的历史K线数（0=全部）
input color AnchorLineColor=clrAqua;
input int AnchorLineWidth=2;
input ENUM_LINE_STYLE AnchorLineStyle=STYLE_DASH;

input double Dev05=0.5;
input double Dev10=1.0;
input double Dev15=1.5;
input double Dev20=2.0;
input double Dev25=2.5;

input bool Show05=true;
input bool Show10=true;
input bool Show15=true;
input bool Show20=true;
input bool Show25=true;

input bool ShowCoreZone=true;
input bool ShowUpperExtremeZone=true;
input bool ShowLowerExtremeZone=true;

input color VWAPColor=clrDeepSkyBlue;
input color Band05Color=clrDodgerBlue;
input color Band10Color=clrSilver;
input color Band15Color=clrGold;
input color Band20Color=clrOrangeRed;
input color Band25Color=clrTomato;
input color CoreZoneColor=clrDodgerBlue;
input color UpperExtremeZoneColor=clrOrangeRed;
input color LowerExtremeZoneColor=clrMediumSeaGreen;
input int LineWidth=1;

double Vwap[],P05[],M05[],P10[],M10[],P15[],M15[],P20[],M20[],P25[],M25[];
double CoreTop[],CoreBottom[],UpperOuter[],UpperInner[],LowerInner[],LowerOuter[];
// Calculation buffers: running sums and session anchor per bar.
// They let each tick resume from the previous bar instead of recomputing all history.
double SumVBuf[],SumPVBuf[],SumP2VBuf[],AnchorBuf[];

// Runtime state.
int      g_serverOffset=0;      // broker server - UTC, rounded to 15 min
bool     g_forceFull=true;      // next OnCalculate recomputes everything
datetime g_freeAnchorRaw=0;     // last seen free-anchor object time

//+------------------------------------------------------------------+
//| Fast date helpers (no StringFormat/StringToTime)                 |
//+------------------------------------------------------------------+
datetime MakeDate(int year,int month,int day)
{
   MqlDateTime s; ZeroMemory(s);
   s.year=year; s.mon=month; s.day=day;
   return StructToTime(s);
}

int DayOfWeek(datetime t)              // 0=Sunday (1970-01-01 was Thursday)
{
   return (int)(((long)t/86400+4)%7);
}

int NthSundayDay(int year,int month,int nth)
{
   int dow=DayOfWeek(MakeDate(year,month,1));
   int firstSunday=1+((7-dow)%7);
   return firstSunday+(nth-1)*7;
}

// US DST boundaries, cached per year (bars are processed in time order,
// so a single-entry cache hits almost always).
int      g_dstYear=0;
datetime g_dstStartLocal=0,g_dstEndLocal=0;   // NY wall-clock 02:00
datetime g_dstStartUTC=0,g_dstEndUTC=0;

void EnsureDstYear(int year)
{
   if(year==g_dstYear) return;
   g_dstYear=year;
   g_dstStartLocal=MakeDate(year,3,NthSundayDay(year,3,2))+2*3600;
   g_dstEndLocal  =MakeDate(year,11,NthSundayDay(year,11,1))+2*3600;
   g_dstStartUTC  =g_dstStartLocal+5*3600;   // 02:00 EST = 07:00 UTC
   g_dstEndUTC    =g_dstEndLocal+4*3600;     // 02:00 EDT = 06:00 UTC
}

int YearOf(datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   return d.year;
}

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

int CurrentServerUtcOffsetSeconds()
{
   datetime server=TimeTradeServer();
   if(server<=0) server=TimeCurrent();

   datetime utc=TimeGMT();
   if(utc<=0 || server<=0) return 0;

   // Round to 15 minutes: the raw difference jitters by a few seconds
   // between calls, which would shift every NY anchor and break caching.
   return (int)MathRound((double)(server-utc)/900.0)*900;
}

datetime NewYorkSessionAnchor(datetime brokerTime,int anchorHour)
{
   datetime utc=brokerTime-g_serverOffset;
   datetime nyClock=utc+NewYorkOffsetAtUTC(utc)*3600;

   datetime localAnchor=(datetime)((long)nyClock-(long)nyClock%86400+anchorHour*3600);

   // 18:00 session belongs to the most recent NY 18:00.
   // NY 00:00 always belongs to the current NY calendar date.
   if(anchorHour==18 && nyClock<localAnchor)
      localAnchor-=86400;

   return localAnchor-NewYorkOffsetAtLocal(localAnchor)*3600+g_serverOffset;
}

datetime PeriodAnchor(datetime t)
{
   datetime day0=(datetime)((long)t-(long)t%86400);

   if(Mode==VWAP_DAILY)
      return day0;

   if(Mode==VWAP_WEEKLY)
      return day0-((DayOfWeek(day0)+6)%7)*86400;   // Monday

   if(Mode==VWAP_MONTHLY)
   {
      MqlDateTime d; TimeToStruct(t,d);
      return MakeDate(d.year,d.mon,1);
   }

   if(Mode==VWAP_NY_MIDNIGHT)
      return NewYorkSessionAnchor(t,0);    // New York 00:00

   // CME / Globex: New York 18:00
   return NewYorkSessionAnchor(t,18);
}

//+------------------------------------------------------------------+
//| Free anchor line                                                 |
//+------------------------------------------------------------------+
string ANCHOR_NAME="JAMMY_ANCHOR";
string AnchorGVName()
{
   return "JAMMY_ANCHOR_TIME_" + _Symbol;
}

void EnsureAnchorLine()
{
   if(Mode!=VWAP_FREE_ANCHOR) return;

   datetime t=FreeAnchor;
   if(GlobalVariableCheck(AnchorGVName()))
      t=(datetime)GlobalVariableGet(AnchorGVName());

   // If an existing object survived chart change, its time wins.
   if(ObjectFind(0,ANCHOR_NAME)>=0)
      t=(datetime)ObjectGetInteger(0,ANCHOR_NAME,OBJPROP_TIME,0);

   // Validate against currently loaded history.
   datetime first=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_FIRSTDATE);
   datetime last=iTime(_Symbol,_Period,0);
   if(first<=0 || last<=0) return;

   if(t<first || t>last)
   {
      int total=Bars(_Symbol,_Period);
      int shift=MathMin(100,MathMax(0,total-1));
      t=iTime(_Symbol,_Period,shift);
   }

   // Snap anchor to the bar containing that absolute time on the NEW timeframe.
   int sh=iBarShift(_Symbol,_Period,t,false);
   if(sh>=0)
      t=iTime(_Symbol,_Period,sh);

   GlobalVariableSet(AnchorGVName(),(double)t);

   if(ObjectFind(0,ANCHOR_NAME)<0)
      ObjectCreate(0,ANCHOR_NAME,OBJ_VLINE,0,t,0);
   else
      ObjectMove(0,ANCHOR_NAME,0,t,0);

   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_COLOR,AnchorLineColor);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_WIDTH,AnchorLineWidth);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_STYLE,AnchorLineStyle);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,ANCHOR_NAME,OBJPROP_BACK,false);
   ChartRedraw();
}

datetime GetLiveAnchor()
{
   if(Mode==VWAP_FREE_ANCHOR && ObjectFind(0,ANCHOR_NAME)>=0)
      return (datetime)ObjectGetInteger(0,ANCHOR_NAME,OBJPROP_TIME,0);
   return FreeAnchor;
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(Mode!=VWAP_FREE_ANCHOR) return;

   if((id==CHARTEVENT_OBJECT_DRAG || id==CHARTEVENT_OBJECT_CHANGE) && sparam==ANCHOR_NAME)
   {
      datetime t=(datetime)ObjectGetInteger(0,ANCHOR_NAME,OBJPROP_TIME,0);
      GlobalVariableSet(AnchorGVName(),(double)t);
      g_forceFull=true;
      // Do not force ChartSetSymbolPeriod here: it reinitializes the indicator.
      // MT5 will recalculate on the next tick; redraw the chart immediately.
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
void LinePlot(int plot,color c,int width)
{
   PlotIndexSetInteger(plot,PLOT_DRAW_TYPE,DRAW_LINE);
   PlotIndexSetInteger(plot,PLOT_LINE_STYLE,STYLE_SOLID);
   PlotIndexSetInteger(plot,PLOT_LINE_WIDTH,width);
   PlotIndexSetInteger(plot,PLOT_LINE_COLOR,c);
   PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
}

int OnInit()
{
   SetIndexBuffer(0,Vwap,INDICATOR_DATA);
   SetIndexBuffer(1,P05,INDICATOR_DATA); SetIndexBuffer(2,M05,INDICATOR_DATA);
   SetIndexBuffer(3,P10,INDICATOR_DATA); SetIndexBuffer(4,M10,INDICATOR_DATA);
   SetIndexBuffer(5,P15,INDICATOR_DATA); SetIndexBuffer(6,M15,INDICATOR_DATA);
   SetIndexBuffer(7,P20,INDICATOR_DATA); SetIndexBuffer(8,M20,INDICATOR_DATA);
   SetIndexBuffer(9,P25,INDICATOR_DATA); SetIndexBuffer(10,M25,INDICATOR_DATA);
   SetIndexBuffer(11,CoreTop,INDICATOR_DATA); SetIndexBuffer(12,CoreBottom,INDICATOR_DATA);
   SetIndexBuffer(13,UpperOuter,INDICATOR_DATA); SetIndexBuffer(14,UpperInner,INDICATOR_DATA);
   SetIndexBuffer(15,LowerInner,INDICATOR_DATA); SetIndexBuffer(16,LowerOuter,INDICATOR_DATA);
   SetIndexBuffer(17,SumVBuf,INDICATOR_CALCULATIONS);
   SetIndexBuffer(18,SumPVBuf,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,SumP2VBuf,INDICATOR_CALCULATIONS);
   SetIndexBuffer(20,AnchorBuf,INDICATOR_CALCULATIONS);

   ArraySetAsSeries(Vwap,true);
   ArraySetAsSeries(P05,true); ArraySetAsSeries(M05,true);
   ArraySetAsSeries(P10,true); ArraySetAsSeries(M10,true);
   ArraySetAsSeries(P15,true); ArraySetAsSeries(M15,true);
   ArraySetAsSeries(P20,true); ArraySetAsSeries(M20,true);
   ArraySetAsSeries(P25,true); ArraySetAsSeries(M25,true);
   ArraySetAsSeries(CoreTop,true); ArraySetAsSeries(CoreBottom,true);
   ArraySetAsSeries(UpperOuter,true); ArraySetAsSeries(UpperInner,true);
   ArraySetAsSeries(LowerInner,true); ArraySetAsSeries(LowerOuter,true);
   ArraySetAsSeries(SumVBuf,true); ArraySetAsSeries(SumPVBuf,true);
   ArraySetAsSeries(SumP2VBuf,true); ArraySetAsSeries(AnchorBuf,true);

   LinePlot(0,VWAPColor,2);
   LinePlot(1,Band05Color,LineWidth); LinePlot(2,Band05Color,LineWidth);
   LinePlot(3,Band10Color,LineWidth); LinePlot(4,Band10Color,LineWidth);
   LinePlot(5,Band15Color,LineWidth); LinePlot(6,Band15Color,LineWidth);
   LinePlot(7,Band20Color,LineWidth); LinePlot(8,Band20Color,LineWidth);
   LinePlot(9,Band25Color,LineWidth); LinePlot(10,Band25Color,LineWidth);

   // In MT5 each DRAW_FILLING plot uses exactly two consecutive buffers.
   PlotIndexSetInteger(11,PLOT_DRAW_TYPE,DRAW_FILLING);
   PlotIndexSetInteger(11,PLOT_LINE_COLOR,0,CoreZoneColor);
   PlotIndexSetInteger(11,PLOT_LINE_COLOR,1,CoreZoneColor);
   PlotIndexSetDouble(11,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   PlotIndexSetInteger(12,PLOT_DRAW_TYPE,DRAW_FILLING);
   PlotIndexSetInteger(12,PLOT_LINE_COLOR,0,UpperExtremeZoneColor);
   PlotIndexSetInteger(12,PLOT_LINE_COLOR,1,UpperExtremeZoneColor);
   PlotIndexSetDouble(12,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   PlotIndexSetInteger(13,PLOT_DRAW_TYPE,DRAW_FILLING);
   PlotIndexSetInteger(13,PLOT_LINE_COLOR,0,LowerExtremeZoneColor);
   PlotIndexSetInteger(13,PLOT_LINE_COLOR,1,LowerExtremeZoneColor);
   PlotIndexSetDouble(13,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,"Jammy VWAP ZoneBands MT5 v1.63 + NY Midnight");

   g_forceFull=true;
   g_dstYear=0;
   g_serverOffset=CurrentServerUtcOffsetSeconds();
   EnsureAnchorLine();
   g_freeAnchorRaw=GetLiveAnchor();
   return(INIT_SUCCEEDED);
}

void EmptyAll()
{
   ArrayInitialize(Vwap,EMPTY_VALUE);
   ArrayInitialize(P05,EMPTY_VALUE); ArrayInitialize(M05,EMPTY_VALUE);
   ArrayInitialize(P10,EMPTY_VALUE); ArrayInitialize(M10,EMPTY_VALUE);
   ArrayInitialize(P15,EMPTY_VALUE); ArrayInitialize(M15,EMPTY_VALUE);
   ArrayInitialize(P20,EMPTY_VALUE); ArrayInitialize(M20,EMPTY_VALUE);
   ArrayInitialize(P25,EMPTY_VALUE); ArrayInitialize(M25,EMPTY_VALUE);
   ArrayInitialize(CoreTop,EMPTY_VALUE); ArrayInitialize(CoreBottom,EMPTY_VALUE);
   ArrayInitialize(UpperOuter,EMPTY_VALUE); ArrayInitialize(UpperInner,EMPTY_VALUE);
   ArrayInitialize(LowerInner,EMPTY_VALUE); ArrayInitialize(LowerOuter,EMPTY_VALUE);
   ArrayInitialize(SumVBuf,0.0); ArrayInitialize(SumPVBuf,0.0);
   ArrayInitialize(SumP2VBuf,0.0); ArrayInitialize(AnchorBuf,0.0);
}

void EmptyBar(int i)
{
   Vwap[i]=P05[i]=M05[i]=P10[i]=M10[i]=P15[i]=M15[i]=P20[i]=M20[i]=P25[i]=M25[i]=EMPTY_VALUE;
   CoreTop[i]=CoreBottom[i]=UpperOuter[i]=UpperInner[i]=LowerInner[i]=LowerOuter[i]=EMPTY_VALUE;
   SumVBuf[i]=SumPVBuf[i]=SumP2VBuf[i]=AnchorBuf[i]=0.0;
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
 const double &open[],const double &high[],const double &low[],const double &close[],
 const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<2) return 0;

   ArraySetAsSeries(time,true); ArraySetAsSeries(high,true); ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true); ArraySetAsSeries(tick_volume,true);

   // Anything that changes the anchor of already-computed bars forces a full pass.
   if(Mode==VWAP_CME_NY_1800 || Mode==VWAP_NY_MIDNIGHT)
   {
      int off=CurrentServerUtcOffsetSeconds();
      if(off!=g_serverOffset) { g_serverOffset=off; g_forceFull=true; }
   }

   datetime freeBarTime=0;
   if(Mode==VWAP_FREE_ANCHOR)
   {
      datetime raw=GetLiveAnchor();
      if(raw!=g_freeAnchorRaw) { g_freeAnchorRaw=raw; g_forceFull=true; }
      int sh=iBarShift(_Symbol,_Period,raw,false);
      freeBarTime=(sh>=0) ? iTime(_Symbol,_Period,sh) : 0;
   }

   // Determine which bars need (re)calculation. Only the newest bar(s)
   // are touched on a normal tick; full history only on first load,
   // history change, or anchor/offset change.
   int limit=rates_total-1;
   if(MaxBars>0 && limit>MaxBars-1) limit=MaxBars-1;

   int start;
   bool full=(prev_calculated<=0 || prev_calculated>rates_total || g_forceFull);
   if(full)
   {
      EmptyAll();
      start=limit;
      g_forceFull=false;
   }
   else
   {
      start=rates_total-prev_calculated;   // 0 on a tick, 1 on a new bar
      if(start>limit) start=limit;
   }

   for(int i=start;i>=0;i--)
   {
      double sV=0.0,sPV=0.0,sP2V=0.0;
      bool havePrev=(i<limit && AnchorBuf[i+1]!=0.0);

      if(Mode==VWAP_FREE_ANCHOR)
      {
         // Bars older than the anchor bar stay empty.
         if(freeBarTime<=0 || time[i]<freeBarTime)
         {
            EmptyBar(i);
            continue;
         }
         AnchorBuf[i]=(double)freeBarTime;
         if(time[i]!=freeBarTime && havePrev)
         {
            sV=SumVBuf[i+1]; sPV=SumPVBuf[i+1]; sP2V=SumP2VBuf[i+1];
         }
      }
      else
      {
         // Reset whenever the session identity changes.
         // Do NOT require bar-open >= anchor; that breaks HTF/week/month display.
         double anchor=(double)PeriodAnchor(time[i]);
         AnchorBuf[i]=anchor;
         if(havePrev && AnchorBuf[i+1]==anchor)
         {
            sV=SumVBuf[i+1]; sPV=SumPVBuf[i+1]; sP2V=SumP2VBuf[i+1];
         }
      }

      double price=UseHLC3?(high[i]+low[i]+close[i])/3.0:close[i];
      double vol=(double)tick_volume[i];
      if(vol<=0.0) vol=1.0;

      sV+=vol;
      sPV+=price*vol;
      sP2V+=price*price*vol;
      SumVBuf[i]=sV; SumPVBuf[i]=sPV; SumP2VBuf[i]=sP2V;

      double vw=sPV/sV;
      double variance=sP2V/sV-vw*vw;
      if(variance<0.0) variance=0.0;
      double sd=MathSqrt(variance);

      Vwap[i]=vw;
      P05[i]=Show05?vw+Dev05*sd:EMPTY_VALUE; M05[i]=Show05?vw-Dev05*sd:EMPTY_VALUE;
      P10[i]=Show10?vw+Dev10*sd:EMPTY_VALUE; M10[i]=Show10?vw-Dev10*sd:EMPTY_VALUE;
      P15[i]=Show15?vw+Dev15*sd:EMPTY_VALUE; M15[i]=Show15?vw-Dev15*sd:EMPTY_VALUE;
      P20[i]=Show20?vw+Dev20*sd:EMPTY_VALUE; M20[i]=Show20?vw-Dev20*sd:EMPTY_VALUE;
      P25[i]=Show25?vw+Dev25*sd:EMPTY_VALUE; M25[i]=Show25?vw-Dev25*sd:EMPTY_VALUE;

      CoreTop[i]=ShowCoreZone?vw+Dev05*sd:EMPTY_VALUE;
      CoreBottom[i]=ShowCoreZone?vw-Dev05*sd:EMPTY_VALUE;
      UpperOuter[i]=ShowUpperExtremeZone?vw+Dev25*sd:EMPTY_VALUE;
      UpperInner[i]=ShowUpperExtremeZone?vw+Dev20*sd:EMPTY_VALUE;
      LowerInner[i]=ShowLowerExtremeZone?vw-Dev20*sd:EMPTY_VALUE;
      LowerOuter[i]=ShowLowerExtremeZone?vw-Dev25*sd:EMPTY_VALUE;
   }

   // With MaxBars, the bar that just fell out of the window must be cleared.
   if(!full && MaxBars>0 && rates_total>limit+1)
      EmptyBar(limit+1);

   return rates_total;
}

void OnDeinit(const int reason)
{
   if(ObjectFind(0,ANCHOR_NAME)>=0)
   {
      datetime t=(datetime)ObjectGetInteger(0,ANCHOR_NAME,OBJPROP_TIME,0);
      GlobalVariableSet(AnchorGVName(),(double)t);

      // REASON_CHARTCHANGE = timeframe/symbol change: keep the object/time alive.
      // Remove only when the indicator itself is removed from the chart.
      if(reason==REASON_REMOVE)
         ObjectDelete(0,ANCHOR_NAME);
   }
}
