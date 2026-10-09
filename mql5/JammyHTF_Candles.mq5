//+------------------------------------------------------------------+
//|                                            JammyHTF_Candles.mq5  |
//|   在小周期图表右侧显示高周期K线（HTF Candles）                       |
//|   + 高周期 CRT 标记 + 未回补 FVG + 开盘价/前高前低 + 收盘倒计时       |
//+------------------------------------------------------------------+
#property copyright "Jammy"
#property version   "1.02"
#property description "Jammy HTF Candles v1.02：在小周期图表右侧显示两个高周期的最近K线（按真实价格），标出 CRT、未回补 FVG、高周期开盘价/前高前低，并显示收盘倒计时"
#property indicator_chart_window
#property indicator_plots 0

input group "=== 高周期 ==="
input bool            AutoHTF          = true;        // 自动按图表周期选择（M1→M15/H1，M5→H1/H4，M15~H1→H4/D1，H4→D1/W1）
input ENUM_TIMEFRAMES HTF1             = PERIOD_H4;   // 手动：第1个高周期（AutoHTF=false 时生效）
input ENUM_TIMEFRAMES HTF2             = PERIOD_D1;   // 手动：第2个高周期
input bool            ShowHTF2         = true;        // 显示第2个高周期
input int             CandlesPerHTF    = 6;           // 每个高周期显示几根K线（含当前进行中的一根）

input group "=== 外观 ==="
input bool            AutoChartShift   = true;        // 自动打开图表右侧留白
input double          ChartShiftPercent= 30;          // 右侧留白比例（10~50%）
input int             OffsetBars       = 6;           // 高周期K线距最新K线的空隙（按当前周期K线数）
input int             CandleWidthBars  = 0;           // 每根高周期K线宽度（按当前周期K线数，0=按留白自动适配）
input int             CandleGapBars    = 1;           // 高周期K线之间的空隙
input int             GroupGapBars     = 5;           // 两组高周期之间的空隙
input color           BullColor        = C'38,166,154';
input color           BearColor        = C'239,83,80';
input color           WickColor        = clrSilver;
input color           TextColor        = clrWhite;
input int             FontSize         = 8;

input group "=== 标记 ==="
input bool            ShowCRT          = true;        // 标记 CRT（扫前一根高/低后收回区间内）
input bool            ShowFVG          = true;        // 显示高周期未回补 FVG
input bool            ShowLevels       = true;        // 当前高周期开盘价 + 前一根高/低点画到图表上
input bool            ShowCountdown    = true;        // 高周期收盘倒计时
input bool            ShowTimeLabels   = true;        // K线下方显示时间（服务器时间；日线显示星期）
input bool            AlertOnCRT       = false;       // 高周期K线收盘形成 CRT 时弹窗+推送

input group "=== CRT 判定（动量K线 + 扫关键高/低 + 收回） ==="
input bool   CRTNeedMomentum     = true;  // C1 必须是动量K线（实体大、区间明显大于近期平均）
input double CRTMomBodyPct       = 0.55;  // 动量：C1 实体 ≥ C1 区间 × 此比例
input double CRTMomRangeMult     = 1.2;   // 动量：C1 区间 ≥ 前N根平均区间 × 此倍数
input int    CRTAvgBars          = 10;    // 平均区间取前几根
input bool   CRTNeedKeyLevel     = true;  // 被扫的必须是关键高/低点：C1 的高(低)点是前N根里最高(最低)
input int    CRTKeyBars          = 5;     // 关键高/低点回看根数
input bool   CRTReversalSideOnly = true;  // 只认反转方向：阳线动量被扫高→空；阴线动量被扫低→多
input int    CRTMaxBars          = 6;     // 确认后最多等几根K线到达目标，超出算失败
input bool   CRTTargetFullRange  = true;  // 目标：true=C1区间另一端，false=C1区间50%
input bool   CRTInvalidOnBreak   = true;  // 收盘突破C2扫点（空=C2高点，多=C2低点）提前判失败
input bool   CRTShowFailed       = true;  // 失败的CRT也显示（灰色）

string   PFX="JHTF_";
string   g_used[];
int      g_usedN=0;
string   g_alertKey[2]={"",""};
ulong    g_lastDrawMs=0;

//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf) { return StringSubstr(EnumToString(tf),7); }

void PickHTF(ENUM_TIMEFRAMES &a,ENUM_TIMEFRAMES &b)
{
   a=HTF1; b=HTF2;
   if(!AutoHTF) return;
   int p=PeriodSeconds(_Period);
   if(p<=60)          { a=PERIOD_M15; b=PERIOD_H1; }
   else if(p<=300)    { a=PERIOD_H1;  b=PERIOD_H4; }
   else if(p<=3600)   { a=PERIOD_H4;  b=PERIOD_D1; }
   else if(p<=14400)  { a=PERIOD_D1;  b=PERIOD_W1; }
   else               { a=PERIOD_W1;  b=PERIOD_MN1; }
}

string CandleLabel(ENUM_TIMEFRAMES tf,datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   if(tf==PERIOD_D1)
   {
      string w[7]={"日","一","二","三","四","五","六"};
      return "周"+w[d.day_of_week];
   }
   if(tf==PERIOD_W1 || tf==PERIOD_MN1) return StringFormat("%02d/%02d",d.mon,d.day);
   return StringFormat("%02d:%02d",d.hour,d.min);
}

string Countdown(datetime openT,ENUM_TIMEFRAMES tf)
{
   datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
   long left=(long)openT+PeriodSeconds(tf)-(long)now;
   if(left<0) left=0;
   int d=(int)(left/86400), h=(int)((left%86400)/3600), m=(int)((left%3600)/60), s=(int)(left%60);
   return d>0 ? StringFormat("%dd %02d:%02d:%02d",d,h,m,s) : StringFormat("%02d:%02d:%02d",h,m,s);
}

//---------------- 对象工具：存在则更新，不存在则创建 ----------------
void Use(string name)
{
   if(g_usedN>=ArraySize(g_used)) ArrayResize(g_used,g_usedN+64);
   g_used[g_usedN++]=name;
}
bool Used(string name)
{
   for(int i=0;i<g_usedN;i++) if(g_used[i]==name) return true;
   return false;
}
void Common(string name,color c,bool back)
{
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_BACK,back);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   Use(name);
}
void RectObj(string n,datetime t1,double p1,datetime t2,double p2,color c,bool fill,bool back)
{
   string name=PFX+n;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   else { ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2); }
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   Common(name,c,back);
}
void LineObj(string n,datetime t1,double p1,datetime t2,double p2,color c,int style,int width)
{
   string name=PFX+n;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   else { ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2); }
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   Common(name,c,false);
}
void TextObj(string n,datetime t,double p,string txt,color c,int size,ENUM_ANCHOR_POINT anchor)
{
   string name=PFX+n;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,p);
   else ObjectMove(0,name,0,t,p);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,MathMax(6,size));
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   Common(name,c,false);
}
void SweepUnused()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string nm=ObjectName(0,i,0,-1);
      if(StringFind(nm,PFX)!=0) continue;
      if(!Used(nm)) ObjectDelete(0,nm);
   }
}

// CRT 结果：c2=扫点K线下标，newer=-1(时间序列数组)/+1(正序数组) 指向更新的K线
// 返回 1=成功（第k根到达目标） -1=失败（why=原因） 0=还在等待（已过k根）
int CRTOutcome(const MqlRates &r[],int c2,int newer,int got,bool bear,double target,double invalid,int &k,string &why)
{
   k=0; why="";
   int lastIdx=(newer<0?0:got-1);                        // 进行中的K线
   for(int m=1;m<=CRTMaxBars;m++)
   {
      int idx=c2+newer*m; if(idx<0 || idx>=got) break;
      k=m;
      if(bear ? r[idx].low<=target : r[idx].high>=target) return 1;
      if(CRTInvalidOnBreak && idx!=lastIdx && (bear ? r[idx].close>invalid : r[idx].close<invalid))
      { why="收盘破扫点"; return -1; }
   }
   int endIdx=c2+newer*CRTMaxBars;
   if(k>=CRTMaxBars && endIdx!=lastIdx) { why="超"+IntegerToString(CRTMaxBars)+"根未到目标"; return -1; }
   return 0;
}

// CRT 过滤：c1=区间K线下标，older=+1(时间序列数组)/-1(正序数组) 指向更早的K线
bool CRTQualify(const MqlRates &r[],int c1,int older,int got,bool bear)
{
   double h1=r[c1].high, l1=r[c1].low, rng=h1-l1;
   if(rng<=0) return false;
   bool c1Bull=(r[c1].close>r[c1].open);
   if(CRTReversalSideOnly && bear!=c1Bull) return false;
   if(CRTNeedMomentum)
   {
      if(MathAbs(r[c1].close-r[c1].open)<CRTMomBodyPct*rng) return false;
      double s=0; int m=0;
      for(int k=1;k<=CRTAvgBars;k++) { int idx=c1+older*k; if(idx<0 || idx>=got) break; s+=r[idx].high-r[idx].low; m++; }
      if(m>0 && rng<CRTMomRangeMult*s/m) return false;
   }
   if(CRTNeedKeyLevel)
   {
      for(int k=1;k<=CRTKeyBars;k++)
      {
         int idx=c1+older*k; if(idx<0 || idx>=got) break;
         if(bear && r[idx].high>h1) return false;
         if(!bear && r[idx].low<l1) return false;
      }
   }
   return true;
}

//---------------- 画一组高周期K线 ----------------
void DrawGroup(int gi,ENUM_TIMEFRAMES tf,int startBar,int n,int W,int G,datetime t0,int ps)
{
   MqlRates r[]; ArraySetAsSeries(r,false);            // r[0]=最早，r[got-1]=当前进行中
   int extra=MathMax(CRTAvgBars,CRTKeyBars)+1;          // 多取几根给 CRT 动量/关键点判断用，不画
   int got=CopyRates(_Symbol,tf,0,n+extra,r);
   if(got<=0) return;                                   // 高周期数据未就绪，下个Tick/计时器重试
   int first=MathMax(0,got-n);                          // 第一根要画的K线

   double hi=r[first].high, lo=r[first].low;
   for(int i=first+1;i<got;i++) { hi=MathMax(hi,r[i].high); lo=MathMin(lo,r[i].low); }
   double pad=(hi-lo)*0.04; if(pad<=0) pad=_Point*10;
   string tn=TFName(tf);
   int step=W+G;
   datetime groupStart=t0+startBar*ps, groupEnd=t0+(startBar+(got-first)*step)*ps;

   // 标题 + 倒计时
   TextObj("H"+IntegerToString(gi),groupStart,hi+pad,
           tn+(ShowCountdown?"  ⏱ "+Countdown(r[got-1].time,tf):""),TextColor,FontSize,ANCHOR_LEFT_LOWER);

   for(int i=first;i<got;i++)
   {
      int xs=startBar+(i-first)*step;
      datetime ta=t0+xs*ps, tb=t0+(xs+W)*ps, tc=t0+(xs+W/2)*ps;
      bool up=(r[i].close>=r[i].open);
      double bt=MathMax(r[i].open,r[i].close), bb=MathMin(r[i].open,r[i].close);
      if(bt-bb<_Point) bt=bb+_Point;
      string k=IntegerToString(gi)+"_"+IntegerToString(i-first);

      LineObj("W"+k,tc,r[i].high,tc,r[i].low,WickColor,STYLE_SOLID,1);
      RectObj("B"+k,ta,bt,tb,bb,up?BullColor:BearColor,true,false);
      if(ShowTimeLabels)
         TextObj("T"+k,tc,r[i].low-pad*0.3,CandleLabel(tf,r[i].time),clrGray,FontSize-1,ANCHOR_UPPER);

      // CRT：本根扫前一根高/低后，收盘回到前一根区间内（进行中的一根用当前价，标 *）
      if(ShowCRT && i>=1)
      {
         double ph=r[i-1].high, pl=r[i-1].low, cl=r[i].close;
         bool bear=(r[i].high>ph && cl<ph && cl>pl);
         bool bull=(r[i].low<pl  && cl>pl && cl<ph);
         if(bear && !CRTQualify(r,i-1,-1,got,true))  bear=false;
         if(bull && !CRTQualify(r,i-1,-1,got,false)) bull=false;
         if(bear || bull)
         {
            bool live=(i==got-1);
            double target=(CRTTargetFullRange ? (bear?pl:ph) : (ph+pl)/2);
            int kk=0; string why=""; int res=0; string st="*";
            if(!live)
            {
               res=CRTOutcome(r,i,1,got,bear,target,bear?r[i].high:r[i].low,kk,why);
               st=(res>0?" ✔"+IntegerToString(kk):(res<0?" ✘":StringFormat(" %d/%d",kk,CRTMaxBars)));
            }
            if(!(res<0 && !CRTShowFailed))
               TextObj("C"+k,tc,r[i].high+pad*0.3,(bear?"CRT▼":"CRT▲")+st,
                       res<0?clrDimGray:(bear?BearColor:BullColor),FontSize-1,ANCHOR_LOWER);
            if(AlertOnCRT && i==got-2)                    // 刚收盘的一根
            {
               string key=tn+IntegerToString((long)r[i].time)+(bear?"S":"B");
               if(g_alertKey[gi]=="") g_alertKey[gi]=key;  // 加载时已存在的不提醒
               else if(key!=g_alertKey[gi])
               {
                  g_alertKey[gi]=key;
                  string msg=StringFormat("%s %s CRT%s：扫前%s %s 后收回，目标 %s",_Symbol,tn,bear?"空":"多",
                                          bear?"高":"低",DoubleToString(bear?ph:pl,_Digits),DoubleToString(bear?pl:ph,_Digits));
                  Alert(msg); SendNotification(msg);
               }
            }
         }
      }

      // FVG：第 i-2 根与第 i 根之间的缺口，只显示之后还没被完全回补的
      if(ShowFVG && i>=first+2)
      {
         bool bf=(r[i].low>r[i-2].high), sf=(r[i].high<r[i-2].low);
         if(bf || sf)
         {
            double top=bf?r[i].low:r[i-2].low, bot=bf?r[i-2].high:r[i].high;
            bool filled=false;
            for(int j=i+1;j<got && !filled;j++)
               filled=(bf ? r[j].low<=bot : r[j].high>=top);
            if(!filled)
               RectObj("F"+k,t0+(startBar+(i-1-first)*step)*ps,top,groupEnd,bot,bf?C'20,70,60':C'85,30,35',true,true);
         }
      }
   }

   // 高周期开盘价、前一根高低点画到图表上（从该K线真实开始时间画到投影区）
   if(ShowLevels && got>=2)
   {
      int st=(gi==0?STYLE_DOT:STYLE_DASH);
      string g=IntegerToString(gi);
      double op=r[got-1].open, ph=r[got-2].high, pl=r[got-2].low;
      LineObj("LO"+g,r[got-1].time,op,groupStart,op,TextColor,st,1);
      TextObj("LOt"+g,groupStart,op,tn+" 开盘",TextColor,FontSize-1,ANCHOR_RIGHT_LOWER);
      LineObj("LH"+g,r[got-2].time,ph,groupStart,ph,BearColor,st,1);
      TextObj("LHt"+g,groupStart,ph,tn+" 前高",BearColor,FontSize-1,ANCHOR_RIGHT_LOWER);
      LineObj("LL"+g,r[got-2].time,pl,groupStart,pl,BullColor,st,1);
      TextObj("LLt"+g,groupStart,pl,tn+" 前低",BullColor,FontSize-1,ANCHOR_RIGHT_UPPER);
   }
}

void DrawAll()
{
   g_usedN=0;
   g_lastDrawMs=GetTickCount64();
   datetime t0=iTime(_Symbol,_Period,0);
   int ps=PeriodSeconds(_Period);
   if(t0<=0 || ps<=0) return;

   ENUM_TIMEFRAMES tf[2]; PickHTF(tf[0],tf[1]);
   ENUM_TIMEFRAMES list[2]; int groups=0;
   for(int i=0;i<(ShowHTF2?2:1);i++)
      if(PeriodSeconds(tf[i])>ps) list[groups++]=tf[i];   // 只画比当前周期大的
   if(groups==0) { SweepUnused(); ChartRedraw(); return; }

   int n=MathMax(1,MathMin(30,CandlesPerHTF));
   int G=MathMax(0,CandleGapBars);
   int W=CandleWidthBars;
   if(W<=0)
   {
      double shift=ChartGetDouble(0,CHART_SHIFT_SIZE);
      int avail=(int)(ChartGetInteger(0,CHART_WIDTH_IN_BARS)*shift/100.0)-OffsetBars-GroupGapBars*(groups-1)-2;
      W=avail/(groups*n)-G;
      if(W<1) W=1;
      if(W>1 && W%2==0) W--;                              // 奇数宽度，影线正好在中间
   }

   int start=MathMax(1,OffsetBars);
   for(int gi=0;gi<groups;gi++)
   {
      DrawGroup(gi,list[gi],start,n,W,G,t0,ps);
      start+=n*(W+G)+MathMax(1,GroupGapBars);
   }
   SweepUnused();
   ChartRedraw();
}

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME,"Jammy HTF Candles");
   if(AutoChartShift)
   {
      ChartSetInteger(0,CHART_SHIFT,true);
      ChartSetDouble(0,CHART_SHIFT_SIZE,MathMax(10.0,MathMin(50.0,ChartShiftPercent)));
   }
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0,PFX);
   ChartRedraw();
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   // 黄金Tick很密：最多每250ms重画一次；新K线立即重画
   if(prev_calculated==0 || rates_total!=prev_calculated || GetTickCount64()-g_lastDrawMs>=250)
      DrawAll();
   return rates_total;
}

void OnTimer() { DrawAll(); }   // 倒计时每秒刷新；高周期数据迟到时也能补画

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE) DrawAll();   // 缩放/拖动后重新适配宽度
}
//+------------------------------------------------------------------+
