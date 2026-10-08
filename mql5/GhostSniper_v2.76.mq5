#property strict
#property version   "2.760"
#property description "幽灵狙击手 - MT5黄金半自动交易与趋势过滤面板 v2.76 执行保护增强版"

#include <Trade/Trade.mqh>
CTrade trade;

enum MANAGE_SCOPE
{
   SCOPE_MAGIC_ONLY=0,       // 当前品种 + 本工具魔术号
   SCOPE_SYMBOL_ALL=1,       // 当前品种全部持仓
   SCOPE_MANUAL_ONLY=2       // 当前品种手工单（魔术号=0）
};

input group "=== 基础设置 ==="
input long         MagicNumber          = 26092488; // 魔术号
input MANAGE_SCOPE ManageScope          = SCOPE_MAGIC_ONLY; // 持仓管理范围
input double       DefaultLot           = 0.01; // 默认手数
input double       MaxPanelLot          = 0.10; // 面板最大手数
input double       LotStepButton        = 0.01; // 手数调整步长
input int          SlippagePoints       = 30; // 允许滑点(Points)
input int          MaxSpreadPoints      = 120; // 最大允许点差(Points)


input group "=== 抢钱 / 狙击模式参数 ==="
input bool         StartShortMode       = true; // 默认交易风格：抢钱模式
input int          ShortTPPoints        = 100; // 抢钱止盈(Points)
input int          ShortLadderGap       = 100; // 抢钱排单间距(Points)
input int          ShortLadderOffset    = 100; // 抢钱排单首单偏移(Points)
input int          LongTPPoints         = 300; // 狙击止盈(Points)
input int          LongLadderGap        = 200; // 狙击排单间距(Points)
input int          LongLadderOffset     = 200; // 狙击排单首单偏移(Points)

input group "=== 福利单设置 ==="
input bool         EnableWelfareOrder   = true; // 福利单●开启（福利单包含在“单数”总数内，不额外增加笔数）
input int          WelfareMinLadder     = 3; // 福利单触发最少排单笔数
input int          WelfareTPPoints      = 10000; // 福利单止盈(Points)
input int          WelfareLayer         = 0; // 福利单挂单层级(0=自动中间层，2~10=指定层)
input double       WelfareProtectedProfitUSD = 1.0; // 福利单最低净盈利保护(账户货币)
input int          WelfareTrailStartPts = 600; // 福利保盈线之外再走多少点后启动独立跟踪
input int          WelfareTrailDistancePts = 350; // 福利单跟踪止损距离(Points)
input int          WelfareTrailStepPts = 100; // 福利单每推进多少点更新一次止损
input long         WelfareMagic         = 26092489; // 福利单魔术号
input long         LockMagic            = 26092490; // 一键锁仓专用魔术号

input group "=== 浮盈监控设置 ==="
input bool         EnableFloatMonitor   = true; // 浮盈监控（开启后自动减仓）
input double       FloatProfitPct       = 30.0; // 浮盈监控触发比例(浮盈÷余额×100)

input group "=== 趋势过滤设置（RSI + ADX + VWAP） ==="
input bool StartTrendFilter=true; // 启动时“只做趋势”总开关
input bool EnableRSIFilter=true; input int RSIPeriod=14;
input double RSINoBuyBelow=40.0; input double RSINoSellAbove=60.0;
input bool EnableADXFilter=true;
input ENUM_TIMEFRAMES ADXTimeframe=PERIOD_M5;
input int ADXPeriod=14;
input double ADXTrendThreshold=25.0;
input double ADXRangeThreshold=20.0;
input bool UseDIDirection=true;
input bool EnableVWAPFilter=true;
input ENUM_TIMEFRAMES VWAPTimeframe=PERIOD_M5;
input int VWAPSlopeLookback=6;
input double VWAPTrendSlopePts=20.0;
input double VWAPFlatSlopePts=8.0;
input bool VWAPRequirePriceSide=true;
input int VWAPSessionStartHour=18; // 纽约18:00 CME交易日起点
input int VWAPSessionStartMinute=0;
input int VWAPServerToNewYorkHours=0; // 服务器时间-纽约时间小时差
input bool AutoNewYorkDST=true; // 自动处理纽约夏令时；关闭时使用上面的手工时差
input bool BlockRangeTradesWhenTrendOnly=true;

input group "=== HTF多周期趋势分析 ==="
input bool   EnableHTFAnalysis       = true;  // 开启H1/H4/7H趋势分析
input bool   UseHTFHardFilter        = true;  // 开启HTF逆向硬过滤
input int    HTFHardFilterMinLevel   = 2;     // 1=偏向/强向均阻止逆向；2=仅强向阻止（默认更适合半自动）
input bool   HTFBlockWhenInvalid      = true;  // HTF历史数据不足/分析失效时禁止新单
input int    HTFEMAFast              = 21;
input int    HTFEMAMid               = 55;
input int    HTFEMASlow1             = 144;
input int    HTFEMASlow2             = 166;
input int    HTFADXPeriod            = 14;
input double HTFADXTrendThreshold    = 25.0;
input int    HTFSlopeLookback        = 3;     // EMA55斜率回看HTF K线数
input double HTFSlopeAtrRatio        = 0.10;  // 斜率至少达到ATR的此比例才计分
input int    HTFH1Weight             = 25;
input int    HTFH4Weight             = 35;
input int    HTF7HWeight             = 40;
input double HTFStrongComposite      = 1.20;  // 加权值>=此值为强多/强空
input double HTFPartialComposite     = 0.35;  // 加权值>=此值为偏多/偏空

input group "=== BB+KC双通道 / VWAP偏差 ==="
input bool EnableDualChannelFilter=true;
input ENUM_TIMEFRAMES ChannelTimeframe=PERIOD_M5;
input int BollingerPeriod=20;
input double BollingerDev1=1.5;
input double BollingerDev2=2.5;
input int KeltnerEMAPeriod=20;
input int KeltnerATRPeriod=20;
input double KeltnerMult1=1.5;
input double KeltnerMult2=2.5;
input double VWAPDev1=1.0;
input double VWAPDev2=2.0;
input double VWAPDevExtreme=2.5;
input int VWAPDevLookbackBars=120;

input group "=== 波动率灯 ==="
input bool EnableVolatilityLight=true;
input int VolatilityLookback=20; // ATR基准回看
input double VolatilityLowRatio=0.80; // 当前ATR/平均ATR <= 此值：低波动
input double VolatilityHighRatio=1.20; // >= 此值：高波动
input double VolatilityExtremeRatio=1.60; // >= 此值：极端波动

input group "=== 综合交易灯 / 状态确认 ==="
input int TrendConfirmBars=2; // 趋势灯升级/反转需连续确认的K线数
input bool BlockChaseAtVWAPExtreme=true; // 同方向进入±2σ后禁止新追单
input bool BlockNewTradesAtExtremeVol=true; // 极端波动时禁止新开仓
input double TradeExtremeZ=2.0; // 交易灯极值起点

input group "=== 账户保护设置 ==="
input double       BuyLossLimitUSD      = 0.0; // 多单最大亏损金额(正数USD，0=关闭)
input double       SellLossLimitUSD     = 0.0; // 空单最大亏损金额(正数USD，0=关闭)
input double       EquityFloor          = 0.0; // 净值下限(0=关闭)
input double       EquityCeiling        = 0.0; // 净值上限(0=关闭)

input group "=== 固定止损 / 止盈设置 ==="
input bool         UseFixedSL           = true; // 固定止损
input int          FixedSLPoints        = 2000; // 止损距离(Points)
input bool         EnableSteppedTP      = true; // 排单止盈（狙击批量单/排单单分层止盈）
input int          FixedTPPoints        = 100; // 排单止盈首级/步长(Points，短狙击模式开启时由模式止盈覆盖)

input group "=== 排单单设置 ==="
input int          LadderOrders         = 5; // 每次下单单数(狙击/排单共用，最多10)
input int          LadderGapPoints      = 100; // 默认排单间距(Points)
input int          LadderOffsetPoints   = 100; // 默认排单首单偏移(Points)
input double       LadderLotMultiplier  = 1.0; // 排单手数倍率
input int          MaxTotalOrders       = 15; // 总单数上限(防过度交易)
input double       MaxSideLots           = 1.0; // 单边最大仓位(手,多/空各独立)
input bool         ReplacePendingOnNewLadder = true; // 新排单下单前删除旧挂单并按新参数重新挂

input group "=== 追踪保护 / 推保本 ==="
input bool         EnableBreakEven      = true; // 自动推保本
input int          BreakEvenTriggerPts  = 100; // 推保本触发距离(Points)
input int          BreakEvenPlusPts     = 30; // 推保本锁盈偏移(Points，文档默认30)
input int          BreakEvenSafetyPts   = 50; // 推保本后SL距当前价最小安全距离(Points)
input bool         EnableCostAwareProtect = true; // 推保本/追踪按真实净成本保护
input bool         AutoReadEntryCommission = true; // 自动读取当前持仓已发生的开仓Commission/Fee
input double       CommissionPerLotRT    = 7.0; // 每手完整往返佣金；当前黄金=7USD/手（单边3.5+3.5）
input bool         IncludeDealFeeCost    = true; // 自动读取历史DEAL_FEE并计入成本
input bool         IncludeSwapCost       = true; // 将当前负Swap计入成本（正Swap不降低保护门槛）
input int          ExtraCostBufferPts    = 5; // 成本额外缓冲(Points)，覆盖轻微滑点/费用误差
input bool         EnableDynamicExecutionBuffer = true; // 动态执行安全缓冲：结合最近不利滑点/实时点差
input double       SlipBufferMultiplier = 1.50; // 平均不利滑点缓冲倍率
input double       SpreadSafetyFraction = 0.15; // 当前点差中作为额外执行安全垫的比例（非重复计成本）
input int          MaxDynamicBufferPts   = 80; // 动态安全缓冲最大Points
input bool         EnableCommissionLearning = true; // 从已完成历史成交自动学习本品种单边佣金/Fee
input int          CommissionLearningDays = 30; // 佣金学习回看天数
input int          CommissionLearningMinDeals = 3; // 单边至少成交笔数后采用学习值
input bool         EnableModifyRetry     = true; // 自动保护SL修改失败后进入轻量重试队列
input int          ModifyRetryDelayMs    = 150; // 修改失败后的重试等待毫秒
input int          ModifyRetryMaxAttempts = 2; // 最多重试次数（不含首次）
input int          ProtectThrottleMs     = 75; // 自动推保/追踪执行节流；账户风控仍每Tick检查
input int          FloatMonitorThrottleMs = 250; // 浮盈监控节流毫秒
input bool         EnableTrailing       = true; // 追踪保护
input int          TrailTriggerPts      = 300; // 追踪启动阈值(Points)
input int          TrailDistancePts     = 200; // 追踪距离(Points)
input int          TrailStepPts         = 50; // 追踪步距(Points)
input int          AverageTPOffsetPts   = 100; // 均价TP偏移(Points)
input bool         EnableUnifiedTP       = true; // 启用“TP→均价±”功能
input bool         UnifiedTPExcludeWelfare = true; // 统一TP默认排除福利单；锁仓单始终排除

input group "=== 快捷键设置 ==="
input bool         EnableKeyboard       = true; // 启用键盘快捷键
input bool         EnableNumPad         = true; // 启用小键盘数字快捷键
input bool         EmergencyDoublePress = true; // 紧急全平需要二次确认
input int          EmergencyWindowSec   = 2; // 二次确认有效时间(秒)
input int          DeletePendingKey      = 110; // 删除挂单快捷键(小键盘小数点)


input group "=== 快捷键(ASCII/虚拟键码) ==="
input int          MarketBuyKey          = 66;  // 狙击买主键(B)
input int          MarketBuyNumKey       = 103; // 狙击买副键(Num7)
input int          LadderBuyKey          = 78;  // 排单买主键(N)
input int          LadderBuyNumKey       = 104; // 排单买副键(Num8)
input int          MarketSellKey         = 83;  // 狙击卖主键(S)
input int          MarketSellNumKey      = 97;  // 狙击卖副键(Num1)
input int          LadderSellKey         = 68;  // 排单卖主键(D)
input int          LadderSellNumKey      = 98;  // 排单卖副键(Num2)
input int          CloseProfitKey        = 80;  // 平浮盈主键(P)
input int          CloseProfitNumKey     = 101; // 平浮盈副键(Num4)
input int          BreakEvenKey          = 84;  // 推保本主键(T)
input int          BreakEvenNumKey       = 102; // 推保本副键(Num5)
input int          CloseBuyKey           = 77;  // 平多单主键(M)
input int          CloseBuyNumKey        = 105; // 平多单副键(Num9)
input int          CloseSellKey          = 70;  // 平空单主键(F)
input int          CloseSellNumKey       = 99;  // 平空单副键(Num3)

input group "=== 面板设置 ==="
input int          PanelX               = 15; // 面板横向位置X
input int          PanelY               = 30; // 面板纵向位置Y
input int          PanelScalePct        = 100; // 面板尺寸缩放%(50~200)
input bool         EnablePanelToggleHotkey = true; // O键隐藏/显示面板
input int          PanelToggleKey        = 79; // O键虚拟键码
input int          PanelRefreshMs        = 1000; // 面板轻量刷新毫秒
input int          SignalCacheRefreshSec = 3; // M5/VWAP/波动过滤缓存刷新秒
input int          HTFCacheRefreshSec    = 60; // H1/H4/7H缓存刷新秒
input int          TodayPnLRefreshSec    = 5; // 今日已实现盈亏缓存刷新秒
input int          TradeCooldownMs       = 1200; // 一次批量市价单提交后的防重复触发冷却
input bool         InstantBatchMarket     = true; // 狙击多/空使用异步极速批量提交
input bool         InstantBatchLadder     = true; // 阶梯排单使用异步极速批量提交
input bool         EnableTradeLatencyMonitor = true; // 记录狙击单：提交→服务器应答→实际成交
input int          LatencyWarnMs          = 1500; // 延迟警告阈值(ms)
input int          LatencySlowMs          = 5000; // 严重延迟阈值(ms)

string PX="JGTM_";

#define OBJ_UNI_BUY_TP  "JGTM_UNI_BUY_TP"
#define OBJ_UNI_BUY_SL  "JGTM_UNI_BUY_SL"
#define OBJ_UNI_SELL_TP "JGTM_UNI_SELL_TP"
#define OBJ_UNI_SELL_SL "JGTM_UNI_SELL_SL"

bool g_unifiedFollowActive=false;
string g_unifiedFollowName="";

double g_lot=0.01;
bool g_pause=false;
datetime g_lastEmergency=0;
string g_status="就绪";
bool g_shortMode=true;
bool g_manualTakeover=false;
bool g_floatTriggered=false;
bool g_trendFilter=true; // 面板运行时“只做趋势”开关
bool g_floatMonitor=true;  // 面板运行时“浮盈监控”开关
bool g_welfareEnabled=true; // 福利单面板运行时开关
bool g_steppedTP=true; // 排单止盈面板运行时开关
bool g_panelHidden=false; // O键/按钮隐藏面板
bool g_statsCollapsed=false; // v2.73 持仓统计区域折叠/展开


// v2.76 真实净成本缓存：避免面板刷新/保护逻辑反复扫描历史成交。
ulong g_costCachePosId[];
double g_costCacheEntryCostPerLot[];
datetime g_costCacheStamp[];

// v2.76：本品种佣金学习缓存。数值均为“每1手、单边”的实际成本。
double g_learnedEntryCostPerLot=0.0;
double g_learnedExitCostPerLot=0.0;
int g_learnedEntryDeals=0;
int g_learnedExitDeals=0;
datetime g_commissionLearnStamp=0;

// v2.76：保护执行节流。
ulong g_lastProtectExecMs=0;
ulong g_lastFloatExecMs=0;

// v2.76：自动保护修改失败重试队列，只用于EA自动推保/追踪，不改变用户手动画线指令。
struct MODIFY_RETRY_ITEM
{
   bool active;
   ulong ticket;
   double sl;
   double tp;
   int attempts;
   ulong dueMs;
   string tag;
};
MODIFY_RETRY_ITEM g_modifyRetry[32];
double g_floatTriggerPct=30.0; // 面板设定：浮盈/余额达到多少%
int g_slPts=2000;
int g_tpPts=100;
int g_gapPts=100;
int g_offsetPts=100;
int g_orderCount=5;
int g_welfareTPPts=10000;
int g_welfareLayer=0; // 0=自动中间层
int hRSI=INVALID_HANDLE;
int hADX=INVALID_HANDLE;
int hBands15=INVALID_HANDLE,hBands25=INVALID_HANDLE,hKCEMA=INVALID_HANDLE,hKCATR=INVALID_HANDLE;
enum MARKET_REGIME{REGIME_RANGE=0,REGIME_TRANSITION=1,REGIME_TREND_UP=2,REGIME_TREND_DOWN=3};
int g_stableTrendBucket=0;
int g_candidateTrendBucket=0;
int g_candidateTrendBars=0;
datetime g_lastTrendConfirmBar=0;

// HTF多周期缓存。H1/H4使用已收盘K线；7H由H1手工合成固定7小时K线。
struct HTF_BAR
{
   datetime time;
   double open;
   double high;
   double low;
   double close;
};
datetime g_lastHTFCalc=0;
datetime g_lastHTFSourceH1=0; // v2.69：HTF只在新的已收盘H1出现时重算
bool g_htfValid=false;
int g_htfH1=0,g_htfH4=0,g_htfH7=0,g_htfComposite=0;
double g_htfCompositeValue=0.0;

// v2.69 响应优化：交易按钮只读取缓存，不再在点击瞬间同步拉取大量历史。
bool g_signalCacheValid=false;
datetime g_lastSignalCache=0;
int g_cacheTrendScore=0;
double g_cacheADX=0.0,g_cachePDI=0.0,g_cacheMDI=0.0;
double g_cacheVWAP=0.0,g_cacheVWAPSlope=0.0,g_cacheRSI=50.0;
double g_cacheZ=0.0,g_cacheVolRatio=1.0,g_cacheATR=0.0;
MARKET_REGIME g_cacheRegime=REGIME_TRANSITION;
string g_cacheVolText="等待";
color g_cacheVolColor=C'180,180,190';

double g_cacheTodayPL=0.0;
datetime g_lastTodayPLCalc=0;

bool g_tradeBusy=false;
ulong g_tradeCooldownUntilMs=0;

// v2.74 交易服务器延迟监控：只跟踪“狙击多/空”异步市价批次。
bool g_latencyActive=false;
ENUM_ORDER_TYPE g_latencySide=ORDER_TYPE_BUY;
int g_latencyExpected=0;
int g_latencyAckCount=0;
int g_latencyFillCount=0;
int g_latencyRejectCount=0;
ulong g_latencyBatchStartMs=0;
double g_latencyAnchorPrice=0.0;
ulong g_latencySubmitMs[10];
bool g_latencyAckDone[10];
bool g_latencyFillDone[10];
double g_latencyLastAckMs=0.0;
double g_latencyMaxAckMs=0.0;
double g_latencyLastFillMs=0.0;
double g_latencyMaxFillMs=0.0;
double g_latencySumFillMs=0.0;
double g_latencyWorstSlipPts=0.0;
double g_latencySumSlipPts=0.0;
string g_latencyText="成交延迟：待机";
color g_latencyColor=C'170,180,190';

//---------------- scope / stats ----------------
bool MatchPos()
{
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol)return false;
   long mg=(long)PositionGetInteger(POSITION_MAGIC);
   if(g_manualTakeover && mg==0)return true;
   if(ManageScope==SCOPE_SYMBOL_ALL)return true;
   if(ManageScope==SCOPE_MANUAL_ONLY)return mg==0;
   return (mg==MagicNumber || mg==WelfareMagic || mg==LockMagic);
}
bool MatchOrder()
{
   if(OrderGetString(ORDER_SYMBOL)!=_Symbol)return false;
   long mg=(long)OrderGetInteger(ORDER_MAGIC);
   if(g_manualTakeover && mg==0)return true;
   if(ManageScope==SCOPE_SYMBOL_ALL)return true;
   if(ManageScope==SCOPE_MANUAL_ONLY)return mg==0;
   return (mg==MagicNumber || mg==WelfareMagic || mg==LockMagic);
}

// 普通组合：只包含普通EA单 + 按管理范围允许的非福利/非锁仓单。
// 福利单与锁仓单永远不参加普通均价保护。
bool IsNormalManagedPositionSelected()
{
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol)return false;
   long mg=(long)PositionGetInteger(POSITION_MAGIC);
   if(mg==WelfareMagic || mg==LockMagic)return false;
   if(g_manualTakeover && mg==0)return true;
   if(ManageScope==SCOPE_SYMBOL_ALL)return true;
   if(ManageScope==SCOPE_MANUAL_ONLY)return mg==0;
   return mg==MagicNumber;
}

bool IsUnifiedTPPositionSelected()
{
   if(!MatchPos())return false;
   long mg=(long)PositionGetInteger(POSITION_MAGIC);
   if(mg==LockMagic)return false;
   if(mg==WelfareMagic && UnifiedTPExcludeWelfare)return false;
   return true;
}

// 锁仓手数不受面板MaxPanelLot限制，只服从经纪商最小/最大/步长。
double NormalizeBrokerVolume(double v)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0)return v;
   v=MathMax(0.0,MathMin(mx,v));
   if(v<mn-1e-12)return 0.0;
   int vd=2;
   if(st<0.01)vd=3;
   if(st<0.001)vd=4;
   return NormalizeDouble(MathFloor(v/st+1e-8)*st,vd);
}

double NLot(double v)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0)return v;
   v=MathMax(mn,MathMin(MathMin(mx,MaxPanelLot),v));
   return NormalizeDouble(MathFloor(v/st+1e-8)*st,2);
}

double RSIValue()
{
 if(hRSI==INVALID_HANDLE)return 50.0;
 double a[];ArraySetAsSeries(a,true);if(CopyBuffer(hRSI,0,0,1,a)<1)return 50.0;return a[0];
}
bool ADXValues(double &a,double &p,double &m)
{
 a=p=m=0;if(hADX==INVALID_HANDLE)return false;
 double x[],y[],z[];ArraySetAsSeries(x,true);ArraySetAsSeries(y,true);ArraySetAsSeries(z,true);
 if(CopyBuffer(hADX,0,0,1,x)<1||CopyBuffer(hADX,1,0,1,y)<1||CopyBuffer(hADX,2,0,1,z)<1)return false;
 a=x[0];p=y[0];m=z[0];return true;
}
datetime NthSundayOfMonth(int year,int month,int nth)
{
   MqlDateTime d;ZeroMemory(d);
   d.year=year;d.mon=month;d.day=1;d.hour=2;d.min=0;d.sec=0;
   datetime first=StructToTime(d);
   MqlDateTime f;TimeToStruct(first,f);
   int firstSunday=1+((7-f.day_of_week)%7);
   d.day=firstSunday+(nth-1)*7;
   return StructToTime(d);
}
bool IsNewYorkDST(datetime utcNow)
{
   MqlDateTime u;TimeToStruct(utcNow,u);
   // 美国DST：3月第二个周日02:00当地标准时开始；11月第一个周日02:00当地夏令时结束。
   datetime marchLocal=NthSundayOfMonth(u.year,3,2);
   datetime novLocal=NthSundayOfMonth(u.year,11,1);
   // 转成UTC：开始前纽约UTC-5，结束前纽约UTC-4。
   datetime startUTC=marchLocal+5*3600;
   datetime endUTC=novLocal+4*3600;
   return (utcNow>=startUTC && utcNow<endUTC);
}
int NewYorkUTCOffsetHours(datetime utcNow)
{
   return IsNewYorkDST(utcNow)?-4:-5;
}
datetime VWAPSessionStartServer()
{
   if(!AutoNewYorkDST)
   {
      datetime sn=TimeCurrent(),ny=sn-VWAPServerToNewYorkHours*3600;
      MqlDateTime x;TimeToStruct(ny,x);
      x.hour=VWAPSessionStartHour;x.min=VWAPSessionStartMinute;x.sec=0;
      datetime st=StructToTime(x);if(ny<st)st-=86400;
      return st+VWAPServerToNewYorkHours*3600;
   }

   datetime utcNow=TimeGMT();
   int nyOff=NewYorkUTCOffsetHours(utcNow);
   datetime nyNow=utcNow+nyOff*3600;
   MqlDateTime x;TimeToStruct(nyNow,x);
   x.hour=VWAPSessionStartHour;x.min=VWAPSessionStartMinute;x.sec=0;
   datetime nyStart=StructToTime(x);
   if(nyNow<nyStart)nyStart-=86400;

   // 18:00纽约时间对应的UTC，再转换为当前经纪商服务器时间。
   datetime utcStart=nyStart-nyOff*3600;
   int serverOffsetSec=(int)(TimeCurrent()-TimeGMT());
   return utcStart+serverOffsetSec;
}
bool BuildSessionVWAP(double &now,double &past,double &slope)
{
 now=past=slope=0;MqlRates r[];ArraySetAsSeries(r,false);
 int n=CopyRates(_Symbol,VWAPTimeframe,VWAPSessionStartServer(),TimeCurrent(),r);
 if(n<MathMax(3,VWAPSlopeLookback+1))return false;
 double pv=0,v=0;double q[];ArrayResize(q,n);
 for(int i=0;i<n;i++){double typ=(r[i].high+r[i].low+r[i].close)/3.0;double vol=(r[i].real_volume>0?(double)r[i].real_volume:(double)r[i].tick_volume);if(vol<=0)vol=1;pv+=typ*vol;v+=vol;q[i]=pv/v;}
 now=q[n-1];int j=MathMax(0,n-1-MathMax(1,VWAPSlopeLookback));past=q[j];slope=(now-past)/_Point;return true;
}
MARKET_REGIME CurrentMarketRegime(double &a,double &p,double &m,double &vw,double &sl)
{
 a=p=m=vw=sl=0;double old=0;
 if(EnableADXFilter&&!ADXValues(a,p,m))return REGIME_TRANSITION;
 if(EnableVWAPFilter&&!BuildSessionVWAP(vw,old,sl))return REGIME_TRANSITION;
 MqlTick k;SymbolInfoTick(_Symbol,k);
 bool trend=!EnableADXFilter||a>=ADXTrendThreshold,range=EnableADXFilter&&a<=ADXRangeThreshold;
 bool up=!EnableVWAPFilter||sl>=VWAPTrendSlopePts,dn=!EnableVWAPFilter||sl<=-VWAPTrendSlopePts,flat=EnableVWAPFilter&&MathAbs(sl)<=VWAPFlatSlopePts;
 bool pab=!EnableVWAPFilter||!VWAPRequirePriceSide||k.bid>=vw,pbl=!EnableVWAPFilter||!VWAPRequirePriceSide||k.ask<=vw;
 bool diu=!EnableADXFilter||!UseDIDirection||p>m,did=!EnableADXFilter||!UseDIDirection||m>p;
 if(trend&&up&&pab&&diu)return REGIME_TREND_UP;if(trend&&dn&&pbl&&did)return REGIME_TREND_DOWN;
 if((range&&(!EnableVWAPFilter||flat))||(!EnableADXFilter&&flat))return REGIME_RANGE;return REGIME_TRANSITION;
}
string RegimeText(MARKET_REGIME r){if(r==REGIME_TREND_UP)return "趋势多";if(r==REGIME_TREND_DOWN)return "趋势空";if(r==REGIME_RANGE)return "震荡";return "过渡";}

bool DualChannelValues(double &bm,double &u15,double &l15,double &u25,double &l25,double &km,double &ku15,double &kl15,double &ku25,double &kl25)
{
 double m1[],a1[],b1[],m2[],a2[],b2[],e[],atr[];ArraySetAsSeries(m1,true);ArraySetAsSeries(a1,true);ArraySetAsSeries(b1,true);ArraySetAsSeries(m2,true);ArraySetAsSeries(a2,true);ArraySetAsSeries(b2,true);ArraySetAsSeries(e,true);ArraySetAsSeries(atr,true);
 if(CopyBuffer(hBands15,0,0,1,m1)<1||CopyBuffer(hBands15,1,0,1,a1)<1||CopyBuffer(hBands15,2,0,1,b1)<1||CopyBuffer(hBands25,0,0,1,m2)<1||CopyBuffer(hBands25,1,0,1,a2)<1||CopyBuffer(hBands25,2,0,1,b2)<1||CopyBuffer(hKCEMA,0,0,1,e)<1||CopyBuffer(hKCATR,0,0,1,atr)<1)return false;
 bm=m1[0];u15=a1[0];l15=b1[0];u25=a2[0];l25=b2[0];km=e[0];
 ku15=km+KeltnerMult1*atr[0];kl15=km-KeltnerMult1*atr[0];
 ku25=km+KeltnerMult2*atr[0];kl25=km-KeltnerMult2*atr[0];
 return true;
}
int DualChannelScore()
{
 if(!EnableDualChannelFilter)return 0;double bm,u1,l1,u2,l2,km,ku1,kl1,ku2,kl2;if(!DualChannelValues(bm,u1,l1,u2,l2,km,ku1,kl1,ku2,kl2))return 0;MqlTick q;SymbolInfoTick(_Symbol,q);double p=(q.bid+q.ask)/2;int s=0;
 if(p>bm&&p>km)s++;else if(p<bm&&p<km)s--;if(p>=u1&&p>=ku1)s+=2;else if(p<=l1&&p<=kl1)s-=2;if(p>=u2&&p>=ku2)s++;else if(p<=l2&&p<=kl2)s--;return s;
}
bool VWAPZ(double &z)
{
 z=0;MqlRates r[];ArraySetAsSeries(r,false);int n=CopyRates(_Symbol,VWAPTimeframe,VWAPSessionStartServer(),TimeCurrent(),r);if(n<10)return false;int f=MathMax(0,n-VWAPDevLookbackBars);double sw=0,sp=0;
 for(int i=f;i<n;i++){double p=(r[i].high+r[i].low+r[i].close)/3,w=(r[i].real_volume>0?(double)r[i].real_volume:(double)r[i].tick_volume);if(w<=0)w=1;sw+=w;sp+=p*w;}double v=sp/sw,var=0;
 for(int i=f;i<n;i++){double p=(r[i].high+r[i].low+r[i].close)/3,w=(r[i].real_volume>0?(double)r[i].real_volume:(double)r[i].tick_volume);if(w<=0)w=1;var+=w*(p-v)*(p-v);}double sd=MathSqrt(var/sw);if(sd<=0)return false;MqlTick q;SymbolInfoTick(_Symbol,q);z=((q.bid+q.ask)/2-v)/sd;return true;
}
string VWAPZoneText(double z){double a=MathAbs(z);if(a>=2.5)return z>0?"上>2.5σ":"下>2.5σ";if(a>=2.0)return z>0?"上2~2.5σ极值":"下2~2.5σ极值";if(a>=1.0)return z>0?"上1~2σ":"下1~2σ";return "±1σ";}

string LocationLightText(double z)
{
   double a=MathAbs(z);
   if(a>=VWAPDevExtreme) return (z>0 ? "上方过度延伸" : "下方过度延伸");
   if(a>=VWAPDev2)      return (z>0 ? "上方极值区"   : "下方极值区");
   if(a>=VWAPDev1)      return (z>0 ? "上方扩张区"   : "下方扩张区");
   return "价值/均衡区";
}
color LocationLightColor(double z)
{
   double a=MathAbs(z);
   if(a>=VWAPDevExtreme) return C'255,55,55';   // >2.5σ 红：过度延伸
   if(a>=VWAPDev2)       return C'255,150,70';  // 2~2.5σ 橙：极值
   if(a>=VWAPDev1)       return C'255,220,70';  // 1~2σ 黄：扩张
   return C'100,210,255';                       // ±1σ 蓝：均衡
}
// v2.65.1 面板五档趋势灯：强多 / 偏多 / 震荡 / 偏空 / 强空。
// 分数只用于显示；真正下单仍由 DirectionAllowed() 的 RSI+ADX+VWAP 硬过滤控制。
int TrendLightScore(double &adx,double &pdi,double &mdi,double &vw,double &slope,double &rsi)
{
   adx=pdi=mdi=vw=slope=0.0;rsi=RSIValue();
   ADXValues(adx,pdi,mdi);
   double old=0.0;BuildSessionVWAP(vw,old,slope);
   MqlTick q;SymbolInfoTick(_Symbol,q);

   int score=0;
   // RSI：中轴50判断方向，强弱区间再加权。
   if(rsi>=60)score+=2; else if(rsi>52)score+=1;
   else if(rsi<=40)score-=2; else if(rsi<48)score-=1;

   // DI方向。
   if(pdi>mdi)score+=1; else if(mdi>pdi)score-=1;

   // ADX只放大已有方向，不单独制造方向。
   if(adx>=ADXTrendThreshold)
   {
      if(pdi>mdi)score+=1;
      else if(mdi>pdi)score-=1;
   }

   // VWAP斜率。
   if(slope>=VWAPTrendSlopePts)score+=2;
   else if(slope>VWAPFlatSlopePts)score+=1;
   else if(slope<=-VWAPTrendSlopePts)score-=2;
   else if(slope<-VWAPFlatSlopePts)score-=1;

   // 价格相对VWAP。
   if(vw>0)
   {
      if(q.bid>vw)score+=1;
      else if(q.ask<vw)score-=1;
   }
   score+=DualChannelScore();
   double z=0;if(VWAPZ(z)){if(z>=1&&z<2)score++;else if(z<=-1&&z>-2)score--;else if(z>=2.5)score--;else if(z<=-2.5)score++;}
   return score;
}
int TrendBucketFromScore(int s)
{
   if(s>=7)return 2;
   if(s>=2)return 1;
   if(s<=-7)return -2;
   if(s<=-2)return -1;
   return 0;
}
void UpdateStableTrend(int rawScore)
{
   datetime bar=iTime(_Symbol,ChannelTimeframe,0);
   if(bar<=0 || bar==g_lastTrendConfirmBar)return;
   g_lastTrendConfirmBar=bar;
   int b=TrendBucketFromScore(rawScore);

   if(g_stableTrendBucket==0 && g_candidateTrendBars==0)
   {
      g_stableTrendBucket=b;
      g_candidateTrendBucket=b;
      return;
   }
   if(b==g_stableTrendBucket)
   {
      g_candidateTrendBucket=b;
      g_candidateTrendBars=0;
      return;
   }
   if(b!=g_candidateTrendBucket)
   {
      g_candidateTrendBucket=b;
      g_candidateTrendBars=1;
   }
   else g_candidateTrendBars++;

   if(g_candidateTrendBars>=MathMax(1,TrendConfirmBars))
   {
      g_stableTrendBucket=g_candidateTrendBucket;
      g_candidateTrendBars=0;
   }
}
string StableTrendText()
{
   if(g_stableTrendBucket>=2)return "强多";
   if(g_stableTrendBucket==1)return "偏多";
   if(g_stableTrendBucket<=-2)return "强空";
   if(g_stableTrendBucket==-1)return "偏空";
   return "震荡";
}
color StableTrendColor()
{
   if(g_stableTrendBucket>=2)return C'0,255,80';
   if(g_stableTrendBucket==1)return C'80,220,120';
   if(g_stableTrendBucket<=-2)return C'255,55,55';
   if(g_stableTrendBucket==-1)return C'255,150,70';
   return C'255,220,70';
}

string TrendLightText(int s)
{
   if(s>=7)return "强多";
   if(s>=2)return "偏多";
   if(s<=-7)return "强空";
   if(s<=-2)return "偏空";
   return "震荡";
}
color TrendLightColor(int s)
{
   if(s>=7)return C'0,255,80';
   if(s>=2)return C'80,220,120';
   if(s<=-7)return C'255,55,55';
   if(s<=-2)return C'255,150,70';
   return C'255,220,70';
}
int ModeTP(){return g_tpPts;} int ModeGap(){return g_gapPts;} int ModeOffset(){return g_offsetPts;}
int StepTPBase(){int v=ModeTP();if(v<=0)v=g_tpPts;return MathMax(1,v);}
double SteppedTPPrice(ENUM_ORDER_TYPE type,double entry,int index){int d=StepTPBase()*(g_steppedTP?index+1:1);return NormalizeDouble(type==ORDER_TYPE_BUY?entry+d*_Point:entry-d*_Point,_Digits);}

//---------------- HTF H1/H4/7H 趋势引擎 ----------------
int RequiredHTFBars()
{
   int p=MathMax(MathMax(HTFEMAFast,HTFEMAMid),MathMax(HTFEMASlow1,HTFEMASlow2));
   return MathMax(p+MathMax(1,HTFSlopeLookback)+30,HTFADXPeriod*3+30);
}
int BuildNativeHTFBars(ENUM_TIMEFRAMES tf,HTF_BAR &out[])
{
   MqlRates r[];ArraySetAsSeries(r,false);
   int need=RequiredHTFBars();
   int got=CopyRates(_Symbol,tf,1,need,r); // 只取已收盘K线，避免高周期未收盘反复翻转
   if(got<=0){ArrayResize(out,0);return 0;}
   ArrayResize(out,got);
   for(int i=0;i<got;i++)
   {
      out[i].time=r[i].time;out[i].open=r[i].open;out[i].high=r[i].high;
      out[i].low=r[i].low;out[i].close=r[i].close;
   }
   return got;
}
int BuildSynthetic7HBars(HTF_BAR &out[])
{
   MqlRates r[];ArraySetAsSeries(r,false);
   int sourceNeed=RequiredHTFBars()*7+40;
   int got=CopyRates(_Symbol,PERIOD_H1,1,sourceNeed,r);
   if(got<=0){ArrayResize(out,0);return 0;}

   ArrayResize(out,0);
   bool first=true;long lastKey=0;int n=0;
   for(int i=0;i<got;i++)
   {
      // 固定7小时桶。以MT5时间戳为基准，避免“滚动7H”每小时改变边界。
      long key=(long)(r[i].time/(7*3600));
      if(first || key!=lastKey)
      {
         n++;ArrayResize(out,n);
         out[n-1].time=r[i].time;out[n-1].open=r[i].open;out[n-1].high=r[i].high;
         out[n-1].low=r[i].low;out[n-1].close=r[i].close;
         first=false;lastKey=key;
      }
      else
      {
         if(r[i].high>out[n-1].high)out[n-1].high=r[i].high;
         if(r[i].low<out[n-1].low)out[n-1].low=r[i].low;
         out[n-1].close=r[i].close;
      }
   }

   // 当前固定7H桶尚未完整收盘时剔除，避免HTF方向在桶内反复翻转。
   long currentKey=(long)(TimeCurrent()/(7*3600));
   if(n>0 && lastKey==currentKey)
   {
      n--;
      ArrayResize(out,n);
   }
   return n;
}
double HTFEMAAt(HTF_BAR &bars[],int n,int period,int endIndex)
{
   if(n<=0 || period<=0 || endIndex<0)return 0.0;
   if(endIndex>=n)endIndex=n-1;
   double alpha=2.0/(period+1.0);
   double ema=bars[0].close;
   for(int i=1;i<=endIndex;i++)ema=alpha*bars[i].close+(1.0-alpha)*ema;
   return ema;
}
bool HTFADX(HTF_BAR &bars[],int n,int period,double &adx,double &pdi,double &mdi,double &atr)
{
   adx=pdi=mdi=atr=0.0;
   if(period<2 || n<period*2+2)return false;

   double smTR=0.0,smP=0.0,smM=0.0;
   for(int i=1;i<=period;i++)
   {
      double up=bars[i].high-bars[i-1].high;
      double dn=bars[i-1].low-bars[i].low;
      double pdm=(up>dn && up>0.0?up:0.0);
      double mdm=(dn>up && dn>0.0?dn:0.0);
      double tr=MathMax(bars[i].high-bars[i].low,
                MathMax(MathAbs(bars[i].high-bars[i-1].close),MathAbs(bars[i].low-bars[i-1].close)));
      smTR+=tr;smP+=pdm;smM+=mdm;
   }

   double dxs[];ArrayResize(dxs,0);int dxc=0;
   for(int i=period;i<n;i++)
   {
      if(i>period)
      {
         double up=bars[i].high-bars[i-1].high;
         double dn=bars[i-1].low-bars[i].low;
         double pdm=(up>dn && up>0.0?up:0.0);
         double mdm=(dn>up && dn>0.0?dn:0.0);
         double tr=MathMax(bars[i].high-bars[i].low,
                   MathMax(MathAbs(bars[i].high-bars[i-1].close),MathAbs(bars[i].low-bars[i-1].close)));
         smTR=smTR-smTR/period+tr;
         smP =smP -smP /period+pdm;
         smM =smM -smM /period+mdm;
      }
      if(smTR<=0.0)continue;
      pdi=100.0*smP/smTR;mdi=100.0*smM/smTR;
      double den=pdi+mdi;
      double dx=(den>0.0?100.0*MathAbs(pdi-mdi)/den:0.0);
      dxc++;ArrayResize(dxs,dxc);dxs[dxc-1]=dx;
   }
   if(dxc<period)return false;

   adx=0.0;
   for(int i=0;i<period;i++)adx+=dxs[i];
   adx/=period;
   for(int i=period;i<dxc;i++)adx=(adx*(period-1)+dxs[i])/period;
   atr=smTR/period;
   return true;
}
bool EvaluateHTFState(HTF_BAR &bars[],int n,int &state)
{
   state=0;
   int maxP=MathMax(MathMax(HTFEMAFast,HTFEMAMid),MathMax(HTFEMASlow1,HTFEMASlow2));
   int lb=MathMax(1,HTFSlopeLookback);
   if(n<MathMax(maxP+lb+5,HTFADXPeriod*2+5))return false;

   int last=n-1;
   double eFast=HTFEMAAt(bars,n,MathMax(1,HTFEMAFast),last);
   double eMid =HTFEMAAt(bars,n,MathMax(1,HTFEMAMid),last);
   double eS1  =HTFEMAAt(bars,n,MathMax(1,HTFEMASlow1),last);
   double eS2  =HTFEMAAt(bars,n,MathMax(1,HTFEMASlow2),last);
   double eMidPast=HTFEMAAt(bars,n,MathMax(1,HTFEMAMid),last-lb);
   double adx,pdi,mdi,atr;
   if(!HTFADX(bars,n,MathMax(2,HTFADXPeriod),adx,pdi,mdi,atr))return false;

   double px=bars[last].close;
   int score=0;

   bool strongBull=(eFast>eMid && eMid>eS1 && eS1>eS2);
   bool strongBear=(eFast<eMid && eMid<eS1 && eS1<eS2);
   if(strongBull)score+=3;
   else if(strongBear)score-=3;
   else
   {
      if(eFast>eMid && eMid>eS1)score+=2;
      else if(eFast<eMid && eMid<eS1)score-=2;
      else if(eFast>eMid)score+=1;
      else if(eFast<eMid)score-=1;
   }

   if(px>eMid)score++; else if(px<eMid)score--;
   if(px>eS1)score++;  else if(px<eS1)score--;

   if(adx>=HTFADXTrendThreshold)
   {
      if(pdi>mdi)score+=2; else if(mdi>pdi)score-=2;
   }
   else if(adx>=HTFADXTrendThreshold*0.70)
   {
      if(pdi>mdi)score++; else if(mdi>pdi)score--;
   }

   double slope=eMid-eMidPast;
   double slopeGate=MathMax(_Point,atr*MathMax(0.0,HTFSlopeAtrRatio));
   if(slope>=slopeGate)score++;
   else if(slope<=-slopeGate)score--;

   if(score>=6)state=2;
   else if(score>=2)state=1;
   else if(score<=-6)state=-2;
   else if(score<=-2)state=-1;
   else state=0;
   return true;
}
string HTFStateText(int s)
{
   if(s>=2)return "强多";
   if(s==1)return "偏多";
   if(s<=-2)return "强空";
   if(s==-1)return "偏空";
   return "震荡";
}
color HTFStateColor(int s)
{
   if(s>=2)return C'0,255,80';
   if(s==1)return C'80,220,120';
   if(s<=-2)return C'255,55,55';
   if(s==-1)return C'255,150,70';
   return C'255,220,70';
}
void RefreshHTFAnalysis(bool force=false)
{
   if(!EnableHTFAnalysis)
   {
      g_htfValid=false;g_htfH1=g_htfH4=g_htfH7=g_htfComposite=0;g_htfCompositeValue=0.0;
      return;
   }

   datetime now=TimeCurrent();
   datetime sourceH1=iTime(_Symbol,PERIOD_H1,1);

   // H1/H4/7H全部基于已收盘K线；没有新H1收盘时无需重复重算。
   // 这样不再每10秒/60秒拉取约上千根H1历史，避免周期性卡顿。
   if(!force)
   {
      if(sourceH1>0 && g_lastHTFSourceH1>0 && sourceH1==g_lastHTFSourceH1)return;

      // 历史还未就绪时使用时间冷却，避免连续请求。
      if(sourceH1<=0 && g_lastHTFCalc>0 &&
         now-g_lastHTFCalc<MathMax(10,HTFCacheRefreshSec))return;
   }

   g_lastHTFCalc=now;
   if(sourceH1>0)g_lastHTFSourceH1=sourceH1;

   HTF_BAR b1[],b4[],b7[];
   int n1=BuildNativeHTFBars(PERIOD_H1,b1);
   int n4=BuildNativeHTFBars(PERIOD_H4,b4);
   int n7=BuildSynthetic7HBars(b7);

   int s1=0,s4=0,s7=0;
   bool ok1=EvaluateHTFState(b1,n1,s1);
   bool ok4=EvaluateHTFState(b4,n4,s4);
   bool ok7=EvaluateHTFState(b7,n7,s7);
   g_htfValid=ok1&&ok4&&ok7;
   if(!g_htfValid)
   {
      g_htfH1=g_htfH4=g_htfH7=g_htfComposite=0;g_htfCompositeValue=0.0;
      return;
   }

   g_htfH1=s1;g_htfH4=s4;g_htfH7=s7;
   double w1=MathMax(0,HTFH1Weight),w4=MathMax(0,HTFH4Weight),w7=MathMax(0,HTF7HWeight);
   double ws=w1+w4+w7;if(ws<=0.0){w1=25;w4=35;w7=40;ws=100;}
   g_htfCompositeValue=(s1*w1+s4*w4+s7*w7)/ws;

   double strong=MathMax(0.50,HTFStrongComposite);
   double partial=MathMax(0.05,MathMin(strong-0.05,HTFPartialComposite));
   if(g_htfCompositeValue>=strong)g_htfComposite=2;
   else if(g_htfCompositeValue>=partial)g_htfComposite=1;
   else if(g_htfCompositeValue<=-strong)g_htfComposite=-2;
   else if(g_htfCompositeValue<=-partial)g_htfComposite=-1;
   else g_htfComposite=0;
}
bool DirectionAllowed(ENUM_ORDER_TYPE type)
{
   if(!g_trendFilter)return true;

   datetime now=TimeCurrent();
   int maxAge=MathMax(10,MathMax(1,SignalCacheRefreshSec)*4);

   // 点击交易按钮时禁止同步重算大批量HTF/VWAP历史。
   // 缓存过旧就安全拒绝一次，由Timer后台刷新，避免界面假死。
   if(!g_signalCacheValid || g_lastSignalCache<=0 || now-g_lastSignalCache>maxAge)
   {
      g_status="趋势缓存正在更新，暂缓新单；请稍后再按一次";
      return false;
   }

   if(EnableHTFAnalysis && UseHTFHardFilter)
   {
      datetime currentClosedH1=iTime(_Symbol,PERIOD_H1,1);
      bool htfFresh=(g_lastHTFCalc>0 &&
                     g_lastHTFSourceH1>0 &&
                     currentClosedH1>0 &&
                     currentClosedH1==g_lastHTFSourceH1);

      if(!htfFresh)
      {
         if(HTFBlockWhenInvalid)
         {
            g_status="HTF缓存过旧/正在更新，暂缓新单";
            return false;
         }
      }
      else if(g_htfValid)
      {
         int gate=MathMax(1,MathMin(2,HTFHardFilterMinLevel));
         if(type==ORDER_TYPE_BUY && g_htfComposite<=-gate)
         {g_status="HTF过滤：综合"+HTFStateText(g_htfComposite)+"，禁止逆势开多";return false;}
         if(type==ORDER_TYPE_SELL && g_htfComposite>=gate)
         {g_status="HTF过滤：综合"+HTFStateText(g_htfComposite)+"，禁止逆势开空";return false;}
      }
      else if(HTFBlockWhenInvalid)
      {
         g_status="HTF过滤：H1/H4/7H数据不足或分析失效，暂缓新单";
         return false;
      }
   }

   double ez=g_cacheZ;
   if(BlockChaseAtVWAPExtreme)
   {
      if(type==ORDER_TYPE_BUY && ez>=TradeExtremeZ)
      {g_status="交易灯：多头处于VWAP极值区，等待回踩";return false;}
      if(type==ORDER_TYPE_SELL && ez<=-TradeExtremeZ)
      {g_status="交易灯：空头处于VWAP极值区，等待反弹";return false;}
   }

   if(BlockNewTradesAtExtremeVol && g_cacheVolRatio>=VolatilityExtremeRatio)
   {g_status="交易灯：极端波动，暂停新开仓";return false;}

   if(EnableRSIFilter)
   {
      double r=g_cacheRSI;
      if(type==ORDER_TYPE_BUY && r<RSINoBuyBelow)
      {g_status="过滤：RSI过弱，禁止开多";return false;}
      if(type==ORDER_TYPE_SELL && r>RSINoSellAbove)
      {g_status="过滤：RSI过强，禁止开空";return false;}
   }

   MARKET_REGIME rg=g_cacheRegime;
   if(rg==REGIME_TREND_UP && type==ORDER_TYPE_SELL)
   {g_status="过滤：ADX+VWAP趋势多，禁止逆势开空";return false;}
   if(rg==REGIME_TREND_DOWN && type==ORDER_TYPE_BUY)
   {g_status="过滤：ADX+VWAP趋势空，禁止逆势开多";return false;}
   if(BlockRangeTradesWhenTrendOnly && (rg==REGIME_RANGE || rg==REGIME_TRANSITION))
   {g_status="过滤："+RegimeText(rg)+"，只做趋势模式禁止新单";return false;}

   return true;
}

bool TradeOK()
{
   if(g_pause){g_status="快捷交易已暂停";return false;}
   MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;
   if((t.ask-t.bid)/_Point>MaxSpreadPoints){g_status="点差过大，拒绝下单";return false;}
   return true;
}
void Stats(ENUM_POSITION_TYPE ty,int &n,double &lots,double &profit,double &avg)
{
   n=0;lots=profit=avg=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      n++;lots+=v;profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);avg+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   if(lots>0)avg/=lots;
}

void StatsNoLock(ENUM_POSITION_TYPE ty,int &n,double &lots,double &profit,double &avg)
{
   n=0;lots=profit=avg=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      n++;lots+=v;profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);avg+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   if(lots>0)avg/=lots;
}

void NormalStats(ENUM_POSITION_TYPE ty,int &n,double &lots,double &profit,double &avg)
{
   n=0;lots=profit=avg=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!IsNormalManagedPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      n++;lots+=v;profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);avg+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   if(lots>0)avg/=lots;
}

double NormalFloatPL()
{
   int n1,n2;double l1,p1,a1,l2,p2,a2;
   NormalStats(POSITION_TYPE_BUY,n1,l1,p1,a1);
   NormalStats(POSITION_TYPE_SELL,n2,l2,p2,a2);
   return p1+p2;
}

void WelfareStatsDetailed(ENUM_POSITION_TYPE ty,int &n,double &lots,double &profit,double &avg,double &costBE,double &profitFloor)
{
   n=0;lots=profit=avg=costBE=profitFloor=0.0;
   double wOpen=0.0,wBE=0.0,wFloor=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=WelfareMagic)continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);if(v<=0)continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double cp=PositionCostPoints();
      double mpp=MoneyPerPointPerLot()*v;
      double pp=(mpp>0?MathMax(0.0,WelfareProtectedProfitUSD)/mpp:0.0);
      double basePts=cp+MathMax(0,BreakEvenPlusPts);
      double be=(ty==POSITION_TYPE_BUY?open+basePts*_Point:open-basePts*_Point);
      double fl=(ty==POSITION_TYPE_BUY?open+(basePts+pp)*_Point:open-(basePts+pp)*_Point);
      n++;lots+=v;profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      wOpen+=open*v;wBE+=be*v;wFloor+=fl*v;
   }
   if(lots>0){avg=wOpen/lots;costBE=wBE/lots;profitFloor=wFloor/lots;}
}

void LockStats(int &n,double &buyLots,double &sellLots,double &profit)
{
   n=0;buyLots=sellLots=profit=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=LockMagic)continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ty==POSITION_TYPE_BUY)buyLots+=v;else sellLots+=v;
      profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);n++;
   }
}
double FloatPL(){int a,b;double l,p,av,l2,p2,av2;Stats(POSITION_TYPE_BUY,a,l,p,av);Stats(POSITION_TYPE_SELL,b,l2,p2,av2);return p+p2;}
bool IsPendingType(ENUM_ORDER_TYPE x){return x==ORDER_TYPE_BUY_LIMIT||x==ORDER_TYPE_SELL_LIMIT||x==ORDER_TYPE_BUY_STOP||x==ORDER_TYPE_SELL_STOP||x==ORDER_TYPE_BUY_STOP_LIMIT||x==ORDER_TYPE_SELL_STOP_LIMIT;}
int TotalManaged(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong k=PositionGetTicket(i);if(k&&PositionSelectByTicket(k)&&MatchPos())n++;}for(int i=OrdersTotal()-1;i>=0;i--){ulong k=OrderGetTicket(i);if(k&&OrderSelect(k)&&MatchOrder()&&IsPendingType((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)))n++;}return n;}
double SideLots(ENUM_POSITION_TYPE ty){int n=0;double l=0,p=0,a=0;Stats(ty,n,l,p,a);return l;}
double SidePendingLots(ENUM_ORDER_TYPE side){double l=0;for(int i=OrdersTotal()-1;i>=0;i--){ulong k=OrderGetTicket(i);if(!k||!OrderSelect(k)||!MatchOrder())continue;ENUM_ORDER_TYPE x=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);bool b=x==ORDER_TYPE_BUY_LIMIT||x==ORDER_TYPE_BUY_STOP||x==ORDER_TYPE_BUY_STOP_LIMIT;bool s=x==ORDER_TYPE_SELL_LIMIT||x==ORDER_TYPE_SELL_STOP||x==ORDER_TYPE_SELL_STOP_LIMIT;if((side==ORDER_TYPE_BUY&&b)||(side==ORDER_TYPE_SELL&&s))l+=OrderGetDouble(ORDER_VOLUME_CURRENT);}return l;}
bool SideCapacityOK(ENUM_ORDER_TYPE type,double add){if(MaxSideLots<=0)return true;ENUM_POSITION_TYPE p=(type==ORDER_TYPE_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL);if(SideLots(p)+SidePendingLots(type)+MathMax(0.0,add)>MaxSideLots+1e-8){g_status=(type==ORDER_TYPE_BUY?"多":"空")+"方向潜在总手数达到上限";return false;}return true;}

//---------------- direct market orders ----------------
int ResolveWelfareLayerForTotal(int total)
{
   if(!g_welfareEnabled || total<MathMax(1,WelfareMinLadder))return 0;
   if(g_welfareLayer<=0)return MathMax(1,(total+1)/2); // 5单时默认第3单为福利单
   return MathMax(1,MathMin(total,g_welfareLayer));
}

bool IsSniperMarketComment(const string c)
{
   return StringFind(c,"幽灵狙击多单 #")>=0 ||
          StringFind(c,"幽灵狙击空单 #")>=0 ||
          StringFind(c,"福利多单 #")>=0 ||
          StringFind(c,"福利空单 #")>=0;
}

int SniperLayerFromComment(const string c)
{
   int p=StringFind(c,"#");
   if(p<0)return 0;
   int layer=(int)StringToInteger(StringSubstr(c,p+1));
   if(layer<1 || layer>10)return 0;
   return layer;
}

int FirstFreeLatencySlot(bool forFill)
{
   for(int i=0;i<10;i++)
   {
      if(i>=g_latencyExpected)break;
      if(forFill)
      {
         if(!g_latencyFillDone[i])return i;
      }
      else
      {
         if(!g_latencyAckDone[i])return i;
      }
   }
   return -1;
}

void UpdateLatencyText()
{
   if(!EnableTradeLatencyMonitor)
   {
      g_latencyText="成交延迟：监控已关闭";
      g_latencyColor=C'150,150,160';
      return;
   }

   if(!g_latencyActive && g_latencyExpected<=0)
   {
      g_latencyText="成交延迟：待机";
      g_latencyColor=C'170,180,190';
      return;
   }

   double avgFill=(g_latencyFillCount>0?g_latencySumFillMs/g_latencyFillCount:0.0);
   double avgSlip=(g_latencyFillCount>0?g_latencySumSlipPts/g_latencyFillCount:0.0);

   g_latencyText=
      "延迟 ● 应答 "+IntegerToString(g_latencyAckCount)+"/"+IntegerToString(g_latencyExpected)+
      "｜成交 "+IntegerToString(g_latencyFillCount)+"/"+IntegerToString(g_latencyExpected)+
      "｜末 "+DoubleToString(g_latencyLastFillMs,0)+"ms"+
      " 最大 "+DoubleToString(g_latencyMaxFillMs,0)+"ms"+
      "｜均 "+DoubleToString(avgFill,0)+"ms"+
      " 滑点 "+DoubleToString(avgSlip,1)+"pt";

   double judge=MathMax(g_latencyMaxAckMs,g_latencyMaxFillMs);
   if(judge>=MathMax(LatencySlowMs,LatencyWarnMs+1))
      g_latencyColor=C'255,70,70';
   else if(judge>=MathMax(1,LatencyWarnMs))
      g_latencyColor=C'255,190,70';
   else if(g_latencyFillCount>0)
      g_latencyColor=C'90,225,130';
   else
      g_latencyColor=C'110,190,255';
}

void FastLatencyUpdate()
{
   UpdateLatencyText();
   if(ObjectFind(0,PX+"I5")>=0)
   {
      ObjectSetString(0,PX+"I5",OBJPROP_TEXT,g_latencyText);
      ObjectSetInteger(0,PX+"I5",OBJPROP_COLOR,g_latencyColor);
   }
   ChartRedraw();
}

void BeginLatencyBatch(ENUM_ORDER_TYPE type,int expected,double anchorPrice)
{
   if(!EnableTradeLatencyMonitor)return;

   g_latencyActive=true;
   g_latencySide=type;
   g_latencyExpected=MathMax(0,MathMin(10,expected));
   g_latencyAckCount=0;
   g_latencyFillCount=0;
   g_latencyRejectCount=0;
   g_latencyBatchStartMs=GetTickCount64();
   g_latencyAnchorPrice=anchorPrice;
   g_latencyLastAckMs=0.0;
   g_latencyMaxAckMs=0.0;
   g_latencyLastFillMs=0.0;
   g_latencyMaxFillMs=0.0;
   g_latencySumFillMs=0.0;
   g_latencyWorstSlipPts=0.0;
   g_latencySumSlipPts=0.0;

   for(int i=0;i<10;i++)
   {
      g_latencySubmitMs[i]=0;
      g_latencyAckDone[i]=false;
      g_latencyFillDone[i]=false;
   }

   UpdateLatencyText();
}

void FinalizeLatencyExpected(int submitted)
{
   if(!EnableTradeLatencyMonitor)return;

   g_latencyExpected=MathMax(0,MathMin(10,submitted));
   if(g_latencyExpected<=0)
   {
      g_latencyActive=false;
      g_latencyText="成交延迟：本轮没有成功提交";
      g_latencyColor=C'255,150,70';
   }
   FastLatencyUpdate();
}

void RegisterLatencySubmit(int layer)
{
   if(!EnableTradeLatencyMonitor || !g_latencyActive)return;
   if(layer<1 || layer>10)return;
   g_latencySubmitMs[layer-1]=GetTickCount64();
}

void RegisterLatencyAck(const string comment,uint retcode)
{
   if(!EnableTradeLatencyMonitor || !g_latencyActive)return;
   if(!IsSniperMarketComment(comment))return;

   int layer=SniperLayerFromComment(comment);
   int idx=(layer>0?layer-1:FirstFreeLatencySlot(false));
   if(idx<0 || idx>=g_latencyExpected)return;
   if(g_latencyAckDone[idx])return;

   g_latencyAckDone[idx]=true;
   g_latencyAckCount++;

   ulong base=(g_latencySubmitMs[idx]>0?g_latencySubmitMs[idx]:g_latencyBatchStartMs);
   double ms=(double)(GetTickCount64()-base);
   g_latencyLastAckMs=ms;
   if(ms>g_latencyMaxAckMs)g_latencyMaxAckMs=ms;

   bool accepted=(retcode==TRADE_RETCODE_DONE ||
                  retcode==TRADE_RETCODE_DONE_PARTIAL ||
                  retcode==TRADE_RETCODE_PLACED);

   if(!accepted)
   {
      g_latencyRejectCount++;
      Print("幽灵狙击延迟监控：服务器拒绝/异常 层=",idx+1,
            " retcode=",retcode,
            " ack=",DoubleToString(ms,0),"ms");
   }
   else
   {
      Print("幽灵狙击延迟监控：服务器应答 层=",idx+1,
            " ack=",DoubleToString(ms,0),"ms retcode=",retcode);
   }

   if(g_latencyFillCount+g_latencyRejectCount>=g_latencyExpected)
      g_latencyActive=false;

   FastLatencyUpdate();
}

void RegisterLatencyFill(ulong dealTicket)
{
   if(!EnableTradeLatencyMonitor || !g_latencyActive || dealTicket==0)return;
   if(!HistoryDealSelect(dealTicket))return;

   string symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
   if(symbol!=_Symbol)return;

   long entry=(long)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT)return;

   long magic=(long)HistoryDealGetInteger(dealTicket,DEAL_MAGIC);
   if(magic!=MagicNumber && magic!=WelfareMagic)return;

   string comment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
   if(!IsSniperMarketComment(comment))return;

   long dealType=(long)HistoryDealGetInteger(dealTicket,DEAL_TYPE);
   if(g_latencySide==ORDER_TYPE_BUY && dealType!=DEAL_TYPE_BUY)return;
   if(g_latencySide==ORDER_TYPE_SELL && dealType!=DEAL_TYPE_SELL)return;

   int layer=SniperLayerFromComment(comment);
   int idx=(layer>0?layer-1:FirstFreeLatencySlot(true));
   if(idx<0 || idx>=g_latencyExpected)return;
   if(g_latencyFillDone[idx])return;

   g_latencyFillDone[idx]=true;
   g_latencyFillCount++;

   ulong base=(g_latencySubmitMs[idx]>0?g_latencySubmitMs[idx]:g_latencyBatchStartMs);
   double ms=(double)(GetTickCount64()-base);
   g_latencyLastFillMs=ms;
   if(ms>g_latencyMaxFillMs)g_latencyMaxFillMs=ms;
   g_latencySumFillMs+=ms;

   double dealPrice=HistoryDealGetDouble(dealTicket,DEAL_PRICE);
   double slipPts=0.0;
   if(_Point>0)
   {
      // 正数=不利滑点，负数=有利滑点。
      slipPts=(g_latencySide==ORDER_TYPE_BUY
               ? dealPrice-g_latencyAnchorPrice
               : g_latencyAnchorPrice-dealPrice)/_Point;
   }

   g_latencySumSlipPts+=slipPts;
   if(slipPts>g_latencyWorstSlipPts)g_latencyWorstSlipPts=slipPts;

   Print("幽灵狙击延迟监控：实际成交 层=",idx+1,
         " deal=",dealTicket,
         " 延迟=",DoubleToString(ms,0),"ms",
         " 成交价=",DoubleToString(dealPrice,_Digits),
         " 锚点=",DoubleToString(g_latencyAnchorPrice,_Digits),
         " 滑点=",DoubleToString(slipPts,1),"pt");

   if(g_latencyFillCount+g_latencyRejectCount>=g_latencyExpected)
   {
      g_latencyActive=false;
      double avgFill=(g_latencyFillCount>0?g_latencySumFillMs/g_latencyFillCount:0.0);

      g_status=(g_latencySide==ORDER_TYPE_BUY?"狙击多":"狙击空")+
               "服务器确认完成｜成交 "+IntegerToString(g_latencyFillCount)+
               "/"+IntegerToString(g_latencyExpected)+
               (g_latencyRejectCount>0?" 拒绝"+IntegerToString(g_latencyRejectCount):"")+
               "｜平均 "+DoubleToString(avgFill,0)+"ms"+
               " 最大 "+DoubleToString(g_latencyMaxFillMs,0)+"ms";
      FastStatusUpdate();
   }

   FastLatencyUpdate();
}

void FastStatusUpdate()
{
   if(ObjectFind(0,PX+"I3")>=0)
      ObjectSetString(0,PX+"I3",OBJPROP_TEXT,"状态："+g_status);
   ChartRedraw();
}

bool Market(ENUM_ORDER_TYPE type)
{
   ulong ms=GetTickCount64();

   if(g_tradeBusy)
   {
      g_status="交易请求处理中，请勿重复点击";
      FastStatusUpdate();
      return false;
   }

   if(ms<g_tradeCooldownUntilMs)
   {
      g_status="刚提交一轮狙击单，已忽略重复按键/点击";
      FastStatusUpdate();
      return false;
   }

   if(!TradeOK() || !DirectionAllowed(type))
   {
      FastStatusUpdate();
      return false;
   }

   double lot=NLot(g_lot);
   if(lot<=0.0)
   {
      g_status="狙击下单失败：手数无效";
      FastStatusUpdate();
      return false;
   }

   // “单数”表示本次总下单数；福利单如启用，占其中1笔，不额外增加。
   int requested=MathMax(1,MathMin(10,g_orderCount));
   int roomByCount=MathMax(0,MaxTotalOrders-TotalManaged());
   int target=MathMin(requested,roomByCount);

   if(target<=0)
   {
      g_status="已达到总单数上限，狙击单未执行";
      FastStatusUpdate();
      return false;
   }

   // 异步模式下，前一笔提交后仓位可能尚未来得及出现在Positions里。
   // 因此必须在发送前一次性预留整批单边仓位，不能在循环内逐笔扫描。
   if(MaxSideLots>0)
   {
      ENUM_POSITION_TYPE side=(type==ORDER_TYPE_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL);
      double used=SideLots(side)+SidePendingLots(type);
      double remain=MathMax(0.0,MaxSideLots-used);
      int byLots=(int)MathFloor(remain/lot+1e-8);
      target=MathMin(target,byLots);

      if(target<=0)
      {
         g_status=(type==ORDER_TYPE_BUY?"多":"空")+"方向潜在总手数达到上限";
         FastStatusUpdate();
         return false;
      }
   }

   MqlTick latencyAnchorTick;
   if(!SymbolInfoTick(_Symbol,latencyAnchorTick))
   {
      g_status="狙击下单失败：无法读取锚点报价";
      FastStatusUpdate();
      return false;
   }
   double latencyAnchor=(type==ORDER_TYPE_BUY?latencyAnchorTick.ask:latencyAnchorTick.bid);
   BeginLatencyBatch(type,target,latencyAnchor);

   g_tradeBusy=true;

   int welfareLayer=ResolveWelfareLayerForTotal(target);
   trade.SetDeviationInPoints(SlippagePoints);

   // 狙击模式默认异步：每笔只把请求快速送入MT5交易队列，
   // 不等待上一笔服务器成交回报，因此能尽量锁定同一时段的价格。
   trade.SetAsyncMode(InstantBatchMarket);

   int submitted=0;
   int welfareSubmittedLayer=0;
   string lastFail="";

   for(int i=0;i<target;i++)
   {
      int layer=i+1;

      MqlTick t;
      if(!SymbolInfoTick(_Symbol,t))
      {
         lastFail="无法读取报价";
         break;
      }

      double entry=(type==ORDER_TYPE_BUY?t.ask:t.bid);
      double sl=0.0,tp=0.0;
      bool isWelfare=(welfareLayer>0 && layer==welfareLayer);

      if(UseFixedSL)
         sl=NormalizeDouble(type==ORDER_TYPE_BUY ? entry-g_slPts*_Point
                                                : entry+g_slPts*_Point,_Digits);

      if(isWelfare)
         tp=NormalizeDouble(type==ORDER_TYPE_BUY ? entry+g_welfareTPPts*_Point
                                                : entry-g_welfareTPPts*_Point,_Digits);
      else
         tp=SteppedTPPrice(type,entry,i);

      trade.SetExpertMagicNumber(isWelfare?WelfareMagic:MagicNumber);
      RegisterLatencySubmit(layer);

      bool ok=(type==ORDER_TYPE_BUY
               ? trade.Buy(lot,_Symbol,0,sl,tp,
                           isWelfare?"福利多单 #"+IntegerToString(layer):
                                     "幽灵狙击多单 #"+IntegerToString(layer))
               : trade.Sell(lot,_Symbol,0,sl,tp,
                            isWelfare?"福利空单 #"+IntegerToString(layer):
                                      "幽灵狙击空单 #"+IntegerToString(layer)));

      // 异步模式下 ok=true 表示请求已成功交给MT5发送队列，
      // 实际成交/拒绝由交易服务器随后回报。
      if(!ok)
      {
         lastFail="第"+IntegerToString(layer)+"笔本地提交失败";
         break;
      }

      submitted++;
      if(isWelfare)welfareSubmittedLayer=layer;
   }

   // 其它功能仍保持同步，避免平仓/锁仓等操作也变成异步。
   trade.SetAsyncMode(false);
   trade.SetExpertMagicNumber(MagicNumber);

   FinalizeLatencyExpected(submitted);

   g_tradeBusy=false;
   g_tradeCooldownUntilMs=GetTickCount64()+(ulong)MathMax(300,TradeCooldownMs);

   if(submitted>0)
   {
      string welfareText=(welfareSubmittedLayer>0
                          ?"；第"+IntegerToString(welfareSubmittedLayer)+"笔为福利单":"");

      g_status=(type==ORDER_TYPE_BUY?"狙击多 ":"狙击空 ")+
               IntegerToString(submitted)+"笔请求已"+
               (InstantBatchMarket?"极速提交，等待服务器成交确认":"同步提交")+
               "（福利单包含在总单数内）"+
               welfareText+
               (lastFail!=""?"；"+lastFail:"");
   }
   else
   {
      g_status="狙击批量下单未提交"+(lastFail!=""?"："+lastFail:"");
   }

   FastStatusUpdate();
   return submitted>0;
}

bool IsOwnLadderPendingSelected(){if(OrderGetString(ORDER_SYMBOL)!=_Symbol)return false;long m=(long)OrderGetInteger(ORDER_MAGIC);return m==MagicNumber||m==WelfareMagic;}
int DeleteExistingPendingForNewLadder(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--){ulong k=OrderGetTicket(i);if(!k||!OrderSelect(k)||!IsOwnLadderPendingSelected())continue;if(IsPendingType((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE))&&trade.OrderDelete(k))n++;}return n;}

// v2.71：发送新阶梯前先快照旧的本EA阶梯挂单。
// 异步撤单时，Positions/Orders列表不会立刻变化，所以风控必须按“逻辑撤除后”的数量和手数预计算。
int SnapshotOwnLadderPending(ulong &tickets[],double &buyLots,double &sellLots)
{
   ArrayResize(tickets,0);
   buyLots=0.0;
   sellLots=0.0;
   int n=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);
      if(!tk || !OrderSelect(tk) || !IsOwnLadderPendingSelected())continue;

      ENUM_ORDER_TYPE ty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsPendingType(ty))continue;

      ArrayResize(tickets,n+1);
      tickets[n]=tk;
      n++;

      double v=OrderGetDouble(ORDER_VOLUME_CURRENT);
      bool isBuy=(ty==ORDER_TYPE_BUY_LIMIT || ty==ORDER_TYPE_BUY_STOP || ty==ORDER_TYPE_BUY_STOP_LIMIT);
      bool isSell=(ty==ORDER_TYPE_SELL_LIMIT || ty==ORDER_TYPE_SELL_STOP || ty==ORDER_TYPE_SELL_STOP_LIMIT);
      if(isBuy)buyLots+=v;
      else if(isSell)sellLots+=v;
   }
   return n;
}

int FitLadderTargetBySideCapacity(ENUM_ORDER_TYPE direction,int target,double oldBuyPendingLots,double oldSellPendingLots)
{
   if(target<=0)return 0;
   if(MaxSideLots<=0)return target;

   ENUM_POSITION_TYPE side=(direction==ORDER_TYPE_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL);
   double used=SideLots(side)+SidePendingLots(direction);

   // ReplacePending开启时，旧阶梯挂单将在本批请求最前面撤掉，因此从逻辑占用里扣除。
   if(ReplacePendingOnNewLadder)
   {
      if(direction==ORDER_TYPE_BUY)used-=oldBuyPendingLots;
      else used-=oldSellPendingLots;
   }

   used=MathMax(0.0,used);
   double remain=MathMax(0.0,MaxSideLots-used);

   double planned=0.0;
   int allowed=0;
   for(int i=0;i<target;i++)
   {
      double lot=NLot(g_lot*MathPow(LadderLotMultiplier,i));
      if(lot<=0.0)break;
      if(planned+lot>remain+1e-8)break;
      planned+=lot;
      allowed++;
   }
   return allowed;
}

void Ladder(ENUM_ORDER_TYPE direction)
{
   ulong ms=GetTickCount64();

   if(g_tradeBusy)
   {
      g_status="交易请求处理中，请勿重复点击";
      FastStatusUpdate();
      return;
   }

   if(ms<g_tradeCooldownUntilMs)
   {
      g_status="刚提交一轮交易请求，已忽略重复按键/点击";
      FastStatusUpdate();
      return;
   }

   if(!TradeOK() || !DirectionAllowed(direction))
   {
      FastStatusUpdate();
      return;
   }

   // 点击瞬间立刻锁定阶梯锚点，后续所有挂单都按这个快照计算。
   // 即使撤旧挂需要一点时间，也不会因为行情继续走而改变本次阶梯基准。
   MqlTick anchor;
   if(!SymbolInfoTick(_Symbol,anchor))
   {
      g_status="排单失败：无法读取报价";
      FastStatusUpdate();
      return;
   }

   int requested=MathMax(1,MathMin(10,g_orderCount));
   int gap=ModeGap(),offset=ModeOffset();
   double firstLot=NLot(g_lot);

   if(requested<1 || firstLot<=0 || gap<0 || offset<0)
   {
      g_status="排单失败：参数无效";
      FastStatusUpdate();
      return;
   }

   // 先快照将被替换的旧阶梯挂单。
   ulong oldTickets[];
   double oldBuyPendingLots=0.0,oldSellPendingLots=0.0;
   int oldPendingCount=SnapshotOwnLadderPending(oldTickets,oldBuyPendingLots,oldSellPendingLots);

   // 总单数上限按“旧阶梯挂单撤除后”的逻辑状态计算，避免异步撤单尚未回报时误判没有空间。
   int logicalManaged=TotalManaged();
   if(ReplacePendingOnNewLadder)
      logicalManaged=MathMax(0,logicalManaged-oldPendingCount);

   int room=MathMax(0,MaxTotalOrders-logicalManaged);
   int target=MathMin(requested,room);

   if(target<=0)
   {
      g_status="排单失败：已达到总单数上限";
      FastStatusUpdate();
      return;
   }

   target=FitLadderTargetBySideCapacity(direction,target,oldBuyPendingLots,oldSellPendingLots);
   if(target<=0)
   {
      g_status="排单失败：单边潜在仓位上限不足";
      FastStatusUpdate();
      return;
   }

   int welfareLayer=ResolveWelfareLayerForTotal(target);

   g_tradeBusy=true;
   trade.SetDeviationInPoints(SlippagePoints);

   // 极速阶梯：撤旧请求、首单市价、剩余Limit挂单全部快速送入MT5交易队列，
   // 不等待上一笔服务器回报，因此不会再出现逐层“卡住”。
   trade.SetAsyncMode(InstantBatchLadder);

   int deleteSubmitted=0;
   string lastFail="";

   if(ReplacePendingOnNewLadder && oldPendingCount>0)
   {
      for(int i=0;i<oldPendingCount;i++)
      {
         if(trade.OrderDelete(oldTickets[i]))
            deleteSubmitted++;
         else
         {
            lastFail="旧挂撤单本地提交失败";
            break;
         }
      }

      // 如果连本地撤单请求都没有全部进入队列，为避免旧新阶梯叠加，直接停止新排单。
      if(deleteSubmitted<oldPendingCount)
      {
         trade.SetAsyncMode(false);
         trade.SetExpertMagicNumber(MagicNumber);
         g_tradeBusy=false;
         g_tradeCooldownUntilMs=GetTickCount64()+(ulong)MathMax(300,TradeCooldownMs);
         g_status="排单已停止："+lastFail+"；未提交新阶梯";
         FastStatusUpdate();
         return;
      }
   }

   int submitted=0;
   int welfareSubmittedLayer=0;

   // ---------- 第1层：立即市价 ----------
   double entry=(direction==ORDER_TYPE_BUY?anchor.ask:anchor.bid);
   double firstSL=0.0,firstTP=0.0;
   bool firstIsWelfare=(welfareLayer==1);

   if(UseFixedSL)
      firstSL=NormalizeDouble(direction==ORDER_TYPE_BUY
                              ? entry-g_slPts*_Point
                              : entry+g_slPts*_Point,_Digits);

   firstTP=firstIsWelfare
           ? NormalizeDouble(direction==ORDER_TYPE_BUY
                              ? entry+g_welfareTPPts*_Point
                              : entry-g_welfareTPPts*_Point,_Digits)
           : SteppedTPPrice(direction,entry,0);

   trade.SetExpertMagicNumber(firstIsWelfare?WelfareMagic:MagicNumber);

   bool firstOK=(direction==ORDER_TYPE_BUY
                 ? trade.Buy(firstLot,_Symbol,0,firstSL,firstTP,
                             firstIsWelfare?"福利多单 第1层":"排单多单 #1")
                 : trade.Sell(firstLot,_Symbol,0,firstSL,firstTP,
                              firstIsWelfare?"福利空单 第1层":"排单空单 #1"));

   if(!firstOK)
   {
      lastFail="首单本地提交失败";
   }
   else
   {
      submitted=1;
      if(firstIsWelfare)welfareSubmittedLayer=1;
   }

   // ---------- 第2层开始：Limit阶梯 ----------
   if(firstOK)
   {
      for(int i=1;i<target;i++)
      {
         double lot=NLot(g_lot*MathPow(LadderLotMultiplier,i));
         if(lot<=0.0)
         {
            lastFail="第"+IntegerToString(i+1)+"层手数无效";
            break;
         }

         int layer=i+1;
         bool isWelfare=(welfareLayer>0 && layer==welfareLayer);
         double dist=(offset+(i-1)*gap)*_Point;
         double p=0.0,sl=0.0,tp=0.0;
         bool ok=false;

         trade.SetExpertMagicNumber(isWelfare?WelfareMagic:MagicNumber);

         if(direction==ORDER_TYPE_BUY)
         {
            p=NormalizeDouble(anchor.bid-dist,_Digits);
            if(UseFixedSL)sl=NormalizeDouble(p-g_slPts*_Point,_Digits);

            tp=isWelfare
               ? NormalizeDouble(p+g_welfareTPPts*_Point,_Digits)
               : SteppedTPPrice(ORDER_TYPE_BUY,p,i);

            ok=trade.BuyLimit(lot,p,_Symbol,sl,tp,ORDER_TIME_GTC,0,
                              isWelfare
                              ? "福利多单 第"+IntegerToString(layer)+"层"
                              : "排单多单 #"+IntegerToString(layer));
         }
         else
         {
            p=NormalizeDouble(anchor.ask+dist,_Digits);
            if(UseFixedSL)sl=NormalizeDouble(p+g_slPts*_Point,_Digits);

            tp=isWelfare
               ? NormalizeDouble(p-g_welfareTPPts*_Point,_Digits)
               : SteppedTPPrice(ORDER_TYPE_SELL,p,i);

            ok=trade.SellLimit(lot,p,_Symbol,sl,tp,ORDER_TIME_GTC,0,
                               isWelfare
                               ? "福利空单 第"+IntegerToString(layer)+"层"
                               : "排单空单 #"+IntegerToString(layer));
         }

         if(!ok)
         {
            lastFail="第"+IntegerToString(layer)+"层本地提交失败";
            break;
         }

         submitted++;
         if(isWelfare)welfareSubmittedLayer=layer;
      }
   }

   // 只让“狙击市价/阶梯排单”使用极速异步。
   // 平仓、锁仓、推保护等风险管理功能继续保持同步。
   trade.SetAsyncMode(false);
   trade.SetExpertMagicNumber(MagicNumber);

   g_tradeBusy=false;
   g_tradeCooldownUntilMs=GetTickCount64()+(ulong)MathMax(300,TradeCooldownMs);

   string dirText=(direction==ORDER_TYPE_BUY?"排单多：":"排单空：");

   if(submitted>0)
   {
      g_status=dirText+
               (ReplacePendingOnNewLadder
                 ? "旧挂撤单请求"+IntegerToString(deleteSubmitted)+"笔；"
                 : "")+
               IntegerToString(submitted)+"笔已"+
               (InstantBatchLadder?"极速提交":"同步提交")+
               "（福利单包含在总单数内）"+
               (welfareSubmittedLayer>0
                 ? "；第"+IntegerToString(welfareSubmittedLayer)+"层为福利单"
                 : "")+
               (lastFail!=""?"；"+lastFail:"");
   }
   else
   {
      g_status=dirText+"未提交新阶梯"+(lastFail!=""?"；"+lastFail:"");
   }

   FastStatusUpdate();
}


bool IsLockPosition()
{
   return ((long)PositionGetInteger(POSITION_MAGIC)==LockMagic);
}
double NetLotsNoLock()
{
   double buy=0,sell=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      long mg=(long)PositionGetInteger(POSITION_MAGIC);
      if(mg==LockMagic)continue;
      if(ManageScope==SCOPE_MAGIC_ONLY && mg!=MagicNumber && mg!=WelfareMagic && !(g_manualTakeover&&mg==0))continue;
      if(ManageScope==SCOPE_MANUAL_ONLY && mg!=0)continue;
      ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double v=PositionGetDouble(POSITION_VOLUME);
      if(ty==POSITION_TYPE_BUY)buy+=v; else if(ty==POSITION_TYPE_SELL)sell+=v;
   }
   return buy-sell;
}

//---------------- close / management ----------------
int CloseSide(ENUM_POSITION_TYPE ty)
{
   int n=0;trade.SetDeviationInPoints(SlippagePoints);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      if(trade.PositionClose(tk,SlippagePoints))n++;
   }
   g_status=(ty==POSITION_TYPE_BUY?"平多单 ":"平空单 ")+IntegerToString(n)+"（锁仓单保留）";
   return n;
}
int CloseByProfit(bool winners)
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if((winners&&p>0)||(!winners&&p<0))if(trade.PositionClose(tk,SlippagePoints))n++;
   }
   g_status=(winners?"平浮盈 ":"平浮亏 ")+IntegerToString(n)+"（锁仓单保留）";
   return n;
}
int CloseAll()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos())continue;
      if(trade.PositionClose(tk,SlippagePoints))n++;
   }
   g_pause=true;g_status="紧急全平 "+IntegerToString(n)+"，快捷交易已暂停";return n;
}
int DeletePending()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);if(!tk||!OrderSelect(tk)||!MatchOrder())continue;
      ENUM_ORDER_TYPE ty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ty==ORDER_TYPE_BUY_LIMIT||ty==ORDER_TYPE_SELL_LIMIT||ty==ORDER_TYPE_BUY_STOP||ty==ORDER_TYPE_SELL_STOP||ty==ORDER_TYPE_BUY_STOP_LIMIT||ty==ORDER_TYPE_SELL_STOP_LIMIT)
         if(trade.OrderDelete(tk))n++;
   }
   g_status="删除挂单 "+IntegerToString(n);return n;
}

double MoneyPerPointPerLot()
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0 || tickValue<=0 || _Point<=0)return 0.0;
   return tickValue*(_Point/tickSize);
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || _Point<=0)return 0.0;
   return MathMax(0.0,(tick.ask-tick.bid)/_Point);
}

double CurrentSpreadMoney(double volume)
{
   if(volume<=0)return 0.0;
   return CurrentSpreadPoints()*MoneyPerPointPerLot()*volume;
}

void ClearCostCache()
{
   ArrayResize(g_costCachePosId,0);
   ArrayResize(g_costCacheEntryCostPerLot,0);
   ArrayResize(g_costCacheStamp,0);
}

int FindCostCacheIndex(ulong posId)
{
   for(int i=0;i<ArraySize(g_costCachePosId);i++)
      if(g_costCachePosId[i]==posId)return i;
   return -1;
}

void StoreCostCache(ulong posId,double entryCostPerLot)
{
   int idx=FindCostCacheIndex(posId);
   if(idx<0)
   {
      idx=ArraySize(g_costCachePosId);
      ArrayResize(g_costCachePosId,idx+1);
      ArrayResize(g_costCacheEntryCostPerLot,idx+1);
      ArrayResize(g_costCacheStamp,idx+1);
      g_costCachePosId[idx]=posId;
   }
   g_costCacheEntryCostPerLot[idx]=MathMax(0.0,entryCostPerLot);
   g_costCacheStamp[idx]=TimeCurrent();
}

// 自动读取该持仓“已发生的开仓侧”Commission + Fee，并折算成每手成本。
// 正常佣金/费用在MT5历史成交中通常为负值，因此这里只把负值转成正成本。
double ActualEntryCostPerLotForSelectedPosition()
{
   if(!AutoReadEntryCommission)return 0.0;

   ulong posId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(posId==0)return 0.0;

   int ci=FindCostCacheIndex(posId);
   if(ci>=0)
   {
      int ttl=(g_costCacheEntryCostPerLot[ci]>0.0 ? 300 : 10);
      if(TimeCurrent()-g_costCacheStamp[ci]<ttl)
         return g_costCacheEntryCostPerLot[ci];
   }

   if(!HistorySelectByPosition(posId))
   {
      StoreCostCache(posId,0.0);
      return 0.0;
   }

   double entryVol=0.0;
   double entryCost=0.0;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)continue;

      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(en!=DEAL_ENTRY_IN && en!=DEAL_ENTRY_INOUT)continue;

      double dv=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(dv<=0)continue;

      double comm=HistoryDealGetDouble(deal,DEAL_COMMISSION);
      double fee=(IncludeDealFeeCost ? HistoryDealGetDouble(deal,DEAL_FEE) : 0.0);

      entryVol+=dv;
      if(comm<0)entryCost+=-comm;
      if(fee<0)entryCost+=-fee;
   }

   double perLot=(entryVol>0 ? entryCost/entryVol : 0.0);
   StoreCostCache(posId,perLot);
   return perLot;
}


// v2.76：从本品种最近历史成交学习实际单边Commission + Fee。
// 只学习明确的 IN 与 OUT/OUT_BY；INOUT 跳过，避免净持仓账户拆分歧义。
void RefreshCommissionLearning(bool force=false)
{
   if(!EnableCommissionLearning)
   {
      g_learnedEntryCostPerLot=0.0;
      g_learnedExitCostPerLot=0.0;
      g_learnedEntryDeals=0;
      g_learnedExitDeals=0;
      return;
   }

   datetime now=TimeCurrent();
   if(!force && g_commissionLearnStamp>0 && now-g_commissionLearnStamp<300)
      return;

   g_commissionLearnStamp=now;

   datetime from=now-(datetime)MathMax(1,CommissionLearningDays)*86400;
   if(!HistorySelect(from,now))
      return;

   double inCost=0.0,inVol=0.0,outCost=0.0,outVol=0.0;
   int inDeals=0,outDeals=0;

   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;

      long dt=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL)continue;

      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_INOUT)continue;

      double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(vol<=0)continue;

      double comm=HistoryDealGetDouble(deal,DEAL_COMMISSION);
      double fee=(IncludeDealFeeCost ? HistoryDealGetDouble(deal,DEAL_FEE) : 0.0);
      double cost=0.0;
      if(comm<0)cost+=-comm;
      if(fee<0)cost+=-fee;
      if(cost<=0)continue;

      if(en==DEAL_ENTRY_IN)
      {
         inCost+=cost;
         inVol+=vol;
         inDeals++;
      }
      else if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY)
      {
         outCost+=cost;
         outVol+=vol;
         outDeals++;
      }
   }

   int minDeals=MathMax(1,CommissionLearningMinDeals);
   g_learnedEntryDeals=inDeals;
   g_learnedExitDeals=outDeals;
   g_learnedEntryCostPerLot=(inDeals>=minDeals && inVol>0 ? inCost/inVol : 0.0);
   g_learnedExitCostPerLot=(outDeals>=minDeals && outVol>0 ? outCost/outVol : 0.0);
}

// 预计该持仓完整开平仓佣金：
// 1) 已读取到开仓侧真实佣金时，真实开仓成本 + 预计平仓成本；
// 2) 平仓侧默认用 CommissionPerLotRT/2；若RT设为0，则按真实开仓侧同额估算；
// 3) 读取不到历史费用时，回退到 CommissionPerLotRT * 当前手数。
double ProjectedCommissionMoneyForSelectedPosition()
{
   if(!EnableCostAwareProtect)return 0.0;

   double vol=PositionGetDouble(POSITION_VOLUME);
   if(vol<=0)return 0.0;

   RefreshCommissionLearning(false);

   double configuredRT=MathMax(0.0,CommissionPerLotRT);
   double entryPerLot=ActualEntryCostPerLotForSelectedPosition();

   // 平仓侧优先使用历史学习值；不足时回退到配置RT的一半，
   // 如果RT也没设置，则用已知开仓侧/学习开仓侧对称估算。
   double learnedEntry=g_learnedEntryCostPerLot;
   double learnedExit=g_learnedExitCostPerLot;

   if(entryPerLot>0.0)
   {
      double closePerLot=0.0;
      if(learnedExit>0.0) closePerLot=learnedExit;
      else if(configuredRT>0.0) closePerLot=configuredRT*0.5;
      else if(learnedEntry>0.0) closePerLot=learnedEntry;
      else closePerLot=entryPerLot;

      return (entryPerLot+closePerLot)*vol;
   }

   if(learnedEntry>0.0 && learnedExit>0.0)
      return (learnedEntry+learnedExit)*vol;

   if(configuredRT>0.0)
      return configuredRT*vol;

   if(learnedEntry>0.0)
      return learnedEntry*2.0*vol;

   if(learnedExit>0.0)
      return learnedExit*2.0*vol;

   return 0.0;
}

double NegativeSwapMoneyForSelectedPosition()
{
   if(!IncludeSwapCost)return 0.0;
   double sw=PositionGetDouble(POSITION_SWAP);
   return (sw<0 ? -sw : 0.0);
}


// v2.76：动态执行安全缓冲。
// 注意：实时Spread已经由 BUY=BID / SELL=ASK 自然反映在可退出浮盈里，
// 这里只取少量Spread比例作为“未来止损执行安全垫”，不是再次把整段点差算成成本。
double EffectiveProtectionBufferPts()
{
   double base=MathMax(0.0,(double)ExtraCostBufferPts);
   if(!EnableDynamicExecutionBuffer)
      return base;

   double avgAdverse=0.0;
   if(g_latencyFillCount>0)
      avgAdverse=MathMax(0.0,g_latencySumSlipPts/g_latencyFillCount);

   double worstAdverse=MathMax(0.0,g_latencyWorstSlipPts);
   double slipBuffer=MathMax(avgAdverse*MathMax(0.0,SlipBufferMultiplier),
                             worstAdverse);

   double spreadBuffer=MathMax(0.0,CurrentSpreadPoints())*
                       MathMax(0.0,SpreadSafetyFraction);

   double result=MathMax(base,MathMax(slipBuffer,spreadBuffer));
   double cap=MathMax(base,(double)MathMax(0,MaxDynamicBufferPts));
   return MathMin(result,cap);
}

// 保护成本只加入：完整往返佣金 + 负Swap + 额外缓冲。
// 点差不再额外加一次，因为多单按BID、空单按ASK计算可退出浮盈，实时Spread已经天然包含在gross里。
double PositionCostPoints()
{
   if(!EnableCostAwareProtect)return 0.0;

   double vol=PositionGetDouble(POSITION_VOLUME);
   if(vol<=0)return 0.0;

   double costMoney=ProjectedCommissionMoneyForSelectedPosition();
   costMoney+=NegativeSwapMoneyForSelectedPosition();

   double mpp=MoneyPerPointPerLot()*vol;
   double pts=(mpp>0 ? costMoney/mpp : 0.0);
   return MathMax(0.0,pts)+EffectiveProtectionBufferPts();
}

double NetProfitPoints(ENUM_POSITION_TYPE ty,double op,double cur)
{
   // BUY用BID、SELL用ASK调用本函数时，gross已经体现当前实时点差。
   double gross=(ty==POSITION_TYPE_BUY ? cur-op : op-cur)/_Point;
   return gross-PositionCostPoints();
}

void ManagedCostSummary(double &commission,double &negSwap,double &spreadPts,double &spreadMoney,double &lots)
{
   commission=negSwap=spreadMoney=lots=0.0;
   spreadPts=CurrentSpreadPoints();

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;

      double v=PositionGetDouble(POSITION_VOLUME);
      if(v<=0)continue;
      lots+=v;

      if(EnableCostAwareProtect)
      {
         commission+=ProjectedCommissionMoneyForSelectedPosition();
         negSwap+=NegativeSwapMoneyForSelectedPosition();
      }
   }

   spreadMoney=CurrentSpreadMoney(lots);
}

bool GroupProtectionData(ENUM_POSITION_TYPE ty,int &count,double &lots,double &avg,
                          double &costPts,double &current,double &netPts)
{
   count=0;lots=avg=costPts=current=netPts=0.0;
   double weighted=0.0,totalCostMoney=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk||!PositionSelectByTicket(tk)||!IsNormalManagedPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      if(v<=0)continue;
      count++;lots+=v;weighted+=PositionGetDouble(POSITION_PRICE_OPEN)*v;
      if(EnableCostAwareProtect)
      {
         totalCostMoney+=ProjectedCommissionMoneyForSelectedPosition();
         totalCostMoney+=NegativeSwapMoneyForSelectedPosition();
      }
   }
   if(count<=0||lots<=0)return false;
   avg=weighted/lots;
   double mpp=MoneyPerPointPerLot()*lots;
   costPts=(EnableCostAwareProtect && mpp>0 ? totalCostMoney/mpp : 0.0);
   costPts=MathMax(0.0,costPts)+EffectiveProtectionBufferPts();
   current=(ty==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK));
   double gross=(ty==POSITION_TYPE_BUY?current-avg:avg-current)/_Point;
   netPts=gross-costPts;
   return true;
}


bool IsRetryableModifyRetcode(uint rc)
{
   return (rc==TRADE_RETCODE_REQUOTE ||
           rc==TRADE_RETCODE_PRICE_CHANGED ||
           rc==TRADE_RETCODE_PRICE_OFF ||
           rc==TRADE_RETCODE_INVALID_STOPS ||
           rc==TRADE_RETCODE_FROZEN ||
           rc==TRADE_RETCODE_LOCKED ||
           rc==TRADE_RETCODE_TOO_MANY_REQUESTS);
}

void QueueModifyRetry(ulong ticket,double sl,double tp,string tag)
{
   if(!EnableModifyRetry || ticket==0)return;

   int slot=-1;
   for(int i=0;i<ArraySize(g_modifyRetry);i++)
   {
      if(g_modifyRetry[i].active && g_modifyRetry[i].ticket==ticket)
      {
         slot=i;
         break;
      }
      if(slot<0 && !g_modifyRetry[i].active)
         slot=i;
   }

   if(slot<0)return;

   g_modifyRetry[slot].active=true;
   g_modifyRetry[slot].ticket=ticket;
   g_modifyRetry[slot].sl=sl;
   g_modifyRetry[slot].tp=tp;
   g_modifyRetry[slot].attempts=0;
   g_modifyRetry[slot].dueMs=GetTickCount64()+(ulong)MathMax(50,ModifyRetryDelayMs);
   g_modifyRetry[slot].tag=tag;
}

bool ResilientPositionModify(ulong ticket,double sl,double tp,string tag)
{
   if(trade.PositionModify(ticket,sl,tp))
      return true;

   uint rc=trade.ResultRetcode();
   if(EnableModifyRetry && IsRetryableModifyRetcode(rc))
   {
      QueueModifyRetry(ticket,sl,tp,tag);
      Print("保护修改进入重试队列｜",tag,
            " ticket=",ticket,
            " retcode=",rc);
      return true; // 表示请求已被保护系统接管，不向上层重复报硬失败。
   }

   Print("保护修改失败｜",tag,
         " ticket=",ticket,
         " retcode=",rc,
         " ",trade.ResultRetcodeDescription());
   return false;
}

void ProcessModifyRetryQueue()
{
   if(!EnableModifyRetry)return;

   ulong now=GetTickCount64();
   int maxAttempts=MathMax(1,ModifyRetryMaxAttempts);

   for(int i=0;i<ArraySize(g_modifyRetry);i++)
   {
      if(!g_modifyRetry[i].active || now<g_modifyRetry[i].dueMs)continue;

      ulong tk=g_modifyRetry[i].ticket;
      if(!PositionSelectByTicket(tk) || PositionGetString(POSITION_SYMBOL)!=_Symbol)
      {
         g_modifyRetry[i].active=false;
         continue;
      }

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double oldSL=PositionGetDouble(POSITION_SL);
      double sl=g_modifyRetry[i].sl;
      double tp=g_modifyRetry[i].tp;

      // 保护型SL绝不允许重试后比当前SL更差。
      if(sl>0 && oldSL>0)
      {
         if(pt==POSITION_TYPE_BUY && sl<=oldSL+_Point)
         {
            g_modifyRetry[i].active=false;
            continue;
         }
         if(pt==POSITION_TYPE_SELL && sl>=oldSL-_Point)
         {
            g_modifyRetry[i].active=false;
            continue;
         }
      }

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick))
      {
         g_modifyRetry[i].dueMs=now+(ulong)MathMax(50,ModifyRetryDelayMs);
         continue;
      }

      long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      double gap=(MathMax((double)stops,(double)freeze)+
                  MathMax(1,BreakEvenSafetyPts))*_Point;

      if(sl>0)
      {
         if(pt==POSITION_TYPE_BUY) sl=MathMin(sl,tick.bid-gap);
         else                      sl=MathMax(sl,tick.ask+gap);
      }

      if(tp>0)
      {
         if(pt==POSITION_TYPE_BUY) tp=MathMax(tp,tick.ask+gap);
         else                      tp=MathMin(tp,tick.bid-gap);
      }

      sl=(sl>0?NormalizeDouble(sl,_Digits):0.0);
      tp=(tp>0?NormalizeDouble(tp,_Digits):0.0);

      if(trade.PositionModify(tk,sl,tp))
      {
         Print("保护修改重试成功｜",g_modifyRetry[i].tag,
               " ticket=",tk,
               " attempt=",g_modifyRetry[i].attempts+1);
         g_modifyRetry[i].active=false;
         continue;
      }

      g_modifyRetry[i].attempts++;
      uint rc=trade.ResultRetcode();

      if(g_modifyRetry[i].attempts>=maxAttempts || !IsRetryableModifyRetcode(rc))
      {
         Print("保护修改重试终止｜",g_modifyRetry[i].tag,
               " ticket=",tk,
               " retcode=",rc,
               " ",trade.ResultRetcodeDescription());
         g_modifyRetry[i].active=false;
      }
      else
      {
         g_modifyRetry[i].dueMs=now+(ulong)MathMax(50,ModifyRetryDelayMs);
      }
   }
}

int ProtectGroupAtAverage(ENUM_POSITION_TYPE ty,int &skipped)
{
   skipped=0;
   int count=0;double lots=0,avg=0,costPts=0,cur=0,netPts=0;
   if(!GroupProtectionData(ty,count,lots,avg,costPts,cur,netPts))return 0;
   if(netPts<BreakEvenTriggerPts){skipped=count;return 0;}

   long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minGap=(MathMax((double)stops,(double)freeze)+BreakEvenSafetyPts)*_Point;
   double groupSL=(ty==POSITION_TYPE_BUY ? avg+(costPts+BreakEvenPlusPts)*_Point
                                         : avg-(costPts+BreakEvenPlusPts)*_Point);
   groupSL=NormalizeDouble(groupSL,_Digits);

   if((ty==POSITION_TYPE_BUY && cur-groupSL<minGap) ||
      (ty==POSITION_TYPE_SELL && groupSL-cur<minGap))
   { skipped=count; return 0; }

   int ok=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk||!PositionSelectByTicket(tk)||!IsNormalManagedPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double oldSL=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(ty==POSITION_TYPE_BUY && oldSL>0 && oldSL>=groupSL-_Point){skipped++;continue;}
      if(ty==POSITION_TYPE_SELL && oldSL>0 && oldSL<=groupSL+_Point){skipped++;continue;}
      if(ResilientPositionModify(tk,groupSL,tp,"均价成本保护"))ok++;else skipped++;
   }
   return ok;
}

void BreakEvenAll()
{
   int skipB=0,skipS=0;
   int okB=ProtectGroupAtAverage(POSITION_TYPE_BUY,skipB);
   int okS=ProtectGroupAtAverage(POSITION_TYPE_SELL,skipS);
   g_status="均价成本保护：成功 "+IntegerToString(okB+okS)+" 单；跳过 "+
            IntegerToString(skipB+skipS)+" 单｜只改SL，不主动平仓";
}

void AutoProtect()
{
   // 普通单 + 接管手工单：组合均价成本保护；福利/锁仓完全排除。
   if(EnableBreakEven)
   {
      int sb=0,ss=0;
      ProtectGroupAtAverage(POSITION_TYPE_BUY,sb);
      ProtectGroupAtAverage(POSITION_TYPE_SELL,ss);
   }
   if(!EnableTrailing)return;

   for(int side=0;side<2;side++)
   {
      ENUM_POSITION_TYPE ty=(side==0?POSITION_TYPE_BUY:POSITION_TYPE_SELL);
      int count=0;double lots=0,avg=0,costPts=0,cur=0,netPts=0;
      if(!GroupProtectionData(ty,count,lots,avg,costPts,cur,netPts))continue;
      if(netPts<TrailTriggerPts)continue;

      double groupFloor=(ty==POSITION_TYPE_BUY ? avg+(costPts+BreakEvenPlusPts)*_Point
                                               : avg-(costPts+BreakEvenPlusPts)*_Point);
      long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      double minGap=(MathMax((double)stops,(double)freeze)+BreakEvenSafetyPts)*_Point;

      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(!tk||!PositionSelectByTicket(tk)||!IsNormalManagedPositionSelected())continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
         double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
         double tr=(ty==POSITION_TYPE_BUY ? cur-TrailDistancePts*_Point
                                          : cur+TrailDistancePts*_Point);
         if(ty==POSITION_TYPE_BUY)tr=MathMax(tr,groupFloor);else tr=MathMin(tr,groupFloor);
         tr=NormalizeDouble(tr,_Digits);
         bool safe=(ty==POSITION_TYPE_BUY ? cur-tr>=minGap : tr-cur>=minGap);
         bool stepOK=(ty==POSITION_TYPE_BUY ? (sl==0||tr>sl+TrailStepPts*_Point)
                                            : (sl==0||tr<sl-TrailStepPts*_Point));
         if(safe&&stepOK)ResilientPositionModify(tk,tr,tp,"普通追踪");
      }
   }
}

int CloseProfitByPercent(double pct,bool showStatus,bool includeWelfare)
{
   pct=MathMax(1.0,MathMin(100.0,pct));
   double realized=0.0, closedLots=0.0;
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
      if(!includeWelfare && IsWelfarePosition())continue;
      double pf=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(pf<=0)continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      double closev=vol*pct/100.0;
      if(step>0)closev=MathFloor(closev/step+1e-8)*step;
      closev=NormalizeDouble(closev,2);
      bool ok=false;
      if(pct>=99.999 || closev>=vol-step/2.0)
      { closev=vol; ok=trade.PositionClose(tk,SlippagePoints); }
      else if(closev>=minv)
         ok=trade.PositionClosePartial(tk,closev,SlippagePoints);
      if(ok)
      {
         realized+=pf*(closev/vol);closedLots+=closev;n++;
      }
   }
   if(showStatus)
      g_status="盈利减仓 "+DoubleToString(pct,0)+"%：处理 "+IntegerToString(n)+
               "单 / "+DoubleToString(closedLots,2)+"手，约兑现 "+DoubleToString(realized,2)+" USD";
   return n;
}
void CloseHalfWinners(){CloseProfitByPercent(50.0,true,true);}
string UnifiedLineName(bool buy,bool tp)
{
   if(buy)return tp?OBJ_UNI_BUY_TP:OBJ_UNI_BUY_SL;
   return tp?OBJ_UNI_SELL_TP:OBJ_UNI_SELL_SL;
}

bool IsUnifiedLineName(const string name)
{
   return name==OBJ_UNI_BUY_TP || name==OBJ_UNI_BUY_SL ||
          name==OBJ_UNI_SELL_TP || name==OBJ_UNI_SELL_SL;
}

void StopUnifiedMouseFollow()
{
   g_unifiedFollowActive=false;
   g_unifiedFollowName="";
}

void PrepareUnifiedLine(bool buy,bool tp)
{
   string name=UnifiedLineName(buy,tp);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      g_status="统一线建立失败：无法读取报价";
      FastStatusUpdate();
      return;
   }

   // 初始价只是备用位置；创建后马上跟随鼠标。
   double base=(buy?tick.bid:tick.ask);
   double offset=MathMax(100,g_tpPts)*_Point;
   double p=base;

   if(buy) p=tp ? base+offset : base-offset;
   else    p=tp ? base-offset : base+offset;

   ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_HLINE,0,0,NormalizeDouble(p,_Digits)))
   {
      g_status="统一线建立失败";
      FastStatusUpdate();
      return;
   }

   ObjectSetInteger(0,name,OBJPROP_COLOR,tp?clrLimeGreen:clrTomato);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,3);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);

   g_unifiedFollowActive=true;
   g_unifiedFollowName=name;

   string side=buy?"多":"空";
   string kind=tp?"止盈":"止损";
   g_status="统一"+side+kind+"线跟随鼠标｜移到目标价后在图表空白处单击固定";
   FastStatusUpdate();
}

bool ValidateUnifiedPrice(bool buy,bool tp,double price,string &why)
{
   why="";
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      why="无法读取报价";
      return false;
   }

   long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double gap=(double)MathMax(stops,freeze)*_Point;

   if(buy && tp && price<=tick.bid+gap)
   {
      why="多单TP必须高于当前Bid及最小止损距离";
      return false;
   }
   if(buy && !tp && price>=tick.bid-gap)
   {
      why="多单SL必须低于当前Bid及最小止损距离";
      return false;
   }
   if(!buy && tp && price>=tick.ask-gap)
   {
      why="空单TP必须低于当前Ask及最小止损距离";
      return false;
   }
   if(!buy && !tp && price<=tick.ask+gap)
   {
      why="空单SL必须高于当前Ask及最小止损距离";
      return false;
   }

   return true;
}

void ApplyUnifiedTPSL(bool buy)
{
   StopUnifiedMouseFollow();

   string tpName=UnifiedLineName(buy,true);
   string slName=UnifiedLineName(buy,false);

   bool hasTP=(ObjectFind(0,tpName)>=0);
   bool hasSL=(ObjectFind(0,slName)>=0);

   if(!hasTP && !hasSL)
   {
      g_status=buy?"统一多：请先建立止盈线或止损线":"统一空：请先建立止盈线或止损线";
      FastStatusUpdate();
      return;
   }

   double tp=(hasTP?NormalizeDouble(ObjectGetDouble(0,tpName,OBJPROP_PRICE),_Digits):0.0);
   double sl=(hasSL?NormalizeDouble(ObjectGetDouble(0,slName,OBJPROP_PRICE),_Digits):0.0);

   string why="";
   if(hasTP && !ValidateUnifiedPrice(buy,true,tp,why))
   {
      g_status="统一"+string(buy?"多":"空")+"失败："+why+"｜线已保留";
      FastStatusUpdate();
      return;
   }
   if(hasSL && !ValidateUnifiedPrice(buy,false,sl,why))
   {
      g_status="统一"+string(buy?"多":"空")+"失败："+why+"｜线已保留";
      FastStatusUpdate();
      return;
   }

   ENUM_POSITION_TYPE wanted=(buy?POSITION_TYPE_BUY:POSITION_TYPE_SELL);

   int target=0,ok=0,fail=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk || !PositionSelectByTicket(tk) || !IsUnifiedTPPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=wanted)continue;

      target++;

      double oldSL=PositionGetDouble(POSITION_SL);
      double oldTP=PositionGetDouble(POSITION_TP);
      double newSL=(hasSL?sl:oldSL);
      double newTP=(hasTP?tp:oldTP);

      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.PositionModify(tk,newSL,newTP))ok++;
      else fail++;
   }

   if(target<=0)
   {
      g_status="统一"+string(buy?"多":"空")+"：当前没有符合管理范围的持仓｜线保留";
      FastStatusUpdate();
      return;
   }

   if(fail==0 && ok==target)
   {
      if(hasTP)ObjectDelete(0,tpName);
      if(hasSL)ObjectDelete(0,slName);
      ChartRedraw();

      string scope=(UnifiedTPExcludeWelfare?"福利单默认排除":"福利单包含");
      g_status="统一"+string(buy?"多":"空")+"TP/SL完成："+IntegerToString(ok)+"笔｜"+scope+"｜辅助线已消失";
   }
   else
   {
      g_status="统一"+string(buy?"多":"空")+"部分完成：成功"+
               IntegerToString(ok)+"/"+IntegerToString(target)+
               "，失败"+IntegerToString(fail)+"｜辅助线保留";
   }

   FastStatusUpdate();
}

void SetAverageTP(ENUM_POSITION_TYPE ty)
{
   if(!EnableUnifiedTP){g_status="统一TP功能已关闭，请在参数窗口开启";return;}
   int n=0;double lots=0.0,weighted=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!IsUnifiedTPPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      double v=PositionGetDouble(POSITION_VOLUME);if(v<=0)continue;
      n++;lots+=v;weighted+=PositionGetDouble(POSITION_PRICE_OPEN)*v;
   }
   if(n<=0||lots<=0){g_status="统一TP：当前没有符合范围的持仓";return;}
   double avg=weighted/lots;
   double target=(ty==POSITION_TYPE_BUY?avg+AverageTPOffsetPts*_Point:avg-AverageTPOffsetPts*_Point);
   target=NormalizeDouble(target,_Digits);
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!IsUnifiedTPPositionSelected())continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=ty)continue;
      if(trade.PositionModify(tk,PositionGetDouble(POSITION_SL),target))c++;
   }
   string scope=(UnifiedTPExcludeWelfare?"普通单/接管单，福利除外":"普通+福利，锁仓除外");
   g_status=(ty==POSITION_TYPE_BUY?"多TP→均价+":"空TP→均价-")+IntegerToString(AverageTPOffsetPts)+
            "｜"+scope+"｜修改 "+IntegerToString(c)+" 单";
}
void SideProtection()
{
   int n;double l,p,a;
   StatsNoLock(POSITION_TYPE_BUY,n,l,p,a); if(BuyLossLimitUSD>0 && p<=-BuyLossLimitUSD)CloseSide(POSITION_TYPE_BUY);
   StatsNoLock(POSITION_TYPE_SELL,n,l,p,a);if(SellLossLimitUSD>0 && p<=-SellLossLimitUSD)CloseSide(POSITION_TYPE_SELL);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if((EquityFloor>0&&eq<=EquityFloor)||(EquityCeiling>0&&eq>=EquityCeiling)){CloseAll();DeletePending();}
}
void FloatMonitor()
{
   if(!g_floatMonitor)return;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal<=0 || g_floatTriggerPct<=0)return;
   // 自动浮盈减仓只看普通组合，不拿福利Runner和锁仓腿触发。
   double ratio=NormalFloatPL()/bal*100.0;
   if(ratio<g_floatTriggerPct*0.80)g_floatTriggered=false;
   if(!g_floatTriggered && ratio>=g_floatTriggerPct)
   {
      int reduced=CloseProfitByPercent(g_floatTriggerPct,false,false);
      if(reduced>0)
      {
         g_floatTriggered=true;
         g_status="普通组合浮盈/余额 "+DoubleToString(ratio,1)+"% ≥ "+DoubleToString(g_floatTriggerPct,1)+
                  "%｜已自动减仓 "+DoubleToString(g_floatTriggerPct,0)+"%（福利/锁仓不动）";
      }
      else
      {
         g_status="浮盈监控已触发，但当前手数不足以执行有效减仓；未锁定触发状态";
      }
   }
}
//---------------- 福利单独立跟踪止损 ----------------
bool IsWelfarePosition()
{
   return (PositionGetInteger(POSITION_MAGIC)==WelfareMagic);
}

// 福利单完全独立管理：
// 1) 完全不参加普通自动/手动均价推保本；
// 2) 先计算独立成本保本+最低净盈利保盈线，再达到启动距离后独立跟踪；
// 3) TP继续保留，先到TP则TP平仓；先回调触发跟踪SL则保护出场。
void WelfareTrailing()
{
   int startPts=MathMax(1,WelfareTrailStartPts);
   int distancePts=MathMax(1,WelfareTrailDistancePts);
   int stepPts=MathMax(1,WelfareTrailStepPts);
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
   long stopLevel=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double brokerGap=(double)MathMax(stopLevel,freezeLevel)*_Point;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(!tk || !PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || !IsWelfarePosition())continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double now=(pt==POSITION_TYPE_BUY?tick.bid:tick.ask);

      // 福利单真实成本保本 + 最低净盈利保底。
      double costPts=PositionCostPoints();
      double mpp=MoneyPerPointPerLot()*vol;
      double protectPts=(mpp>0?MathMax(0.0,WelfareProtectedProfitUSD)/mpp:0.0);
      double basePts=costPts+MathMax(0,BreakEvenPlusPts);
      double floor=(pt==POSITION_TYPE_BUY ? open+(basePts+protectPts)*_Point
                                          : open-(basePts+protectPts)*_Point);
      double trigger=(pt==POSITION_TYPE_BUY ? floor+startPts*_Point
                                            : floor-startPts*_Point);
      bool active=(pt==POSITION_TYPE_BUY ? now>=trigger : now<=trigger);
      if(!active)continue;

      double newSL=(pt==POSITION_TYPE_BUY ? now-distancePts*_Point
                                          : now+distancePts*_Point);
      if(pt==POSITION_TYPE_BUY)newSL=MathMax(newSL,floor);else newSL=MathMin(newSL,floor);

      if(pt==POSITION_TYPE_BUY)
      {
         double maxSL=tick.bid-brokerGap;newSL=MathMin(newSL,maxSL);newSL=NormalizeDouble(newSL,_Digits);
         if(newSL<floor-_Point)continue;
         if(oldSL>0 && newSL<=oldSL+stepPts*_Point)continue;
      }
      else
      {
         double minSL=tick.ask+brokerGap;newSL=MathMax(newSL,minSL);newSL=NormalizeDouble(newSL,_Digits);
         if(newSL>floor+_Point)continue;
         if(oldSL>0 && newSL>=oldSL-stepPts*_Point)continue;
      }
      trade.SetExpertMagicNumber(WelfareMagic);
      if(!ResilientPositionModify(tk,newSL,tp,"福利保盈/跟踪"))
         Print("福利单独立保盈/跟踪修改失败，订单=",tk," 错误=",trade.ResultRetcode());
   }
   trade.SetExpertMagicNumber(MagicNumber);
}

//---------------- 今日已实现盈亏 ----------------
// 按交易服务器“今天”统计当前品种已平仓交易。
// 包含本EA普通单、福利单、锁仓单；如已开启“接管手工单”，也包含当前品种手工单。
// 净值 = 平仓利润 + 手续费 + 隔夜费 + 费用。
double TodayRealizedPL()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   tm.hour=0;tm.min=0;tm.sec=0;
   datetime dayStart=StructToTime(tm);
   datetime now=TimeCurrent();

   if(!HistorySelect(dayStart,now))return 0.0;

   double total=0.0;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;

      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      // 只统计产生已实现结果的离场成交；INOUT也可能产生已实现盈亏。
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT)continue;

      long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
      bool managed=(magic==MagicNumber || magic==WelfareMagic || magic==LockMagic);
      if(!managed && !(g_manualTakeover && magic==0))continue;

      total+=HistoryDealGetDouble(deal,DEAL_PROFIT);
      total+=HistoryDealGetDouble(deal,DEAL_COMMISSION);
      total+=HistoryDealGetDouble(deal,DEAL_SWAP);
      total+=HistoryDealGetDouble(deal,DEAL_FEE);
   }
   return total;
}

int PendingStats(double &lots)
{
   int n=0;lots=0;
   for(int i=OrdersTotal()-1;i>=0;i--){ulong tk=OrderGetTicket(i);if(!tk||!OrderSelect(tk)||!MatchOrder())continue;n++;lots+=OrderGetDouble(ORDER_VOLUME_CURRENT);}
   return n;
}

void HedgeClose()
{
   double win=0,loss=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p>0)win+=p; else if(p<0)loss+=p;
   }
   if(win<=0 || loss>=0){g_status="对冲平仓：需要同时存在浮盈单和浮亏单";return;}

   // 文档：优先用“浮盈最小”的盈利单对消亏损。
   while(true)
   {
      ulong loseTk=0,winTk=0;
      double worstLoss=0,smallWin=DBL_MAX;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk)||!MatchPos()||IsLockPosition())continue;
         double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         if(p<0 && p<worstLoss){worstLoss=p;loseTk=tk;}
         if(p>0 && p<smallWin){smallWin=p;winTk=tk;}
      }
      if(!loseTk || !winTk)break;
      if(smallWin + worstLoss < 0)break; // 当前最小盈利不足以覆盖这笔亏损，停止
      if(!trade.PositionClose(winTk,SlippagePoints))break;
      if(!trade.PositionClose(loseTk,SlippagePoints))break;
   }
   g_status="对冲平仓执行完成";
}

bool LockPosition()
{
   ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_status="一键锁仓仅支持MT5对冲(Hedging)账户；当前账户不是对冲模式";
      return false;
   }
   double net=NetLotsNoLock();
   if(MathAbs(net)<1e-8){g_status="当前净头寸为0，无需锁仓";return false;}
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && (long)PositionGetInteger(POSITION_MAGIC)==LockMagic)
      {g_status="已存在锁仓单，请先解锁";return false;}
   }

   double remaining=MathAbs(net),locked=0.0;
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   trade.SetExpertMagicNumber(LockMagic);trade.SetDeviationInPoints(SlippagePoints);
   bool allOK=true;
   while(remaining>=minv-1e-12)
   {
      double chunk=NormalizeBrokerVolume(MathMin(remaining,maxv));
      if(chunk<minv-1e-12)break;
      bool ok=(net>0 ? trade.Sell(chunk,_Symbol,0,0,0,"锁仓单")
                     : trade.Buy(chunk,_Symbol,0,0,0,"锁仓单"));
      if(!ok){allOK=false;break;}
      locked+=chunk;remaining-=chunk;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   bool exact=(MathAbs(locked-MathAbs(net))<=MathMax(1e-8,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)/2.0));
   if(exact)g_status="一键锁仓成功：净头寸 "+DoubleToString(MathAbs(net),2)+" 手已完整对冲";
   else if(locked>0)g_status="⚠ 锁仓仅完成 "+DoubleToString(locked,2)+" / "+DoubleToString(MathAbs(net),2)+" 手，请立即检查";
   else g_status="锁仓失败，错误 "+IntegerToString((int)trade.ResultRetcode());
   return allOK&&exact;
}
void UnlockPosition()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);if(!tk||!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=LockMagic)continue;
      if(trade.PositionClose(tk,SlippagePoints))n++;
   }
   g_status="解锁：已平锁仓单 "+IntegerToString(n)+" 笔";
}

//---------------- panel ----------------
int S(int v){return (int)MathRound(v*PanelScalePct/100.0);}
void Rect(string n,int x,int y,int w,int h,color bg)
{
 n=PX+n;if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_XDISTANCE,S(x));ObjectSetInteger(0,n,OBJPROP_YDISTANCE,S(y));ObjectSetInteger(0,n,OBJPROP_XSIZE,S(w));ObjectSetInteger(0,n,OBJPROP_YSIZE,S(h));ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,C'80,80,80');
}
void Txt(string n,int x,int y,string v,int fs=9,color c=clrWhite)
{
 n=PX+n;if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_LABEL,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_XDISTANCE,S(x));ObjectSetInteger(0,n,OBJPROP_YDISTANCE,S(y));ObjectSetInteger(0,n,OBJPROP_FONTSIZE,S(fs));ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetString(0,n,OBJPROP_FONT,"Microsoft YaHei");ObjectSetString(0,n,OBJPROP_TEXT,v);
}
void Btn(string n,int x,int y,int w,int h,string v,color bg)
{
 n=PX+n;if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_XDISTANCE,S(x));ObjectSetInteger(0,n,OBJPROP_YDISTANCE,S(y));ObjectSetInteger(0,n,OBJPROP_XSIZE,S(w));ObjectSetInteger(0,n,OBJPROP_YSIZE,S(h));ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,n,OBJPROP_FONTSIZE,S(8));ObjectSetString(0,n,OBJPROP_FONT,"Microsoft YaHei");ObjectSetString(0,n,OBJPROP_TEXT,v);
}
void EditBox(string n,int x,int y,int w,int h,string v)
{
 n=PX+n;
 if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_EDIT,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
 ObjectSetInteger(0,n,OBJPROP_XDISTANCE,S(x));
 ObjectSetInteger(0,n,OBJPROP_YDISTANCE,S(y));
 ObjectSetInteger(0,n,OBJPROP_XSIZE,S(w));
 ObjectSetInteger(0,n,OBJPROP_YSIZE,S(h));
 ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'245,245,245');
 ObjectSetInteger(0,n,OBJPROP_COLOR,clrBlack);
 ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,C'120,130,145');
 ObjectSetInteger(0,n,OBJPROP_FONTSIZE,S(8));
 ObjectSetInteger(0,n,OBJPROP_ALIGN,ALIGN_CENTER);
 ObjectSetString(0,n,OBJPROP_FONT,"Microsoft YaHei");
 // 正在编辑时不覆盖用户尚未提交的输入
 if(!ObjectGetInteger(0,n,OBJPROP_SELECTED))
    ObjectSetString(0,n,OBJPROP_TEXT,v);
}
void ApplyEdit(string key,string text)
{
 StringTrimLeft(text);StringTrimRight(text);
 double d=StringToDouble(text);
 int v=(int)MathRound(d);

 if(key=="SLV"){g_slPts=MathMax(0,v);g_status="止损距离已改为 "+IntegerToString(g_slPts)+" 点";}
 else if(key=="TPV"){g_tpPts=MathMax(1,v);g_status="止盈点数已改为 "+IntegerToString(g_tpPts)+" 点";}
 else if(key=="OFV"){g_offsetPts=MathMax(0,v);g_status="排单偏移已改为 "+IntegerToString(g_offsetPts)+" 点";}
 else if(key=="GPV"){g_gapPts=MathMax(1,v);g_status="排单间距已改为 "+IntegerToString(g_gapPts)+" 点";}
 else if(key=="CNTV"){g_orderCount=MathMax(1,MathMin(10,v));g_status="每次单数已改为 "+IntegerToString(g_orderCount);}
 else if(key=="WTV"){g_welfareTPPts=MathMax(1,v);g_status="福利单TP已改为 "+IntegerToString(g_welfareTPPts)+" 点";}
 else if(key=="WLV")
 {
    g_welfareLayer=(v<=0?0:MathMax(2,MathMin(10,v)));
    g_status=(g_welfareLayer==0?"福利单层级：自动中间层":"福利单层级：第"+IntegerToString(g_welfareLayer)+"层");
 }
 Draw();
}
double CurrentATRValue()
{
   if(hKCATR==INVALID_HANDLE)return 0.0;
   double a[];ArraySetAsSeries(a,true);
   if(CopyBuffer(hKCATR,0,0,1,a)<1)return 0.0;
   return a[0];
}
double VolatilityRatio()
{
   if(hKCATR==INVALID_HANDLE)return 1.0;
   int n=MathMax(5,VolatilityLookback);
   double a[];ArraySetAsSeries(a,true);
   int got=CopyBuffer(hKCATR,0,0,n,a);
   if(got<5)return 1.0;
   double avg=0.0;for(int i=0;i<got;i++)avg+=a[i];avg/=got;
   return avg>0?a[0]/avg:1.0;
}

void RefreshAnalysisCache(bool force=false)
{
   datetime now=TimeCurrent();
   int ttl=MathMax(1,SignalCacheRefreshSec);

   if(!force && g_lastSignalCache>0 && now-g_lastSignalCache<ttl)
   {
      // 今日已实现盈亏单独低频更新。
      if(g_lastTodayPLCalc<=0 || now-g_lastTodayPLCalc>=MathMax(1,TodayPnLRefreshSec))
      {
         g_cacheTodayPL=TodayRealizedPL();
         g_lastTodayPLCalc=now;
      }

      // HTF比M5过滤慢得多，独立刷新。
      RefreshHTFAnalysis(false);
      return;
   }

   double fa=0,fp=0,fm=0,fv=0,fs=0,frsi=50.0;
   int score=TrendLightScore(fa,fp,fm,fv,fs,frsi);
   UpdateStableTrend(score);

   double z=0.0;
   VWAPZ(z);

   double vr=VolatilityRatio();
   double atr=CurrentATRValue();

   double a=0,p=0,m=0,v=0,s=0;
   MARKET_REGIME rg=CurrentMarketRegime(a,p,m,v,s);

   g_cacheTrendScore=score;
   g_cacheADX=fa;
   g_cachePDI=fp;
   g_cacheMDI=fm;
   g_cacheVWAP=fv;
   g_cacheVWAPSlope=fs;
   g_cacheRSI=frsi;
   g_cacheZ=z;
   g_cacheVolRatio=vr;
   g_cacheATR=atr;
   g_cacheRegime=rg;

   // 波动灯文字/颜色也缓存，避免Draw里再次CopyBuffer双通道。
   g_cacheVolText=VolatilityLightText(vr);
   if(g_cacheVolText=="极端扩张")g_cacheVolColor=C'255,55,55';
   else if(g_cacheVolText=="趋势扩张"||g_cacheVolText=="高波动")g_cacheVolColor=C'255,150,70';
   else if(g_cacheVolText=="低波动/挤压"||g_cacheVolText=="低波动/收缩")g_cacheVolColor=C'100,180,255';
   else g_cacheVolColor=C'100,230,140';

   g_lastSignalCache=now;
   g_signalCacheValid=true;

   RefreshHTFAnalysis(false);

   if(g_lastTodayPLCalc<=0 || now-g_lastTodayPLCalc>=MathMax(1,TodayPnLRefreshSec))
   {
      g_cacheTodayPL=TodayRealizedPL();
      g_lastTodayPLCalc=now;
   }
}
string VolatilityLightText(double r)
{
   if(!EnableVolatilityLight)return "关闭";
   double bm,u1,l1,u2,l2,km,ku1,kl1,ku2,kl2;
   bool ch=DualChannelValues(bm,u1,l1,u2,l2,km,ku1,kl1,ku2,kl2);
   MqlTick q;SymbolInfoTick(_Symbol,q);double px=(q.bid+q.ask)*0.5;

   if(ch)
   {
      bool outside25=(px>=u2&&px>=ku2)||(px<=l2&&px<=kl2);
      bool outside15=(px>=u1&&px>=ku1)||(px<=l1&&px<=kl1);
      bool squeeze=(u1<=ku1 && l1>=kl1);
      if(r>=VolatilityExtremeRatio || outside25)return "极端扩张";
      if(r>=VolatilityHighRatio && outside15)return "趋势扩张";
      if(r<=VolatilityLowRatio && squeeze)return "低波动/挤压";
   }
   if(r>=VolatilityHighRatio)return "高波动";
   if(r<=VolatilityLowRatio)return "低波动/收缩";
   return "正常波动";
}
color VolatilityLightColor(double r)
{
   string s=VolatilityLightText(r);
   if(s=="极端扩张")return C'255,55,55';
   if(s=="趋势扩张"||s=="高波动")return C'255,150,70';
   if(s=="低波动/挤压"||s=="低波动/收缩")return C'100,180,255';
   return C'100,230,140';
}
string TradeLightText(int score,double z,double vr)
{
   if(BlockNewTradesAtExtremeVol && vr>=VolatilityExtremeRatio)return "极端波动｜暂停新单";
   if(score>=2)
   {
      if(z>=TradeExtremeZ)return "多头极值｜等待回踩";
      return (score>=7?"强多｜允许顺势多":"偏多｜允许顺势多");
   }
   if(score<=-2)
   {
      if(z<=-TradeExtremeZ)return "空头极值｜等待反弹";
      return (score<=-7?"强空｜允许顺势空":"偏空｜允许顺势空");
   }
   return "震荡/过渡｜等待";
}
color TradeLightColor(int score,double z,double vr)
{
   if(BlockNewTradesAtExtremeVol && vr>=VolatilityExtremeRatio)return C'255,55,55';
   if((score>=2&&z>=TradeExtremeZ)||(score<=-2&&z<=-TradeExtremeZ))return C'255,200,70';
   if(score>=2)return C'80,220,120';
   if(score<=-2)return C'255,150,70';
   return C'180,180,190';
}


void DeleteStatDetailObjects()
{
   string names[]={"BS","BN","BW","SS","SN","SW","LK","PEND","PS","LOC","VOL","TRADE","HTF"};
   for(int i=0;i<ArraySize(names);i++)
      ObjectDelete(0,PX+names[i]);
}

void Draw()
{
 int x=PanelX,y=PanelY,w=430;

 if(g_panelHidden)
 {
    if(ObjectFind(0,PX+"SHOW")<0)
       Btn("SHOW",x,y,95,24,"显示面板 [O]",C'35,85,120');
    ChartRedraw();
    return;
 }

 // 持仓统计展开高度约265px；折叠后保留36px标题栏，
 // 下方所有按钮整体上移229px，同时缩短主面板。
 int statShift=(g_statsCollapsed?-229:0);
 int panelH=1015+statShift;

 Rect("BG",x,y,w,panelH,C'20,22,27');
 Txt("TITLE",x+10,y+7,"幽灵狙击手  MT5 v2.76 EXEC GUARD",11,C'255,210,40');
 Btn("HIDE",x+345,y+5,60,20,"隐藏 O",C'55,65,80');
 Txt("MODE",x+10,y+26,"Ghost Sniper · 黄金半自动交易/趋势过滤系统",8,C'210,210,210');

 Btn("SHORT",x+10,y+41,190,22,"★ 抢钱模式",g_shortMode?C'190,125,0':C'80,80,85');
 Btn("LONG",x+210,y+41,195,22,"狙击模式",!g_shortMode?C'40,115,75':C'80,80,85');

 Txt("LOT",x+10,y+69,"手数  "+DoubleToString(g_lot,2),9);
 Btn("LM",x+125,y+65,45,22,"-手",C'80,80,90');
 Btn("LP",x+175,y+65,45,22,"+手",C'80,80,90');

 Btn("B7",x+10,y+94,125,29,"▲ 狙击多 [7]",C'0,120,35');
 Btn("B8",x+145,y+94,125,29,"▲ 排单多 [8]",C'0,105,75');
 Btn("B9",x+280,y+94,125,29,"平多单 [9]",C'0,100,65');

 Btn("S1",x+10,y+129,125,29,"▼ 狙击空 [1]",C'175,22,35');
 Btn("S2",x+145,y+129,125,29,"▼ 排单空 [2]",C'145,55,25');
 Btn("S3",x+280,y+129,125,29,"平空单 [3]",C'145,35,35');

 Txt("PROT",x+10,y+165,"面板快速参数（双击数值 → 输入 → Enter，立即生效）",8,C'110,230,130');
 Txt("SLT",x+10,y+184,"止损",8);
 EditBox("SLV",x+58,y+180,105,21,IntegerToString(g_slPts));

 Txt("TPT",x+215,y+184,"止盈",8);
 EditBox("TPV",x+263,y+180,105,21,IntegerToString(g_tpPts));

 Txt("OFT",x+10,y+207,"偏移",8);
 EditBox("OFV",x+58,y+203,105,21,IntegerToString(g_offsetPts));

 Txt("GPT",x+215,y+207,"间距",8);
 EditBox("GPV",x+263,y+203,105,21,IntegerToString(g_gapPts));

 Txt("CNTT",x+10,y+231,"单数",8);
 EditBox("CNTV",x+58,y+227,105,21,IntegerToString(g_orderCount));

 Txt("WTT",x+185,y+231,"福利TP",8);
 EditBox("WTV",x+240,y+227,70,21,IntegerToString(g_welfareTPPts));

 Txt("WLT",x+315,y+231,"层",8);
 EditBox("WLV",x+337,y+227,68,21,(g_welfareLayer<=0?"中间":IntegerToString(g_welfareLayer)));

 Txt("LAD",x+10,y+253,
     "总上限："+IntegerToString(MaxTotalOrders)+
     "  单边："+DoubleToString(MaxSideLots,2)+
     "手 | 浮盈 "+DoubleToString(g_floatTriggerPct,0)+"%→普通单减仓",
     8,C'230,200,80');

 // =========================
 // 持仓统计：可折叠区域
 // =========================
 if(g_statsCollapsed)
 {
    DeleteStatDetailObjects();

    Rect("STAT",x+10,y+282,395,36,C'28,32,38');
    Txt("SH",x+20,y+292,"持仓统计｜真实净成本保护（展开看明细）",8,C'100,220,220');
    Btn("STATTOG",x+330,y+288,65,22,"展开 ▼",C'45,70,90');
 }
 else
 {
    int bn,sn;
    double bl,bp,ba,sl,sp,sa;
    StatsNoLock(POSITION_TYPE_BUY,bn,bl,bp,ba);
    StatsNoLock(POSITION_TYPE_SELL,sn,sl,sp,sa);

    int nbn,nsn;
    double nbl,nbp,nba,nsl,nsp,nsa;
    NormalStats(POSITION_TYPE_BUY,nbn,nbl,nbp,nba);
    NormalStats(POSITION_TYPE_SELL,nsn,nsl,nsp,nsa);

    int wbn,wsn;
    double wbl,wbp,wba,wbbe,wbfl,wsl,wsp,wsa,wsbe,wsfl;
    WelfareStatsDetailed(POSITION_TYPE_BUY,wbn,wbl,wbp,wba,wbbe,wbfl);
    WelfareStatsDetailed(POSITION_TYPE_SELL,wsn,wsl,wsp,wsa,wsbe,wsfl);

    int lkn;
    double lkBuy,lkSell,lkPf;
    LockStats(lkn,lkBuy,lkSell,lkPf);

    int gc=0;
    double gl=0,gavg=0,gcost=0,gcur=0,gnet=0;
    double nBuyBE=0,nSellBE=0;
    if(GroupProtectionData(POSITION_TYPE_BUY,gc,gl,gavg,gcost,gcur,gnet))
       nBuyBE=gavg+gcost*_Point;
    if(GroupProtectionData(POSITION_TYPE_SELL,gc,gl,gavg,gcost,gcur,gnet))
       nSellBE=gavg-gcost*_Point;

    Rect("STAT",x+10,y+282,395,265,C'28,32,38');
    RefreshCommissionLearning(false);
    double uiComm=0,uiSwap=0,uiSpreadPts=0,uiSpreadMoney=0,uiCostLots=0;
    ManagedCostSummary(uiComm,uiSwap,uiSpreadPts,uiSpreadMoney,uiCostLots);

    string learnedCostText=(g_learnedEntryCostPerLot>0 || g_learnedExitCostPerLot>0
       ? " 学习 "+DoubleToString(g_learnedEntryCostPerLot,2)+"/"+DoubleToString(g_learnedExitCostPerLot,2)
       : " 学习 --/--");
    Txt("SH",x+20,y+291,
        "持仓统计｜RT$"+DoubleToString(CommissionPerLotRT,2)+learnedCostText+
        "｜Spread "+DoubleToString(uiSpreadPts,0)+"pt",
        7,C'100,220,220');
    Btn("STATTOG",x+330,y+287,65,22,"收起 ▲",C'45,70,90');

    Txt("BS",x+20,y+311,
        "多总："+IntegerToString(bn)+"单 "+DoubleToString(bl,2)+"手  "+DoubleToString(bp,2)+" USD",
        8,clrLime);

    Txt("BN",x+20,y+329,
        "普通多："+IntegerToString(nbn)+"单 均价 "+
        (nbn>0?DoubleToString(nba,_Digits):"--")+
        " 成本保本 "+(nBuyBE>0?DoubleToString(nBuyBE,_Digits):"--"),
        8,C'120,235,150');

    Txt("BW",x+20,y+347,
        "福利多："+IntegerToString(wbn)+"单 均价 "+
        (wbn>0?DoubleToString(wba,_Digits):"--")+
        " 成本 "+(wbbe>0?DoubleToString(wbbe,_Digits):"--")+
        " 保盈 "+(wbfl>0?DoubleToString(wbfl,_Digits):"--"),
        7,C'220,190,60');

    Txt("SS",x+20,y+366,
        "空总："+IntegerToString(sn)+"单 "+DoubleToString(sl,2)+"手  "+DoubleToString(sp,2)+" USD",
        8,C'255,120,120');

    Txt("SN",x+20,y+384,
        "普通空："+IntegerToString(nsn)+"单 均价 "+
        (nsn>0?DoubleToString(nsa,_Digits):"--")+
        " 成本保本 "+(nSellBE>0?DoubleToString(nSellBE,_Digits):"--"),
        8,C'245,145,145');

    Txt("SW",x+20,y+402,
        "福利空："+IntegerToString(wsn)+"单 均价 "+
        (wsn>0?DoubleToString(wsa,_Digits):"--")+
        " 成本 "+(wsbe>0?DoubleToString(wsbe,_Digits):"--")+
        " 保盈 "+(wsfl>0?DoubleToString(wsfl,_Digits):"--"),
        7,C'220,190,60');

    Txt("LK",x+20,y+420,
        "锁仓："+IntegerToString(lkn)+"单 多"+DoubleToString(lkBuy,2)+
        " / 空"+DoubleToString(lkSell,2)+"手  "+DoubleToString(lkPf,2)+" USD",
        8,C'185,150,235');

    double pendLots=0;
    int pendN=PendingStats(pendLots);

    int fscore=g_cacheTrendScore;
    double fa=g_cacheADX,frsi=g_cacheRSI;
    double z=g_cacheZ,vr=g_cacheVolRatio,atrNow=g_cacheATR;
    color flight=StableTrendColor();

    Txt("COST",x+20,y+438,
        "持仓成本：佣$"+DoubleToString(uiComm,2)+
        " Swap$"+DoubleToString(uiSwap,2)+
        " Spread$"+DoubleToString(uiSpreadMoney,2)+
        " 缓冲"+DoubleToString(EffectiveProtectionBufferPts(),0)+"pt",
        7,C'110,210,255');

    Txt("PEND",x+20,y+454,
        "挂单："+IntegerToString(pendN)+"单 "+DoubleToString(pendLots,2)+"手",
        7,C'110,210,255');

    Txt("PS",x+20,y+470,
        "方向灯 ● "+StableTrendText()+
        " | ADX "+DoubleToString(fa,1)+
        " | RSI "+DoubleToString(frsi,1),
        8,flight);

    Txt("LOC",x+20,y+486,
        "位置灯 ● "+LocationLightText(z)+
        " | VWAP "+VWAPZoneText(z)+
        " | Z "+DoubleToString(z,2),
        8,LocationLightColor(z));

    Txt("VOL",x+20,y+502,
        "波动灯 ● "+g_cacheVolText+
        " | ATR "+DoubleToString(atrNow,_Digits)+
        " | 比率 "+DoubleToString(vr,2),
        8,g_cacheVolColor);

    Txt("TRADE",x+20,y+518,
        "交易灯 ● "+TradeLightText(fscore,z,vr),
        8,TradeLightColor(fscore,z,vr));

    string htfLine=(!EnableHTFAnalysis?"HTF ● 关闭":
                    (!g_htfValid?"HTF ● 数据不足":
                     "HTF ● H1 "+HTFStateText(g_htfH1)+
                     " | H4 "+HTFStateText(g_htfH4)+
                     " | 7H "+HTFStateText(g_htfH7)+
                     " | 综合 "+HTFStateText(g_htfComposite)));

    Txt("HTF",x+20,y+534,htfLine,8,
        (g_htfValid?HTFStateColor(g_htfComposite):C'180,180,190'));
 }

 // =========================
 // 折叠区域以下：自动整体上移
 // =========================
 int sy=statShift;

 Btn("FLOAT",x+10,y+562+sy,125,26,
     g_floatMonitor?"浮盈监控 ● 开":"浮盈监控 ○ 关",
     g_floatMonitor?C'0,125,55':C'105,105,105');

 Btn("FMINUS",x+145,y+562+sy,55,26,"阈值-",C'70,75,85');
 Btn("FPLUS",x+205,y+562+sy,55,26,"阈值+",C'70,75,85');
 Btn("FVAL",x+265,y+562+sy,140,26,
     DoubleToString(g_floatTriggerPct,0)+"% → 普通单减仓",
     C'25,85,120');

 Btn("HALF",x+10,y+593+sy,125,26,"手动平50%浮盈",C'0,115,105');
 Btn("TAKE",x+145,y+593+sy,125,26,
     g_manualTakeover?"手工单已接管":"接管手工单",
     C'30,55,145');
 Btn("FILTER",x+280,y+593+sy,125,26,
     g_trendFilter?"只做趋势 ● 开":"只做趋势 ○ 关",
     g_trendFilter?C'0,125,55':C'105,105,105');

 Btn("WIN",x+10,y+624+sy,125,26,"平浮盈 [4]",C'0,110,70');
 Btn("BE",x+145,y+624+sy,125,26,"均价推保 [5]",C'40,85,150');
 Btn("LOSS",x+280,y+624+sy,125,26,"平浮亏 [6]",C'150,55,45');

 Btn("DEL",x+10,y+655+sy,125,26,"删除挂单",C'155,125,45');
 Btn("PAUSE",x+145,y+655+sy,125,26,
     g_pause?"▶ 恢复 [0]":"⏸ 暂停 [0]",
     g_pause?C'30,130,70':C'80,85,100');
 Btn("ALL",x+280,y+655+sy,125,26,"紧急全平 [.]",C'180,35,35');

 Btn("BTP",x+10,y+686+sy,190,26,
     "多TP→均价+"+IntegerToString(AverageTPOffsetPts),
     C'0,100,110');
 Btn("STP",x+210,y+686+sy,195,26,
     "空TP→均价-"+IntegerToString(AverageTPOffsetPts),
     C'125,45,100');

 Btn("WELFARE",x+10,y+717+sy,190,26,
     g_welfareEnabled?"福利单 ● 开":"福利单 ○ 关",
     g_welfareEnabled?C'120,90,15':C'85,85,85');
 Btn("STEP_TP",x+210,y+717+sy,195,26,
     g_steppedTP?"排单止盈 ● 开":"固定止盈 ○ 关",
     g_steppedTP?C'0,105,110':C'85,85,85');

 Btn("UBTP",x+10,y+748+sy,125,26,"多止盈线",C'0,115,70');
 Btn("UBSL",x+145,y+748+sy,125,26,"多止损线",C'125,55,45');
 Btn("UBOK",x+280,y+748+sy,125,26,"确认统一多",C'45,85,145');

 Btn("USTP",x+10,y+779+sy,125,26,"空止盈线",C'125,45,95');
 Btn("USSL",x+145,y+779+sy,125,26,"空止损线",C'155,70,35');
 Btn("USOK",x+280,y+779+sy,125,26,"确认统一空",C'70,70,145');

 Btn("HEDGE",x+10,y+812+sy,125,26,"对冲平仓",C'110,70,30');
 Btn("LOCK",x+145,y+812+sy,125,26,"🔒 一键锁仓",C'80,55,125');
 Btn("UNLOCK",x+280,y+812+sy,125,26,"解锁",C'55,90,125');

 Rect("INFO",x+10,y+845+sy,395,108,C'28,32,38');
 Txt("I1",x+20,y+855+sy,
     "余额 "+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
     "   净值 "+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
     9);

 Txt("I2",x+20,y+875+sy,
     "当前管理浮盈 "+DoubleToString(FloatPL(),2)+
     " USD   总管理 "+IntegerToString(TotalManaged()),
     8,C'245,220,80');

 double todayPL=g_cacheTodayPL;
 color todayColor=(todayPL>0?C'70,210,110':
                  (todayPL<0?C'240,85,85':C'210,210,210'));
 string todaySign=(todayPL>0?"+":"");

 Txt("I4",x+20,y+895+sy,
     "今日盈利 "+todaySign+DoubleToString(todayPL,2)+" USD"+
     (todayPL>0?"  ● 盈利":(todayPL<0?"  ● 亏损":"  ● 持平")),
     8,todayColor);

 Txt("I3",x+20,y+915+sy,"状态："+g_status,8,C'200,210,220');

 UpdateLatencyText();
 Txt("I5",x+20,y+935+sy,g_latencyText,7,g_latencyColor);

 Txt("KEY",x+10,y+970+sy,
     "NumPad: 7狙击多/8排单多/9平多 | 1狙击空/2排单空/3平空 | O隐藏/显示 | .删除挂单",
     7,C'170,180,190');

 ChartRedraw();
}

//---------------- panel hide/show ----------------
void SetPanelHidden(bool hidden)
{
   g_panelHidden=hidden;
   ObjectsDeleteAll(0,PX);
   if(hidden)
   {
      Btn("SHOW",PanelX,PanelY,95,24,"显示面板 [O]",C'35,85,120');
      g_status="面板已隐藏，按 O 或点击“显示面板”恢复";
      ChartRedraw();
   }
   else
   {
      g_status="面板已显示";
      Draw();
   }
}

//---------------- click / keyboard ----------------
void Action(string a)
{
 bool lightOnly=false;

 if(a=="HIDE"){SetPanelHidden(true);return;}
 if(a=="SHOW"){SetPanelHidden(false);return;}
 if(a=="STATTOG")
 {
   g_statsCollapsed=!g_statsCollapsed;
   g_status=g_statsCollapsed?"持仓统计已折叠":"持仓统计已展开";
 }
 else if(a=="SHORT"){g_shortMode=true;g_tpPts=ShortTPPoints;g_gapPts=ShortLadderGap;g_offsetPts=ShortLadderOffset;g_status="已切换抢钱模式并载入抢钱参数";}
 else if(a=="LONG"){g_shortMode=false;g_tpPts=LongTPPoints;g_gapPts=LongLadderGap;g_offsetPts=LongLadderOffset;g_status="已切换狙击模式并载入狙击参数";}
 else if(a=="B7"){Market(ORDER_TYPE_BUY);lightOnly=true;}
 else if(a=="B8"){Ladder(ORDER_TYPE_BUY);lightOnly=true;}
 else if(a=="B9"){CloseSide(POSITION_TYPE_BUY);lightOnly=true;}
 else if(a=="S1"){Market(ORDER_TYPE_SELL);lightOnly=true;}
 else if(a=="S2"){Ladder(ORDER_TYPE_SELL);lightOnly=true;}
 else if(a=="S3"){CloseSide(POSITION_TYPE_SELL);lightOnly=true;}
 else if(a=="FLOAT"){g_floatMonitor=!g_floatMonitor;g_floatTriggered=false;g_status=g_floatMonitor?"浮盈监控已开启（普通单）":"浮盈监控已关闭";}
 else if(a=="FMINUS"){g_floatTriggerPct=MathMax(1.0,g_floatTriggerPct-5.0);g_floatTriggered=false;g_status="浮盈触发阈值 "+DoubleToString(g_floatTriggerPct,0)+"%";}
 else if(a=="FPLUS"){g_floatTriggerPct=MathMin(500.0,g_floatTriggerPct+5.0);g_floatTriggered=false;g_status="浮盈触发阈值 "+DoubleToString(g_floatTriggerPct,0)+"%";}
 else if(a=="FVAL")g_status="自动浮盈监控只处理普通组合；福利Runner和锁仓单不参与自动减仓";
 else if(a=="STEP_TP"){g_steppedTP=!g_steppedTP;g_status=g_steppedTP?"新单使用排单止盈":"新单使用固定止盈距离（当前面板止盈点数）";}
 else if(a=="WELFARE"){g_welfareEnabled=!g_welfareEnabled;g_status=g_welfareEnabled?"福利单已开启":"福利单已关闭（已有福利单不自动删除）";}
 else if(a=="HEDGE"){HedgeClose();lightOnly=true;}
 else if(a=="LOCK"){LockPosition();lightOnly=true;}
 else if(a=="UNLOCK"){UnlockPosition();lightOnly=true;}
 else if(a=="HALF"){CloseHalfWinners();lightOnly=true;}
 else if(a=="TAKE"){g_manualTakeover=!g_manualTakeover;g_status=g_manualTakeover?"已接管当前品种手工单":"已取消手工单接管";}
 else if(a=="FILTER"){g_trendFilter=!g_trendFilter;g_status=g_trendFilter?"只做趋势总过滤已开启":"只做趋势总过滤已关闭";}
 else if(a=="BTP"){SetAverageTP(POSITION_TYPE_BUY);lightOnly=true;}
 else if(a=="STP"){SetAverageTP(POSITION_TYPE_SELL);lightOnly=true;}

 else if(a=="UBTP"){PrepareUnifiedLine(true,true);lightOnly=true;}
 else if(a=="UBSL"){PrepareUnifiedLine(true,false);lightOnly=true;}
 else if(a=="UBOK"){ApplyUnifiedTPSL(true);lightOnly=true;}

 else if(a=="USTP"){PrepareUnifiedLine(false,true);lightOnly=true;}
 else if(a=="USSL"){PrepareUnifiedLine(false,false);lightOnly=true;}
 else if(a=="USOK"){ApplyUnifiedTPSL(false);lightOnly=true;}

 else if(a=="WIN"){CloseByProfit(true);lightOnly=true;}
 else if(a=="BE"){BreakEvenAll();lightOnly=true;}
 else if(a=="LOSS"){CloseByProfit(false);lightOnly=true;}
 else if(a=="DEL"){DeletePending();lightOnly=true;}
 else if(a=="PAUSE"){g_pause=!g_pause;g_status=g_pause?"快捷交易已暂停":"快捷交易已恢复";}
 else if(a=="LM"){g_lot=NLot(g_lot-LotStepButton);g_status="手数 "+DoubleToString(g_lot,2);}
 else if(a=="LP"){g_lot=NLot(g_lot+LotStepButton);g_status="手数 "+DoubleToString(g_lot,2);}
 else if(a=="ALL")
 {
   if(!EmergencyDoublePress)CloseAll();
   else if(TimeCurrent()-g_lastEmergency<=EmergencyWindowSec)CloseAll();
   else {g_lastEmergency=TimeCurrent();g_status="再次点击紧急全平进行确认";}
   lightOnly=true;
 }

 if(lightOnly)FastStatusUpdate();
 else Draw();
}

void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
{
 // v2.72：统一TP/SL辅助线跟随鼠标。
 if(id==CHARTEVENT_MOUSE_MOVE && g_unifiedFollowActive)
 {
   if(g_unifiedFollowName!="" && ObjectFind(0,g_unifiedFollowName)>=0)
   {
      int subwin=0;
      datetime tm=0;
      double price=0.0;
      if(ChartXYToTimePrice(0,(int)lp,(int)dp,subwin,tm,price) && subwin==0 && price>0)
      {
         ObjectSetDouble(0,g_unifiedFollowName,OBJPROP_PRICE,NormalizeDouble(price,_Digits));
         ChartRedraw();
      }
   }
   return;
 }

 // 在图表空白处单击固定当前统一线；固定后仍可以继续拖动微调。
 if(id==CHARTEVENT_CLICK && g_unifiedFollowActive)
 {
   string fixedName=g_unifiedFollowName;
   StopUnifiedMouseFollow();

   if(fixedName!="" && ObjectFind(0,fixedName)>=0)
   {
      ObjectSetInteger(0,fixedName,OBJPROP_SELECTED,true);
      g_status="统一线已固定｜可继续拖动微调，确认后自动消失";
      FastStatusUpdate();
   }
   return;
 }

 if(id==CHARTEVENT_OBJECT_DRAG && IsUnifiedLineName(sp))
 {
   StopUnifiedMouseFollow();
   g_status="统一线已手工拖动固定｜确认后自动消失";
   FastStatusUpdate();
   return;
 }

 if(id==CHARTEVENT_OBJECT_ENDEDIT)
 {
   if(StringFind(sp,PX)==0)
   {
      string key=StringSubstr(sp,StringLen(PX));
      if(key=="SLV"||key=="TPV"||key=="OFV"||key=="GPV"||key=="CNTV"||key=="WTV"||key=="WLV")
      {
         ApplyEdit(key,ObjectGetString(0,sp,OBJPROP_TEXT));return;
      }
   }
 }
 if(id==CHARTEVENT_OBJECT_CLICK)
 {
   string a=sp;if(StringFind(a,PX)==0)a=StringSubstr(a,StringLen(PX));
   if(a=="SLV"||a=="TPV"||a=="OFV"||a=="GPV"||a=="CNTV"||a=="WTV"||a=="WLV")return;

   // 先弹起按钮再执行交易，避免同步下单期间按钮看起来“卡死”。
   if(ObjectFind(0,sp)>=0)ObjectSetInteger(0,sp,OBJPROP_STATE,false);
   ChartRedraw();

   Action(a);
   return;
 }
 if(id==CHARTEVENT_KEYDOWN)
 {
   int k=(int)lp;
   if(EnablePanelToggleHotkey && k==PanelToggleKey){SetPanelHidden(!g_panelHidden);return;}
   if(!EnableKeyboard)return;
   if(k==MarketBuyKey || k==55 || (EnableNumPad&&k==MarketBuyNumKey))Action("B7");
   else if(k==LadderBuyKey || k==56 || (EnableNumPad&&k==LadderBuyNumKey))Action("B8");
   else if(k==CloseBuyKey || k==57 || (EnableNumPad&&k==CloseBuyNumKey))Action("B9");
   else if(k==MarketSellKey || k==49 || (EnableNumPad&&k==MarketSellNumKey))Action("S1");
   else if(k==LadderSellKey || k==50 || (EnableNumPad&&k==LadderSellNumKey))Action("S2");
   else if(k==CloseSellKey || k==51 || (EnableNumPad&&k==CloseSellNumKey))Action("S3");
   else if(k==CloseProfitKey || k==52 || (EnableNumPad&&k==CloseProfitNumKey))Action("WIN");
   else if(k==BreakEvenKey || k==53 || (EnableNumPad&&k==BreakEvenNumKey))Action("BE");
   else if(k==54)Action("LOSS");
   else if(k==48 || (EnableNumPad&&k==96))Action("PAUSE");
   else if(k==46)Action("DEL");
   else if(EnableNumPad && (k==DeletePendingKey || k==110))Action("DEL");
   else if(EnableNumPad && k==107)Action("LP");
   else if(EnableNumPad && k==109)Action("LM");
 }
}
int OnInit()
{
 g_lot=NLot(DefaultLot);g_shortMode=StartShortMode;g_trendFilter=StartTrendFilter;g_floatMonitor=EnableFloatMonitor;
 g_slPts=FixedSLPoints;
 g_tpPts=(g_shortMode?ShortTPPoints:LongTPPoints); if(g_tpPts<=0)g_tpPts=FixedTPPoints;
 g_gapPts=(g_shortMode?ShortLadderGap:LongLadderGap); if(g_gapPts<=0)g_gapPts=LadderGapPoints;
 g_offsetPts=(g_shortMode?ShortLadderOffset:LongLadderOffset); if(g_offsetPts<0)g_offsetPts=LadderOffsetPoints;
 g_orderCount=MathMax(1,MathMin(10,LadderOrders));g_welfareTPPts=WelfareTPPoints;g_welfareLayer=WelfareLayer;
 g_welfareEnabled=EnableWelfareOrder;g_steppedTP=EnableSteppedTP;g_floatTriggerPct=FloatProfitPct;g_panelHidden=false;
 hRSI=iRSI(_Symbol,PERIOD_CURRENT,RSIPeriod,PRICE_CLOSE);
 hADX=iADX(_Symbol,ADXTimeframe,ADXPeriod);
 hBands15=iBands(_Symbol,ChannelTimeframe,BollingerPeriod,0,BollingerDev1,PRICE_CLOSE); hBands25=iBands(_Symbol,ChannelTimeframe,BollingerPeriod,0,BollingerDev2,PRICE_CLOSE);
 hKCEMA=iMA(_Symbol,ChannelTimeframe,KeltnerEMAPeriod,0,MODE_EMA,PRICE_TYPICAL); hKCATR=iATR(_Symbol,ChannelTimeframe,KeltnerATRPeriod);
 trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);
 ClearCostCache();
 RefreshCommissionLearning(true);

 // 首次加载时预热一次分析缓存；后续交易按钮只读缓存，不在点击瞬间拉历史。
 RefreshAnalysisCache(true);

 ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
 EventSetMillisecondTimer(MathMax(250,PanelRefreshMs));
 g_status="幽灵狙击手 v2.76 就绪｜佣金自学习+动态滑点缓冲+保护修改重试";
 Draw();return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
 ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);
 EventKillTimer();
 if(hRSI!=INVALID_HANDLE)IndicatorRelease(hRSI);
 if(hADX!=INVALID_HANDLE)IndicatorRelease(hADX);
 if(hBands15!=INVALID_HANDLE)IndicatorRelease(hBands15);
 if(hBands25!=INVALID_HANDLE)IndicatorRelease(hBands25);
 if(hKCEMA!=INVALID_HANDLE)IndicatorRelease(hKCEMA);
 if(hKCATR!=INVALID_HANDLE)IndicatorRelease(hKCATR);
 ObjectsDeleteAll(0,PX);
 ObjectDelete(0,OBJ_UNI_BUY_TP);
 ObjectDelete(0,OBJ_UNI_BUY_SL);
 ObjectDelete(0,OBJ_UNI_SELL_TP);
 ObjectDelete(0,OBJ_UNI_SELL_SL);
}
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // 任意新增成交都可能改变实际Commission/Fee，先失效成本缓存。
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      ClearCostCache();
      g_commissionLearnStamp=0; // 新成交可能带来新的真实佣金样本
   }

   if(!EnableTradeLatencyMonitor)return;

   // 异步请求收到交易服务器正式应答。
   if(trans.type==TRADE_TRANSACTION_REQUEST)
   {
      if(request.symbol==_Symbol &&
         (request.magic==MagicNumber || request.magic==WelfareMagic) &&
         IsSniperMarketComment(request.comment))
      {
         RegisterLatencyAck(request.comment,result.retcode);
      }
      return;
   }

   // 真正成交写入历史后，记录提交→成交延迟与滑点。
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0)
   {
      RegisterLatencyFill(trans.deal);
      return;
   }
}

void OnTick()
{
   // 账户/方向亏损保护保持最高优先级：每个Tick都检查。
   SideProtection();

   ulong now=GetTickCount64();

   // 推保、普通追踪、福利追踪错峰限流，减少黄金高速Tick时主线程负担。
   if(g_lastProtectExecMs==0 ||
      now-g_lastProtectExecMs>=(ulong)MathMax(20,ProtectThrottleMs))
   {
      g_lastProtectExecMs=now;
      ProcessModifyRetryQueue();
      AutoProtect();
      WelfareTrailing();
   }

   // 浮盈减仓无需每个Tick重复扫描。
   if(g_lastFloatExecMs==0 ||
      now-g_lastFloatExecMs>=(ulong)MathMax(50,FloatMonitorThrottleMs))
   {
      g_lastFloatExecMs=now;
      FloatMonitor();
   }
}

void OnTimer()
{
   RefreshCommissionLearning(false);
   RefreshAnalysisCache(false);
   Draw();
}
