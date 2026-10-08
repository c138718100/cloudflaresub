#property copyright "Jammy / OpenAI - independent MT5 port"
#property version   "1.681"
#property strict
#property description "Jammy Smart Accumulation MT5 v1.68.1 Trading Core Lite + NumPad + RiskGuard"
#property description "Trading core only: smart accumulation + manual market/pending manager. Heatmap/MTF dashboard moved to standalone indicator."

// v1.67.3 UI变化：主面板底部信息区可折叠；状态文字拆成多行并始终留在面板背景内部。
// 增加“隐藏面板 [0]”按钮；隐藏后保留一个“显示面板 [0]”小按钮，数字0/小键盘0仍可切换。
// 继承 v1.67.2：手工市价/排单的设置单数仅为最大单数，实际单数由风险预算与止损距离自适应。

#include <Trade/Trade.mqh>

CTrade trade;

enum JsaDirection
{
   DIR_LONG = 0,
   DIR_SHORT = 1
};

enum JsaFollowMode
{
   FOLLOW_DYNAMIC_BOX = 0,
   FOLLOW_H4_EMA8 = 1
};

enum JsaTakeProfitMode
{
   TP_NORMAL = 0,      // 普通止盈
   TP_ADVANCED = 1     // 进阶止盈
};

enum JsaHeatmapTimeframe
{
   HEAT_M15 = 0,
   HEAT_H1 = 1,
   HEAT_H4 = 2,
   HEAT_D1 = 3
};

// =========================
// 1) 核心参数
// =========================
input group "核心"
input(name="以损定量 USD") double RiskUsd = 200.0;
input(name="手工最大开仓单数") int ManualOrderCount = 10;
input(name="单笔最大手数") double MaxLotsPerOrder = 1.0;
input(name="最大总手数（多空合计，含挂单）") double MaxTotalLots = 10.0;

// =========================
// 原版净值风险
// =========================
input group "原版净值风险"
input(name="使用净值百分比定量（仅兼容保留，不覆盖面板风险）") bool UseEquityRiskSizing = true;
input(name="默认净值风险%（仅兼容/参考）") double DefaultEquityRiskPct = 1.0;
input(name="启用最大净值风险安全上限") bool EnableMaxEquityRiskCap = true;
input(name="最大净值风险安全上限%（只限幅，不定量）") double MaxEquityRiskPct = 2.0;

// =========================
// 原版吸金参数
// =========================
input group "原版吸金参数"
input(name="智能网格单数量上限") int SmartGridCount = 10;
input(name="启用框内自适应排单") bool AutoSmartGridSizing = true;
input(name="自适应最少排单数") int AutoSmartMinOrders = 2;
input(name="智能网格间距（不建议<100）") int FixedGridGapPoints = 100;
input(name="智能网格止盈点数（默认50点）") int OddTpPoints = 100;
input(name="默认盈亏比") double EvenRR = 2.5;
input(name="排单有效期10根K线") int PendingValidBars = 10;
input(name="排单有效期分钟（>0时取代K线数，不随图表周期变化）") int PendingValidMinutes = 0;

// =========================
// 止盈模式
// =========================
input group "止盈模式"
input(name="默认选择止盈模式") JsaTakeProfitMode TakeProfitMode = TP_NORMAL;
input(name="进阶模式组合RR扩展倍率（建议1.10-1.50）") double AdvancedRrProgressionMultiplier = 1.25;
input(name="吸筹组合RR硬上限") double SmartPortfolioMaxRR = 4.0;
input(name="偶数单分批止盈") bool EvenBatchTakeProfit = true;
input(name="偶数单止盈批次数（1-3）") int EvenTpBatchCount = 3;
input(name="偶数TP1距离权重") double EvenTp1DistanceWeight = 0.70;
input(name="偶数TP2距离权重") double EvenTp2DistanceWeight = 1.00;
input(name="偶数TP3距离权重") double EvenTp3DistanceWeight = 1.35;

input group "手工市价/排单止盈"
input(name="手工分仓起始RR") double ManualFirstTpR = 0.50;
input(name="手工TP硬上限RR") double ManualHardMaxTpR = 4.00;
input(name="进阶分层曲线（1=线性，建议1.20-1.60）") double ManualAdvancedCurve = 1.35;
input(name="循环小止盈最大R") double ManualCycleTpMaxR = 0.50;

// =========================
// 原版手工智能跟踪
// =========================
input group "原版手工智能跟踪"
input(name="市价/排单智能跟踪模式") bool ManualSmartTracking = true;
input(name="市价开仓止盈后继续循环跟踪排单") bool MarketCycleTracking = true;
input(name="排单开仓止盈后继续循环跟踪排单") bool PendingCycleTracking = true;
input(name="回调N格排单") int ManualTrackPullbackGrids = 1;

// =========================
// 原版动态吸金
// =========================
input group "原版动态吸金"
input(name="动态吸金（仅单边行情使用）") bool DynamicAccumulation = true;
input(name="超过长方形宽度多少开始移动，默认5%") double MoveTriggerWidthPct = 0.05;
input(name="0:跟随价格(默认)，1:跟随EMA") JsaFollowMode FollowMode = FOLLOW_DYNAMIC_BOX;
input(name="EMA/ATR跟踪周期（默认H4）") ENUM_TIMEFRAMES FollowTimeframe = PERIOD_H4;
input(name="跟踪EMA周期（默认8）") int H4EmaPeriod = 8;
input(name="跟踪限制N倍ATR，默认1") double FollowAtrMultiple = 1.0;
input(name="是否均线控制排单") bool EmaFilterOrders = false;
input(name="趋势反转自动退出或删除排单") bool DynamicReverseExit = true;

input group "动态吸金"
input(name="框移动后排单自动重排") bool DynamicRegridPendingOrders = true;
input(name="重载后自动恢复吸金") bool AutoResumeSmartStrategy = true;
input(name="重排触发=网格间距比例") double DynamicRegridGapFraction = 0.10;
input(name="奇数单框内无限做T") bool InfiniteOddRecycle = true;
input(name="停止吸金时保留智能排单") bool KeepSmartPendingOnStop = false;

// =========================
// 原版高价品种 ATR 规则
// =========================
input group "原版高价品种"
input(name="大于1W的品种，间距=1小时ATR的10%") double H1AtrGridPct = 0.10;
input(name="最大网格间距=日线ATR的30%") double D1AtrMaxGridPct = 0.30;
input(name="大于1W的品种，止盈=1小时ATR的10%") double H1AtrOddTpPct = 0.10;

// =========================
// 吸金框
// =========================
input group "吸金框"
input(name="初始框高度(点)") int InitialBoxHeightPoints = 5000;
input(name="框向左显示K线") int BoxBarsLeft = 30;
input(name="现价靠近入场边容许比例") double EntryEdgeTolerancePct = 0.25;

// =========================
// 风控
// =========================
input group "风控"
input(name="触及动态止损边界清仓") bool HardStopEnabled = true;
input(name="风险预算容许误差%") double RiskTolerancePct = 3.0;
input(name="点差过大拒绝新排单") bool SpreadFilter = true;
input(name="最大点差/网格比例") double MaxSpreadToGapRatio = 0.50;
input(name="启用吸筹+手工组合总风险上限") bool EnableCombinedRiskCap = true;
input(name="组合总风险上限倍数（相对生效风险预算）") double CombinedRiskCapMultiplier = 1.00;
input(name="仅TP成交后允许循环回挂") bool RecycleOnlyOnTakeProfit = true;
input(name="部分排单失败时撤销本轮新排单") bool RollbackPartialPendingPlan = true;
input(name="每手往返佣金USD（计入止损风险，0=不计）") double CommissionPerLotRT = 7.0;
input(name="当日最大亏损USD（已实现+浮动，达到后禁止新开仓，0=关闭）") double DailyMaxLossUsd = 0.0;

// =========================
// v1.68 拍卖理论增强（全部可关，关掉=v1.67行为）
// =========================
input group "v1.68 波动自适应 / 止损缓冲"
input(name="黄金等所有品种也按ATR计算网格间距/小止盈") bool AtrAdaptiveAllSymbols = true;
input(name="小止盈=1小时ATR的比例（非高价品种）") double OddTpAtrPct = 0.12;
input(name="小止盈至少=单次交易成本(点差+佣金)的倍数") double OddTpMinCostMultiple = 3.0;
input(name="止损放在框外的缓冲（1小时ATR倍数，0=贴框边）") double SmartStopBufferATR = 0.15;
input(name="硬止损需收盘确认跌破/升破框边（关=碰框边即清仓）") bool HardStopCloseConfirm = true;
input(name="收盘确认周期") ENUM_TIMEFRAMES HardStopConfirmTF = PERIOD_M15;

input group "v1.68 新闻暂停（MT5经济日历）"
input(name="高影响数据前后暂停自动补单/重排/循环") bool NewsPauseEnable = false;
input(name="新闻货币") string NewsCurrency = "USD";
input(name="公布前暂停分钟") int NewsPauseBeforeMin = 15;
input(name="公布后暂停分钟") int NewsPauseAfterMin = 15;
input(name="新闻前撤销未成交吸筹挂单（结束后自动重挂）") bool NewsCancelPending = false;

// =========================
// 管理范围
// =========================
input group "管理范围"
input(name="接管旧版JSA订单") bool AdoptLegacyJsaOrders = true;
input(name="接管当前品种全部订单") bool AdoptAllSymbolOrders = false;

// =========================
// 市场热图 / 多周期共振
// =========================
input group "市场热图/共振"
input(name="显示市场强弱热图") bool ShowMarketHeatmap = true;
input(name="热图周期(已改为当日累计/此项保留兼容)") JsaHeatmapTimeframe HeatmapTimeframe = HEAT_H1;
input(name="显示多周期方向共振") bool ShowMtfConfluence = true;
input(name="共振刷新秒") int ConfluenceRefreshSeconds = 60;
input(name="热图刷新秒") int HeatmapRefreshSeconds = 300;
input(name="热图点击自动切换品种") bool HeatmapClickSwitchSymbol = true;
input(name="有持仓/排单时新图表打开") bool HeatmapSafeOpenNewChart = true;
input(name="偏多/偏空阈值") int DirectionScoreThreshold = 25;
input(name="强共振阈值") int StrongScoreThreshold = 60;

// =========================
// 面板
// =========================
input group "面板"
input(name="面板宽度") int PanelWidth = 430;
input(name="面板顶部偏移") int PanelTopOffset = 95;
input(name="面板左侧偏移") int PanelLeftOffset = 5;
input(name="按钮高度") int ButtonHeight = 32;
input(name="字体大小") int FontSize = 13;

// =========================
// 半自动工具
// =========================
input group "半自动工具"
input(name="一键追踪距离(点)") int ManualTrailPoints = 200;
input(name="底仓成本保护启动(R)") double BaseProtectStartR = 2.0;
input(name="底仓动态跟随启动(R)") double BaseTrailStartR = 2.5;
input(name="动态跟随距离(R)") double BaseTrailDistanceR = 0.5;
input(name="动态跟随步进(R)") double BaseTrailStepR = 0.10;
input(name="保护额外缓冲(点)") int BaseProtectExtraPoints = 20;
input(name="手续费保护倍数") double CommissionProtectMultiplier = 1.0;
input(name="画线止损默认距离(点)") int ManualStopDefaultPoints = 1000;
input(name="手工止损线宽度") int ManualStopLineWidth = 4;
input(name="手工止损线默认错开(点)") int ManualStopVisualOffsetPoints = 80;
input(name="固定仓位(手,0=关闭)") double FixedLotsDefault = 0.0;
input(name="底仓比例") double BasePositionRatioDefault = 0.30;

// =========================
// MT5适配（策略逻辑不变）
// =========================
input group "MT5适配"
input(name="Magic Number") long MagicNumber = 510051;
input(name="最大滑点(点)") int SlippagePoints = 30;
input(name="启用经纪商最小距离/冻结距离检查") bool ValidateBrokerStops = true;
input(name="内置热图已拆分为独立指标（本项保留兼容）") bool EnableFloatingAnalyticsPanel = false;

// =========================
// 小键盘快捷键（需打开NumLock；面板显示时才生效）
// 7多头框 8空头框 9计算吸金 +确认吸金 -停止吸金
// 4画线止损 5计算市价 6确认市价 | 1排单线 2计算排单 3确认排单
// .删除排单 *一键清仓(按两次) /锁仓·解锁(按两次) 0隐藏面板
// =========================
input group "小键盘快捷键"
input(name="启用小键盘快捷键") bool EnableNumpadHotkeys = true;
input(name="危险操作二次确认秒数") int HotkeyConfirmSeconds = 2;

#define ORIGINAL_HIGH_PRICE_THRESHOLD 10000.0
#define PREFIX "智能_"
#define ODD_PREFIX "智能奇_"
#define EVEN_PREFIX "智能偶_"
#define MANUAL_BASE "手工底仓"
#define MANUAL_SPLIT_PREFIX "手工分仓_"
#define LOCK_LABEL "锁仓保护"

#define OBJ_BOX "JSA51_MT5_BOX"
#define OBJ_SMART_STOP "JSA51_MT5_STOP"
#define OBJ_MANUAL_STOP "JSA51_MT5_MANUAL_STOP"
#define OBJ_ENTRY "JSA51_MT5_ENTRY"
#define OBJ_LONG_TP "JSA51_MT5_LONG_TP"
#define OBJ_LONG_SL "JSA51_MT5_LONG_SL"
#define OBJ_SHORT_TP "JSA51_MT5_SHORT_TP"
#define OBJ_SHORT_SL "JSA51_MT5_SHORT_SL"

#define UI_PREFIX "JSA51_MT5_UI_"
#define A_PREFIX  "JSA51_MT5_A_"
#define RESTORE_UI_OBJ "JSA51_MT5_RESTORE_UI"

struct SmartPlanItem
{
   int slot;
   bool odd;
   string comment;
   double price;
   double lots;
   double risk_usd;
   double tp_price;
};

struct ManualEntrySlice
{
   bool is_base;
   bool tracking_seed;
   int index;
   double lots;
   double tp_r;
   double tp_distance;
};

struct ExpireItem
{
   ulong ticket;
   string comment;
   bool odd;
};

struct TfScoreResult
{
   string name;
   double weight;
   double total;
   double ema;
   double macd;
   double rsi;
   double dmi;
   double boll;
   double vwap;
   double vwap_value;
   double vwap_slope;
};

// =========================
// 运行时状态
// =========================
double g_risk_usd;
double g_fixed_lots;
double g_base_ratio;
int g_manual_orders;
int g_smart_orders;
double g_even_rr;

// v1.67.2：手工单数为“最大值”，实际单数按风险与最小手数自适应。
string g_manual_plan_build_reason="";
int g_manual_plan_actual_orders=0;
double g_manual_plan_calc_total_lots=0.0;
JsaTakeProfitMode g_tp_mode=TP_NORMAL;

// v1.66 执行安全：防双击/重复发送
bool g_exec_smart=false;
bool g_exec_manual_market=false;
bool g_exec_manual_pending=false;
ulong g_exec_last_smart=0;          // v1.67.6：真实毫秒计时，无报价时不会一直锁住
ulong g_exec_last_manual_market=0;
ulong g_exec_last_manual_pending=0;


JsaDirection g_direction = DIR_LONG;
bool g_direction_prepared = false;
bool g_running = false;
bool g_paused = false;
bool g_one_key_trailing = false;
bool g_smart_plan_ready = false;
bool g_smart_user_confirmed = false; // 只有用户点击“确认/开始吸金”后才允许任何自动排单/补单/推进
SmartPlanItem g_smart_plan[];

double g_smart_equal_lots = 0.0;
double g_even_batch_tp1=0.0;
double g_even_batch_tp2=0.0;
double g_even_batch_tp3=0.0;
double g_last_regrid_center = 0.0;
datetime g_last_regrid_time = 0;
double g_smart_confirm_box_low = 0.0;
double g_smart_confirm_box_high = 0.0;
double g_smart_trend_extreme = 0.0; // 多头=确认后的最高Ask；空头=确认后的最低Bid
bool g_regrid_busy = false;
bool g_user_stopped_smart = false;

bool g_manual_plan_ready = false;
int g_manual_plan_mode = 0; // 1 market / 2 pending
ENUM_ORDER_TYPE g_manual_plan_type = ORDER_TYPE_BUY;
double g_manual_plan_entry = 0.0;
double g_manual_plan_stop = 0.0;
ManualEntrySlice g_manual_plan[];

bool g_manual_tracking_active = false;
int g_manual_tracking_source_mode = 0; // 1=市价开仓，2=排单开仓
ENUM_ORDER_TYPE g_manual_tracking_type = ORDER_TYPE_BUY;
double g_manual_tracking_initial_stop = 0.0;
double g_manual_tracking_initial_risk = 0.0;
double g_manual_tracking_seed_lots = 0.0;
int g_manual_tracking_cycles = 0;

bool g_analytics_loaded = false;
datetime g_next_analytics_refresh = 0;     // 多周期共振下一次刷新
datetime g_next_heat_refresh = 0;          // 热图下一次刷新
bool g_analytics_busy = false;             // 防止分析重复进入/连续加载
bool g_analytics_custom_moved = false;

// v1.66.6：右下角停靠防抖，避免 CHART_CHANGE -> 重定位 -> CHART_CHANGE 的循环。
long g_analytics_last_chart_w = -1;
long g_analytics_last_chart_h = -1;
bool g_analytics_repositioning = false;

// 统一TP/SL辅助线鼠标跟随状态
bool g_unified_follow_active = false;
string g_unified_follow_name = "";
int g_analytics_x = 0;
int g_analytics_y = 0;

string g_heat_keys[15] = {"XAU","XAG","WTI","BRENT","BTC","NAS","SPX","US30","EUR","GBP","AUD","NZD","CAD","CHF","JPY"};
string g_heat_symbols[15];

// v1.66.5：热图使用“最后有效值缓存”。
// 外部品种短暂未同步时不再把单元格打回 --，避免看起来一直加载/刷新。
double g_heat_cache[15];
bool g_heat_cache_valid[15];
datetime g_heat_last_request[15];

ulong g_suppress_position_ids[];
string g_status = "初始化";
bool g_ui_hidden = false; // 小键盘0/数字0：只隐藏界面，不影响交易逻辑
bool g_info_collapsed = false; // v1.67.3：底部信息/状态区折叠开关
bool g_edit_focus = false;      // 正在面板输入框里打字时屏蔽快捷键
string g_hotkey_pending = "";   // 等待二次确认的危险操作
ulong g_hotkey_pending_ms = 0;
#define JSA_KF_REPEAT 0x4000          // CHARTEVENT_KEYDOWN sparam：按住不放产生的自动重复
#define JSA_MIN_DOUBLE_PRESS_MS 250   // 二次确认至少间隔，过滤“00/000”键连发和手抖

// v1.67.6：吸筹计划实际使用的网格间距与最大槽位，奇数单补回必须按同一套网格。
double g_plan_gap_price=0.0;
int g_plan_slot_max=0;
double g_smart_gap_price=0.0;
int g_smart_slot_max=0;

// v1.68：止损缓冲（价格单位）。计算吸金计划时冻结，运行期间不随ATR变化，避免SL反复被改。
double g_stop_buffer=0.0;
double g_h1atr=0.0; datetime g_h1atr_bar=0;
datetime g_news_check=0; bool g_news_active=false; string g_news_name=""; bool g_news_cancelled=false;

// v1.67.6：运行中拖框防误触，记录上一次合法的框位置。
datetime g_box_t0=0,g_box_t1=0;
double g_box_p0=0.0,g_box_p1=0.0;

// v1.67.6：底仓保护的佣金缓存，避免每Tick扫描历史成交。
ulong g_comm_cache_id[];
double g_comm_cache_val[];
ulong g_comm_cache_ms[];

// v1.64 稳定性：任务ID + 风险快照 + 重载识别
long g_smart_task_id=0;
long g_manual_task_id=0;
double g_snap_risk_budget=0.0;
double g_snap_existing_risk=0.0;
double g_snap_new_risk=0.0;
double g_snap_total_lots=0.0;
double g_snap_stop=0.0;
datetime g_snap_time=0;
bool g_recovery_pending=false; // 重载后只识别，不自动补单/重排
bool g_recover_smart_was_running=false;
bool g_recover_manual_was_active=false;
bool g_recover_onekey_was_on=false;

double g_today_pnl_cache = 0.0;
bool g_today_pnl_loaded = false;

// 前置声明：风控辅助会在多个模块交叉调用。
double SmartRiskNow(int &no_stop);
double ManualRiskNow(int &no_stop);

// =========================
// 基础工具
// =========================
double PointValue()
{
   return SymbolInfoDouble(_Symbol,SYMBOL_POINT);
}

int DigitsValue()
{
   return (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
}

double TickSizeValue()
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) ts=PointValue();
   return MathMax(PointValue(),ts);
}

double NormalizePrice(const double price)
{
   double ts=TickSizeValue();
   double aligned=MathRound(price/ts)*ts;
   return NormalizeDouble(aligned,DigitsValue());
}

double BrokerMinDistance()
{
   if(!ValidateBrokerStops) return 0.0;
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)MathMax(stops,freeze)*PointValue(),TickSizeValue());
}

bool ValidateOrderLevels(ENUM_ORDER_TYPE type,double entry,double sl,double tp,string &reason)
{
   reason="";
   if(!ValidateBrokerStops) return true;
   double minDist=BrokerMinDistance();
   double bid=CurrentBid(), ask=CurrentAsk();
   bool buy=(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);

   if(buy)
   {
      if(sl>0 && entry-sl<minDist-1e-12){ reason=StringFormat("SL距离不足，至少%.1f点",minDist/PointValue()); return false; }
      if(tp>0 && tp-entry<minDist-1e-12){ reason=StringFormat("TP距离不足，至少%.1f点",minDist/PointValue()); return false; }
      if(type==ORDER_TYPE_BUY_LIMIT && ask-entry<minDist-1e-12){ reason="Buy Limit距现价过近"; return false; }
      if(type==ORDER_TYPE_BUY_STOP  && entry-ask<minDist-1e-12){ reason="Buy Stop距现价过近"; return false; }
   }
   else
   {
      if(sl>0 && sl-entry<minDist-1e-12){ reason=StringFormat("SL距离不足，至少%.1f点",minDist/PointValue()); return false; }
      if(tp>0 && entry-tp<minDist-1e-12){ reason=StringFormat("TP距离不足，至少%.1f点",minDist/PointValue()); return false; }
      if(type==ORDER_TYPE_SELL_LIMIT && entry-bid<minDist-1e-12){ reason="Sell Limit距现价过近"; return false; }
      if(type==ORDER_TYPE_SELL_STOP  && bid-entry<minDist-1e-12){ reason="Sell Stop距现价过近"; return false; }
   }
   return true;
}

bool ValidatePositionProtection(ulong ticket,double sl,double tp)
{
   if(!ValidateBrokerStops) return true;
   if(!PositionSelectByTicket(ticket)) return false;
   double minDist=BrokerMinDistance();
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(pt==POSITION_TYPE_BUY)
   {
      double bid=CurrentBid();
      if(sl>0 && bid-sl<minDist-1e-12) return false;
      if(tp>0 && tp-bid<minDist-1e-12) return false;
   }
   else
   {
      double ask=CurrentAsk();
      if(sl>0 && sl-ask<minDist-1e-12) return false;
      if(tp>0 && ask-tp<minDist-1e-12) return false;
   }
   return true;
}

string LastTradeResultText(string prefix)
{
   return StringFormat("%s retcode=%I64u (%s)",prefix,(ulong)trade.ResultRetcode(),trade.ResultRetcodeDescription());
}

double NormalizeLotsDown(double lots)
{
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=minv;
   if(lots<minv) return 0.0;
   lots=MathMin(lots,maxv);
   double n=MathFloor((lots+1e-12)/step)*step;
   int vd=2;
   if(step<0.01) vd=3;
   if(step<0.001) vd=4;
   return NormalizeDouble(n,vd);
}

double CurrentBid()
{
   MqlTick t;
   if(SymbolInfoTick(_Symbol,t)) return t.bid;
   return SymbolInfoDouble(_Symbol,SYMBOL_BID);
}

double CurrentAsk()
{
   MqlTick t;
   if(SymbolInfoTick(_Symbol,t)) return t.ask;
   return SymbolInfoDouble(_Symbol,SYMBOL_ASK);
}

double MidPrice()
{
   return (CurrentBid()+CurrentAsk())*0.5;
}

void RenderMainStatusRows()
{
   // MT5 的 OBJ_LABEL 不会自动换行。v1.67.3 固定拆成最多3行，
   // 避免长状态文字横向/纵向跑出主面板。
   string full="状态: "+g_status;
   int max_chars=36;
   int line_count=3;
   int len=StringLen(full);

   for(int i=0;i<line_count;i++)
   {
      string name=UI_PREFIX+"STATUS_"+IntegerToString(i);
      if(ObjectFind(0,name)<0) continue;

      int start=i*max_chars;
      string part="";
      if(start<len) part=StringSubstr(full,start,max_chars);

      if(i==line_count-1 && len>(i+1)*max_chars)
      {
         int n=StringLen(part);
         if(n>3) part=StringSubstr(part,0,n-3)+"...";
      }
      ObjectSetString(0,name,OBJPROP_TEXT,part);
   }
}

void SetStatus(string text)
{
   g_status=text;
   RenderMainStatusRows();
   ChartRedraw();
}

bool IsHedgingAccount()
{
   long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return mm==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}

string NormalizeToken(string s)
{
   StringToUpper(s);
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      bool ok=((c>=65 && c<=90) || (c>=48 && c<=57));
      if(ok) out+=ShortToString(c);
   }
   return out;
}

bool StartsWith(const string text,const string prefix)
{
   if(StringLen(text)<StringLen(prefix)) return false;
   return StringSubstr(text,0,StringLen(prefix))==prefix;
}

bool Contains(const string text,const string part)
{
   return StringFind(text,part)>=0;
}

bool IsEaFamilyComment(string c)
{
   if(c=="") return false;

   // v1.51 中文订单注释
   if(StartsWith(c,PREFIX) ||
      StartsWith(c,ODD_PREFIX) ||
      StartsWith(c,EVEN_PREFIX) ||
      c==MANUAL_BASE ||
      StartsWith(c,MANUAL_SPLIT_PREFIX) ||
      c==LOCK_LABEL)
      return true;

   // 兼容旧版英文订单注释，升级后不会失去对旧仓位/排单的识别
   if(AdoptLegacyJsaOrders &&
      (StartsWith(c,"JSA") ||
       Contains(c,"_ODD_") ||
       Contains(c,"_EVEN_") ||
       Contains(c,"MANUAL_") ||
       Contains(c,"_LOCK")))
      return true;

   return false;
}

bool IsManagedPositionSelected()
{
   string sym=PositionGetString(POSITION_SYMBOL);
   if(sym!=_Symbol) return false;
   if(AdoptAllSymbolOrders) return true;
   long magic=PositionGetInteger(POSITION_MAGIC);
   string c=PositionGetString(POSITION_COMMENT);
   return magic==MagicNumber || IsEaFamilyComment(c);
}

bool IsManagedOrderSelected()
{
   string sym=OrderGetString(ORDER_SYMBOL);
   if(sym!=_Symbol) return false;
   if(AdoptAllSymbolOrders) return true;
   long magic=OrderGetInteger(ORDER_MAGIC);
   string c=OrderGetString(ORDER_COMMENT);
   return magic==MagicNumber || IsEaFamilyComment(c);
}

bool IsFamilyPositionSelected()
{
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   long magic=PositionGetInteger(POSITION_MAGIC);
   string c=PositionGetString(POSITION_COMMENT);
   return magic==MagicNumber || IsEaFamilyComment(c);
}

bool IsFamilyOrderSelected()
{
   if(OrderGetString(ORDER_SYMBOL)!=_Symbol) return false;
   long magic=OrderGetInteger(ORDER_MAGIC);
   string c=OrderGetString(ORDER_COMMENT);
   return magic==MagicNumber || IsEaFamilyComment(c);
}

bool IsSmartComment(string c)
{
   return StartsWith(c,ODD_PREFIX) || StartsWith(c,EVEN_PREFIX) ||
          Contains(c,"_ODD_") || Contains(c,"_EVEN_");
}

bool IsOddComment(string c)
{
   return StartsWith(c,ODD_PREFIX) || Contains(c,"_ODD_");
}

bool IsEvenComment(string c)
{
   return StartsWith(c,EVEN_PREFIX) || Contains(c,"_EVEN_");
}

bool IsManualSplitComment(string c)
{
   return StartsWith(c,MANUAL_SPLIT_PREFIX) || Contains(c,"MANUAL_SPLIT_");
}

bool IsManualBaseComment(string c)
{
   return c==MANUAL_BASE || Contains(c,"MANUAL_BASE");
}

bool IsManualCycleComment(string c)
{
   return IsManualBaseComment(c) || IsManualSplitComment(c);
}

bool IsManualCyclePositionSelected()
{
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   string c=PositionGetString(POSITION_COMMENT);
   return IsManualCycleComment(c);
}

bool IsManualCycleOrderSelected()
{
   if(OrderGetString(ORDER_SYMBOL)!=_Symbol) return false;
   string c=OrderGetString(ORDER_COMMENT);
   return IsManualCycleComment(c);
}

bool IsLockComment(string c)
{
   return c==LOCK_LABEL || Contains(c,"_LOCK");
}

int ExtractSlot(string c)
{
   // v1.51 中文注释
   if(StartsWith(c,ODD_PREFIX))
      return (int)StringToInteger(StringSubstr(c,StringLen(ODD_PREFIX)));
   if(StartsWith(c,EVEN_PREFIX))
      return (int)StringToInteger(StringSubstr(c,StringLen(EVEN_PREFIX)));

   // 兼容旧版英文注释
   int p=StringFind(c,"_ODD_");
   int len=5;
   if(p<0) { p=StringFind(c,"_EVEN_"); len=6; }
   if(p<0) return -1;
   string tail=StringSubstr(c,p+len);
   return (int)StringToInteger(tail);
}

ENUM_ORDER_TYPE PositionDirectionOrderType(ENUM_POSITION_TYPE pt)
{
   return pt==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

bool IsBuyOrderType(ENUM_ORDER_TYPE t)
{
   return t==ORDER_TYPE_BUY || t==ORDER_TYPE_BUY_LIMIT || t==ORDER_TYPE_BUY_STOP || t==ORDER_TYPE_BUY_STOP_LIMIT;
}

bool IsSellOrderType(ENUM_ORDER_TYPE t)
{
   return t==ORDER_TYPE_SELL || t==ORDER_TYPE_SELL_LIMIT || t==ORDER_TYPE_SELL_STOP || t==ORDER_TYPE_SELL_STOP_LIMIT;
}

bool ModifyPositionTicket(ulong ticket,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   if(!PositionSelectByTicket(ticket)) return false;

   sl=sl>0?NormalizePrice(sl):0.0;
   tp=tp>0?NormalizePrice(tp):0.0;
   if(!ValidatePositionProtection(ticket,sl,tp))
   {
      Print("JSA v1.67.1 保护价修改跳过：票号=",ticket,"｜触及 Stops/Freeze 距离");
      return false;
   }

   req.action=TRADE_ACTION_SLTP;
   req.position=ticket;
   req.symbol=PositionGetString(POSITION_SYMBOL);
   req.sl=sl;
   req.tp=tp;
   bool ok=OrderSend(req,res);
   bool done=ok && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL || res.retcode==TRADE_RETCODE_NO_CHANGES);
   if(!done) Print("JSA v1.67.1 修改保护失败：票号=",ticket," retcode=",res.retcode," comment=",res.comment);
   return done;
}

bool ClosePositionTicket(ulong ticket)
{
   return trade.PositionClose(ticket,SlippagePoints);
}

bool DeleteOrderTicket(ulong ticket)
{
   return trade.OrderDelete(ticket);
}

// =========================
// 交易风险/手数
// =========================
double RiskPerLotAtStop(ENUM_ORDER_TYPE type,double entry,double sl,string symbol="")
{
   if(symbol=="") symbol=_Symbol;
   if(entry<=0 || sl<=0 || MathAbs(entry-sl)<SymbolInfoDouble(symbol,SYMBOL_POINT)) return 0.0;
   ENUM_ORDER_TYPE dir=IsBuyOrderType(type)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double p=0.0;
   if(!OrderCalcProfit(dir,symbol,1.0,entry,sl,p)) return 0.0;
   double loss=MathAbs(p);
   // v1.67.6：止损出场时佣金同样是亏损的一部分，计入“以损定量”。
   if(symbol==_Symbol && CommissionPerLotRT>0) loss+=CommissionPerLotRT;
   return loss;
}

double EffectiveRiskBudgetUsd()
{
   // v1.60：面板“以损定量 USD”点击应用后的 g_risk_usd 是唯一的开仓定量基准。
   // 系统参数中的净值风险只作为安全上限，不再覆盖/重算用户在面板输入的风险。
   double requested=MathMax(0.01,g_risk_usd);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(EnableMaxEquityRiskCap && equity>0 && MaxEquityRiskPct>0)
   {
      double cap=equity*MaxEquityRiskPct/100.0;
      requested=MathMin(requested,cap);
   }

   return MathMax(0.01,requested);
}

double EquityRiskCapUsd()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!EnableMaxEquityRiskCap || equity<=0 || MaxEquityRiskPct<=0)
      return 0.0;

   return equity*MaxEquityRiskPct/100.0;
}

double LotsForRisk(ENUM_ORDER_TYPE type,double entry,double sl,double risk_usd)
{
   double r=RiskPerLotAtStop(type,entry,sl,_Symbol);
   if(r<=0 || risk_usd<=0) return 0.0;
   return NormalizeLotsDown(risk_usd/r);
}

double MoneyAtExit(ENUM_ORDER_TYPE type,double volume,double entry,double exit_price,string symbol="")
{
   if(symbol=="") symbol=_Symbol;
   double p=0;
   ENUM_ORDER_TYPE dir=IsBuyOrderType(type)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(dir,symbol,volume,entry,exit_price,p)) return 0.0;
   return p;
}

double CurrentSmartRisk(int &no_stop)
{
   no_stop=0;
   double risk=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsFamilyPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(!IsSmartComment(c)) continue;
      double sl=PositionGetDouble(POSITION_SL);
      if(sl<=0) { no_stop++; continue; }
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool risk_side=(pt==POSITION_TYPE_BUY ? sl<entry : sl>entry);
      if(!risk_side) continue;
      risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),entry,sl)*vol;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !IsFamilyOrderSelected()) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(!IsSmartComment(c)) continue;
      double sl=OrderGetDouble(ORDER_SL);
      if(sl<=0) { no_stop++; continue; }
      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      double vol=OrderGetDouble(ORDER_VOLUME_CURRENT);
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      risk+=RiskPerLotAtStop(ot,entry,sl)*vol;
   }
   return MathMax(0.0,risk);
}


// v1.55.2【吸金风控层】本EA独立风险池。
// 只统计 Jammy EA 家族订单（本EA Magic / 本EA识别逻辑）的持仓与排单。
// 其他EA、手工单即使同为XAUUSD，也绝不参与“是否允许继续吸金”的风险锁定。
// 注意：这与“风险盈亏统计层”分离；风险盈亏统计仍统计当前品种全部订单。
double CurrentSymbolRiskPool(int &no_stop)
{
   no_stop=0; double risk=0.0;
   // v1.65：只统计吸筹系统（智能奇/智能偶），手工底仓/分仓/循环不占吸筹风险池。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT); if(!IsSmartComment(c)) continue;
      double sl=PositionGetDouble(POSITION_SL); if(sl<=0){no_stop++;continue;}
      double ep=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((pt==POSITION_TYPE_BUY && sl<ep)||(pt==POSITION_TYPE_SELL && sl>ep))
         risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),ep,sl,_Symbol)*vol;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string c=OrderGetString(ORDER_COMMENT); if(!IsSmartComment(c)) continue;
      double sl=OrderGetDouble(ORDER_SL); if(sl<=0){no_stop++;continue;}
      risk+=RiskPerLotAtStop((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE),
                            OrderGetDouble(ORDER_PRICE_OPEN),sl,_Symbol)*OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return MathMax(0.0,risk);
}
double RemainingSymbolRiskBudget(int &no_stop)
{
   double used=CurrentSymbolRiskPool(no_stop);
   if(no_stop>0) return 0.0;
   return MathMax(0.0,EffectiveRiskBudgetUsd()-used);
}

// 仅统计已经成交的吸筹仓风险；动态重排预计算时不能把即将撤掉的旧挂单重复占用预算。
double CurrentSmartPositionRiskPool(int &no_stop)
{
   no_stop=0; double risk=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT); if(!IsSmartComment(c)) continue;
      double sl=PositionGetDouble(POSITION_SL); if(sl<=0){no_stop++;continue;}
      double ep=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((pt==POSITION_TYPE_BUY && sl<ep)||(pt==POSITION_TYPE_SELL && sl>ep))
         risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),ep,sl,_Symbol)*vol;
   }
   return MathMax(0.0,risk);
}

double CombinedRiskCapUsd()
{
   if(!EnableCombinedRiskCap) return 1.0e100;
   return EffectiveRiskBudgetUsd()*MathMax(0.10,CombinedRiskCapMultiplier);
}

double CombinedRiskNow(int &no_stop)
{
   int sns=0,mns=0;
   double sr=SmartRiskNow(sns);
   double mr=ManualRiskNow(mns);
   no_stop=sns+mns;
   return sr+mr;
}

double CombinedRemainingRiskBudget(int &no_stop)
{
   double used=CombinedRiskNow(no_stop);
   if(no_stop>0) return 0.0;
   return MathMax(0.0,CombinedRiskCapUsd()-used);
}

double ManualAvailableRiskBudget(int &no_stop)
{
   int mns=0,sns=0;
   double mr=ManualRiskNow(mns);
   double sr=SmartRiskNow(sns);
   no_stop=mns+sns;
   if(no_stop>0) return 0.0;

   double ownRemain=MathMax(0.0,EffectiveRiskBudgetUsd()-mr);
   if(!EnableCombinedRiskCap) return ownRemain;
   double comboRemain=MathMax(0.0,CombinedRiskCapUsd()-sr-mr);
   return MathMin(ownRemain,comboRemain);
}

double SmartTotalLots()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !IsFamilyPositionSelected()) continue;
      if(IsSmartComment(PositionGetString(POSITION_COMMENT))) total+=PositionGetDouble(POSITION_VOLUME);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !IsFamilyOrderSelected()) continue;
      if(IsSmartComment(OrderGetString(ORDER_COMMENT))) total+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return total;
}

double SmartPositionLots()
{
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !IsFamilyPositionSelected()) continue;
      if(IsSmartComment(PositionGetString(POSITION_COMMENT))) total+=PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

double TotalManagedLots()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !IsManagedPositionSelected()) continue;
      total+=PositionGetDouble(POSITION_VOLUME);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !IsManagedOrderSelected()) continue;
      total+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return total;
}

// =========================
// 指标计算
// =========================
bool LoadRates(string symbol,ENUM_TIMEFRAMES tf,int start_pos,int count,MqlRates &rates[])
{
   ArrayFree(rates);
   ArraySetAsSeries(rates,true);
   int copied=CopyRates(symbol,tf,start_pos,count,rates);
   return copied>0;
}

double CalcATR(string symbol,ENUM_TIMEFRAMES tf,int period,int shift=1)
{
   MqlRates r[];
   if(!LoadRates(symbol,tf,shift,period+2,r)) return 0.0;
   if(ArraySize(r)<period+1) return 0.0;
   double sum=0;
   for(int i=0;i<period;i++)
   {
      double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
      sum+=tr;
   }
   return sum/period;
}

double CalcEMA(string symbol,ENUM_TIMEFRAMES tf,int period,int shift=1)
{
   MqlRates r[];
   int need=MathMax(period*6,period+20);
   if(!LoadRates(symbol,tf,shift,need,r)) return 0.0;
   int n=ArraySize(r);
   if(n<period+2) return 0.0;
   double k=2.0/(period+1.0);
   double ema=r[n-1].close;
   for(int i=n-2;i>=0;i--) ema=r[i].close*k+ema*(1.0-k);
   return ema;
}

double RSIFromRates(MqlRates &r[],int period)
{
   if(ArraySize(r)<period+1) return EMPTY_VALUE;
   double gains=0,losses=0;
   for(int i=period-1;i>=0;i--)
   {
      double d=r[i].close-r[i+1].close;
      if(d>0) gains+=d; else losses-=d;
   }
   if(losses<=0) return 100.0;
   double rs=gains/losses;
   return 100.0-100.0/(1.0+rs);
}

double EMAArrayValue(double &values[],int period)
{
   int n=ArraySize(values);
   if(n==0) return 0.0;
   double k=2.0/(period+1.0);
   double ema=values[0];
   for(int i=1;i<n;i++) ema=values[i]*k+ema*(1.0-k);
   return ema;
}

bool TryMACD(MqlRates &r[],double &macd,double &signal)
{
   int n=ArraySize(r);
   if(n<80) return false;
   int m=MathMin(n,120);
   double c[];
   ArrayResize(c,m);
   for(int i=0;i<m;i++) c[i]=r[m-1-i].close; // chronological
   double e12=EMAArrayValue(c,12);
   double e26=EMAArrayValue(c,26);
   macd=e12-e26;

   double macd_series[];
   ArrayResize(macd_series,m);
   double k12=2.0/13.0,k26=2.0/27.0;
   double a12=c[0],a26=c[0];
   for(int i=0;i<m;i++)
   {
      if(i>0) { a12=c[i]*k12+a12*(1.0-k12); a26=c[i]*k26+a26*(1.0-k26); }
      macd_series[i]=a12-a26;
   }
   signal=EMAArrayValue(macd_series,9);
   return true;
}

bool TryDMI(MqlRates &r[],int period,double &plus_di,double &minus_di)
{
   if(ArraySize(r)<period+2) return false;
   double trsum=0,pdm=0,mdm=0;
   for(int i=period-1;i>=0;i--)
   {
      double up=r[i].high-r[i+1].high;
      double dn=r[i+1].low-r[i].low;
      double p=(up>dn && up>0)?up:0;
      double m=(dn>up && dn>0)?dn:0;
      double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
      trsum+=tr; pdm+=p; mdm+=m;
   }
   if(trsum<=0) return false;
   plus_di=pdm/trsum*100.0;
   minus_di=mdm/trsum*100.0;
   return true;
}

bool TryBoll(MqlRates &r[],int period,double &mid,double &stdv)
{
   if(ArraySize(r)<period) return false;
   double sum=0;
   for(int i=0;i<period;i++) sum+=r[i].close;
   mid=sum/period;
   double ss=0;
   for(int i=0;i<period;i++) { double d=r[i].close-mid; ss+=d*d; }
   stdv=MathSqrt(ss/period);
   return true;
}

datetime VwapAnchor(string tf_name,datetime ref)
{
   MqlDateTime d;
   TimeToStruct(ref,d);
   if(tf_name=="M5" || tf_name=="M15")
   {
      d.hour=0; d.min=0; d.sec=0;
      return StructToTime(d);
   }
   if(tf_name=="H1" || tf_name=="H4")
   {
      d.hour=0; d.min=0; d.sec=0;
      datetime day0=StructToTime(d);
      int dow=d.day_of_week; // 0 Sunday
      int from_monday=(dow+6)%7;
      return day0-from_monday*86400;
   }
   d.day=1; d.hour=0; d.min=0; d.sec=0;
   return StructToTime(d);
}

bool TryAnchoredVWAP(string tf_name,MqlRates &r[],double &vwap,double &prev)
{
   int n=ArraySize(r);
   if(n<2) return false;
   datetime anchor=VwapAnchor(tf_name,r[0].time);
   double pv=0,v=0,pvp=0,vp=0;
   for(int i=0;i<n;i++)
   {
      if(r[i].time<anchor) break;
      double typical=(r[i].high+r[i].low+r[i].close)/3.0;
      double vol=(double)r[i].tick_volume;
      if(vol<=0) vol=1.0;
      pv+=typical*vol; v+=vol;
      if(i>0) { pvp+=typical*vol; vp+=vol; }
   }
   if(v<=0) return false;
   vwap=pv/v;
   prev=vp>0?pvp/vp:vwap;
   return true;
}

double ScoreVWAP(string tf_name,MqlRates &r[],double close,double &vwap,double &slope)
{
   double prev=0;
   if(!TryAnchoredVWAP(tf_name,r,vwap,prev)) return 0;
   slope=vwap-prev;
   double atr=0;
   int n=ArraySize(r);
   if(n>=16)
   {
      for(int i=0;i<14;i++) atr+=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
      atr/=14.0;
   }
   double tol=MathMax(PointValue()*2.0,atr>0?atr*0.08:PointValue()*2.0);
   double st=MathMax(PointValue()*0.5,tol*0.03);
   double dist=close-vwap;
   if(MathAbs(dist)<=tol) return 0;
   if(dist>0) return slope>st?2:1;
   return slope<-st?-2:-1;
}

ENUM_TIMEFRAMES TfByName(string name)
{
   if(name=="M5") return PERIOD_M5;
   if(name=="M15") return PERIOD_M15;
   if(name=="H1") return PERIOD_H1;
   if(name=="H4") return PERIOD_H4;
   return PERIOD_D1;
}

TfScoreResult ScoreTimeframe(string name,double weight)
{
   TfScoreResult x;
   x.name=name; x.weight=weight; x.total=0; x.ema=0; x.macd=0; x.rsi=0; x.dmi=0; x.boll=0; x.vwap=0; x.vwap_value=0; x.vwap_slope=0;
   MqlRates r[];
   if(!LoadRates(_Symbol,TfByName(name),1,600,r) || ArraySize(r)<220) return x;
   double close=r[0].close;

   // EMA20/50 + price vs EMA200 = ±4
   double c[];
   int n=MathMin(ArraySize(r),500);
   ArrayResize(c,n);
   for(int i=0;i<n;i++) c[i]=r[n-1-i].close;
   double e20=EMAArrayValue(c,20),e50=EMAArrayValue(c,50),e200=EMAArrayValue(c,200);
   x.ema+=(e20>e50?2:-2);
   x.ema+=(close>e200?2:-2);

   double m=0,sg=0;
   if(TryMACD(r,m,sg)) x.macd=(m>sg?2:(m<sg?-2:0));

   double rv=RSIFromRates(r,14);
   if(rv!=EMPTY_VALUE) { if(rv>=55) x.rsi=1; else if(rv<=45) x.rsi=-1; }

   double pdi=0,mdi=0;
   if(TryDMI(r,14,pdi,mdi)) { double d=pdi-mdi; if(d>=5)x.dmi=2; else if(d<=-5)x.dmi=-2; }

   double bm=0,bs=0;
   if(TryBoll(r,20,bm,bs) && bs>0) { double z=(close-bm)/bs; if(z>=0.15)x.boll=1; else if(z<=-0.15)x.boll=-1; }

   x.vwap=ScoreVWAP(name,r,close,x.vwap_value,x.vwap_slope);
   double raw=x.ema+x.macd+x.rsi+x.dmi+x.boll+x.vwap;
   x.total=raw/12.0*100.0;
   return x;
}

string ScoreLabel(double score)
{
   double strong=MathMax(DirectionScoreThreshold,StrongScoreThreshold);
   double weak=MathMin(DirectionScoreThreshold,strong);
   if(score>=strong) return "强多";
   if(score>=weak) return "偏多";
   if(score<=-strong) return "强空";
   if(score<=-weak) return "偏空";
   return "中性";
}

// =========================
// 高价品种 ATR / 网格 / TP
// =========================
bool IsHighPriceInstrument()
{
   return MidPrice()>ORIGINAL_HIGH_PRICE_THRESHOLD;
}

double CachedH1ATR()
{
   datetime b=iTime(_Symbol,PERIOD_H1,0);
   if(b!=g_h1atr_bar || g_h1atr<=0) { g_h1atr=CalcATR(_Symbol,PERIOD_H1,14,1); g_h1atr_bar=b; }
   return g_h1atr;
}

// 单次往返交易成本（点）：当前点差 + 往返佣金
double TradeCostPoints()
{
   double pt=PointValue(); if(pt<=0) return 0.0;
   double spread=(CurrentAsk()-CurrentBid())/pt;
   double mpp=MoneyPerPrice(1.0)*pt;
   double comm=(mpp>0 && CommissionPerLotRT>0) ? CommissionPerLotRT/mpp : 0.0;
   return MathMax(0.0,spread)+comm;
}

bool UseAtrAdaptive() { return IsHighPriceInstrument() || AtrAdaptiveAllSymbols; }

double GetGridGapPoints()
{
   if(!UseAtrAdaptive()) return (double)FixedGridGapPoints;
   double h1=CachedH1ATR();
   double d1=CalcATR(_Symbol,PERIOD_D1,14,1);
   if(h1<=0) return FixedGridGapPoints;
   double adaptive=h1*H1AtrGridPct/PointValue();
   if(d1>0) adaptive=MathMin(adaptive,d1*D1AtrMaxGridPct/PointValue());
   return MathMax(1.0,adaptive);
}

double GetOddTpPoints()
{
   if(!UseAtrAdaptive()) return (double)OddTpPoints;
   double h1=CachedH1ATR();
   if(h1<=0) return OddTpPoints;
   double pct=IsHighPriceInstrument() ? H1AtrOddTpPct : OddTpAtrPct;
   double tp=h1*pct/PointValue();
   // v1.68：小止盈至少覆盖若干倍交易成本，避免做T利润被点差+佣金吃掉
   if(!IsHighPriceInstrument() && OddTpMinCostMultiple>0)
      tp=MathMax(tp,TradeCostPoints()*OddTpMinCostMultiple);
   return MathMax(1.0,tp);
}

double EffectiveTpRR(double base_rr,int rank=1)
{
   // v1.67：彻底取消指数型 RR 递增。
   // 旧逻辑 base_rr * multiplier^(rank-1) 会把远端TP推到极端价格。
   // 现在“进阶止盈”只对【吸筹偶数仓组合目标RR】做温和扩展，并受硬上限保护。
   double base=MathMax(0.10,base_rr);
   double hard=MathMax(0.10,SmartPortfolioMaxRR);
   if(g_tp_mode==TP_NORMAL) return MathMin(base,hard);

   double mult=MathMax(1.0,MathMin(2.0,AdvancedRrProgressionMultiplier));
   return MathMin(base*mult,hard);
}

double ManualMaxTpR()
{
   // 面板“目标RR”仍是手工分仓的最终目标上限；再叠加独立硬上限，双保险。
   return MathMax(0.10,MathMin(g_even_rr,MathMax(0.10,ManualHardMaxTpR)));
}

double ManualLayerRR(int rank,int count)
{
   double maxr=ManualMaxTpR();
   double minr=MathMin(maxr,MathMax(0.10,ManualFirstTpR));
   if(count<=1) return maxr;

   double x=(double)(rank-1)/(double)(count-1);
   x=MathMax(0.0,MathMin(1.0,x));

   // 普通模式：起始RR → MaxR 线性分层。
   // 进阶模式：只改变“分层形状”，最大RR仍不突破 MaxR，绝不指数扩张。
   if(g_tp_mode==TP_ADVANCED)
   {
      double curve=MathMax(0.50,MathMin(3.00,ManualAdvancedCurve));
      x=MathPow(x,curve);
   }

   return minr+(maxr-minr)*x;
}

double ManualCycleTpDistance(double riskdist)
{
   double fixedDist=MathMax(PointValue(),GetOddTpPoints()*PointValue());
   double maxByR=MathMax(PointValue(),riskdist*MathMax(0.10,ManualCycleTpMaxR));
   return MathMin(fixedDist,maxByR);
}

bool ValidateManualTpPlan(double entry,ManualEntrySlice &plan[],string &reason)
{
   reason="";
   double riskdist=MathAbs(entry-ManualStopPrice());
   if(riskdist<PointValue()) { reason="止损距离无效"; return false; }

   double hardDist=riskdist*ManualMaxTpR()+PointValue()*2.0;
   double lastRRDist=0.0;
   for(int i=0;i<ArraySize(plan);i++)
   {
      if(plan[i].is_base) continue;
      if(plan[i].tp_distance<=0) { reason=StringFormat("第%d分仓TP距离无效",i); return false; }

      if(plan[i].tracking_seed)
      {
         double seedCap=riskdist*MathMax(0.10,ManualCycleTpMaxR)+PointValue()*2.0;
         if(plan[i].tp_distance>seedCap) { reason="循环小止盈超过安全R上限"; return false; }
         continue;
      }

      if(plan[i].tp_distance>hardDist)
      {
         reason=StringFormat("第%d分仓TP超过%.2fR硬上限",i,ManualMaxTpR());
         return false;
      }
      if(lastRRDist>0 && plan[i].tp_distance+PointValue()<lastRRDist)
      {
         reason="分层TP顺序异常";
         return false;
      }
      lastRRDist=plan[i].tp_distance;
   }
   return true;
}

string TpModeText()
{
   return g_tp_mode==TP_ADVANCED ? "进阶止盈" : "普通止盈";
}

void ToggleTpMode()
{
   g_tp_mode=(g_tp_mode==TP_NORMAL ? TP_ADVANCED : TP_NORMAL);
   g_smart_plan_ready=false;
   g_manual_plan_ready=false;
   if(ObjectFind(0,UI_PREFIX+"TPMODE")>=0)
   {
      ObjectSetString(0,UI_PREFIX+"TPMODE",OBJPROP_TEXT,TpModeText());
      ObjectSetInteger(0,UI_PREFIX+"TPMODE",OBJPROP_BGCOLOR,g_tp_mode==TP_ADVANCED?clrDarkGoldenrod:clrDarkSlateGray);
   }
   SetStatus("止盈模式切换为："+TpModeText()+"｜已有仓位TP不修改，新计划重新计算后生效");
}

double SmartTpDistance(int slot,bool odd,double entry,double stop)
{
   if(odd) return GetOddTpPoints()*PointValue();
   // v1.54 偶数单由分批TP引擎分配；这里仅作安全兜底。
   return MathAbs(entry-stop)*EffectiveTpRR(g_even_rr,MathMax(1,slot/2));
}

bool SpreadAcceptable()
{
   if(!SpreadFilter) return true;
   double gap=MathMax(PointValue(),GetGridGapPoints()*PointValue());
   return (CurrentAsk()-CurrentBid())<=gap*MaxSpreadToGapRatio;
}

// =========================
// 图表对象：吸金框 / 线
// =========================
bool BoxExists()
{
   return ObjectFind(0,OBJ_BOX)>=0;
}

double BoxLow()
{
   if(!BoxExists()) return 0;
   double p0=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,0);
   double p1=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,1);
   return MathMin(p0,p1);
}

double BoxHigh()
{
   if(!BoxExists()) return 0;
   double p0=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,0);
   double p1=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,1);
   return MathMax(p0,p1);
}

double BoxWidth()
{
   return MathMax(PointValue(),BoxHigh()-BoxLow());
}

double LiveStopBuffer()
{
   if(SmartStopBufferATR<=0) return 0.0;
   double a=CachedH1ATR();
   return a>0 ? a*SmartStopBufferATR : 0.0;
}

double StopBuffer() { return g_stop_buffer>0 ? g_stop_buffer : LiveStopBuffer(); }

// 框边（价值区边界）
double BoxEdgeStop() { return g_direction==DIR_LONG?BoxLow():BoxHigh(); }

// v1.68：实际止损 = 框边再往外放一段缓冲，给“扫止损”留空间；手数按此距离计算，总风险不变
double StopPrice()
{
   double b=StopBuffer();
   if(b<=0) return BoxEdgeStop();
   return NormalizePrice(g_direction==DIR_LONG ? BoxLow()-b : BoxHigh()+b);
}

void DrawSmartStop()
{
   if(!BoxExists()) return;
   double p=StopPrice();
   if(ObjectFind(0,OBJ_SMART_STOP)<0) ObjectCreate(0,OBJ_SMART_STOP,OBJ_HLINE,0,0,p);
   ObjectSetDouble(0,OBJ_SMART_STOP,OBJPROP_PRICE,p);
   ObjectSetInteger(0,OBJ_SMART_STOP,OBJPROP_COLOR,clrOrangeRed);
   ObjectSetInteger(0,OBJ_SMART_STOP,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,OBJ_SMART_STOP,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,OBJ_SMART_STOP,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,OBJ_SMART_STOP,OBJPROP_SELECTED,false);
}

void CreateDirectionalBox(JsaDirection dir)
{
   g_direction=dir;
   g_direction_prepared=true;
   g_stop_buffer=0.0;   // 新框：止损缓冲在计算计划时重新冻结
   datetime t2=iTime(_Symbol,_Period,0);
   int bars=Bars(_Symbol,_Period);
   int shift=MathMin(MathMax(1,BoxBarsLeft),MathMax(1,bars-1));
   datetime t1=iTime(_Symbol,_Period,shift);
   double h=InitialBoxHeightPoints*PointValue();
   double low,high;
   if(dir==DIR_LONG) { high=CurrentAsk(); low=high-h; }
   else { low=CurrentBid(); high=low+h; }
   ObjectDelete(0,OBJ_BOX);
   ObjectCreate(0,OBJ_BOX,OBJ_RECTANGLE,0,t1,NormalizePrice(low),t2,NormalizePrice(high));
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_FILL,false);
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_SELECTED,false);
   DrawSmartStop();
   CacheBox();
   g_smart_plan_ready=false;
   g_smart_user_confirmed=false;
   g_smart_confirm_box_low=0.0;
   g_smart_confirm_box_high=0.0;
   g_smart_trend_extreme=0.0;
   g_running=false;
   g_paused=false;
   ArrayResize(g_smart_plan,0);
   SetStatus(dir==DIR_LONG?"多头框已建立：上沿靠现价，下沿拖到拐点":"空头框已建立：下沿靠现价，上沿拖到拐点");
}

bool ValidateBox(string &reason)
{
   reason="";
   if(!BoxExists() || !g_direction_prepared) { reason="请先建立多头框或空头框"; return false; }
   double mid=MidPrice();
   double w=BoxWidth();
   if(w<PointValue()*10) { reason="吸金框过窄"; return false; }
   double tol=MathMax(PointValue()*10,w*EntryEdgeTolerancePct);
   if(g_direction==DIR_LONG)
   {
      if(BoxLow()>=mid) { reason="多头框错误：下沿必须在现价下方"; return false; }
      if(MathAbs(mid-BoxHigh())>tol) { reason="多头框错误：上沿应靠近现价"; return false; }
   }
   else
   {
      if(BoxHigh()<=mid) { reason="空头框错误：上沿必须在现价上方"; return false; }
      if(MathAbs(mid-BoxLow())>tol) { reason="空头框错误：下沿应靠近现价"; return false; }
   }
   return true;
}

void GridLayout(int &count,double &gap_price,double &gap_points)
{
   gap_points=GetGridGapPoints();
   gap_price=MathMax(PointValue(),gap_points*PointValue());
   double width=BoxWidth();
   int fit=MathMax(0,(int)MathFloor(width/gap_price)-1);
   count=MathMin(g_smart_orders,fit);
   if(count<2)
   {
      count=MathMax(2,g_smart_orders);
      gap_price=width/(count+1.0);
      gap_points=gap_price/PointValue();
   }
}

bool EntryInsideRiskBoundary(double price)
{
   if(g_direction==DIR_LONG) return price>StopPrice()+PointValue() && price<BoxHigh()-PointValue();
   return price<StopPrice()-PointValue() && price>BoxLow()+PointValue();
}

bool EmaDirectionAllowed()
{
   if(!EmaFilterOrders) return true;
   double ema=CalcEMA(_Symbol,FollowTimeframe,H4EmaPeriod,1);
   if(ema<=0) return true;
   return g_direction==DIR_LONG ? CurrentBid()>=ema : CurrentAsk()<=ema;
}

bool FollowEmaReversal()
{
   double ema=CalcEMA(_Symbol,FollowTimeframe,H4EmaPeriod,1);
   if(ema<=0) return false;
   return g_direction==DIR_LONG ? CurrentBid()<ema : CurrentAsk()>ema;
}

// =========================
// 智能吸金计划
// =========================
double EqualLotsForPrices(double &prices[],double budget,double existing_lots_override=-1.0)
{
   int n=ArraySize(prices);
   if(n<=0 || budget<=0) return 0;
   double sum_risk_1lot=0;
   ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   for(int i=0;i<n;i++)
   {
      double r=RiskPerLotAtStop(dir,prices[i],StopPrice());
      if(r<=0) return 0;
      sum_risk_1lot+=r;
   }
   if(sum_risk_1lot<=0) return 0;
   double lots=budget/sum_risk_1lot;
   lots=MathMin(lots,MaxLotsPerOrder);
   if(MaxTotalLots>0)
   {
      double existing_lots=(existing_lots_override>=0.0 ? existing_lots_override : SmartTotalLots());
      double remaining_lots=MathMax(0.0,MaxTotalLots-existing_lots);
      lots=MathMin(lots,remaining_lots/n);
   }
   return NormalizeLotsDown(lots);
}

// 根据画框宽度、最小交易手数和账户风险预算，自动决定本次框内能排多少单。
// 原则：
// 1) 先按画框宽度 / 网格间距得到“空间允许的最大单数”；
// 2) 再从最大单数向下试，确保即使每单只用最小手数，总SL风险也不超过账户风险预算；
// 3) 找到可行单数后，再反算统一手数，使总SL风险尽量贴近风险预算但绝不主动超预算。
// SmartGridCount 现在是“上限”，不再强迫一定排满。
bool BuildAdaptiveSmartGrid(double risk_budget,
                            double &prices[],
                            int &slots[],
                            double &lots,
                            double &gap_price,
                            double &gap_points,
                            string &reason,
                            double existing_lots_override=-1.0)
{
   ArrayResize(prices,0);
   ArrayResize(slots,0);
   lots=0.0;
   reason="";

   double width=BoxWidth();
   if(width<=PointValue()*2)
   {
      reason="吸金框过窄，无法建立自适应网格";
      return false;
   }

   double preferred_gap=MathMax(PointValue(),GetGridGapPoints()*PointValue());
   int max_by_width=(int)MathFloor(width/preferred_gap)-1;
   int max_orders=MathMin(MathMax(2,g_smart_orders),MathMax(0,max_by_width));

   // 如果画框较窄，仍允许在框内均匀放置至少2单。
   if(max_orders<2)
      max_orders=MathMin(MathMax(2,g_smart_orders),2);

   int min_orders=MathMax(2,MathMin(AutoSmartMinOrders,max_orders));
   double min_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(min_lot<=0)
   {
      reason="无法读取本品种最小交易手数";
      return false;
   }

   ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);

   // 从最多单数向下寻找风险可承受的方案。
   for(int n=max_orders;n>=min_orders;n--)
   {
      double gp=width/(n+1.0);
      double temp_prices[];
      int temp_slots[];
      ArrayResize(temp_prices,0);
      ArrayResize(temp_slots,0);

      double min_lot_risk=0.0;
      bool valid=true;

      for(int i=1;i<=n;i++)
      {
         double p=g_direction==DIR_LONG ? BoxHigh()-gp*i : BoxLow()+gp*i;
         p=NormalizePrice(p);
         if(!EntryInsideRiskBoundary(p))
         {
            valid=false;
            break;
         }

         double r1=RiskPerLotAtStop(dir,p,StopPrice());
         if(r1<=0)
         {
            valid=false;
            break;
         }

         int k=ArraySize(temp_prices);
         ArrayResize(temp_prices,k+1);
         ArrayResize(temp_slots,k+1);
         temp_prices[k]=p;
         temp_slots[k]=i;
         min_lot_risk+=r1*min_lot;
      }

      if(!valid || ArraySize(temp_prices)<2)
         continue;

      // 单数过多时，即使每单最小手数也会超风险预算，则自动减少单数。
      if(min_lot_risk>risk_budget*(1.0+RiskTolerancePct/100.0)+0.01)
         continue;

      double candidate_lots=EqualLotsForPrices(temp_prices,risk_budget,existing_lots_override);
      if(candidate_lots<min_lot-1e-9)
         continue;

      // 再做一次实际规格后的风险复核。
      double actual_risk=0.0;
      for(int k=0;k<ArraySize(temp_prices);k++)
         actual_risk+=RiskPerLotAtStop(dir,temp_prices[k],StopPrice())*candidate_lots;

      if(actual_risk>risk_budget*(1.0+RiskTolerancePct/100.0)+0.01)
         continue;

      ArrayResize(prices,ArraySize(temp_prices));
      ArrayResize(slots,ArraySize(temp_slots));
      for(int k=0;k<ArraySize(temp_prices);k++)
      {
         prices[k]=temp_prices[k];
         slots[k]=temp_slots[k];
      }

      lots=candidate_lots;
      gap_price=gp;
      gap_points=gp/PointValue();
      return true;
   }

   reason=StringFormat(
      "风险预算不足：当前框宽 %.1f点，在最小手数 %.4f 下连%d单都无法满足 $%.2f 风险预算",
      width/PointValue(),min_lot,min_orders,risk_budget);
   return false;
}


// =========================
// v1.54 偶数单：分批止盈 + 总体RR约束
// 总目标盈利 = 全部偶数单SL总风险 × EvenRR。
// 偶数单按顺序最多分3批，TP1/TP2/TP3按距离权重展开，
// 再统一缩放距离，使最终三批合计盈利接近总体目标。
// =========================
int EffectiveEvenBatchCount(int n)
{
   if(n<=0) return 0;
   return MathMin(MathMin(MathMax(1,EvenTpBatchCount),3),n);
}

int EvenBatchIndexByRank(int rank,int total,int batches)
{
   if(batches<=1) return 1;
   int base=total/batches, rem=total%batches, cur=0;
   for(int b=1;b<=batches;b++)
   {
      int sz=base+(b<=rem?1:0);
      if(rank<cur+sz) return b;
      cur+=sz;
   }
   return batches;
}

double EvenBatchWeight(int b)
{
   double w1=MathMax(0.05,EvenTp1DistanceWeight);
   double w2=MathMax(w1+0.01,EvenTp2DistanceWeight);
   double w3=MathMax(w2+0.01,EvenTp3DistanceWeight);
   if(b<=1) return w1;
   if(b==2) return w2;
   return w3;
}

bool CalcEvenBatchTargets(double &prices[],int &slots[],double lots,double stop,double rr,
                          double &tp1,double &tp2,double &tp3,
                          double &group_risk,double &target_profit,double &actual_profit)
{
   tp1=tp2=tp3=0.0;
   group_risk=target_profit=actual_profit=0.0;
   if(lots<=0 || stop<=0) return false;

   int idxs[]; ArrayResize(idxs,0);
   ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);

   for(int i=0;i<ArraySize(prices);i++)
   {
      if(slots[i]%2!=0) continue;
      double r=RiskPerLotAtStop(dir,prices[i],stop)*lots;
      if(r<=0) continue;
      int n=ArraySize(idxs); ArrayResize(idxs,n+1); idxs[n]=i;
      group_risk+=r;
   }

   int nEven=ArraySize(idxs);
   if(nEven<=0 || group_risk<=0) return false;
   int batches=EffectiveEvenBatchCount(nEven);
   target_profit=group_risk*MathMax(0.1,rr);

   // 各批平均入场价
   double sum1=0,sum2=0,sum3=0; int c1=0,c2=0,c3=0;
   double baseDist=0;
   for(int r=0;r<nEven;r++)
   {
      int i=idxs[r], b=EvenBatchIndexByRank(r,nEven,batches);
      baseDist+=MathAbs(prices[i]-stop);
      if(b==1){sum1+=prices[i];c1++;}
      else if(b==2){sum2+=prices[i];c2++;}
      else {sum3+=prices[i];c3++;}
   }
   baseDist=MathMax(PointValue(),baseDist/nEven);
   double avg1=(c1>0?sum1/c1:0), avg2=(c2>0?sum2/c2:0), avg3=(c3>0?sum3/c3:0);

   // 给定scale后，用最终“批次共同TP”核算组合盈利。
   double lo=0.0001, hi=1.0;
   for(int ex=0;ex<30;ex++)
   {
      double d1=baseDist*EvenBatchWeight(1)*hi;
      double d2=baseDist*EvenBatchWeight(2)*hi;
      double d3=baseDist*EvenBatchWeight(3)*hi;
      double q1=(c1>0?NormalizePrice(g_direction==DIR_LONG?avg1+d1:avg1-d1):0);
      double q2=(c2>0?NormalizePrice(g_direction==DIR_LONG?avg2+d2:avg2-d2):0);
      double q3=(c3>0?NormalizePrice(g_direction==DIR_LONG?avg3+d3:avg3-d3):0);
      double p=0;
      for(int r=0;r<nEven;r++)
      {
         int i=idxs[r], b=EvenBatchIndexByRank(r,nEven,batches);
         double q=(b==1?q1:(b==2?q2:q3)), one=0;
         if(q>0 && OrderCalcProfit(dir,_Symbol,lots,prices[i],q,one) && one>0) p+=one;
      }
      if(p>=target_profit) break;
      hi*=2.0;
   }

   for(int it=0;it<70;it++)
   {
      double mid=(lo+hi)*0.5;
      double d1=baseDist*EvenBatchWeight(1)*mid;
      double d2=baseDist*EvenBatchWeight(2)*mid;
      double d3=baseDist*EvenBatchWeight(3)*mid;
      double q1=(c1>0?NormalizePrice(g_direction==DIR_LONG?avg1+d1:avg1-d1):0);
      double q2=(c2>0?NormalizePrice(g_direction==DIR_LONG?avg2+d2:avg2-d2):0);
      double q3=(c3>0?NormalizePrice(g_direction==DIR_LONG?avg3+d3:avg3-d3):0);
      double p=0;
      for(int r=0;r<nEven;r++)
      {
         int i=idxs[r], b=EvenBatchIndexByRank(r,nEven,batches);
         double q=(b==1?q1:(b==2?q2:q3)), one=0;
         if(q>0 && OrderCalcProfit(dir,_Symbol,lots,prices[i],q,one) && one>0) p+=one;
      }
      if(p<target_profit) lo=mid; else hi=mid;
   }

   double scale=(lo+hi)*0.5;
   if(c1>0) tp1=NormalizePrice(g_direction==DIR_LONG?avg1+baseDist*EvenBatchWeight(1)*scale:avg1-baseDist*EvenBatchWeight(1)*scale);
   if(c2>0) tp2=NormalizePrice(g_direction==DIR_LONG?avg2+baseDist*EvenBatchWeight(2)*scale:avg2-baseDist*EvenBatchWeight(2)*scale);
   if(c3>0) tp3=NormalizePrice(g_direction==DIR_LONG?avg3+baseDist*EvenBatchWeight(3)*scale:avg3-baseDist*EvenBatchWeight(3)*scale);

   for(int r=0;r<nEven;r++)
   {
      int i=idxs[r], b=EvenBatchIndexByRank(r,nEven,batches);
      double q=(b==1?tp1:(b==2?tp2:tp3)), one=0;
      if(q>0 && OrderCalcProfit(dir,_Symbol,lots,prices[i],q,one) && one>0) actual_profit+=one;
   }
   return true;
}


int ExistingSmartPositionCount()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsFamilyPositionSelected()) continue;
      if(IsSmartComment(PositionGetString(POSITION_COMMENT))) n++;
   }
   return n;
}

double ExistingSmartRiskAtNewBoxStop(int &invalid_count)
{
   invalid_count=0;
   double risk=0.0;
   double new_stop=StopPrice();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsFamilyPositionSelected()) continue;
      if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double vol=PositionGetDouble(POSITION_VOLUME);

      bool valid=(pt==POSITION_TYPE_BUY ? new_stop<entry-PointValue() : new_stop>entry+PointValue());
      if(!valid) { invalid_count++; continue; }

      risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),entry,new_stop,_Symbol)*vol;
   }
   return risk;
}

bool AdoptExistingSmartPositionsToNewBox()
{
   double new_stop=NormalizePrice(StopPrice());

   // 第一遍只做合法性/冻结距离预检；任何一笔不允许修改时，不动任何旧仓SL。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsFamilyPositionSelected()) continue;
      if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldsl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      bool valid=(pt==POSITION_TYPE_BUY ? new_stop<entry-TickSizeValue() : new_stop>entry+TickSizeValue());
      if(!valid)
      {
         SetStatus(StringFormat("旧吸筹仓%I64u无法纳入新框：新止损已越过开仓价",ticket));
         return false;
      }
      if(MathAbs(oldsl-new_stop)>TickSizeValue() && !ValidatePositionProtection(ticket,new_stop,tp))
      {
         SetStatus(StringFormat("旧吸筹仓%I64u暂不能改到新框止损：触及Stops/Freeze限制",ticket));
         return false;
      }
   }

   // 第二遍统一修改；若经纪商临时拒绝，直接停止确认，不继续新增风险。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsFamilyPositionSelected()) continue;
      if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;
      double oldsl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      if(MathAbs(oldsl-new_stop)>TickSizeValue() && !ModifyPositionTicket(ticket,new_stop,tp))
      {
         SetStatus(StringFormat("旧吸筹仓%I64u止损更新失败，已阻止新一轮吸筹确认",ticket));
         return false;
      }
   }
   return true;
}

void PrepareSmartPlan()
{
   // 只计算计划，不允许在此阶段产生任何真实订单。
   g_smart_user_confirmed=false;
   g_running=false;
   g_paused=false;
   g_risk_usd=MathMax(1.0,g_risk_usd);
   string reason;
   if(!ValidateBox(reason)) { SetStatus(reason); return; }
   g_stop_buffer=LiveStopBuffer();   // v1.68：冻结本轮止损缓冲

   // v1.61：旧吸筹挂单撤销后，已经成交的吸筹仓位允许进入下一轮新框。
   // 对旧成交仓不再按“旧SL”占用风险，而是先按“新框止损边界”重新核算。
   int pool_no_stop=0;
   double other_pool=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !IsFamilyPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(IsSmartComment(c)) continue;
      double sl=PositionGetDouble(POSITION_SL);
      if(sl<=0){pool_no_stop++;continue;}
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool risk_side=(pt==POSITION_TYPE_BUY?sl<entry:sl>entry);
      if(risk_side) other_pool+=RiskPerLotAtStop(PositionDirectionOrderType(pt),entry,sl,_Symbol)*vol;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0 || !IsFamilyOrderSelected()) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(IsSmartComment(c)) continue;
      double sl=OrderGetDouble(ORDER_SL);
      if(sl<=0){pool_no_stop++;continue;}
      double entry=OrderGetDouble(ORDER_PRICE_OPEN),vol=OrderGetDouble(ORDER_VOLUME_CURRENT);
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      other_pool+=RiskPerLotAtStop(ot,entry,sl,_Symbol)*vol;
   }
   if(pool_no_stop>0)
   {
      SetStatus(StringFormat("本EA风险锁定：存在%d笔非吸筹无止损持仓/排单",pool_no_stop));
      return;
   }

   int invalid_old=0;
   double old_smart_risk=ExistingSmartRiskAtNewBoxStop(invalid_old);
   if(invalid_old>0)
   {
      SetStatus(StringFormat("新框无效：%d笔旧吸筹仓的开仓价已越过新框止损边界",invalid_old));
      return;
   }

   double used_pool=old_smart_risk;

   int manual_no_stop=0;
   double manual_risk=ManualRiskNow(manual_no_stop);
   if(manual_no_stop>0)
   {
      SetStatus(StringFormat("组合风险锁定：存在%d笔手工系统订单无有效SL",manual_no_stop));
      return;
   }

   double own_remaining=MathMax(0.0,EffectiveRiskBudgetUsd()-used_pool);
   double combo_remaining=EnableCombinedRiskCap
      ? MathMax(0.0,CombinedRiskCapUsd()-manual_risk-used_pool)
      : own_remaining;
   double risk_budget=MathMin(own_remaining,combo_remaining);

   if(risk_budget<=0.01)
   {
      SetStatus(StringFormat("吸筹风险已满：旧吸筹$%.2f + 手工$%.2f｜组合上限$%.2f",
                             old_smart_risk,manual_risk,CombinedRiskCapUsd()));
      return;
   }
   if(!EmaDirectionAllowed()) { SetStatus("EMA过滤：当前方向不允许新建吸金计划"); return; }

   // v1.61：已有“成交”的智能吸筹仓允许纳入新框；旧未成交挂单必须先撤销，避免两轮计划混杂。
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0 || !IsFamilyOrderSelected()) continue;
      if(IsSmartComment(OrderGetString(ORDER_COMMENT)))
      {
         SetStatus("仍有上一轮吸筹挂单：请先停止/撤销旧吸筹挂单，再计算新框");
         return;
      }
   }

   double gp=0.0,gpts=0.0;
   double prices[];
   int slots[];
   double lots=0.0;

   if(AutoSmartGridSizing)
   {
      string adaptive_reason;
      if(!BuildAdaptiveSmartGrid(risk_budget,prices,slots,lots,gp,gpts,adaptive_reason))
      {
         SetStatus(adaptive_reason);
         return;
      }
   }
   else
   {
      int count;
      GridLayout(count,gp,gpts);
      ArrayResize(prices,0);
      ArrayResize(slots,0);

      for(int i=1;i<=count;i++)
      {
         double p=g_direction==DIR_LONG ? BoxHigh()-gp*i : BoxLow()+gp*i;
         p=NormalizePrice(p);
         if(!EntryInsideRiskBoundary(p)) continue;

         int n=ArraySize(prices);
         ArrayResize(prices,n+1);
         ArrayResize(slots,n+1);
         prices[n]=p;
         slots[n]=i;
      }

      if(ArraySize(prices)<2)
      {
         SetStatus("当前框内有效网格不足2个");
         return;
      }

      lots=EqualLotsForPrices(prices,risk_budget);
      if(lots<=0)
      {
         SetStatus("总风险过小/订单过多，统一手数低于最小手数");
         return;
      }
   }

   g_plan_gap_price=gp;
   g_plan_slot_max=0;
   for(int si=0;si<ArraySize(slots);si++) g_plan_slot_max=MathMax(g_plan_slot_max,slots[si]);

   g_even_batch_tp1=g_even_batch_tp2=g_even_batch_tp3=0.0;
   double even_group_risk=0.0,even_target_profit=0.0,even_actual_profit=0.0;
   bool even_tp_ok=EvenBatchTakeProfit &&
      CalcEvenBatchTargets(prices,slots,lots,StopPrice(),EffectiveTpRR(g_even_rr,2),
                           g_even_batch_tp1,g_even_batch_tp2,g_even_batch_tp3,
                           even_group_risk,even_target_profit,even_actual_profit);

   ArrayResize(g_smart_plan,ArraySize(prices));
   double total_risk=0,total_lots=0;
   for(int k=0;k<ArraySize(prices);k++)
   {
      int slot=slots[k]; bool odd=(slot%2==1);
      ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      double risk=RiskPerLotAtStop(dir,prices[k],StopPrice())*lots;
      double dist=SmartTpDistance(slot,odd,prices[k],StopPrice());
      double tp=(g_direction==DIR_LONG?prices[k]+dist:prices[k]-dist);
      if(!odd && even_tp_ok)
      {
         int rank=0,totalEven=0;
         for(int z=0;z<ArraySize(slots);z++) if(slots[z]%2==0) totalEven++;
         for(int z=0;z<k;z++) if(slots[z]%2==0) rank++;
         int b=EvenBatchIndexByRank(rank,totalEven,EffectiveEvenBatchCount(totalEven));
         tp=(b==1?g_even_batch_tp1:(b==2?g_even_batch_tp2:g_even_batch_tp3));
      }
      g_smart_plan[k].slot=slot;
      g_smart_plan[k].odd=odd;
      g_smart_plan[k].comment=StringFormat("%s%d",odd?ODD_PREFIX:EVEN_PREFIX,slot);
      g_smart_plan[k].price=prices[k];
      g_smart_plan[k].lots=lots;
      g_smart_plan[k].risk_usd=risk;
      g_smart_plan[k].tp_price=NormalizePrice(tp);
      total_risk+=risk; total_lots+=lots;
   }
   g_smart_equal_lots=lots;
   g_smart_plan_ready=true;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_pct=(eq>0 ? total_risk/eq*100.0 : 0.0);
   double even_real_rr=(even_group_risk>0?even_actual_profit/even_group_risk:0.0);
   double snap_lots=0.0;
   for(int si=0;si<ArraySize(g_smart_plan);si++) snap_lots+=g_smart_plan[si].lots;
   SaveRiskSnapshot(EffectiveRiskBudgetUsd(),used_pool,total_risk,snap_lots,StopPrice());
   SetStatus(StringFormat("吸金待确认：旧成交仓%d笔｜旧吸筹风险$%.2f｜新增%d单 %.4f手｜新增风险$%.2f｜吸筹预算$%.2f",
                          ExistingSmartPositionCount(),used_pool,ArraySize(g_smart_plan),lots,total_risk,EffectiveRiskBudgetUsd()));
}

double SmartRiskNow(int &no_stop)
{
   return CurrentSymbolRiskPool(no_stop);
}

double ManualRiskNow(int &no_stop)
{
   no_stop=0; double risk=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(!(IsManualBaseComment(c)||IsManualSplitComment(c))) continue;
      double sl=PositionGetDouble(POSITION_SL); if(sl<=0){no_stop++;continue;}
      double ep=PositionGetDouble(POSITION_PRICE_OPEN),v=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((pt==POSITION_TYPE_BUY&&sl<ep)||(pt==POSITION_TYPE_SELL&&sl>ep))
         risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),ep,sl,_Symbol)*v;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i); if(tk==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(!IsManualCycleComment(c)) continue;
      double sl=OrderGetDouble(ORDER_SL); if(sl<=0){no_stop++;continue;}
      risk+=RiskPerLotAtStop((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE),
         OrderGetDouble(ORDER_PRICE_OPEN),sl,_Symbol)*OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return MathMax(0.0,risk);
}

double ManagedDirectionalLots()
{
   double lots=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(IsSmartComment(c)||IsManualBaseComment(c)||IsManualSplitComment(c))
         lots+=PositionGetDouble(POSITION_VOLUME);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i); if(tk==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(IsSmartComment(c)||IsManualCycleComment(c))
         lots+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return lots;
}

double FamilyFloatingPnL()
{
   double pl=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      pl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

// v1.67.6：所有“新增风险”的入口共用：非对冲账户、当日亏损达到上限时一律禁止。
bool NewRiskAllowed(string action)
{
   if(!IsHedgingAccount())
   {
      SetStatus(action+"已阻止：当前不是Hedging(对冲)账户，本EA多订单/锁仓/硬止损逻辑无法正常工作");
      return false;
   }
   if(DailyMaxLossUsd>0)
   {
      double day=LoadTodayPnL()+FamilyFloatingPnL();
      if(day<=-DailyMaxLossUsd)
      {
         SetStatus(StringFormat("%s已阻止：今日亏损$%.2f（含浮动）已达上限$%.2f",action,-day,DailyMaxLossUsd));
         return false;
      }
   }
   return true;
}

bool ExecutionSafetyCheck(string action,double add_lots=0.0,string family="")
{
   if(!NewRiskAllowed(action)) return false;
   int sns=0,mns=0;
   SmartRiskNow(sns); ManualRiskNow(mns);
   int bad_sl=(family=="S" ? sns : ((family=="M" || family=="P") ? mns : sns+mns));
   if(bad_sl>0)
   {
      SetStatus(StringFormat("%s已阻止：本系统检测到%d个受管订单无有效SL，请先处理",action,bad_sl));
      return false;
   }
   if(ManagedDirectionalLots()+MathMax(0.0,add_lots)>MaxTotalLots+1e-9)
   {
      SetStatus(StringFormat("%s已阻止：预计总手数%.3f超过上限%.3f",action,
         ManagedDirectionalLots()+MathMax(0.0,add_lots),MaxTotalLots));
      return false;
   }
   return true;
}

bool AcquireExecutionLock(string kind)
{
   ulong now=GetTickCount64();
   if(kind=="S")
   {
      if(g_exec_smart || (g_exec_last_smart>0 && now-g_exec_last_smart<2000)){ SetStatus("吸筹确认处理中，请勿重复点击"); return false; }
      g_exec_smart=true; g_exec_last_smart=now; return true;
   }
   if(kind=="M")
   {
      if(g_exec_manual_market || (g_exec_last_manual_market>0 && now-g_exec_last_manual_market<2000)){ SetStatus("市价开仓处理中，请勿重复点击"); return false; }
      g_exec_manual_market=true; g_exec_last_manual_market=now; return true;
   }
   if(g_exec_manual_pending || (g_exec_last_manual_pending>0 && now-g_exec_last_manual_pending<2000)){ SetStatus("排单确认处理中，请勿重复点击"); return false; }
   g_exec_manual_pending=true; g_exec_last_manual_pending=now; return true;
}
void ReleaseExecutionLock(string kind)
{
   if(kind=="S") g_exec_smart=false;
   else if(kind=="M") g_exec_manual_market=false;
   else g_exec_manual_pending=false;
}

bool PlaceSmartOrder(string comment,int slot,bool odd,double price,double lots)
{
   if(!NewRiskAllowed("吸筹下单")) return false;
   if(!SpreadAcceptable()) { SetStatus("点差过大，暂不新增排单"); return false; }
   if(EmaFilterOrders && !EmaDirectionAllowed()) return false;
   double sl=NormalizePrice(StopPrice());
   price=NormalizePrice(price);
   if(!EntryInsideRiskBoundary(price)) return false;

   int no_stop=0; double used=CurrentSymbolRiskPool(no_stop);
   if(no_stop>0) { SetStatus("本EA风险锁定：本EA存在无止损持仓/排单"); return false; }
   ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   double candidate=RiskPerLotAtStop(dir,price,sl)*lots;
   if(used+candidate>EffectiveRiskBudgetUsd()*(1.0+RiskTolerancePct/100.0)+0.01)
   { SetStatus("风险预算不足，停止新增网格"); return false; }

   int mns=0; double manualRisk=ManualRiskNow(mns);
   if(mns>0) { SetStatus("组合风险锁定：手工系统存在无SL订单"); return false; }
   if(EnableCombinedRiskCap && used+candidate+manualRisk>CombinedRiskCapUsd()*(1.0+RiskTolerancePct/100.0)+0.01)
   { SetStatus("组合总风险上限不足，停止新增网格"); return false; }

   if(SmartTotalLots()+lots>MaxTotalLots+1e-9) { SetStatus("达到最大总手数"); return false; }
   double dist=SmartTpDistance(slot,odd,price,sl);
   double tp=NormalizePrice(g_direction==DIR_LONG?price+dist:price-dist);
   for(int pi=0;pi<ArraySize(g_smart_plan);pi++)
   {
      if(g_smart_plan[pi].slot==slot && g_smart_plan[pi].tp_price>0)
      {
         tp=NormalizePrice(g_smart_plan[pi].tp_price);
         break;
      }
   }

   datetime expiration=0; // 由EA按K线数自行过期
   bool ok=false;
   ENUM_ORDER_TYPE actualType=dir;
   double validateEntry=price;
   if(g_direction==DIR_LONG)
   {
      if(MathAbs(price-CurrentAsk())<=PointValue()*2){ actualType=ORDER_TYPE_BUY; validateEntry=CurrentAsk(); }
      else if(price<CurrentAsk()) actualType=ORDER_TYPE_BUY_LIMIT;
      else actualType=ORDER_TYPE_BUY_STOP;
   }
   else
   {
      if(MathAbs(price-CurrentBid())<=PointValue()*2){ actualType=ORDER_TYPE_SELL; validateEntry=CurrentBid(); }
      else if(price>CurrentBid()) actualType=ORDER_TYPE_SELL_LIMIT;
      else actualType=ORDER_TYPE_SELL_STOP;
   }

   string levelReason="";
   if(!ValidateOrderLevels(actualType,validateEntry,sl,tp,levelReason))
   {
      SetStatus(StringFormat("槽位%d已阻止：%s",slot,levelReason));
      return false;
   }

   if(actualType==ORDER_TYPE_BUY) ok=trade.Buy(lots,_Symbol,0,sl,tp,comment);
   else if(actualType==ORDER_TYPE_BUY_LIMIT) ok=trade.BuyLimit(lots,price,_Symbol,sl,tp,ORDER_TIME_GTC,expiration,comment);
   else if(actualType==ORDER_TYPE_BUY_STOP) ok=trade.BuyStop(lots,price,_Symbol,sl,tp,ORDER_TIME_GTC,expiration,comment);
   else if(actualType==ORDER_TYPE_SELL) ok=trade.Sell(lots,_Symbol,0,sl,tp,comment);
   else if(actualType==ORDER_TYPE_SELL_LIMIT) ok=trade.SellLimit(lots,price,_Symbol,sl,tp,ORDER_TIME_GTC,expiration,comment);
   else if(actualType==ORDER_TYPE_SELL_STOP) ok=trade.SellStop(lots,price,_Symbol,sl,tp,ORDER_TIME_GTC,expiration,comment);

   if(!ok)
      Print("JSA v1.67.1 槽位",slot,"下单失败｜",LastTradeResultText(comment));
   return ok;
}

void ConfirmSmartPlan()
{
   if(!AcquireExecutionLock("S")) return;
   if(!g_smart_plan_ready || ArraySize(g_smart_plan)==0){ SetStatus("请先计算吸筹计划"); ReleaseExecutionLock("S"); return; }

   double addlots=0.0, planrisk=0.0;
   for(int i=0;i<ArraySize(g_smart_plan);i++){ addlots+=g_smart_plan[i].lots; planrisk+=g_smart_plan[i].risk_usd; }

   int ns=0,mns=0;
   double live=SmartRiskNow(ns);
   double manualRisk=ManualRiskNow(mns);
   double projectedSmart=MathMax(live,g_snap_existing_risk)+planrisk;
   double projectedCombined=projectedSmart+manualRisk;

   if(!ExecutionSafetyCheck("吸筹确认",addlots,"S") || ns>0 || mns>0 ||
      projectedSmart>EffectiveRiskBudgetUsd()*(1.0+RiskTolerancePct/100.0)+0.01 ||
      (EnableCombinedRiskCap && projectedCombined>CombinedRiskCapUsd()*(1.0+RiskTolerancePct/100.0)+0.01))
   {
      if(ns==0 && mns==0 && projectedSmart>EffectiveRiskBudgetUsd()*(1.0+RiskTolerancePct/100.0)+0.01)
         SetStatus(StringFormat("吸筹确认已阻止：预计吸筹风险$%.2f > 预算$%.2f",projectedSmart,EffectiveRiskBudgetUsd()));
      else if(ns==0 && mns==0 && EnableCombinedRiskCap && projectedCombined>CombinedRiskCapUsd()*(1.0+RiskTolerancePct/100.0)+0.01)
         SetStatus(StringFormat("吸筹确认已阻止：组合风险$%.2f > 总上限$%.2f",projectedCombined,CombinedRiskCapUsd()));
      ReleaseExecutionLock("S"); return;
   }

   // 下单前逐槽做一次 Broker Stops/Freeze 预检，避免先进入运行态再发现价格不合法。
   for(int i=0;i<ArraySize(g_smart_plan);i++)
   {
      double price=NormalizePrice(g_smart_plan[i].price);
      double sl=NormalizePrice(StopPrice());
      double tp=NormalizePrice(g_smart_plan[i].tp_price);
      ENUM_ORDER_TYPE ot;
      double validateEntry=price;
      if(g_direction==DIR_LONG)
      {
         if(MathAbs(price-CurrentAsk())<=PointValue()*2){ ot=ORDER_TYPE_BUY; validateEntry=CurrentAsk(); }
         else if(price<CurrentAsk()) ot=ORDER_TYPE_BUY_LIMIT;
         else ot=ORDER_TYPE_BUY_STOP;
      }
      else
      {
         if(MathAbs(price-CurrentBid())<=PointValue()*2){ ot=ORDER_TYPE_SELL; validateEntry=CurrentBid(); }
         else if(price>CurrentBid()) ot=ORDER_TYPE_SELL_LIMIT;
         else ot=ORDER_TYPE_SELL_STOP;
      }
      string why="";
      if(!ValidateOrderLevels(ot,validateEntry,sl,tp,why))
      {
         SetStatus(StringFormat("吸筹确认已阻止：第%d槽 %s",g_smart_plan[i].slot,why));
         ReleaseExecutionLock("S"); return;
      }
   }

   if(!AdoptExistingSmartPositionsToNewBox())
   {
      ReleaseExecutionLock("S");
      return;
   }

   g_user_stopped_smart=false; g_smart_user_confirmed=true; g_running=true; g_paused=false;
   g_smart_confirm_box_low=BoxLow(); g_smart_confirm_box_high=BoxHigh();
   g_smart_trend_extreme=(g_direction==DIR_LONG ? CurrentAsk() : CurrentBid());
   SetSmartGrid(g_plan_gap_price,g_plan_slot_max);
   GlobalVariableSet(StableGV("SBF"),g_stop_buffer);
   CacheBox();

   BeginSmartTask();
   SaveTaskSnapshot("S",g_smart_task_id,g_snap_risk_budget,g_snap_existing_risk,g_snap_new_risk,g_snap_total_lots,g_snap_stop);
   AdoptExistingSmartPositionsToCurrentTask();
   g_recovery_pending=false;

   int expected=ArraySize(g_smart_plan);
   int ok=0;
   for(int i=0;i<expected;i++)
      if(PlaceSmartOrder(g_smart_plan[i].comment,g_smart_plan[i].slot,g_smart_plan[i].odd,g_smart_plan[i].price,g_smart_plan[i].lots)) ok++;

   g_smart_plan_ready=false; ArrayResize(g_smart_plan,0);
   if(ok<=0)
   {
      g_smart_user_confirmed=false; g_running=false; g_paused=true;
      SaveRecoveryRuntimeState();
      SetStatus("确认失败：没有成功建立吸筹订单，请重新计算后确认");
      ReleaseExecutionLock("S"); return;
   }
   if(ok<expected)
   {
      // 市场单可能已经成交，不做强制反向平仓；未成交的新智能排单全部撤销，避免残缺计划继续扩大风险。
      CancelSmartPending();
      g_smart_user_confirmed=false; g_running=false; g_paused=true;
      SaveRecoveryRuntimeState();
      SetStatus(StringFormat("吸筹部分执行：成功%d/%d｜未成交新排单已撤销｜系统已暂停，请检查成交仓后重新计算",ok,expected));
      ReleaseExecutionLock("S"); return;
   }

   int afterNS=0; double actual=SmartRiskNow(afterNS);
   SaveRecoveryRuntimeState();
   SetStatus(StringFormat("已确认启动：%d/%d槽位｜实际吸筹风险$%.2f / 预算$%.2f｜组合上限$%.2f",
                          ok,expected,actual,EffectiveRiskBudgetUsd(),CombinedRiskCapUsd()));
   ReleaseExecutionLock("S");
}

bool SmartSlotOccupied(int slot,bool odd)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(ExtractSlot(c)==slot && (odd?IsOddComment(c):IsEvenComment(c))) return true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsFamilyOrderSelected()) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(ExtractSlot(c)==slot && (odd?IsOddComment(c):IsEvenComment(c))) return true;
   }
   return false;
}

bool SmartSlotPositionOccupied(int slot,bool odd)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(ExtractSlot(c)==slot && (odd?IsOddComment(c):IsEvenComment(c))) return true;
   }
   return false;
}

void RearmOddSlot(string old_comment)
{
   if(g_recovery_pending) return; // v1.65 重载后禁止自动吸筹补挂
   if(NewsBlocked("奇数补单")) return;

   if(!g_smart_user_confirmed) return;
   if(!g_running || g_paused || !InfiniteOddRecycle || !BoxExists()) return;
   int slot=ExtractSlot(old_comment);
   if(slot<1 || SmartSlotOccupied(slot,true)) return;
   // v1.67.6：按本轮计划实际网格补回原槽位；自适应网格的间距≠固定间距。
   double gp=g_smart_gap_price; int maxSlot=g_smart_slot_max;
   if(gp<=0 || maxSlot<=0) { int count; double gpts; GridLayout(count,gp,gpts); maxSlot=count; }
   if(slot>maxSlot) return;
   double target=g_direction==DIR_LONG?BoxHigh()-gp*slot:BoxLow()+gp*slot;
   target=NormalizePrice(target);
   if(!EntryInsideRiskBoundary(target)) return;
   int no_stop=0; double used=CurrentSymbolRiskPool(no_stop);
   if(no_stop>0) { SetStatus("奇数循环暂停：本EA存在无止损风险"); return; }
   double rem=MathMax(0.0,EffectiveRiskBudgetUsd()-used);
   int mns=0; double manualRisk=ManualRiskNow(mns);
   if(mns>0) { SetStatus("奇数循环暂停：手工系统存在无SL订单"); return; }
   if(EnableCombinedRiskCap) rem=MathMin(rem,MathMax(0.0,CombinedRiskCapUsd()-used-manualRisk));
   ENUM_ORDER_TYPE dir=(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   double maxlots=LotsForRisk(dir,target,StopPrice(),rem);
   double lots=g_smart_equal_lots>0?MathMin(g_smart_equal_lots,maxlots):maxlots;
   lots=NormalizeLotsDown(lots);
   if(lots<=0) { SetStatus("奇数循环暂停：剩余风险不足"); return; }
   string c=StringFormat("%s%d",ODD_PREFIX,slot);
   if(PlaceSmartOrder(c,slot,true,target,lots))
      SetStatus(StringFormat("框内吸金循环：第%d槽原位补回 @ %.*f｜框不后退、不整体重排",slot,DigitsValue(),target));
}

// v1.68：高影响数据公布前后窗口（MT5经济日历，30秒缓存）
bool NewsWindowActive()
{
   if(!NewsPauseEnable) return false;
   datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
   if(g_news_check>0 && now-g_news_check<30) return g_news_active;
   g_news_check=now; g_news_active=false; g_news_name="";
   MqlCalendarValue v[];
   int n=CalendarValueHistory(v,now-MathMax(0,NewsPauseAfterMin)*60,now+MathMax(0,NewsPauseBeforeMin)*60,NULL,NewsCurrency);
   for(int i=0;i<n;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(v[i].event_id,ev) || ev.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
      g_news_active=true;
      g_news_name=ev.name+" "+TimeToString(v[i].time,TIME_MINUTES);
      break;
   }
   return g_news_active;
}

bool NewsBlocked(string action)
{
   if(!NewsWindowActive()) return false;
   string msg=action+"暂停：高影响数据 "+g_news_name+" 前后";
   if(g_status!=msg) SetStatus(msg);
   return true;
}

// 每秒调用：新闻前可选撤销吸筹挂单；新闻窗口结束后按当前框补齐/重挂
// （窗口内被暂停的奇数补单、过期补单都在这里一次性补回）
bool g_news_was_active=false;
void NewsGuardTick()
{
   if(!NewsPauseEnable) return;
   bool active=NewsWindowActive();
   bool running=(g_smart_user_confirmed && g_running && !g_paused);
   if(active && running && NewsCancelPending && !g_news_cancelled)
   {
      CancelSmartPending();
      g_news_cancelled=true;
      SetStatus("新闻前已撤销未成交吸筹挂单："+g_news_name+"｜结束后自动重挂");
   }
   if(!active && g_news_was_active)
   {
      g_news_cancelled=false;
      if(running) RebuildPendingGrid(true);
   }
   g_news_was_active=active;
}

void SetSmartGrid(double gap_price,int slot_max)
{
   g_smart_gap_price=gap_price;
   g_smart_slot_max=slot_max;
   GlobalVariableSet(StableGV("GAP"),gap_price);
   GlobalVariableSet(StableGV("SMX"),(double)slot_max);
   // v1.68.1：方向和统一手数也要记住，否则重载后空头任务会被当成多头、补单手数失控
   GlobalVariableSet(StableGV("DIR"),(double)g_direction);
   GlobalVariableSet(StableGV("EQL"),g_smart_equal_lots);
}

// 从现有吸筹持仓/挂单推断方向：只有买单=多头，只有卖单=空头，否则返回false
bool InferSmartDirection(JsaDirection &dir)
{
   int buy=0,sell=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buy++; else sell++;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if(!IsSmartComment(OrderGetString(ORDER_COMMENT))) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(IsBuyOrderType(ot)) buy++; else if(IsSellOrderType(ot)) sell++;
   }
   if(buy>0 && sell==0) { dir=DIR_LONG;  return true; }
   if(sell>0 && buy==0) { dir=DIR_SHORT; return true; }
   return false;
}

void CacheBox()
{
   if(!BoxExists()) return;
   g_box_t0=(datetime)ObjectGetInteger(0,OBJ_BOX,OBJPROP_TIME,0);
   g_box_t1=(datetime)ObjectGetInteger(0,OBJ_BOX,OBJPROP_TIME,1);
   g_box_p0=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,0);
   g_box_p1=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,1);
}

void RestoreCachedBox()
{
   if(!BoxExists() || g_box_p0<=0 || g_box_p1<=0) return;
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_TIME,0,g_box_t0);
   ObjectSetInteger(0,OBJ_BOX,OBJPROP_TIME,1,g_box_t1);
   ObjectSetDouble(0,OBJ_BOX,OBJPROP_PRICE,0,g_box_p0);
   ObjectSetDouble(0,OBJ_BOX,OBJPROP_PRICE,1,g_box_p1);
   DrawSmartStop();
}

// 止损边界必须仍在现价外侧，否则下一Tick就会触发硬止损清仓。
bool BoxStopSafeNow()
{
   double gap=MathMax(BrokerMinDistance(),TickSizeValue());
   return g_direction==DIR_LONG ? BoxLow()<CurrentBid()-gap : BoxHigh()>CurrentAsk()+gap;
}

void CancelSmartPending()
{
   ulong tickets[]; ArrayResize(tickets,0);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsFamilyOrderSelected()) continue;
      if(IsSmartComment(OrderGetString(ORDER_COMMENT))) { int n=ArraySize(tickets); ArrayResize(tickets,n+1); tickets[n]=t; }
   }
   for(int i=0;i<ArraySize(tickets);i++) DeleteOrderTicket(tickets[i]);
}

void RebuildPendingGrid(bool force=false)
{
   // 未经过用户确认，任何来源（Timer / 拖框 / Tick）都禁止真实排单。
   if(!g_smart_user_confirmed) return;
   if(!g_running || g_paused || !DynamicRegridPendingOrders || !BoxExists() || g_regrid_busy) return;

   int count; double old_gp,old_gpts;
   GridLayout(count,old_gp,old_gpts);
   double center=(BoxLow()+BoxHigh())*0.5;
   double threshold=MathMax(PointValue(),old_gp*DynamicRegridGapFraction);
   if(!force && g_last_regrid_time>0 && TimeCurrent()-g_last_regrid_time<1) return;
   if(!force && g_last_regrid_center!=0 && MathAbs(center-g_last_regrid_center)<threshold) return;

   if(NewsBlocked("动态推进"))
   {
      g_last_regrid_center=center; g_last_regrid_time=TimeCurrent();
      return;   // 旧排单保持不动
   }
   if(!NewRiskAllowed("动态推进"))
   {
      g_last_regrid_center=center; g_last_regrid_time=TimeCurrent();
      return; // 旧排单保持不动
   }

   g_regrid_busy=true;

   // v1.67.1 两阶段重排：先按“成交仓风险/手数”完整计算新计划，确认可执行后才撤旧挂单。
   int no_stop=0,mns=0;
   double used=CurrentSmartPositionRiskPool(no_stop);
   double manualRisk=ManualRiskNow(mns);
   if(no_stop>0 || mns>0)
   {
      g_regrid_busy=false;
      SetStatus("动态推进暂停：吸筹/手工系统存在无有效SL订单");
      return;
   }

   double budget=EffectiveRiskBudgetUsd();
   double ownRemain=MathMax(0.0,budget-used);
   double comboRemain=EnableCombinedRiskCap ? MathMax(0.0,CombinedRiskCapUsd()-used-manualRisk) : ownRemain;
   double remaining=MathMin(ownRemain,comboRemain);
   if(remaining<=0.01)
   {
      g_last_regrid_center=center; g_last_regrid_time=TimeCurrent(); g_regrid_busy=false;
      SetStatus(StringFormat("动态推进等待：风险池已满｜吸筹$%.2f 手工$%.2f 组合上限$%.2f",used,manualRisk,CombinedRiskCapUsd()));
      return;
   }

   double prices[]; int slots[]; double lots=0.0; double gp=0.0,gpts=0.0;
   double existingLots=SmartPositionLots();

   if(AutoSmartGridSizing)
   {
      string why="";
      if(!BuildAdaptiveSmartGrid(remaining,prices,slots,lots,gp,gpts,why,existingLots))
      {
         g_last_regrid_center=center; g_last_regrid_time=TimeCurrent(); g_regrid_busy=false;
         SetStatus("动态推进等待："+why+"｜旧排单保持不动");
         return;
      }
   }
   else
   {
      GridLayout(count,gp,gpts);
      ArrayResize(prices,0); ArrayResize(slots,0);
      for(int slot=1;slot<=count;slot++)
      {
         bool odd=(slot%2==1);
         if(SmartSlotPositionOccupied(slot,odd)) continue;
         double p=g_direction==DIR_LONG ? BoxHigh()-gp*slot : BoxLow()+gp*slot;
         p=NormalizePrice(p);
         if(!EntryInsideRiskBoundary(p)) continue;
         int n=ArraySize(prices); ArrayResize(prices,n+1); ArrayResize(slots,n+1);
         prices[n]=p; slots[n]=slot;
      }
      if(ArraySize(prices)>0) lots=EqualLotsForPrices(prices,remaining,existingLots);
   }

   // 旧未成交挂单不会阻挡新方案；只排除已经成交占用的槽位。
   double filtered_prices[]; int filtered_slots[];
   ArrayResize(filtered_prices,0); ArrayResize(filtered_slots,0);
   for(int k=0;k<ArraySize(prices);k++)
   {
      int slot=slots[k]; bool odd=(slot%2==1);
      if(SmartSlotPositionOccupied(slot,odd)) continue;
      int n=ArraySize(filtered_prices); ArrayResize(filtered_prices,n+1); ArrayResize(filtered_slots,n+1);
      filtered_prices[n]=prices[k]; filtered_slots[n]=slot;
   }

   if(ArraySize(filtered_prices)<=0)
   {
      g_last_regrid_center=center; g_last_regrid_time=TimeCurrent(); g_regrid_busy=false;
      SetStatus("动态推进等待：没有可新增槽位｜旧排单保持不动");
      return;
   }

   lots=EqualLotsForPrices(filtered_prices,remaining,existingLots);
   if(lots<=0)
   {
      g_last_regrid_center=center; g_last_regrid_time=TimeCurrent(); g_regrid_busy=false;
      SetStatus("动态推进等待：最小手数超过剩余风险｜旧排单保持不动");
      return;
   }

   g_even_batch_tp1=g_even_batch_tp2=g_even_batch_tp3=0.0;
   double evenRisk=0.0,evenTarget=0.0,evenProfit=0.0;
   bool evenOk=EvenBatchTakeProfit &&
      CalcEvenBatchTargets(filtered_prices,filtered_slots,lots,StopPrice(),EffectiveTpRR(g_even_rr,2),
                           g_even_batch_tp1,g_even_batch_tp2,g_even_batch_tp3,evenRisk,evenTarget,evenProfit);

   ArrayResize(g_smart_plan,ArraySize(filtered_prices));
   int totalEven=0; for(int z=0;z<ArraySize(filtered_slots);z++) if(filtered_slots[z]%2==0) totalEven++;

   double projectedRisk=0.0;
   for(int k=0;k<ArraySize(filtered_prices);k++)
   {
      int slot=filtered_slots[k]; bool odd=(slot%2==1); double p=filtered_prices[k];
      double dist=SmartTpDistance(slot,odd,p,StopPrice());
      double tp=(g_direction==DIR_LONG ? p+dist : p-dist);
      if(!odd && evenOk)
      {
         int rank=0; for(int z=0;z<k;z++) if(filtered_slots[z]%2==0) rank++;
         int b=EvenBatchIndexByRank(rank,totalEven,EffectiveEvenBatchCount(totalEven));
         tp=(b==1 ? g_even_batch_tp1 : (b==2 ? g_even_batch_tp2 : g_even_batch_tp3));
      }
      g_smart_plan[k].slot=slot; g_smart_plan[k].odd=odd;
      g_smart_plan[k].comment=StringFormat("%s%d",odd?ODD_PREFIX:EVEN_PREFIX,slot);
      g_smart_plan[k].price=NormalizePrice(p); g_smart_plan[k].lots=lots;
      g_smart_plan[k].risk_usd=RiskPerLotAtStop(g_direction==DIR_LONG?ORDER_TYPE_BUY:ORDER_TYPE_SELL,p,StopPrice())*lots;
      g_smart_plan[k].tp_price=NormalizePrice(tp);
      projectedRisk+=g_smart_plan[k].risk_usd;
   }

   if(used+projectedRisk>budget*(1.0+RiskTolerancePct/100.0)+0.01 ||
      (EnableCombinedRiskCap && used+manualRisk+projectedRisk>CombinedRiskCapUsd()*(1.0+RiskTolerancePct/100.0)+0.01))
   {
      ArrayResize(g_smart_plan,0); g_smart_plan_ready=false; g_regrid_busy=false;
      SetStatus("动态推进预检失败：新计划风险超过上限｜旧排单保持不动");
      return;
   }

   // Broker 预检全部通过后，才真正撤销旧排单。
   for(int k=0;k<ArraySize(g_smart_plan);k++)
   {
      double price=g_smart_plan[k].price, sl=NormalizePrice(StopPrice()), tp=g_smart_plan[k].tp_price;
      ENUM_ORDER_TYPE ot; double ve=price;
      if(g_direction==DIR_LONG)
      {
         if(MathAbs(price-CurrentAsk())<=PointValue()*2){ ot=ORDER_TYPE_BUY; ve=CurrentAsk(); }
         else if(price<CurrentAsk()) ot=ORDER_TYPE_BUY_LIMIT; else ot=ORDER_TYPE_BUY_STOP;
      }
      else
      {
         if(MathAbs(price-CurrentBid())<=PointValue()*2){ ot=ORDER_TYPE_SELL; ve=CurrentBid(); }
         else if(price>CurrentBid()) ot=ORDER_TYPE_SELL_LIMIT; else ot=ORDER_TYPE_SELL_STOP;
      }
      string why="";
      if(!ValidateOrderLevels(ot,ve,sl,tp,why))
      {
         int badSlot=g_smart_plan[k].slot;
         ArrayResize(g_smart_plan,0); g_smart_plan_ready=false; g_regrid_busy=false;
         SetStatus(StringFormat("动态推进预检失败：槽%d %s｜旧排单保持不动",badSlot,why));
         return;
      }
   }

   int expected=ArraySize(g_smart_plan);
   CancelSmartPending();
   g_smart_equal_lots=lots;
   int regridSlotMax=0;
   for(int si=0;si<ArraySize(slots);si++) regridSlotMax=MathMax(regridSlotMax,slots[si]);
   SetSmartGrid(gp,regridSlotMax);

   int placed=0;
   for(int k=0;k<expected;k++)
      if(PlaceSmartOrder(g_smart_plan[k].comment,g_smart_plan[k].slot,g_smart_plan[k].odd,g_smart_plan[k].price,g_smart_plan[k].lots)) placed++;

   ArrayResize(g_smart_plan,0); g_smart_plan_ready=false;
   int after_no_stop=0; double after_used=CurrentSymbolRiskPool(after_no_stop);
   double pct=(AccountInfoDouble(ACCOUNT_EQUITY)>0 ? after_used/AccountInfoDouble(ACCOUNT_EQUITY)*100.0 : 0.0);
   g_last_regrid_center=center; g_last_regrid_time=TimeCurrent(); g_regrid_busy=false;

   if(placed<expected)
   {
      CancelSmartPending();
      g_paused=true;
      SaveRecoveryRuntimeState();
      SetStatus(StringFormat("动态重排部分执行：成功%d/%d｜本轮未成交排单已撤销｜系统已暂停",placed,expected));
      return;
   }

   SetStatus(StringFormat("动态推进完成：新增%d/%d单｜吸筹风险$%.2f / $%.2f (%.2f%%净值)｜组合余$%.2f",
      placed,expected,after_used,budget,pct,MathMax(0.0,CombinedRiskCapUsd()-after_used-manualRisk)));
}

void UpdateDynamicBox()
{
   if(!g_smart_user_confirmed) return;
   if(!BoxExists() || !g_running || g_paused || !DynamicAccumulation) return;

   double width=BoxWidth();
   if(width<=PointValue()) return;

   double trigger=MathMax(PointValue(),width*MoveTriggerWidthPct);
   double shift=0.0;

   if(FollowMode==FOLLOW_DYNAMIC_BOX)
   {
      if(g_direction==DIR_LONG)
      {
         // 只认趋势方向的新高。回落不更新极值，更不会把框往下拖。
         double px=CurrentAsk();
         if(g_smart_trend_extreme<=0.0) g_smart_trend_extreme=px;
         if(px>g_smart_trend_extreme) g_smart_trend_extreme=px;

         // 只有价格真正突破当前框上沿，并继续向上超过触发距离，才整体上移。
         double advance=g_smart_trend_extreme-BoxHigh();
         if(advance>=trigger)
            shift=advance;
      }
      else
      {
         // 空头只认趋势方向的新低。反弹不更新极值，更不会把框往上拖。
         double px=CurrentBid();
         if(g_smart_trend_extreme<=0.0) g_smart_trend_extreme=px;
         if(px<g_smart_trend_extreme) g_smart_trend_extreme=px;

         // 只有价格真正跌破当前框下沿，并继续向下超过触发距离，才整体下移。
         double advance=BoxLow()-g_smart_trend_extreme;
         if(advance>=trigger)
            shift=-advance;
      }
   }
   else
   {
      // EMA模式也执行“单向推进”限制：多头只能上移，空头只能下移。
      double ema=CalcEMA(_Symbol,FollowTimeframe,H4EmaPeriod,1);
      double atr=CalcATR(_Symbol,FollowTimeframe,14,1);
      if(ema<=0 || atr<=0) return;

      if(g_direction==DIR_LONG)
      {
         double desired=ema-atr*FollowAtrMultiple;
         if(desired>BoxLow())
         {
            double candidate=desired-BoxLow();
            if(candidate>=trigger) shift=candidate;
         }
      }
      else
      {
         double desired=ema+atr*FollowAtrMultiple;
         if(desired<BoxHigh())
         {
            double candidate=desired-BoxHigh(); // negative only
            if(MathAbs(candidate)>=trigger) shift=candidate;
         }
      }
   }

   // 最终方向硬门：多头绝不下移；空头绝不上移。
   if(g_direction==DIR_LONG && shift<=0.0) return;
   if(g_direction==DIR_SHORT && shift>=0.0) return;
   if(MathAbs(shift)<PointValue()) return;

   double p0=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,0)+shift;
   double p1=ObjectGetDouble(0,OBJ_BOX,OBJPROP_PRICE,1)+shift;
   ObjectSetDouble(0,OBJ_BOX,OBJPROP_PRICE,0,NormalizePrice(p0));
   ObjectSetDouble(0,OBJ_BOX,OBJPROP_PRICE,1,NormalizePrice(p1));
   DrawSmartStop();
   CacheBox();

   // 只有“趋势方向推进”发生时才允许重排未成交排单。
   RebuildPendingGrid(false);
}

void TightenSmartStops()
{
   if(!BoxExists()) return;
   double sl=StopPrice();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !IsFamilyPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT); if(!IsSmartComment(c)) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double old=PositionGetDouble(POSITION_SL); double tp=PositionGetDouble(POSITION_TP);
      if(pt==POSITION_TYPE_BUY)
      {
         if(sl>=CurrentBid()) continue;
         if(old<=0 || sl>old+PointValue()) ModifyPositionTicket(ticket,sl,tp);
      }
      else
      {
         if(sl<=CurrentAsk()) continue;
         if(old<=0 || sl<old-PointValue()) ModifyPositionTicket(ticket,sl,tp);
      }
   }
}

bool HitHardStop()
{
   if(!BoxExists()) return false;
   // 实际止损（含缓冲）被触及：经纪商SL也会成交，这里清理剩余仓位与挂单
   if(g_direction==DIR_LONG ? CurrentBid()<=StopPrice() : CurrentAsk()>=StopPrice()) return true;

   if(!HardStopCloseConfirm)
      return g_direction==DIR_LONG ? CurrentBid()<=BoxLow() : CurrentAsk()>=BoxHigh();

   // v1.68：收盘确认——已收盘K线收在框外 = 价格在价值区外被接受，结束本轮吸筹；
   // 只是影线扫过框边（扫止损）不触发。
   double c=iClose(_Symbol,HardStopConfirmTF,1);
   if(c<=0) return false;
   return g_direction==DIR_LONG ? c<BoxLow() : c>BoxHigh();
}

// v1.57：彻底结束“吸金框任务”。
// 注意：这里只清理框内吸金，不修改 g_manual_tracking_active。
// 因此市价/排单独立循环跟踪可在吸金框消失后继续工作。
void ClearSmartTaskContext()
{
   g_smart_plan_ready=false;
   g_smart_user_confirmed=false;
   g_running=false;
   g_paused=true;
   g_direction_prepared=false;
   g_last_regrid_center=0.0;
   g_last_regrid_time=0;
   g_smart_confirm_box_low=0.0;
   g_smart_confirm_box_high=0.0;
   g_smart_trend_extreme=0.0;
   g_smart_equal_lots=0.0;
   g_even_batch_tp1=0.0;
   g_even_batch_tp2=0.0;
   g_even_batch_tp3=0.0;
   ArrayResize(g_smart_plan,0);

   SetSmartGrid(0.0,0);
   g_stop_buffer=0.0; GlobalVariableSet(StableGV("SBF"),0.0);
   ObjectDelete(0,OBJ_BOX);
   ObjectDelete(0,OBJ_SMART_STOP);
   ChartRedraw();
}

void EmergencyStop(string reason)
{
   g_running=false; g_paused=true; g_user_stopped_smart=true; g_smart_user_confirmed=false;
   CancelSmartPending();
   ulong tickets[]; ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      if(IsSmartComment(PositionGetString(POSITION_COMMENT))) { int n=ArraySize(tickets); ArrayResize(tickets,n+1); tickets[n]=t; }
   }
   for(int i=0;i<ArraySize(tickets);i++) ClosePositionTicket(tickets[i]);

   // 硬止损/趋势反转等策略结束后，旧框与旧计划立即失效。
   ClearSmartTaskContext();
   SetStatus("策略结束并已清除吸金框："+reason+"｜下一轮请重新画框→计算→确认");
}

void EndSmartStrategy()
{
   g_running=false;
   g_paused=true;
   g_smart_user_confirmed=false;
   g_user_stopped_smart=true;

   if(!KeepSmartPendingOnStop)
   {
      CancelSmartPending();
      ClearSmartTaskContext();
      SetStatus("已停止吸金：旧挂单已撤销；已成交吸筹仓保留，可直接纳入下一轮新框重新计算总风险");
   }
   else
   {
      // 用户选择保留已存在的智能排单时，只保留订单本身；
      // 旧框仍必须删除，且不会再自动补单/重排。
      ClearSmartTaskContext();
      SetStatus("已停止吸金：现有智能排单按设置保留，但旧吸金框已删除且不会再自动补单｜下一轮需重新画框→计算→确认");
   }
}

bool TryAutoResumeSmart()
{
   // v1.58：安全优先。重载/挂载EA后绝不因为旧框或旧订单自动进入“已确认”状态。
   // 用户必须重新计算计划并点击确认。这样EA加载、拖框、Timer都不会未经确认排单。
   if(!g_smart_user_confirmed) return false;
   if(g_user_stopped_smart) return false;
   if(g_running || !AutoResumeSmartStrategy || !BoxExists()) return false;
   int buy=0,sell=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buy++; else sell++;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsFamilyOrderSelected()) continue;
      if(!IsSmartComment(OrderGetString(ORDER_COMMENT))) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(IsBuyOrderType(ot)) buy++; else if(IsSellOrderType(ot)) sell++;
   }
   if(buy>0 && sell==0) { g_direction=DIR_LONG; g_direction_prepared=true; g_running=true; g_paused=false; DrawSmartStop(); return true; }
   if(sell>0 && buy==0) { g_direction=DIR_SHORT; g_direction_prepared=true; g_running=true; g_paused=false; DrawSmartStop(); return true; }
   return false;
}

void ExpireSmartOrders()
{
   if(PendingValidBars<=0 && PendingValidMinutes<=0) return;
   ExpireItem arr[]; ArrayResize(arr,0);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsFamilyOrderSelected()) continue;
      string c=OrderGetString(ORDER_COMMENT); if(!IsSmartComment(c)) continue;
      datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
      bool expired=(PendingValidMinutes>0
                    ? TimeCurrent()-setup>=(datetime)PendingValidMinutes*60
                    : iBarShift(_Symbol,_Period,setup,false)>=PendingValidBars);
      if(expired)
      {
         int n=ArraySize(arr); ArrayResize(arr,n+1); arr[n].ticket=t; arr[n].comment=c; arr[n].odd=IsOddComment(c);
      }
   }
   for(int i=0;i<ArraySize(arr);i++)
   {
      if(DeleteOrderTicket(arr[i].ticket) && arr[i].odd && g_running && !g_paused && InfiniteOddRecycle) RearmOddSlot(arr[i].comment);
   }
}

// =========================
// 手工市价 / 排单管理
// =========================
bool ManualStopExists() { return ObjectFind(0,OBJ_MANUAL_STOP)>=0; }
double ManualStopPrice() { return ManualStopExists()?ObjectGetDouble(0,OBJ_MANUAL_STOP,OBJPROP_PRICE):0.0; }
bool EntryLineExists() { return ObjectFind(0,OBJ_ENTRY)>=0; }
double EntryPriceLine() { return EntryLineExists()?ObjectGetDouble(0,OBJ_ENTRY,OBJPROP_PRICE):0.0; }

void DrawManualStop()
{
   double p=ManualStopPrice();
   if(p<=0)
   {
      double off=MathMax(1,ManualStopDefaultPoints)*PointValue();
      p=(g_direction==DIR_LONG?CurrentBid()-off:CurrentAsk()+off);
   }

   // 若手工止损线恰好与吸筹止损线重叠，首次显示时主动错开一点，
   // 避免鼠标命中吸筹边界而无法拖动手工线。
   if(BoxExists())
   {
      double smart=StopPrice();
      double minsep=MathMax(10,ManualStopVisualOffsetPoints)*PointValue();
      if(MathAbs(p-smart)<minsep)
         p=(g_direction==DIR_LONG?smart+minsep:smart-minsep);
   }

   if(ObjectFind(0,OBJ_MANUAL_STOP)<0)
      ObjectCreate(0,OBJ_MANUAL_STOP,OBJ_HLINE,0,0,NormalizePrice(p));

   ObjectSetDouble(0,OBJ_MANUAL_STOP,OBJPROP_PRICE,NormalizePrice(p));
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_COLOR,clrDeepSkyBlue);
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_WIDTH,MathMax(2,ManualStopLineWidth));
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_SELECTED,true);
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_BACK,false);
   ObjectSetInteger(0,OBJ_MANUAL_STOP,OBJPROP_ZORDER,100);
   ChartRedraw();
}

void DrawEntryLine()
{
   double p=EntryLineExists()?EntryPriceLine():MidPrice();
   ObjectDelete(0,OBJ_ENTRY);
   ObjectCreate(0,OBJ_ENTRY,OBJ_HLINE,0,0,NormalizePrice(p));
   ObjectSetInteger(0,OBJ_ENTRY,OBJPROP_COLOR,clrDodgerBlue);
   ObjectSetInteger(0,OBJ_ENTRY,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,OBJ_ENTRY,OBJPROP_SELECTABLE,true);
   ObjectSetString(0,UI_PREFIX+"ED_ENTRY",OBJPROP_TEXT,DoubleToString(p,DigitsValue()));
   SetStatus("排单入场线已建立：拖到计划价格后计算排单风险");
}

bool ManualTypeFromStop(double entry,ENUM_ORDER_TYPE &type)
{
   double sl=ManualStopPrice();
   if(sl<=0 || MathAbs(sl-entry)<PointValue()) return false;
   type=(sl<entry?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   return true;
}

double ManualTotalLots(double entry,ENUM_ORDER_TYPE type)
{
   int no_stop=0;
   double available=ManualAvailableRiskBudget(no_stop);
   if(no_stop>0 || available<=0.01) return 0.0;

   double risk_lots=LotsForRisk(type,entry,ManualStopPrice(),available);
   if(risk_lots<=0) return 0.0;

   // 固定仓位仍允许使用，但绝不允许绕过“剩余风险”与组合风险硬上限。
   if(g_fixed_lots>0)
      return NormalizeLotsDown(MathMin(MathMin(g_fixed_lots,MaxTotalLots),risk_lots));

   return risk_lots;
}

bool BuildManualPlan(double entry,ENUM_ORDER_TYPE type,ManualEntrySlice &plan[])
{
   ArrayResize(plan,0);
   g_manual_plan_build_reason="";
   g_manual_plan_actual_orders=0;
   g_manual_plan_calc_total_lots=0.0;

   // “手工最大开仓单数”只是上限，不再要求必须排满。
   // 实际可开单数由：风险金额、止损距离、最小手数/步进、单笔最大手数共同决定。
   int max_orders=MathMax(1,g_manual_orders);
   double total_lots=ManualTotalLots(entry,type);
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(minv<=0)
   {
      g_manual_plan_build_reason="无法读取本品种最小手数";
      return false;
   }
   if(total_lots<minv-1e-12)
   {
      g_manual_plan_build_reason=StringFormat("当前风险/止损距离只能计算 %.4f 手，低于最小手数 %.4f",total_lots,minv);
      return false;
   }

   g_manual_plan_calc_total_lots=total_lots;

   // 先用“总手数 / 最小手数”得到理论最多可拆几单，再受用户设置的最大单数限制。
   int by_min_lot=(int)MathFloor((total_lots+1e-12)/minv);
   int candidate_max=MathMin(max_orders,MathMax(1,by_min_lot));

   // 从最多单数向下试，找到第一个可执行方案就是“当前风险下能开的最多单数”。
   for(int total=candidate_max; total>=1; total--)
   {
      // 只有1单时直接作为底仓；不设固定TP，后续仍可由底仓保护/一键追踪管理。
      if(total==1)
      {
         double base=NormalizeLotsDown(MathMin(total_lots,MaxLotsPerOrder));
         if(base<minv-1e-12) continue;

         ArrayResize(plan,1);
         plan[0].is_base=true;
         plan[0].tracking_seed=false;
         plan[0].index=0;
         plan[0].lots=base;
         plan[0].tp_r=0;
         plan[0].tp_distance=0;
         g_manual_plan_actual_orders=1;
         g_manual_plan_build_reason=StringFormat("风险自适应：最大%d单，当前只能安全执行1单",max_orders);
         return true;
      }

      int split=total-1;
      double preferred_base=total_lots*MathMax(0.0,MathMin(1.0,g_base_ratio));
      double rem=MathMax(0.0,total_lots-preferred_base);

      // 底仓比例是“偏好”，不是阻止开仓的硬条件。
      // 分仓先按偏好比例均分，但同时限制为 <= 平均仓位，确保底仓最终不会小于单个分仓。
      double avg_cap=total_lots/total;
      double raw_each=rem/split;
      // 先追求“风险预算允许的最多单数”：只要总手数足以给每张最小手数，就允许底仓比例因手数步进产生轻微偏离。
      // 例如总仓0.06、最小0.01、上限10单时，可执行6×0.01，而不是因为20%底仓偏好被迫降成5单。
      double desired_each=MathMax(minv,MathMin(raw_each,avg_cap));
      double each=NormalizeLotsDown(desired_each);
      if(each<minv-1e-12) continue;
      if(each>MaxLotsPerOrder+1e-9) continue;

      // 归一化后的尾差全部归到底仓，尽量使用完整风险额度。
      double base=NormalizeLotsDown(total_lots-each*split);
      if(base<minv-1e-12) continue;
      if(base>MaxLotsPerOrder+1e-9) continue;
      if(base+1e-12<each) continue;

      ArrayResize(plan,total);
      plan[0].is_base=true;
      plan[0].tracking_seed=false;
      plan[0].index=0;
      plan[0].lots=base;
      plan[0].tp_r=0;
      plan[0].tp_distance=0;

      double riskdist=MathAbs(entry-ManualStopPrice());
      bool hasSeed=(ManualSmartTracking && split>=1);
      int rrCount=split-(hasSeed?1:0);

      for(int i=1;i<=split;i++)
      {
         bool seed=(hasSeed && i==1);
         double rr=0.0;
         double tpDist=0.0;

         if(seed)
         {
            rr=MathMin(ManualMaxTpR(),MathMax(0.10,ManualCycleTpMaxR));
            tpDist=ManualCycleTpDistance(riskdist);
         }
         else
         {
            int rank=i-(hasSeed?1:0);
            rr=ManualLayerRR(rank,MathMax(1,rrCount));
            tpDist=riskdist*rr;
         }

         plan[i].is_base=false;
         plan[i].tracking_seed=seed;
         plan[i].index=i;
         plan[i].lots=each;
         plan[i].tp_r=rr;
         plan[i].tp_distance=tpDist;
      }

      g_manual_plan_actual_orders=total;
      double used_lots=base+each*split;
      g_manual_plan_build_reason=StringFormat("风险自适应：最大%d单 → 实际%d单｜风险可用总仓%.4f｜实际分配%.4f",max_orders,total,total_lots,used_lots);
      return true;
   }

   g_manual_plan_build_reason=StringFormat(
      "风险自适应失败：最大%d单｜风险可用总仓%.4f｜最小手数%.4f｜当前止损距离过大或单笔上限过低",
      max_orders,total_lots,minv);
   return false;
}

void StoreManualPlan(int mode,double entry,ENUM_ORDER_TYPE type,ManualEntrySlice &plan[])
{
   g_manual_plan_mode=mode; g_manual_plan_entry=entry; g_manual_plan_stop=ManualStopPrice(); g_manual_plan_type=type; g_manual_plan_ready=true;
   ArrayResize(g_manual_plan,ArraySize(plan));
   for(int i=0;i<ArraySize(plan);i++) g_manual_plan[i]=plan[i];
   double total=0; for(int i=0;i<ArraySize(plan);i++) total+=plan[i].lots;

   double firstTp=0.0,lastTp=0.0;
   for(int i=1;i<ArraySize(plan);i++)
   {
      double q=(type==ORDER_TYPE_BUY?entry+plan[i].tp_distance:entry-plan[i].tp_distance);
      q=NormalizePrice(q);
      if(firstTp<=0) firstTp=q;
      lastTp=q;
   }

   double plannedRisk=0.0;
   double r1=RiskPerLotAtStop(type,entry,g_manual_plan_stop);
   for(int i=0;i<ArraySize(plan);i++) plannedRisk+=r1*plan[i].lots;
   int mns=0,sns=0;
   double mr=ManualRiskNow(mns), sr=SmartRiskNow(sns);
   double manualRemain=MathMax(0.0,EffectiveRiskBudgetUsd()-mr-plannedRisk);
   double comboRemain=EnableCombinedRiskCap ? MathMax(0.0,CombinedRiskCapUsd()-sr-mr-plannedRisk) : manualRemain;

   SetStatus(StringFormat(
      "手工%s待确认：风险自适应 %d/%d单｜总仓%.4f｜底仓%.4f｜新增风险$%.2f｜止损%.*f｜TP %.*f→%.*f｜最大%.2fR｜确认后余$%.2f/组合$%.2f%s",
      mode==1?"市价":"排单",ArraySize(plan),MathMax(1,g_manual_orders),total,plan[0].lots,plannedRisk,DigitsValue(),g_manual_plan_stop,
      DigitsValue(),firstTp,DigitsValue(),lastTp,ManualMaxTpR(),manualRemain,comboRemain,
      ManualSmartTracking?"｜首分仓循环":""));
}

void PrepareManualMarket()
{
   if(!ManualStopExists()) { SetStatus("请先画线止损"); return; }
   ENUM_ORDER_TYPE type;
   if(!ManualTypeFromStop(MidPrice(),type)) { SetStatus("止损线不能与现价重合"); return; }
   double entry=(type==ORDER_TYPE_BUY?CurrentAsk():CurrentBid());
   ManualEntrySlice p[];
   if(!BuildManualPlan(entry,type,p)) { SetStatus("市价风险计算失败："+g_manual_plan_build_reason); return; }
   double planned=0; for(int i=0;i<ArraySize(p);i++) planned+=p[i].lots;
   if(TotalManagedLots()+planned>MaxTotalLots+1e-9) { SetStatus("风险计算失败：计划总仓将超过最大总手数"); return; }
   StoreManualPlan(1,entry,type,p);
}

void PrepareManualPending()
{
   if(!ManualStopExists()) { SetStatus("请先画线止损"); return; }
   if(!EntryLineExists()) { DrawEntryLine(); return; }
   double entry=EntryPriceLine(); ENUM_ORDER_TYPE type;
   if(!ManualTypeFromStop(entry,type)) { SetStatus("止损线不能与入场线重合"); return; }
   ManualEntrySlice p[];
   if(!BuildManualPlan(entry,type,p)) { SetStatus("排单风险计算失败："+g_manual_plan_build_reason); return; }
   double planned=0; for(int i=0;i<ArraySize(p);i++) planned+=p[i].lots;
   if(TotalManagedLots()+planned>MaxTotalLots+1e-9) { SetStatus("风险计算失败：计划总仓将超过最大总手数"); return; }
   StoreManualPlan(2,entry,type,p);
}

string StableGV(string suffix)
{
   return StringFormat("JSA_STB_%I64d_%s_%s",MagicNumber,_Symbol,suffix);
}

void LoadStabilityState()
{
   if(GlobalVariableCheck(StableGV("SID"))) g_smart_task_id=(long)GlobalVariableGet(StableGV("SID"));
   if(GlobalVariableCheck(StableGV("MID"))) g_manual_task_id=(long)GlobalVariableGet(StableGV("MID"));
   if(GlobalVariableCheck(StableGV("RB")))  g_snap_risk_budget=GlobalVariableGet(StableGV("RB"));
   if(GlobalVariableCheck(StableGV("ER")))  g_snap_existing_risk=GlobalVariableGet(StableGV("ER"));
   if(GlobalVariableCheck(StableGV("NR")))  g_snap_new_risk=GlobalVariableGet(StableGV("NR"));
   if(GlobalVariableCheck(StableGV("TL")))  g_snap_total_lots=GlobalVariableGet(StableGV("TL"));
   if(GlobalVariableCheck(StableGV("SP")))  g_snap_stop=GlobalVariableGet(StableGV("SP"));
   if(GlobalVariableCheck(StableGV("TM")))  g_snap_time=(datetime)GlobalVariableGet(StableGV("TM"));
   if(GlobalVariableCheck(StableGV("GAP"))) g_smart_gap_price=GlobalVariableGet(StableGV("GAP"));
   if(GlobalVariableCheck(StableGV("SMX"))) g_smart_slot_max=(int)GlobalVariableGet(StableGV("SMX"));
   if(GlobalVariableCheck(StableGV("SBF"))) g_stop_buffer=GlobalVariableGet(StableGV("SBF"));
   if(GlobalVariableCheck(StableGV("EQL"))) g_smart_equal_lots=GlobalVariableGet(StableGV("EQL"));
   if(GlobalVariableCheck(StableGV("DIR"))) g_direction=(GlobalVariableGet(StableGV("DIR"))>0.5?DIR_SHORT:DIR_LONG);
}

void SaveRiskSnapshot(double budget,double existing_risk,double new_risk,double total_lots,double stop)
{
   g_snap_risk_budget=budget;
   g_snap_existing_risk=existing_risk;
   g_snap_new_risk=new_risk;
   g_snap_total_lots=total_lots;
   g_snap_stop=stop;
   g_snap_time=TimeCurrent();
   GlobalVariableSet(StableGV("RB"),budget);
   GlobalVariableSet(StableGV("ER"),existing_risk);
   GlobalVariableSet(StableGV("NR"),new_risk);
   GlobalVariableSet(StableGV("TL"),total_lots);
   GlobalVariableSet(StableGV("SP"),stop);
   GlobalVariableSet(StableGV("TM"),(double)g_snap_time);
}

void SaveTaskSnapshot(string kind,long tid,double budget,double existing_risk,double new_risk,double lots,double stop)
{
   SaveRiskSnapshot(budget,existing_risk,new_risk,lots,stop);
   if(tid<=0) return;
   string b=StringFormat("%s_%s%I64d_",StableGV("H"),kind,tid);
   GlobalVariableSet(b+"RB",budget); GlobalVariableSet(b+"ER",existing_risk);
   GlobalVariableSet(b+"NR",new_risk); GlobalVariableSet(b+"TL",lots);
   GlobalVariableSet(b+"SP",stop); GlobalVariableSet(b+"TM",(double)TimeCurrent());
}

bool PositionBelongsToSmartTask(ulong posid,long tid)
{
   string gv=PositionTaskGV(posid);
   return tid>0 && GlobalVariableCheck(gv) && (long)MathRound(GlobalVariableGet(gv))==tid;
}
bool PositionBelongsToManualTask(ulong posid,long tid)
{
   string gv=PositionTaskGV(posid);
   return tid>0 && GlobalVariableCheck(gv) && (long)MathRound(GlobalVariableGet(gv))==-tid;
}
void AdoptExistingSmartPositionsToCurrentTask()
{
   if(g_smart_task_id<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT); if(!IsSmartComment(c)) continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      GlobalVariableSet(PositionTaskGV(pid),(double)g_smart_task_id);
   }
}

long BeginSmartTask()
{
   g_smart_task_id++;
   GlobalVariableSet(StableGV("SID"),(double)g_smart_task_id);
   return g_smart_task_id;
}

long BeginManualTask()
{
   g_manual_task_id++;
   GlobalVariableSet(StableGV("MID"),(double)g_manual_task_id);
   return g_manual_task_id;
}

string PositionTaskGV(ulong posid)
{
   return StringFormat("JSA_PID_%I64d_%s_%I64u",MagicNumber,_Symbol,posid);
}

void TagPositionTask(ulong posid,string comment)
{
   if(posid==0) return;
   double tag=0;
   if(IsSmartComment(comment)) tag=(double)g_smart_task_id;
   else if(IsManualCycleComment(comment)) tag=-(double)g_manual_task_id;
   if(tag!=0) GlobalVariableSet(PositionTaskGV(posid),tag);
}

void SaveRecoveryRuntimeState()
{
   GlobalVariableSet(StableGV("RUN"),g_running?1.0:0.0);
   GlobalVariableSet(StableGV("MTA"),g_manual_tracking_active?1.0:0.0);
   GlobalVariableSet(StableGV("OKT"),g_one_key_trailing?1.0:0.0);
}
void LoadRecoveryRuntimeState()
{
   g_recover_smart_was_running=(GlobalVariableCheck(StableGV("RUN")) && GlobalVariableGet(StableGV("RUN"))>0.5);
   g_recover_manual_was_active=(GlobalVariableCheck(StableGV("MTA")) && GlobalVariableGet(StableGV("MTA"))>0.5);
   g_recover_onekey_was_on=(GlobalVariableCheck(StableGV("OKT")) && GlobalVariableGet(StableGV("OKT"))>0.5);
}
void ResumeRecoveredTasks()
{
   if(!g_recovery_pending){ SetStatus("当前没有待恢复任务"); return; }

   // v1.68.1：用户主动点“恢复任务”时，只要吸金框还在且有吸筹单，就恢复吸金运行，
   // 不再因为上次退出时保存的运行标记为关而“保持停止”。
   JsaDirection d;
   bool hasSmart=InferSmartDirection(d);
   bool resumeSmart=BoxExists() && (g_recover_smart_was_running || hasSmart);
   if(hasSmart) g_direction=d;

   g_running=resumeSmart;
   g_smart_user_confirmed=resumeSmart;
   g_paused=false;
   g_manual_tracking_active=g_recover_manual_was_active;
   g_one_key_trailing=g_recover_onekey_was_on;
   g_recovery_pending=false;
   SaveRecoveryRuntimeState();

   if(resumeSmart)
   {
      g_direction_prepared=true;
      g_smart_trend_extreme=0.0;     // 从当前价重新跟踪趋势极值
      // 旧版本建立的任务没有记录止损缓冲：按现有吸筹单的实际SL反推，保持整轮止损一致
      if(g_stop_buffer<=0)
      {
         double edge=BoxEdgeStop(), b=-1.0;
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong t=PositionGetTicket(i); if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if(!IsSmartComment(PositionGetString(POSITION_COMMENT))) continue;
            double sl=PositionGetDouble(POSITION_SL); if(sl<=0) continue;
            double gap=(g_direction==DIR_LONG ? edge-sl : sl-edge);
            if(gap>=0) b=MathMax(b,gap);
         }
         if(b>=0) g_stop_buffer=MathMax(b,1e-9);   // 1e-9 = 贴框边，但仍视为“已冻结”
         GlobalVariableSet(StableGV("SBF"),g_stop_buffer);
      }
      DrawSmartStop();
      CacheBox();
      SetSmartGrid(g_smart_gap_price,g_smart_slot_max);
      RebuildPendingGrid(true);       // 按当前框把未成交挂单重新对齐/补齐
   }
   SetStatus(StringFormat("恢复完成：吸筹%s｜手工循环%s｜一键追踪%s｜不重复建仓/挂单",
      g_running?"继续":"保持停止",g_manual_tracking_active?"继续":"保持停止",g_one_key_trailing?"开启":"关闭"));
}
void AbandonRecoveredTasks()
{
   if(!g_recovery_pending){ SetStatus("当前没有待恢复任务"); return; }
   g_running=false; g_smart_user_confirmed=false; g_manual_tracking_active=false; g_one_key_trailing=false;
   g_recovery_pending=false;
   SaveRecoveryRuntimeState();
   SetStatus("已放弃旧任务恢复：现有持仓/挂单/SL/TP保持不变，可重新画框建立新任务");
}

void RecoverExistingTasksSafe()
{
   int sp=0,so=0,mb=0,ms=0,mo=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(IsSmartComment(c)) sp++; else if(IsManualBaseComment(c)) mb++; else if(IsManualSplitComment(c)) ms++;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i); if(tk==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(IsSmartComment(c)) so++; else if(IsManualCycleComment(c)) mo++;
   }
   g_recovery_pending=(sp+so+mb+ms+mo)>0;
   if(g_recovery_pending)
   {
      LoadRecoveryRuntimeState();
      g_running=false; g_smart_user_confirmed=false; g_manual_tracking_active=false; g_one_key_trailing=false;
      SetStatus(StringFormat("安全恢复待确认：吸筹仓%d/挂%d｜底仓%d｜手工分仓%d/挂%d",sp,so,mb,ms,mo));
   }
}

string TrackGV(string suffix)
{
   return StringFormat("JSA_TRK_%I64d_%s_%s",MagicNumber,_Symbol,suffix);
}

void SaveTrackingState()
{
   GlobalVariableSet(TrackGV("A"),g_manual_tracking_active?1:0);
   GlobalVariableSet(TrackGV("M"),(double)g_manual_tracking_source_mode);
   GlobalVariableSet(TrackGV("T"),(double)g_manual_tracking_type);
   GlobalVariableSet(TrackGV("S"),g_manual_tracking_initial_stop);
   GlobalVariableSet(TrackGV("R"),g_manual_tracking_initial_risk);
   GlobalVariableSet(TrackGV("L"),g_manual_tracking_seed_lots);
   GlobalVariableSet(TrackGV("C"),g_manual_tracking_cycles);
}

void LoadTrackingState()
{
   if(!ManualSmartTracking) return;
   if(GlobalVariableCheck(TrackGV("A"))) g_manual_tracking_active=(GlobalVariableGet(TrackGV("A"))>0.5);
   if(GlobalVariableCheck(TrackGV("M"))) g_manual_tracking_source_mode=(int)GlobalVariableGet(TrackGV("M"));
   if(GlobalVariableCheck(TrackGV("T"))) g_manual_tracking_type=(ENUM_ORDER_TYPE)(int)GlobalVariableGet(TrackGV("T"));
   if(GlobalVariableCheck(TrackGV("S"))) g_manual_tracking_initial_stop=GlobalVariableGet(TrackGV("S"));
   if(GlobalVariableCheck(TrackGV("R"))) g_manual_tracking_initial_risk=GlobalVariableGet(TrackGV("R"));
   if(GlobalVariableCheck(TrackGV("L"))) g_manual_tracking_seed_lots=GlobalVariableGet(TrackGV("L"));
   if(GlobalVariableCheck(TrackGV("C"))) g_manual_tracking_cycles=(int)GlobalVariableGet(TrackGV("C"));
}

void ArmManualTracking(ENUM_ORDER_TYPE type,double stop,double initial_risk,double seed_lots,int source_mode)
{
   bool source_enabled=(source_mode==1 ? MarketCycleTracking : PendingCycleTracking);
   if(!ManualSmartTracking || !source_enabled)
   {
      g_manual_tracking_active=false;
      g_manual_tracking_source_mode=0;
      SaveTrackingState();
      return;
   }

   g_manual_tracking_active=true;
   g_manual_tracking_source_mode=source_mode;
   g_manual_tracking_type=type;
   g_manual_tracking_initial_stop=stop;
   g_manual_tracking_initial_risk=initial_risk;
   g_manual_tracking_seed_lots=seed_lots;
   g_manual_tracking_cycles=0;
   SaveTrackingState();
}

bool PlaceManualPendingSlice(ENUM_ORDER_TYPE type,double entry,ManualEntrySlice &slc)
{
   entry=NormalizePrice(entry);
   double sl=NormalizePrice(ManualStopPrice());
   double tp=0;
   if(!slc.is_base) tp=NormalizePrice(type==ORDER_TYPE_BUY?entry+slc.tp_distance:entry-slc.tp_distance);
   string c=slc.is_base?MANUAL_BASE:StringFormat("%s%d",MANUAL_SPLIT_PREFIX,slc.index);

   ENUM_ORDER_TYPE ot;
   if(type==ORDER_TYPE_BUY)
      ot=(entry<CurrentAsk()?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_BUY_STOP);
   else
      ot=(entry>CurrentBid()?ORDER_TYPE_SELL_LIMIT:ORDER_TYPE_SELL_STOP);

   string reason="";
   if(!ValidateOrderLevels(ot,entry,sl,tp,reason))
   {
      Print("JSA v1.67.2 手工排单层",slc.index,"预检失败：",reason);
      return false;
   }

   bool ok=false;
   if(ot==ORDER_TYPE_BUY_LIMIT) ok=trade.BuyLimit(slc.lots,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,c);
   else if(ot==ORDER_TYPE_BUY_STOP) ok=trade.BuyStop(slc.lots,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,c);
   else if(ot==ORDER_TYPE_SELL_LIMIT) ok=trade.SellLimit(slc.lots,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,c);
   else if(ot==ORDER_TYPE_SELL_STOP) ok=trade.SellStop(slc.lots,entry,_Symbol,sl,tp,ORDER_TIME_GTC,0,c);

   if(!ok) Print("JSA v1.67.2 手工排单层",slc.index,"失败｜",LastTradeResultText(c));
   return ok;
}

string BaseRiskGV(ulong pos_id)
{
   return StringFormat("JSA_BASE_%I64d_%s_%I64u",MagicNumber,_Symbol,pos_id);
}

void ConfirmManualMarket()
{
   if(!AcquireExecutionLock("M")) return;
   if(!g_manual_plan_ready || g_manual_plan_mode!=1){ SetStatus("请先计算市价风险"); ReleaseExecutionLock("M"); return; }
   ENUM_ORDER_TYPE type=g_manual_plan_type;
   double entry=NormalizePrice(type==ORDER_TYPE_BUY?CurrentAsk():CurrentBid());
   ManualEntrySlice p[];
   if(!BuildManualPlan(entry,type,p) || ArraySize(p)!=ArraySize(g_manual_plan))
   { SetStatus("价格变化导致手数/剩余风险变化，请重新计算"); PrepareManualMarket(); ReleaseExecutionLock("M"); return; }

   string tpReason="";
   if(!ValidateManualTpPlan(entry,p,tpReason))
   { SetStatus("市价开仓已阻止：TP安全校验失败｜"+tpReason); ReleaseExecutionLock("M"); return; }

   double planned_lots=0.0, planned_risk=0.0, sl=NormalizePrice(ManualStopPrice());
   for(int i=0;i<ArraySize(p);i++){ planned_lots+=p[i].lots; planned_risk+=RiskPerLotAtStop(type,entry,sl)*p[i].lots; }

   int mns=0,sns=0;
   double currentManual=ManualRiskNow(mns);
   double currentSmart=SmartRiskNow(sns);
   double tol=1.0+RiskTolerancePct/100.0;
   if(!ExecutionSafetyCheck("市价开仓",planned_lots,"M") || mns>0 || sns>0 ||
      currentManual+planned_risk>EffectiveRiskBudgetUsd()*tol+0.01 ||
      (EnableCombinedRiskCap && currentManual+currentSmart+planned_risk>CombinedRiskCapUsd()*tol+0.01))
   {
      if(mns==0 && sns==0 && currentManual+planned_risk>EffectiveRiskBudgetUsd()*tol+0.01)
         SetStatus(StringFormat("市价开仓已阻止：手工已有$%.2f + 新增$%.2f > 手工预算$%.2f",currentManual,planned_risk,EffectiveRiskBudgetUsd()));
      else if(mns==0 && sns==0 && EnableCombinedRiskCap && currentManual+currentSmart+planned_risk>CombinedRiskCapUsd()*tol+0.01)
         SetStatus(StringFormat("市价开仓已阻止：组合风险预计$%.2f > 总上限$%.2f",currentManual+currentSmart+planned_risk,CombinedRiskCapUsd()));
      ReleaseExecutionLock("M"); return;
   }

   // Broker 预检：全部分仓都合法才真正发送。
   for(int i=0;i<ArraySize(p);i++)
   {
      double tp=0; if(!p[i].is_base) tp=NormalizePrice(type==ORDER_TYPE_BUY?entry+p[i].tp_distance:entry-p[i].tp_distance);
      string why="";
      if(!ValidateOrderLevels(type,entry,sl,tp,why))
      {
         SetStatus(StringFormat("市价开仓已阻止：第%d分仓 %s",i,why));
         ReleaseExecutionLock("M"); return;
      }
   }

   BeginManualTask(); g_recovery_pending=false;
   // 新手工任务接管循环状态，避免旧任务的循环标记串入本轮。
   g_manual_tracking_active=false; g_manual_tracking_source_mode=0; SaveTrackingState();
   int expected=ArraySize(p),ok=0;
   bool seedSuccess=false;
   string lastFail="";
   for(int i=0;i<expected;i++)
   {
      double tp=0; if(!p[i].is_base) tp=NormalizePrice(type==ORDER_TYPE_BUY?entry+p[i].tp_distance:entry-p[i].tp_distance);
      string c=p[i].is_base?MANUAL_BASE:StringFormat("%s%d",MANUAL_SPLIT_PREFIX,p[i].index);
      bool r=(type==ORDER_TYPE_BUY?trade.Buy(p[i].lots,_Symbol,0,sl,tp,c):trade.Sell(p[i].lots,_Symbol,0,sl,tp,c));
      if(r)
      {
         ok++;
         if(p[i].tracking_seed) seedSuccess=true;
      }
      else
      {
         lastFail=LastTradeResultText(StringFormat("第%d分仓",i));
         Print("JSA v1.67.1 市价分仓失败｜",lastFail);
      }
   }

   int ns=0; double actual=ManualRiskNow(ns);
   double addedActual=MathMax(0.0,actual-currentManual);
   if(ok>0) SaveTaskSnapshot("M",g_manual_task_id,EffectiveRiskBudgetUsd(),currentManual,addedActual,planned_lots,ManualStopPrice());

   // 只有整批成功且循环种子单真实成交，才启动循环，避免残缺计划自动扩散。
   bool cycleReady=(ok==expected && seedSuccess && ManualSmartTracking && MarketCycleTracking && expected>=2);
   if(cycleReady)
      ArmManualTracking(type,ManualStopPrice(),actual,p[1].lots,1);

   g_manual_plan_ready=false; ArrayResize(g_manual_plan,0);
   if(ok<expected)
      SetStatus(StringFormat("市价部分执行：成功%d/%d｜已禁止自动循环｜实际手工风险$%.2f%s",
         ok,expected,actual,lastFail==""?"":"｜"+lastFail));
   else
      SetStatus(StringFormat("市价开仓完成：%d/%d单｜实际手工风险$%.2f / 预算$%.2f%s",
         ok,expected,actual,EffectiveRiskBudgetUsd(),cycleReady?"｜首批循环就绪":""));
   ReleaseExecutionLock("M");
}

void ConfirmManualPending()
{
   if(!AcquireExecutionLock("P")) return;
   if(!g_manual_plan_ready || g_manual_plan_mode!=2){ SetStatus("请先计算排单风险"); ReleaseExecutionLock("P"); return; }
   if(!EntryLineExists() || MathAbs(EntryPriceLine()-g_manual_plan_entry)>TickSizeValue()*2 || MathAbs(ManualStopPrice()-g_manual_plan_stop)>TickSizeValue()*2)
   { SetStatus("入场线/止损线已变化，请重新计算"); ReleaseExecutionLock("P"); return; }

   string tpReason="";
   if(!ValidateManualTpPlan(g_manual_plan_entry,g_manual_plan,tpReason))
   { SetStatus("排单已阻止：TP安全校验失败｜"+tpReason); ReleaseExecutionLock("P"); return; }

   double planned_lots=0.0,planned_risk=0.0;
   for(int i=0;i<ArraySize(g_manual_plan);i++)
   { planned_lots+=g_manual_plan[i].lots; planned_risk+=RiskPerLotAtStop(g_manual_plan_type,g_manual_plan_entry,g_manual_plan_stop)*g_manual_plan[i].lots; }

   int mns=0,sns=0;
   double currentManual=ManualRiskNow(mns);
   double currentSmart=SmartRiskNow(sns);
   double tol=1.0+RiskTolerancePct/100.0;
   if(!ExecutionSafetyCheck("排单入场",planned_lots,"P") || mns>0 || sns>0 ||
      currentManual+planned_risk>EffectiveRiskBudgetUsd()*tol+0.01 ||
      (EnableCombinedRiskCap && currentManual+currentSmart+planned_risk>CombinedRiskCapUsd()*tol+0.01))
   {
      if(mns==0 && sns==0 && currentManual+planned_risk>EffectiveRiskBudgetUsd()*tol+0.01)
         SetStatus(StringFormat("排单已阻止：手工已有$%.2f + 新增$%.2f > 手工预算$%.2f",currentManual,planned_risk,EffectiveRiskBudgetUsd()));
      else if(mns==0 && sns==0 && EnableCombinedRiskCap && currentManual+currentSmart+planned_risk>CombinedRiskCapUsd()*tol+0.01)
         SetStatus(StringFormat("排单已阻止：组合风险预计$%.2f > 总上限$%.2f",currentManual+currentSmart+planned_risk,CombinedRiskCapUsd()));
      ReleaseExecutionLock("P"); return;
   }

   // 全计划 Broker 预检：确保撤销/发送之前每层价位都满足最小距离。
   for(int i=0;i<ArraySize(g_manual_plan);i++)
   {
      double entry=NormalizePrice(g_manual_plan_entry);
      double sl=NormalizePrice(g_manual_plan_stop);
      double tp=0; if(!g_manual_plan[i].is_base) tp=NormalizePrice(g_manual_plan_type==ORDER_TYPE_BUY?entry+g_manual_plan[i].tp_distance:entry-g_manual_plan[i].tp_distance);
      ENUM_ORDER_TYPE ot=(g_manual_plan_type==ORDER_TYPE_BUY ? (entry<CurrentAsk()?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_BUY_STOP)
                                                           : (entry>CurrentBid()?ORDER_TYPE_SELL_LIMIT:ORDER_TYPE_SELL_STOP));
      string why="";
      if(!ValidateOrderLevels(ot,entry,sl,tp,why))
      {
         SetStatus(StringFormat("排单已阻止：第%d分仓 %s",i,why));
         ReleaseExecutionLock("P"); return;
      }
   }

   BeginManualTask(); g_recovery_pending=false;
   // 新手工任务接管循环状态，避免旧任务的循环标记串入本轮。
   g_manual_tracking_active=false; g_manual_tracking_source_mode=0; SaveTrackingState();
   int expected=ArraySize(g_manual_plan),ok=0;
   ulong created[]; ArrayResize(created,0);
   bool seedPlaced=false;
   string lastFail="";
   for(int i=0;i<expected;i++)
   {
      bool placed=PlaceManualPendingSlice(g_manual_plan_type,g_manual_plan_entry,g_manual_plan[i]);
      if(placed)
      {
         ok++;
         if(g_manual_plan[i].tracking_seed) seedPlaced=true;
         ulong ord=trade.ResultOrder();
         if(ord>0){ int n=ArraySize(created); ArrayResize(created,n+1); created[n]=ord; }
      }
      else
      {
         lastFail=LastTradeResultText(StringFormat("第%d分仓",i));
      }
   }

   if(ok<expected && RollbackPartialPendingPlan)
   {
      int removed=0;
      for(int i=0;i<ArraySize(created);i++)
         if(created[i]>0 && OrderSelect(created[i]) && DeleteOrderTicket(created[i])) removed++;
      int ns2=0; double actual2=ManualRiskNow(ns2);
      g_manual_plan_ready=false; ArrayResize(g_manual_plan,0);
      SetStatus(StringFormat("排单部分失败：成功%d/%d，已回滚%d张本轮新排单｜当前手工风险$%.2f%s",
         ok,expected,removed,actual2,lastFail==""?"":"｜"+lastFail));
      ReleaseExecutionLock("P"); return;
   }

   int ns=0; double actual=ManualRiskNow(ns);
   double addedActual=MathMax(0.0,actual-currentManual);
   if(ok>0) SaveTaskSnapshot("M",g_manual_task_id,EffectiveRiskBudgetUsd(),currentManual,addedActual,planned_lots,g_manual_plan_stop);

   bool cycleReady=(ok==expected && seedPlaced && ManualSmartTracking && PendingCycleTracking && expected>=2);
   if(cycleReady)
      ArmManualTracking(g_manual_plan_type,g_manual_plan_stop,actual,g_manual_plan[1].lots,2);

   g_manual_plan_ready=false; ArrayResize(g_manual_plan,0);
   if(ok<expected)
      SetStatus(StringFormat("排单部分执行：成功%d/%d｜已禁止自动循环｜当前手工风险$%.2f%s",
         ok,expected,actual,lastFail==""?"":"｜"+lastFail));
   else
      SetStatus(StringFormat("排单入场完成：%d/%d单｜当前手工风险$%.2f / 预算$%.2f%s",
         ok,expected,actual,EffectiveRiskBudgetUsd(),cycleReady?"｜第1分批智能小止盈循环":""));
   ReleaseExecutionLock("P");
}

void CancelManualPlan()
{
   g_manual_plan_ready=false; g_manual_plan_mode=0; ArrayResize(g_manual_plan,0); SetStatus("已取消手工待确认计划");
}

double ManualTrackingCurrentRisk(int &no_stop)
{
   no_stop=0; double risk=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsManualCyclePositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      double sl=PositionGetDouble(POSITION_SL); if(sl<=0){no_stop++;continue;}
      double e=PositionGetDouble(POSITION_PRICE_OPEN),v=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool risk_side=(pt==POSITION_TYPE_BUY?sl<e:sl>e); if(!risk_side) continue;
      risk+=RiskPerLotAtStop(PositionDirectionOrderType(pt),e,sl)*v;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsManualCycleOrderSelected()) continue;
      string c=OrderGetString(ORDER_COMMENT);
      double sl=OrderGetDouble(ORDER_SL); if(sl<=0){no_stop++;continue;}
      risk+=RiskPerLotAtStop((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE),OrderGetDouble(ORDER_PRICE_OPEN),sl)*OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return risk;
}

void RearmManualTracking()
{
   if(g_recovery_pending) return; // 重载后禁止自动手工循环补单

   // 独立于吸金框：停止框内吸金不会关闭这里。
   if(!ManualSmartTracking || !g_manual_tracking_active) return;
   if(!NewRiskAllowed("手工循环回挂")) return;
   if(NewsBlocked("手工循环回挂")) return;
   // 市价首批循环必须由“一键追踪”明确开启；吸筹系统完全不参与。
   if(g_manual_tracking_source_mode==1 && (!MarketCycleTracking || !g_one_key_trailing)) return;
   if(g_manual_tracking_source_mode==2 && !PendingCycleTracking) return;

   string slot=StringFormat("%s1",MANUAL_SPLIT_PREFIX);
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t>0 && IsFamilyPositionSelected() && PositionGetString(POSITION_COMMENT)==slot) return; }
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t>0 && IsFamilyOrderSelected() && OrderGetString(ORDER_COMMENT)==slot) return; }

   double pull=MathMax(PointValue(),GetGridGapPoints()*PointValue())*MathMax(1,ManualTrackPullbackGrids);
   double target=(g_manual_tracking_type==ORDER_TYPE_BUY?CurrentBid()-pull:CurrentAsk()+pull);
   target=NormalizePrice(target);
   double stop=NormalizePrice(g_manual_tracking_initial_stop);
   if(g_manual_tracking_type==ORDER_TYPE_BUY && target<=stop+TickSizeValue()) { SetStatus("手工智能跟踪暂停：回挂价已接近初始止损"); return; }
   if(g_manual_tracking_type==ORDER_TYPE_SELL && target>=stop-TickSizeValue()) { SetStatus("手工智能跟踪暂停：回挂价已接近初始止损"); return; }

   int no=0; double used=ManualTrackingCurrentRisk(no); if(no>0) return;
   double rem=MathMax(0.0,g_manual_tracking_initial_risk-used);
   int availNS=0; double safeAvailable=ManualAvailableRiskBudget(availNS);
   if(availNS>0) { SetStatus("手工智能跟踪暂停：受管系统存在无SL订单"); return; }
   rem=MathMin(rem,safeAvailable);

   double maxlots=LotsForRisk(g_manual_tracking_type,target,stop,rem);
   double lots=NormalizeLotsDown(MathMin(g_manual_tracking_seed_lots,maxlots));
   if(lots<=0) { SetStatus("手工智能跟踪暂停：剩余风险不足"); return; }

   double riskdist=MathAbs(target-stop);
   double dist=ManualCycleTpDistance(riskdist); // v1.67.1：每次回挂继续受循环TP最大R限制
   double tp=NormalizePrice(g_manual_tracking_type==ORDER_TYPE_BUY?target+dist:target-dist);
   ENUM_ORDER_TYPE ot=(g_manual_tracking_type==ORDER_TYPE_BUY?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT);
   string why="";
   if(!ValidateOrderLevels(ot,target,stop,tp,why))
   {
      SetStatus("手工智能跟踪暂停："+why);
      return;
   }

   bool ok=(g_manual_tracking_type==ORDER_TYPE_BUY?trade.BuyLimit(lots,target,_Symbol,stop,tp,ORDER_TIME_GTC,0,slot):trade.SellLimit(lots,target,_Symbol,stop,tp,ORDER_TIME_GTC,0,slot));
   if(ok)
   {
      g_manual_tracking_cycles++;
      SaveTrackingState();
      string src=(g_manual_tracking_source_mode==1?"市价":"排单");
      SetStatus(StringFormat("%s独立循环跟踪第%d次回挂 @ %.*f｜TP %.2fR内｜止盈后继续跟踪",
         src,g_manual_tracking_cycles,DigitsValue(),target,dist/MathMax(TickSizeValue(),riskdist)));
   }
   else
   {
      SetStatus("手工智能跟踪回挂失败｜"+LastTradeResultText(slot));
   }
}

// =========================
// 底仓保护 / 一键追踪
// =========================
double PositionCommissionCost(ulong pos_id)
{
   if(!HistorySelectByPosition(pos_id)) return 0;
   double c=0;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      c+=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
   }
   return MathAbs(c);
}

double CachedPositionCommission(ulong pos_id)
{
   ulong now=GetTickCount64();
   int n=ArraySize(g_comm_cache_id);
   for(int i=0;i<n;i++)
      if(g_comm_cache_id[i]==pos_id && now-g_comm_cache_ms[i]<60000) return g_comm_cache_val[i];

   double v=PositionCommissionCost(pos_id);
   int idx=-1;
   for(int i=0;i<n;i++) if(g_comm_cache_id[i]==pos_id) { idx=i; break; }
   if(idx<0)
   {
      if(n>=64) { ArrayResize(g_comm_cache_id,0); ArrayResize(g_comm_cache_val,0); ArrayResize(g_comm_cache_ms,0); n=0; }
      idx=n; ArrayResize(g_comm_cache_id,n+1); ArrayResize(g_comm_cache_val,n+1); ArrayResize(g_comm_cache_ms,n+1);
      g_comm_cache_id[idx]=pos_id;
   }
   g_comm_cache_val[idx]=v; g_comm_cache_ms[idx]=now;
   return v;
}

double MoneyPerPrice(double volume)
{
   double tickval=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickval<=0) tickval=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ticksize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ticksize<=0) return 0;
   return tickval*volume/ticksize;
}

double CostAwareBreakEven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   double mpp=MoneyPerPrice(vol); if(mpp<=0) return entry;
   double spread=MathMax(0.0,CurrentAsk()-CurrentBid());
   // v1.67.6：持仓中只扣了开仓佣金，平仓佣金还没发生；按往返估算，并不低于参数里的每手往返佣金。
   double commission=MathMax(CachedPositionCommission(id)*2.0,CommissionPerLotRT*vol)*CommissionProtectMultiplier;
   double swap=MathMax(0.0,-PositionGetDouble(POSITION_SWAP));
   double extra=BaseProtectExtraPoints*PointValue();
   double cost_price=(spread*mpp+commission+swap)/mpp+extra;
   return NormalizePrice(pt==POSITION_TYPE_BUY?entry+cost_price:entry-cost_price);
}

double GetInitialRiskPrice(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string gv=BaseRiskGV(id);
   if(GlobalVariableCheck(gv)) return GlobalVariableGet(gv);
   double e=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   bool valid=(sl>0 && (pt==POSITION_TYPE_BUY?sl<e:sl>e));
   if(valid)
   {
      double r=MathAbs(e-sl);
      if(r>PointValue()) { GlobalVariableSet(gv,r); return r; }
   }
   return 0;
}

void ApplyBaseProtection()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      if(!IsManualBaseComment(PositionGetString(POSITION_COMMENT))) continue;
      double R=GetInitialRiskPrice(t); if(R<=0) continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double current=(pt==POSITION_TYPE_BUY?CurrentBid():CurrentAsk());
      double move=(pt==POSITION_TYPE_BUY?current-entry:entry-current);
      if(move<BaseProtectStartR*R) continue;
      double oldsl=PositionGetDouble(POSITION_SL); double tp=PositionGetDouble(POSITION_TP);
      double be=CostAwareBreakEven(t);
      double desired=be;
      if(move>=BaseTrailStartR*R)
      {
         double trail=(pt==POSITION_TYPE_BUY?current-BaseTrailDistanceR*R:current+BaseTrailDistanceR*R);
         if(pt==POSITION_TYPE_BUY) desired=MathMax(be,trail); else desired=MathMin(be,trail);
      }
      desired=NormalizePrice(desired);
      bool improve=(pt==POSITION_TYPE_BUY?(oldsl<=0 || desired>oldsl+BaseTrailStepR*R):(oldsl<=0 || desired<oldsl-BaseTrailStepR*R));
      if(improve) ModifyPositionTicket(t,desired,tp);
   }
}

// =========================
// v1.59 一键追踪 = “手工首批止盈循环”，不再等于全仓推保护。
// 规则：
// 1) 不删除任何TP；
// 2) 不修改吸筹单（智能奇/智能偶）；
// 3) 不修改手工底仓；
// 4) 只控制手工分仓1的“止盈后回调再挂、继续吃利润”循环。
// =========================
void ToggleOneKeyTrailing()
{
   g_one_key_trailing=!g_one_key_trailing;
   SaveRecoveryRuntimeState();

   if(g_one_key_trailing)
   {
      // 如果市价开仓时已经ArmManualTracking，则这里只是打开循环开关。
      // 若EA重载后状态存在，也直接继续；绝不扫描/修改吸筹仓位。
      if(!g_manual_tracking_active)
      {
         SetStatus("一键追踪已开启：等待手工市价/排单计划；不会撤TP、不会接管吸筹单");
         return;
      }
      SetStatus("一键追踪已开启：仅手工第1分批止盈循环｜TP保留｜吸筹单隔离｜底仓不参与");
   }
   else
   {
      SetStatus("一键追踪已关闭：现有TP/SL保持不变，不撤单");
   }
}

void ApplyOneKeyTrailing()
{
   // v1.59：这里故意不再逐Tick修改任何持仓SL/TP。
   // 循环补单由 OnTradeTransaction -> RearmManualTracking() 驱动。
   // 这样“一键追踪”不会再把手工单/吸筹单统一变成推保护状态。
   return;
}

// =========================
// 锁仓 / 统一止盈止损 / 平仓
// =========================
void ToggleLock()
{
   ulong locktickets[]; ArrayResize(locktickets,0);
   double buy=0,sell=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsManagedPositionSelected()) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(IsLockComment(c)) { int n=ArraySize(locktickets); ArrayResize(locktickets,n+1); locktickets[n]=t; continue; }
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buy+=PositionGetDouble(POSITION_VOLUME); else sell+=PositionGetDouble(POSITION_VOLUME);
   }
   if(ArraySize(locktickets)>0)
   {
      int ok=0; for(int i=0;i<ArraySize(locktickets);i++) if(ClosePositionTicket(locktickets[i])) ok++;
      SetStatus(StringFormat("已解锁：%d笔",ok)); return;
   }
   if(!IsHedgingAccount()) { SetStatus("锁仓已阻止：非对冲账户反向开单会直接平仓，不是锁仓"); return; }
   double net=buy-sell; double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(MathAbs(net)<minv) { SetStatus("无需锁仓：净头寸接近0"); return; }
   double lots=NormalizeLotsDown(MathAbs(net));
   bool ok=(net>0?trade.Sell(lots,_Symbol,0,0,0,LOCK_LABEL):trade.Buy(lots,_Symbol,0,0,0,LOCK_LABEL));
   SetStatus(ok?"一键锁仓成功":"锁仓失败");
}

void CloseAllStrategy()
{
   ulong orders[]; ArrayResize(orders,0);
   ulong pos[]; ArrayResize(pos,0);
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t>0 && IsManagedOrderSelected()){int n=ArraySize(orders);ArrayResize(orders,n+1);orders[n]=t;} }
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t>0 && IsManagedPositionSelected()){int n=ArraySize(pos);ArrayResize(pos,n+1);pos[n]=t;} }
   for(int i=0;i<ArraySize(orders);i++) DeleteOrderTicket(orders[i]);
   for(int i=0;i<ArraySize(pos);i++) ClosePositionTicket(pos[i]);
   g_running=false; g_paused=true; SetStatus("已结束策略并平掉/撤销本策略全部订单");
}

void CancelAllPending()
{
   ulong arr[]; ArrayResize(arr,0);
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t>0 && IsManagedOrderSelected()){int n=ArraySize(arr);ArrayResize(arr,n+1);arr[n]=t;} }
   int ok=0; for(int i=0;i<ArraySize(arr);i++) if(DeleteOrderTicket(arr[i])) ok++;
   SetStatus(StringFormat("已撤销排单：%d笔",ok));
}

void AddSuppressId(ulong id)
{
   int n=ArraySize(g_suppress_position_ids); ArrayResize(g_suppress_position_ids,n+1); g_suppress_position_ids[n]=id;
}

bool ConsumeSuppressId(ulong id)
{
   for(int i=0;i<ArraySize(g_suppress_position_ids);i++)
   {
      if(g_suppress_position_ids[i]==id)
      {
         for(int j=i;j<ArraySize(g_suppress_position_ids)-1;j++) g_suppress_position_ids[j]=g_suppress_position_ids[j+1];
         ArrayResize(g_suppress_position_ids,ArraySize(g_suppress_position_ids)-1);
         return true;
      }
   }
   return false;
}

void CloseByProfit(bool winners)
{
   ulong arr[]; ulong ids[]; ArrayResize(arr,0); ArrayResize(ids,0);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsManagedPositionSelected()) continue;
      if(!IsManualSplitComment(PositionGetString(POSITION_COMMENT))) continue;
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if((winners && p>0) || (!winners && p<0))
      {
         int n=ArraySize(arr); ArrayResize(arr,n+1); ArrayResize(ids,n+1); arr[n]=t; ids[n]=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      }
   }
   int ok=0;
   for(int i=0;i<ArraySize(arr);i++) { AddSuppressId(ids[i]); if(ClosePositionTicket(arr[i])) ok++; }
   SetStatus(StringFormat("%s完成：%d笔（底仓/智能吸金不处理）",winners?"平分批盈":"平分批损",ok));
}

void PrepareUnifiedLine(bool buy,bool tp)
{
   string name;
   if(buy) name=tp?OBJ_LONG_TP:OBJ_LONG_SL; else name=tp?OBJ_SHORT_TP:OBJ_SHORT_SL;

   // 先给一个安全初始价；随后立即进入“跟随鼠标”模式。
   double p;
   if(buy) p=tp?CurrentAsk()+100*PointValue():CurrentBid()-100*PointValue();
   else p=tp?CurrentBid()-100*PointValue():CurrentAsk()+100*PointValue();

   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_HLINE,0,0,NormalizePrice(p));
   ObjectSetInteger(0,name,OBJPROP_COLOR,tp?clrLimeGreen:clrRed);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,3);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);

   g_unified_follow_active=true;
   g_unified_follow_name=name;

   SetStatus("统一线跟随鼠标：移动到目标价后，在图表空白处单击固定，再点确认统一");
}

void ApplyUnified(bool buy)
{
   string tpname=buy?OBJ_LONG_TP:OBJ_SHORT_TP;
   string slname=buy?OBJ_LONG_SL:OBJ_SHORT_SL;
   bool htp=ObjectFind(0,tpname)>=0;
   bool hsl=ObjectFind(0,slname)>=0;

   if(!htp && !hsl)
   {
      SetStatus(StringFormat("统一%s：请先建立止盈线或止损线",buy?"多":"空"));
      return;
   }

   double tp=htp?ObjectGetDouble(0,tpname,OBJPROP_PRICE):0;
   double sl=hsl?ObjectGetDouble(0,slname,OBJPROP_PRICE):0;

   int target=0;
   int ok=0;
   int fail=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !IsManagedPositionSelected()) continue;
      if(IsLockComment(PositionGetString(POSITION_COMMENT))) continue;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((buy && pt!=POSITION_TYPE_BUY) || (!buy && pt!=POSITION_TYPE_SELL)) continue;

      target++;
      double nsl=hsl?sl:PositionGetDouble(POSITION_SL);
      double ntp=htp?tp:PositionGetDouble(POSITION_TP);

      if(ModifyPositionTicket(t,nsl,ntp)) ok++;
      else fail++;
   }

   if(target<=0)
   {
      g_unified_follow_active=false;
      g_unified_follow_name="";
      SetStatus(StringFormat("统一%s：当前没有可处理持仓，统一线保留",buy?"多":"空"));
      return;
   }

   // v1.66.2：全部目标仓位修改成功后，自动删除本方向统一TP/SL辅助线。
   // 若有任意失败则保留辅助线，方便用户检查后直接重试，避免误以为全部设置成功。
   g_unified_follow_active=false;
   g_unified_follow_name="";

   if(fail==0 && ok==target)
   {
      if(htp) ObjectDelete(0,tpname);
      if(hsl) ObjectDelete(0,slname);
      ChartRedraw();
      SetStatus(StringFormat("统一%s已应用：%d笔｜统一线已自动消失",buy?"多":"空",ok));
   }
   else
   {
      SetStatus(StringFormat("统一%s部分完成：成功%d/%d，失败%d｜统一线保留便于重试",
                             buy?"多":"空",ok,target,fail));
   }
}

// =========================
// 当前品种：持仓 + 排单风险弹窗
// 计算口径：以各订单当前止损价为最大风险边界。
// 无止损项无法得到有限最大风险，因此单独计数并醒目标记。
// =========================
void ShowCurrentSymbolRiskPopup()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);

   double pos_risk=0.0, pos_profit=0.0;
   double pend_risk=0.0, pend_profit=0.0;
   double pos_lots=0.0, pend_lots=0.0;

   int pos_count=0, pend_count=0;
   int pos_no_sl=0, pos_no_tp=0;
   int pend_no_sl=0, pend_no_tp=0;

   // =====【风险盈亏统计层】当前品种全部持仓 =====
   // 与Jammy吸金风控完全分离。
   // 不限制 Magic Number，也不限制订单注释：只要是当前图表品种就统计。
   // 因此：Jammy EA + 其他EA + 手工单，全部进入本风险盈亏面板。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      pos_count++;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=PositionDirectionOrderType(pt);

      pos_lots+=volume;

      // SL风险：只把到SL时为负的金额计入“风险”。
      // 如果SL已经推进盈利区，则不把锁定利润抵扣其它订单风险。
      if(sl<=0)
         pos_no_sl++;
      else
      {
         double money_sl=MoneyAtExit(ot,volume,entry,sl,_Symbol);
         if(money_sl<0) pos_risk+=-money_sl;
      }

      // TP收益：只把到TP时为正的金额计入“止盈潜力”。
      if(tp<=0)
         pos_no_tp++;
      else
      {
         double money_tp=MoneyAtExit(ot,volume,entry,tp,_Symbol);
         if(money_tp>0) pos_profit+=money_tp;
      }
   }

   // ===== 当前品种全部未成交排单 =====
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;

      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool is_pending=(ot==ORDER_TYPE_BUY_LIMIT ||
                       ot==ORDER_TYPE_SELL_LIMIT ||
                       ot==ORDER_TYPE_BUY_STOP ||
                       ot==ORDER_TYPE_SELL_STOP ||
                       ot==ORDER_TYPE_BUY_STOP_LIMIT ||
                       ot==ORDER_TYPE_SELL_STOP_LIMIT);
      if(!is_pending) continue;

      pend_count++;

      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      double volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
      double sl=OrderGetDouble(ORDER_SL);
      double tp=OrderGetDouble(ORDER_TP);

      pend_lots+=volume;

      // 排单风险/收益以“假设按排单价成交”为基准。
      if(sl<=0)
         pend_no_sl++;
      else
      {
         double r=RiskPerLotAtStop(ot,entry,sl,_Symbol)*volume;
         if(r>0) pend_risk+=r;
      }

      if(tp<=0)
         pend_no_tp++;
      else
      {
         double money_tp=MoneyAtExit(ot,volume,entry,tp,_Symbol);
         if(money_tp>0) pend_profit+=money_tp;
      }
   }

   double total_risk=pos_risk+pend_risk;
   double total_profit=pos_profit+pend_profit;

   double pos_risk_pct=(equity>0 ? pos_risk/equity*100.0 : 0.0);
   double pend_risk_pct=(equity>0 ? pend_risk/equity*100.0 : 0.0);
   double total_risk_pct=(equity>0 ? total_risk/equity*100.0 : 0.0);

   string pos_rr=(pos_risk>0.000001
                  ? StringFormat("1 : %.2f",pos_profit/pos_risk)
                  : (pos_profit>0.000001 ? "无可量化亏损风险" : "--"));

   string pend_rr=(pend_risk>0.000001
                   ? StringFormat("1 : %.2f",pend_profit/pend_risk)
                   : (pend_profit>0.000001 ? "无可量化亏损风险" : "--"));

   string total_rr=(total_risk>0.000001
                    ? StringFormat("1 : %.2f",total_profit/total_risk)
                    : (total_profit>0.000001 ? "无可量化亏损风险" : "--"));

   string warning="";
   if(pos_no_sl>0 || pos_no_tp>0 || pend_no_sl>0 || pend_no_tp>0)
   {
      warning=StringFormat(
         "\n\n【未完全量化】\n"
         "持仓无SL：%d笔｜无TP：%d笔\n"
         "排单无SL：%d笔｜无TP：%d笔\n"
         "以上无SL/TP订单不包含在对应的风险/收益金额中。",
         pos_no_sl,pos_no_tp,pend_no_sl,pend_no_tp);
   }

   string msg=StringFormat(
      "【%s 全部持仓/排单风险盈亏】\n\n"
      "账户净值：$%.2f\n"
      "账户余额：$%.2f\n"
      "统计范围：当前品种全部订单（Jammy + 其他EA + 手工单）\n\n"
      "【所有持仓】\n"
      "数量：%d笔｜总手数：%.4f\n"
      "止损风险：-$%.2f\n"
      "止盈潜力：+$%.2f\n"
      "风险收益比：%s\n"
      "风险 / 净值：%.2f%%\n\n"
      "【所有未成交排单】\n"
      "数量：%d笔｜总手数：%.4f\n"
      "成交后止损风险：-$%.2f\n"
      "成交后止盈潜力：+$%.2f\n"
      "风险收益比：%s\n"
      "风险 / 净值：%.2f%%\n\n"
      "【持仓 + 排单合计】\n"
      "总止损风险：-$%.2f\n"
      "总止盈潜力：+$%.2f\n"
      "综合风险收益比：%s\n"
      "总风险 / 净值：%.2f%%%s",
      _Symbol,
      equity,balance,
      pos_count,pos_lots,pos_risk,pos_profit,pos_rr,pos_risk_pct,
      pend_count,pend_lots,pend_risk,pend_profit,pend_rr,pend_risk_pct,
      total_risk,total_profit,total_rr,total_risk_pct,
      warning);

   MessageBox(msg,"Jammy｜当前品种全部订单风险盈亏",MB_OK|MB_ICONINFORMATION);

   SetStatus(StringFormat(
      "%s｜持仓 R -$%.2f / P +$%.2f｜排单 R -$%.2f / P +$%.2f｜总RR %s",
      _Symbol,pos_risk,pos_profit,pend_risk,pend_profit,total_rr));
}

// =========================
// EA家族风险面板 / 统计
// =========================
double FamilyKnownRisk(int &no_sl,double &locked,double &tp_potential,int &no_tp)
{
   no_sl=0; no_tp=0; locked=0; tp_potential=0; double risk=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsFamilyPositionSelected()) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=PositionDirectionOrderType(pt);
      double e=PositionGetDouble(POSITION_PRICE_OPEN),v=PositionGetDouble(POSITION_VOLUME),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(sl<=0) no_sl++;
      else
      {
         double p=MoneyAtExit(ot,v,e,sl);
         if(p<0) risk+=-p; else locked+=p;
      }
      if(tp<=0) no_tp++; else { double p=MoneyAtExit(ot,v,e,tp); if(p>0) tp_potential+=p; }
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i); if(t==0 || !IsFamilyOrderSelected()) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE); double e=OrderGetDouble(ORDER_PRICE_OPEN),v=OrderGetDouble(ORDER_VOLUME_CURRENT),sl=OrderGetDouble(ORDER_SL),tp=OrderGetDouble(ORDER_TP);
      if(sl<=0) no_sl++; else risk+=RiskPerLotAtStop(ot,e,sl)*v;
      if(tp<=0) no_tp++; else { double p=MoneyAtExit(ot,v,e,tp); if(p>0) tp_potential+=p; }
   }
   return risk;
}

double WeightedAverage(bool buy)
{
   double pv=0,v=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsManagedPositionSelected()) continue;
      if(IsLockComment(PositionGetString(POSITION_COMMENT))) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((buy&&pt!=POSITION_TYPE_BUY)||(!buy&&pt!=POSITION_TYPE_SELL)) continue;
      double vol=PositionGetDouble(POSITION_VOLUME); pv+=PositionGetDouble(POSITION_PRICE_OPEN)*vol; v+=vol;
   }
   return v>0?pv/v:0;
}

double SidePnL(bool buy)
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i); if(t==0 || !IsManagedPositionSelected()) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((buy&&pt==POSITION_TYPE_BUY)||(!buy&&pt==POSITION_TYPE_SELL)) p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

int NthSundayOfMonth(int year,int month,int nth)
{
   MqlDateTime d={};
   d.year=year; d.mon=month; d.day=1;
   datetime first=StructToTime(d);

   MqlDateTime f={};
   TimeToStruct(first,f);

   int daysToSunday=(7-f.day_of_week)%7;
   return 1+daysToSunday+7*(nth-1);
}

int NewYorkUtcOffsetSeconds(datetime utcTime)
{
   MqlDateTime u={};
   TimeToStruct(utcTime,u);

   int marchSunday=NthSundayOfMonth(u.year,3,2);
   int novemberSunday=NthSundayOfMonth(u.year,11,1);

   MqlDateTime ds={};
   ds.year=u.year; ds.mon=3; ds.day=marchSunday; ds.hour=7;

   MqlDateTime de={};
   de.year=u.year; de.mon=11; de.day=novemberSunday; de.hour=6;

   datetime dstStartUtc=StructToTime(ds);
   datetime dstEndUtc=StructToTime(de);

   return (utcTime>=dstStartUtc && utcTime<dstEndUtc) ? -4*3600 : -5*3600;
}

int NewYorkOffsetAtSessionOpen(int year,int month,int day)
{
   int marchSunday=NthSundayOfMonth(year,3,2);
   int novemberSunday=NthSundayOfMonth(year,11,1);

   if(month<3 || month>11) return -5*3600;
   if(month>3 && month<11) return -4*3600;
   if(month==3) return day>=marchSunday ? -4*3600 : -5*3600;
   return day<novemberSunday ? -4*3600 : -5*3600;
}

datetime CmeSessionStartUtc()
{
   datetime utcNow=TimeGMT();
   int currentNyOffset=NewYorkUtcOffsetSeconds(utcNow);
   datetime nyClock=utcNow+currentNyOffset;

   MqlDateTime ny={};
   TimeToStruct(nyClock,ny);

   int shiftDays=0;

   if(ny.day_of_week==5)           // Friday
      shiftDays=-1;
   else if(ny.day_of_week==6)      // Saturday
      shiftDays=-2;
   else if(ny.day_of_week==0)      // Sunday
      shiftDays=(ny.hour>=18 ? 0 : -3);
   else
      shiftDays=(ny.hour>=18 ? 0 : -1);

   MqlDateTime noon=ny;
   noon.hour=12; noon.min=0; noon.sec=0;

   datetime shiftedNoon=StructToTime(noon)+shiftDays*86400;

   MqlDateTime sessionLocal={};
   TimeToStruct(shiftedNoon,sessionLocal);
   sessionLocal.hour=18; sessionLocal.min=0; sessionLocal.sec=0;

   datetime sessionNyClock=StructToTime(sessionLocal);
   int sessionNyOffset=NewYorkOffsetAtSessionOpen(
      sessionLocal.year,sessionLocal.mon,sessionLocal.day);

   return sessionNyClock-sessionNyOffset;
}

datetime CmeSessionStartInServerTime()
{
   datetime utcNow=TimeGMT();
   datetime serverNow=TimeTradeServer();
   if(serverNow<=0) serverNow=TimeCurrent();

   long serverOffset=(long)(serverNow-utcNow);
   return CmeSessionStartUtc()+serverOffset;
}

string CmeOpenBeijingTimeText()
{
   datetime bj=CmeSessionStartUtc()+8*3600;
   MqlDateTime b={};
   TimeToStruct(bj,b);
   return StringFormat("%02d:%02d",b.hour,b.min);
}

double LoadTodayPnL()
{
   datetime from=CmeSessionStartInServerTime();
   datetime to=TimeTradeServer();
   if(to<=0) to=TimeCurrent();

   if(!HistorySelect(from,to))
      return 0;

   double sum=0;
   int n=HistoryDealsTotal();

   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;

      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol)
         continue;

      long magic=HistoryDealGetInteger(d,DEAL_MAGIC);
      string c=HistoryDealGetString(d,DEAL_COMMENT);

      // This EA family only.
      if(!(magic==MagicNumber || IsEaFamilyComment(c)))
         continue;

      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(en!=DEAL_ENTRY_OUT && en!=DEAL_ENTRY_OUT_BY)
         continue;

      sum += HistoryDealGetDouble(d,DEAL_PROFIT)
           + HistoryDealGetDouble(d,DEAL_SWAP)
           + HistoryDealGetDouble(d,DEAL_COMMISSION)
           + HistoryDealGetDouble(d,DEAL_FEE);
   }

   g_today_pnl_cache=sum;
   g_today_pnl_loaded=true;
   return sum;
}

// =========================
// 热图：自动识别代码 + 当日累计涨跌
// =========================
string FindBrokerSymbol(string aliases)
{
   string parts[]; int pc=StringSplit(aliases,StringGetCharacter("|",0),parts);
   string best=""; int bestscore=-1;
   int total=SymbolsTotal(false);
   for(int i=0;i<total;i++)
   {
      string name=SymbolName(i,false); string norm=NormalizeToken(name);
      for(int j=0;j<pc;j++)
      {
         string a=NormalizeToken(parts[j]); if(a=="") continue;
         int sc=-1;
         if(norm==a) sc=100;
         else if(StartsWith(norm,a)) sc=90;
         else if(StringFind(norm,a)>=0) sc=70;
         if(sc>bestscore) { bestscore=sc; best=name; }
      }
   }
   if(bestscore>=70) { SymbolSelect(best,true); return best; }
   return "";
}

void DetectHeatSymbols()
{
   g_heat_symbols[0]=FindBrokerSymbol("XAUUSD|GOLD");
   g_heat_symbols[1]=FindBrokerSymbol("XAGUSD|SILVER");
   g_heat_symbols[2]=FindBrokerSymbol("XTIUSD|USOIL|WTIUSD|WTI");
   g_heat_symbols[3]=FindBrokerSymbol("XBRUSD|UKOIL|BRENT");
   g_heat_symbols[4]=FindBrokerSymbol("BTCUSD|BTCUSDT");
   g_heat_symbols[5]=FindBrokerSymbol("NAS100|US100|USTEC|NDX100|NASDAQ100");
   g_heat_symbols[6]=FindBrokerSymbol("SP500|SPX500|US500|SPX|S&P500");
   g_heat_symbols[7]=FindBrokerSymbol("US30|DJ30|DJI|DOW30|WS30");
   g_heat_symbols[8]=FindBrokerSymbol("EURUSD");
   g_heat_symbols[9]=FindBrokerSymbol("GBPUSD");
   g_heat_symbols[10]=FindBrokerSymbol("AUDUSD");
   g_heat_symbols[11]=FindBrokerSymbol("NZDUSD");
   g_heat_symbols[12]=FindBrokerSymbol("USDCAD");
   g_heat_symbols[13]=FindBrokerSymbol("USDCHF");
   g_heat_symbols[14]=FindBrokerSymbol("USDJPY");
}

bool CurrentChartHasManagedExposure()
{
   // 当前图表仍有本EA管理的持仓/挂单时，不直接改掉图表品种，
   // 避免EA因切换品种重新初始化后失去对原品种的持续管理。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(IsManagedPositionSelected()) return true;
   }

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0) continue;
      if(IsManagedOrderSelected()) return true;
   }

   return g_running || g_manual_tracking_active || g_smart_user_confirmed;
}

int HeatCellIndex(const string object_name)
{
   string prefix=A_PREFIX+"CELL_";
   if(!StartsWith(object_name,prefix)) return -1;

   string tail=StringSubstr(object_name,StringLen(prefix));
   if(tail=="") return -1;

   int idx=(int)StringToInteger(tail);
   if(idx<0 || idx>=15) return -1;
   return idx;
}

void SwitchHeatmapSymbolByIndex(const int idx)
{
   if(!HeatmapClickSwitchSymbol)
   {
      SetStatus("热图点击切换已关闭");
      return;
   }

   if(idx<0 || idx>=15) return;

   // 如果用户还没点过“加载市场分析”，这里也自动完成经纪商品种映射。
   if(g_heat_symbols[idx]=="")
      DetectHeatSymbols();

   string target=g_heat_symbols[idx];
   if(target=="")
   {
      SetStatus("热图映射失败："+g_heat_keys[idx]+"｜当前经纪商未找到对应品种");
      return;
   }

   if(!SymbolSelect(target,true))
   {
      SetStatus("无法选择品种："+target);
      return;
   }

   ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)ChartPeriod(0);

   if(target==_Symbol)
   {
      SetStatus("当前已经是 "+target+"｜周期 "+EnumToString(tf));
      return;
   }

   // 安全模式：当前图表有持仓/排单/运行任务时，在新图表打开，
   // 不把正在管理交易的EA图表直接切走。
   if(HeatmapSafeOpenNewChart && CurrentChartHasManagedExposure())
   {
      long cid=ChartOpen(target,tf);
      if(cid>0)
         SetStatus("已自动映射 "+g_heat_keys[idx]+" → "+target+"｜检测到持仓/任务，已在新图表打开");
      else
         SetStatus("自动映射成功但新图表打开失败："+target);
      return;
   }

   SetStatus("正在切换："+g_heat_keys[idx]+" → "+target+"｜保持 "+EnumToString(tf));
   if(!ChartSetSymbolPeriod(0,target,tf))
      SetStatus("图表切换失败："+target);
}

bool TryDayReturnCached(const int i,double &out_value,const bool allow_request=false)
{
   out_value=EMPTY_VALUE;
   if(i<0 || i>=15) return false;

   string symbol=g_heat_symbols[i];
   if(symbol=="") return false;

   // 先尝试使用已经同步好的D1数据。
   long synced=SeriesInfoInteger(symbol,PERIOD_D1,SERIES_SYNCHRONIZED);
   if(synced!=0)
   {
      MqlRates r[];
      ArraySetAsSeries(r,true);
      if(CopyRates(symbol,PERIOD_D1,0,1,r)>=1 && r[0].open>0)
      {
         MqlTick t;
         if(SymbolInfoTick(symbol,t))
         {
            double cur=(t.bid+t.ask)*0.5;
            if(cur<=0) cur=t.last;
            if(cur>0)
            {
               bool inverse=(i==12 || i==13 || i==14);
               double v=inverse ? (r[0].open/cur-1.0)*100.0
                                : (cur-r[0].open)/r[0].open*100.0;
               g_heat_cache[i]=v;
               g_heat_cache_valid[i]=true;
               out_value=v;
               return true;
            }
         }
      }
   }

   // 历史暂未同步时，最多60秒主动请求一次；但UI继续显示最后有效缓存，不闪回“--”。
   if(allow_request)
   {
      datetime now=TimeCurrent();
      if(g_heat_last_request[i]==0 || now-g_heat_last_request[i]>=60)
      {
         g_heat_last_request[i]=now;
         MqlRates warm[];
         ArraySetAsSeries(warm,true);
         CopyRates(symbol,PERIOD_D1,0,2,warm);
      }
   }

   if(g_heat_cache_valid[i])
   {
      out_value=g_heat_cache[i];
      return true;
   }

   return false;
}

double HeatValue(int i)
{
   double v=EMPTY_VALUE;
   TryDayReturnCached(i,v,false);
   return v;
}

void WarmupHeatHistory()
{
   // 只做低频预热；失败的品种以后按60秒冷却重试。
   for(int i=0;i<15;i++)
   {
      if(g_heat_symbols[i]=="") continue;
      double v=EMPTY_VALUE;
      TryDayReturnCached(i,v,true);
   }
}

void LoadAnalytics()
{
   if(g_analytics_busy) return;
   g_analytics_busy=true;

   DetectHeatSymbols();
   WarmupHeatHistory();

   g_analytics_loaded=true;

   datetime now=TimeCurrent();
   // 加载后立即画一次，随后从“现在+间隔”开始计时，
   // 不再把next设为0导致下一秒Timer又重复刷新一次。
   g_next_analytics_refresh=now+MathMax(30,ConfluenceRefreshSeconds);
   g_next_heat_refresh=now+MathMax(60,HeatmapRefreshSeconds);

   RefreshConfluence();
   RefreshHeatmap();

   if(ObjectFind(0,A_PREFIX+"LOAD")>=0)
      ObjectSetString(0,A_PREFIX+"LOAD",OBJPROP_TEXT,"市场分析已加载");

   SetStatus("市场分析已加载｜热图采用缓存稳定显示，不再反复闪回加载状态");
   g_analytics_busy=false;
   ChartRedraw();
}

// =========================
// GUI helpers
// =========================
void DeleteByPrefix(string prefix)
{
   int n=ObjectsTotal(0,-1,-1);
   for(int i=n-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(StartsWith(name,prefix)) ObjectDelete(0,name);
   }
}

void RectLabel(string name,int x,int y,int w,int h,color bg,bool selectable=false)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_BACK,false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Label(string name,string text,int x,int y,color col=clrWhite,int fs=-1)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs>0?fs:FontSize);
   ObjectSetString(0,name,OBJPROP_TEXT,text); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Button(string name,string text,int x,int y,int w,int h,color bg)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,MathMax(8,FontSize-1)); ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void CompactButton(string name,string text,int x,int y,int w,int h,color bg,int fs)
{
   Button(name,text,x,y,w,h,bg);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,MathMax(7,fs));
}

void EditBox(string name,string text,int x,int y,int w,int h)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h); ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack); ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,MathMax(8,FontSize-1)); ObjectSetString(0,name,OBJPROP_TEXT,text); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void BuildMainPanel()
{
   DeleteByPrefix(UI_PREFIX);
   int x=PanelLeftOffset,y=PanelTopOffset,w=PanelWidth,bh=ButtonHeight,g=3;

   // 先给足背景高度，最后再按实际内容精确收口，避免构建过程中出现文字短暂跑出背景。
   RectLabel(UI_PREFIX+"BG",x,y,w,780,C'11,16,22');
   Label(UI_PREFIX+"TITLE","Jammy 吞金兽 MT5 v1.68.1｜Auction + NumPad",x+8,y+6,clrDeepSkyBlue,FontSize+1);
   int yy=y+28; int bw=(w-5*g)/4;
   Button(UI_PREFIX+"LOCK","一键锁仓 [/]",x+g,yy,bw,bh,clrMaroon); Button(UI_PREFIX+"CLOSEALL","一键清仓 [*]",x+2*g+bw,yy,bw,bh,clrRed); Button(UI_PREFIX+"TRAIL","一键追踪",x+3*g+2*bw,yy,bw,bh,clrSteelBlue); Button(UI_PREFIX+"SMARTCALC","智能吸金/计算",x+4*g+3*bw,yy,bw,bh,clrPurple);
   yy+=bh+g;
   Button(UI_PREFIX+"LTP","统一多盈线",x+g,yy,bw,bh,clrDarkGreen); Button(UI_PREFIX+"LSL","统一多损线",x+2*g+bw,yy,bw,bh,clrFireBrick); Button(UI_PREFIX+"LAPPLY","确认统一多",x+3*g+2*bw,yy,bw,bh,clrSteelBlue); Button(UI_PREFIX+"DEAN","修心悟道",x+4*g+3*bw,yy,bw,bh,clrDarkGreen);
   yy+=bh+g;
   Button(UI_PREFIX+"STP","统一空盈线",x+g,yy,bw,bh,clrDarkGreen); Button(UI_PREFIX+"SSL","统一空损线",x+2*g+bw,yy,bw,bh,clrFireBrick); Button(UI_PREFIX+"SAPPLY","确认统一空",x+3*g+2*bw,yy,bw,bh,clrSteelBlue); Button(UI_PREFIX+"RISK","计算风险",x+4*g+3*bw,yy,bw,bh,clrDarkSlateBlue);
   yy+=bh+g;
   int bw3=(w-4*g)/3;
   Button(UI_PREFIX+"BOXBUY","▲ 建立多头框 [7]",x+g,yy,bw3,bh,clrTeal); Button(UI_PREFIX+"BOXSELL","▼ 建立空头框 [8]",x+2*g+bw3,yy,bw3,bh,clrFireBrick); Button(UI_PREFIX+"PLAN","计算吸金计划 [9]",x+3*g+2*bw3,yy,bw3,bh,clrSteelBlue);
   yy+=bh+g;
   Button(UI_PREFIX+"START","? 确认开始吸金 [+]",x+g,yy,(w-3*g)/2,bh,clrDarkGreen); Button(UI_PREFIX+"CANCELPLAN","取消吸金计划",x+2*g+(w-3*g)/2,yy,(w-3*g)/2,bh,clrSaddleBrown);
   yy+=bh+g;
   Button(UI_PREFIX+"DRAWSL","画线止损 [4]",x+g,yy,bw3,bh,clrMediumVioletRed); Button(UI_PREFIX+"CANCELORD","删除排单 [.]",x+2*g+bw3,yy,bw3,bh,clrGoldenrod); Button(UI_PREFIX+"CLOSELOSS","平分批损",x+3*g+2*bw3,yy,bw3,bh,clrFireBrick);
   yy+=bh+g;
   Button(UI_PREFIX+"MKTCALC","计算市价风险 [5]",x+g,yy,(w-3*g)/2,bh,clrSteelBlue); Button(UI_PREFIX+"MKTGO","?确认市价开仓 [6]",x+2*g+(w-3*g)/2,yy,(w-3*g)/2,bh,clrDarkGreen);
   yy+=bh+g;
   Button(UI_PREFIX+"ENTRY","设置排单线 [1]",x+g,yy,bw3,bh,clrDodgerBlue); Button(UI_PREFIX+"PENDCALC","计算排单风险 [2]",x+2*g+bw3,yy,bw3,bh,clrSteelBlue); Button(UI_PREFIX+"PENDGO","?确认排单入场 [3]",x+3*g+2*bw3,yy,bw3,bh,clrDarkGreen);
   yy+=bh+g;
   Button(UI_PREFIX+"CANCELMAN","取消手工计划",x+g,yy,bw3,bh,clrSaddleBrown); Button(UI_PREFIX+"CLOSEWIN","平分批盈",x+2*g+bw3,yy,bw3,bh,clrDarkGreen); Button(UI_PREFIX+"TODAY","加载CME盈亏",x+3*g+2*bw3,yy,bw3,bh,clrDimGray);
   yy+=bh+g+2;
   Label(UI_PREFIX+"LRISK","风险$",x+g,yy+5,clrWhite); EditBox(UI_PREFIX+"ED_RISK",DoubleToString(g_risk_usd,2),x+50,yy,70,bh);
   Label(UI_PREFIX+"LLOTS","固定手",x+126,yy+5,clrWhite); EditBox(UI_PREFIX+"ED_LOTS",DoubleToString(g_fixed_lots,3),x+180,yy,66,bh);
   Label(UI_PREFIX+"LBASE","底仓比",x+252,yy+5,clrWhite); EditBox(UI_PREFIX+"ED_BASE",DoubleToString(g_base_ratio,2),x+306,yy,56,bh);
   Button(UI_PREFIX+"APPLY","?应用",x+366,yy,58,bh,clrSteelBlue);

   yy+=bh+g;
   Label(UI_PREFIX+"LRR","目标RR",x+g,yy+5,clrWhite);
   EditBox(UI_PREFIX+"ED_RR",DoubleToString(g_even_rr,2),x+58,yy,72,bh);
   Label(UI_PREFIX+"LTPMODE","止盈模式",x+142,yy+5,clrWhite);
   Button(UI_PREFIX+"TPMODE",TpModeText(),x+205,yy,72,bh,g_tp_mode==TP_ADVANCED?clrDarkGoldenrod:clrDarkSlateGray);
   Label(UI_PREFIX+"LRRNOTE","普通=线性｜进阶=曲线，不再倍增",x+280,yy+5,clrLightGray,MathMax(8,FontSize-4));

   yy+=bh+g;
   Label(UI_PREFIX+"LSL2","止损",x+g,yy+5,clrWhite); EditBox(UI_PREFIX+"ED_STOP",ManualStopExists()?DoubleToString(ManualStopPrice(),DigitsValue()):"0",x+42,yy,92,bh);
   Label(UI_PREFIX+"LENT","入场",x+140,yy+5,clrWhite); EditBox(UI_PREFIX+"ED_ENTRY",EntryLineExists()?DoubleToString(EntryPriceLine(),DigitsValue()):"0",x+182,yy,92,bh);
   Button(UI_PREFIX+"PAUSE","暂停/恢复补单",x+282,yy,142,bh,clrDarkSlateGray);
   yy+=bh+g;
   Button(UI_PREFIX+"RECOVER","恢复任务",x+g,yy,(w-3*g)/2,bh,clrDarkGreen);
   Button(UI_PREFIX+"ABANDON","放弃恢复",x+2*g+(w-3*g)/2,yy,(w-3*g)/2,bh,clrDarkSlateGray);
   yy+=bh+g;
   Button(UI_PREFIX+"STOPSMART","停止吸金 [-]",x+g,yy,(w-3*g)/2,bh,clrDimGray); Button(UI_PREFIX+"ENDALL","结束+全平",x+2*g+(w-3*g)/2,yy,(w-3*g)/2,bh,clrRed);

   // v1.67.3：这里就是用户指定的“折叠位置”。
   // 左键折叠/展开底部统计与状态；右侧可直接隐藏整个主/分析面板。
   yy+=bh+g;
   Button(UI_PREFIX+"FOLDINFO",g_info_collapsed?"▼ 展开状态信息":"▲ 折叠状态信息",x+g,yy,(w-3*g)/2,bh,clrDarkSlateGray);
   Button(UI_PREFIX+"HIDEUI","隐藏面板 [0]",x+2*g+(w-3*g)/2,yy,(w-3*g)/2,bh,clrDimGray);
   yy+=bh+7;

   if(!g_info_collapsed)
   {
      // MT5 OBJ_LABEL 不会自动裁剪/换行，因此统计采用独立行，状态采用3行软换行。
      int infoFs=MathMax(8,FontSize-4);
      int lineH=MathMax(16,infoFs+6);

      for(int i=0;i<8;i++)
      {
         color c=(i>=5 ? clrGold : clrWhite);
         Label(UI_PREFIX+"INFO_"+IntegerToString(i),"",x+8,yy+i*lineH,c,infoFs);
      }

      yy+=8*lineH+6;
      int statusFs=MathMax(8,FontSize-4);
      int statusH=MathMax(16,statusFs+6);
      for(int i=0;i<3;i++)
         Label(UI_PREFIX+"STATUS_"+IntegerToString(i),"",x+8,yy+i*statusH,clrLightGray,statusFs);

      RenderMainStatusRows();
      yy+=3*statusH+12;
   }
   else
   {
      int fs=MathMax(8,FontSize-4);
      int h=MathMax(17,fs+7);
      Label(UI_PREFIX+"INFO_FOLDED","状态信息已折叠｜点击“展开状态信息”恢复",x+8,yy+1,clrLightGray,fs);
      yy+=h+10;
   }

   // 背景始终比最后一行文字多留安全边距，确保所有文字完全处于UI内部。
   int totalh=MathMax(120,yy-y+10);
   ObjectSetInteger(0,UI_PREFIX+"BG",OBJPROP_YSIZE,totalh);
}

void ToggleInfoCollapsed()
{
   g_info_collapsed=!g_info_collapsed;
   BuildMainPanel();
   RefreshMainStats();
   ChartRedraw();
}

void MoveAnalyticsChildren(int x,int y)
{
   g_analytics_x=x;
   g_analytics_y=y;

   ObjectSetInteger(0,A_PREFIX+"BG",OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,A_PREFIX+"BG",OBJPROP_YDISTANCE,y);

   int afs=MathMax(8,FontSize-4);
   int titleFs=MathMax(9,FontSize-3);

   Label(A_PREFIX+"TITLE","市场热图 + 多周期共振",x+8,y+6,clrDeepSkyBlue,titleFs);

   CompactButton(A_PREFIX+"LEFT","右上",x+250,y+3,50,22,clrDarkSlateGray,afs);
   CompactButton(A_PREFIX+"RIGHT","右下",x+302,y+3,50,22,clrDarkSlateGray,afs);
   CompactButton(A_PREFIX+"REFRESH","刷新",x+354,y+3,58,22,clrSteelBlue,afs);

   CompactButton(A_PREFIX+"LOAD","加载市场分析",x+8,y+31,110,22,clrTeal,afs);
   Label(A_PREFIX+"HEATDESC","热图: 当天累计(D1开盘→当前价)",
         x+126,y+35,clrLightGray,afs);

   // Confluence section uses smaller fonts and more rows to avoid clipping.
   Label(A_PREFIX+"CF1","多周期共振：未加载",x+8,y+62,clrGold,afs);
   Label(A_PREFIX+"CF2","",x+8,y+79,clrWhite,afs);
   Label(A_PREFIX+"CF3","",x+8,y+96,clrWhite,afs);
   Label(A_PREFIX+"CF4","",x+8,y+113,clrLightGray,afs);
   Label(A_PREFIX+"CF5","",x+8,y+130,clrLightGray,afs);
   Label(A_PREFIX+"CF6","",x+8,y+147,clrLightGray,afs);
   Label(A_PREFIX+"CF7","",x+8,y+164,clrGold,afs);

   int cy=y+187;
   for(int i=0;i<15;i++)
   {
      int row=i/5;
      int col=i%5;
      string n=A_PREFIX+"CELL_"+IntegerToString(i);
      CompactButton(n,g_heat_keys[i]+" 等待",
                    x+8+col*80,
                    cy+row*27,
                    76,24,clrDarkSlateGray,MathMax(7,afs-1));
   }
}

void MoveAnalyticsRightBottom()
{
   if(g_analytics_repositioning) return;

   long cw=0,ch=0;
   ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0,cw);
   ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0,ch);

   int x=MathMax(5,(int)cw-430);
   int y=MathMax(5,(int)ch-295);

   // 已经在目标位置时不重复移动，避免右下角不断触发重绘。
   if(ObjectFind(0,A_PREFIX+"BG")>=0 &&
      g_analytics_x==x && g_analytics_y==y)
   {
      g_analytics_last_chart_w=cw;
      g_analytics_last_chart_h=ch;
      g_analytics_custom_moved=false;
      return;
   }

   g_analytics_repositioning=true;
   g_analytics_last_chart_w=cw;
   g_analytics_last_chart_h=ch;

   MoveAnalyticsChildren(x,y);
   g_analytics_custom_moved=false;

   g_analytics_repositioning=false;
}

void MoveAnalyticsRightTop()
{
   long cw=0,ch=0;
   ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0,cw);
   ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0,ch);

   int x=MathMax(5,(int)cw-430);
   int y=28;

   MoveAnalyticsChildren(x,y);
   g_analytics_last_chart_w=cw;
   g_analytics_last_chart_h=ch;
   g_analytics_custom_moved=true;
}

void BuildAnalyticsPanel()
{
   if(!EnableFloatingAnalyticsPanel) return;
   DeleteByPrefix(A_PREFIX);
   RectLabel(A_PREFIX+"BG",20,20,420,285,C'11,16,22',true);
   ObjectSetInteger(0,A_PREFIX+"BG",OBJPROP_HIDDEN,false); ObjectSetInteger(0,A_PREFIX+"BG",OBJPROP_SELECTABLE,true);
   MoveAnalyticsRightBottom();
}

void ApplyPanelInputs()
{
   string v=ObjectGetString(0,UI_PREFIX+"ED_RISK",OBJPROP_TEXT); double r=StringToDouble(v); if(r>0) g_risk_usd=r;
   v=ObjectGetString(0,UI_PREFIX+"ED_LOTS",OBJPROP_TEXT); double l=StringToDouble(v); if(l>=0) g_fixed_lots=l;
   v=ObjectGetString(0,UI_PREFIX+"ED_BASE",OBJPROP_TEXT); double b=StringToDouble(v); if(b>0 && b<=1) g_base_ratio=b;

   v=ObjectGetString(0,UI_PREFIX+"ED_RR",OBJPROP_TEXT);
   double rr=StringToDouble(v);
   if(rr>=0.10 && rr<=20.0)
      g_even_rr=rr;

   v=ObjectGetString(0,UI_PREFIX+"ED_STOP",OBJPROP_TEXT); double sl=StringToDouble(v); if(sl>0)
   {
      if(!ManualStopExists()) DrawManualStop(); ObjectSetDouble(0,OBJ_MANUAL_STOP,OBJPROP_PRICE,NormalizePrice(sl));
   }
   v=ObjectGetString(0,UI_PREFIX+"ED_ENTRY",OBJPROP_TEXT); double en=StringToDouble(v); if(en>0)
   {
      if(!EntryLineExists()) DrawEntryLine(); ObjectSetDouble(0,OBJ_ENTRY,OBJPROP_PRICE,NormalizePrice(en));
   }
   double effectiveRisk=EffectiveRiskBudgetUsd();
   double capRisk=EquityRiskCapUsd();

   if(capRisk>0)
      SetStatus(StringFormat("面板参数已应用｜盈亏比 %.2f｜风险输入 $%.2f｜生效 $%.2f｜上限 $%.2f",
                             g_even_rr,g_risk_usd,effectiveRisk,capRisk));
   else
      SetStatus(StringFormat("面板参数已应用｜盈亏比 %.2f｜生效风险 $%.2f",
                             g_even_rr,effectiveRisk));
}

void RefreshMainStats()
{
   if(ObjectFind(0,UI_PREFIX+"INFO_0")<0) return;

   double ba=WeightedAverage(true);
   double sa=WeightedAverage(false);
   double bp=SidePnL(true);
   double sp=SidePnL(false);

   string stateText=g_running ? (g_paused ? "暂停" : "运行") : "未启动";
   string dirText=g_direction==DIR_LONG ? "多" : "空";

   ObjectSetString(0,UI_PREFIX+"INFO_0",OBJPROP_TEXT,
      StringFormat("状态 %s｜方向 %s｜动态 %s｜跟踪 %s",
                   stateText,dirText,DynamicAccumulation?"开":"关",EnumToString(FollowTimeframe)));

   ObjectSetString(0,UI_PREFIX+"INFO_1",OBJPROP_TEXT,
      StringFormat("多均价 %s｜P/L %+.2f",
                   ba>0?DoubleToString(ba,DigitsValue()):"--",bp));

   ObjectSetString(0,UI_PREFIX+"INFO_2",OBJPROP_TEXT,
      StringFormat("空均价 %s｜P/L %+.2f",
                   sa>0?DoubleToString(sa,DigitsValue()):"--",sp));

   ObjectSetString(0,UI_PREFIX+"INFO_3",OBJPROP_TEXT,
      StringFormat("网格 %.1f点｜小TP %.1f点｜目标RR %.2f｜手工最多 %d单 / %.2fR",
                   GetGridGapPoints(),GetOddTpPoints(),g_even_rr,MathMax(1,g_manual_orders),ManualMaxTpR()));

   ObjectSetString(0,UI_PREFIX+"INFO_4",OBJPROP_TEXT,
      StringFormat("手工跟踪 %s｜循环 %d｜CME %s",
                   ManualSmartTracking?"开":"关",
                   g_manual_tracking_cycles,
                   g_today_pnl_loaded?DoubleToString(g_today_pnl_cache,2):"--"));

   int nosl=0,notp=0;
   double locked=0,tpp=0;
   double risk=FamilyKnownRisk(nosl,locked,tpp,notp);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double pct=eq>0?risk/eq*100.0:0;

   int sns=0,mns=0;
   double sr=SmartRiskNow(sns), mr=ManualRiskNow(mns);
   double smart_remaining=MathMax(0.0,EffectiveRiskBudgetUsd()-sr);
   double manual_remaining=MathMax(0.0,EffectiveRiskBudgetUsd()-mr);
   double combined_cap=CombinedRiskCapUsd();
   double combined_remaining=EnableCombinedRiskCap ? MathMax(0.0,combined_cap-sr-mr) : 0.0;
   if(EnableCombinedRiskCap)
   {
      ObjectSetString(0,UI_PREFIX+"INFO_5",OBJPROP_TEXT,
         StringFormat("吸筹 $%.2f｜手工 $%.2f｜组合 $%.2f / $%.2f",sr,mr,sr+mr,combined_cap));
      ObjectSetString(0,UI_PREFIX+"INFO_6",OBJPROP_TEXT,
         StringFormat("吸筹余 $%.2f｜手工余 $%.2f｜组合余 $%.2f｜TP %s",smart_remaining,manual_remaining,combined_remaining,TpModeText()));
   }
   else
   {
      ObjectSetString(0,UI_PREFIX+"INFO_5",OBJPROP_TEXT,
         StringFormat("吸筹 $%.2f｜手工 $%.2f｜组合 $%.2f｜总上限 OFF",sr,mr,sr+mr));
      ObjectSetString(0,UI_PREFIX+"INFO_6",OBJPROP_TEXT,
         StringFormat("吸筹余 $%.2f｜手工余 $%.2f｜TP %s",smart_remaining,manual_remaining,TpModeText()));
   }

   ObjectSetString(0,UI_PREFIX+"INFO_7",OBJPROP_TEXT,
      StringFormat("Task 吸#%I64d 手#%I64d｜无SL %d｜无TP %d",g_smart_task_id,g_manual_task_id,nosl,notp));

   ObjectSetInteger(0,UI_PREFIX+"INFO_5",OBJPROP_COLOR,
      nosl>0 ? clrOrange : clrGold);
   ObjectSetInteger(0,UI_PREFIX+"INFO_6",OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,UI_PREFIX+"INFO_7",OBJPROP_COLOR,
      (nosl>0 || notp>0) ? clrOrange : clrGold);

   RenderMainStatusRows();

   if(ManualStopExists())
      ObjectSetString(0,UI_PREFIX+"ED_STOP",OBJPROP_TEXT,
                      DoubleToString(ManualStopPrice(),DigitsValue()));

   if(EntryLineExists())
      ObjectSetString(0,UI_PREFIX+"ED_ENTRY",OBJPROP_TEXT,
                      DoubleToString(EntryPriceLine(),DigitsValue()));
}

void RefreshConfluence()
{
   if(!g_analytics_loaded || !EnableFloatingAnalyticsPanel) return;

   if(!ShowMtfConfluence)
   {
      ObjectSetString(0,A_PREFIX+"CF1",OBJPROP_TEXT,"多周期共振：参数已关闭");
      ObjectSetString(0,A_PREFIX+"CF2",OBJPROP_TEXT,"");
      ObjectSetString(0,A_PREFIX+"CF3",OBJPROP_TEXT,"");
      ObjectSetString(0,A_PREFIX+"CF4",OBJPROP_TEXT,"");
      ObjectSetString(0,A_PREFIX+"CF5",OBJPROP_TEXT,"");
      ObjectSetString(0,A_PREFIX+"CF6",OBJPROP_TEXT,"");
      ObjectSetString(0,A_PREFIX+"CF7",OBJPROP_TEXT,"");
      return;
   }

   TfScoreResult a[5];
   a[0]=ScoreTimeframe("M5",1.0);
   a[1]=ScoreTimeframe("M15",1.5);
   a[2]=ScoreTimeframe("H1",2.0);
   a[3]=ScoreTimeframe("H4",3.0);
   a[4]=ScoreTimeframe("D1",3.5);

   double ws=0,os=0;
   int bull=0,bear=0;
   for(int i=0;i<5;i++)
   {
      ws+=a[i].weight;
      os+=a[i].total*a[i].weight;
      if(a[i].total>=DirectionScoreThreshold) bull++;
      if(a[i].total<=-DirectionScoreThreshold) bear++;
   }

   double overall=ws>0?os/ws:0;

   ObjectSetString(0,A_PREFIX+"CF1",OBJPROP_TEXT,
      StringFormat("综合 %+.0f/100 · %s · 多%d/空%d",
                   overall,ScoreLabel(overall),bull,bear));

   ObjectSetString(0,A_PREFIX+"CF2",OBJPROP_TEXT,
      StringFormat("%s:%+.0f VW%+.0f   %s:%+.0f VW%+.0f   %s:%+.0f VW%+.0f",
                   a[0].name,a[0].total,a[0].vwap,
                   a[1].name,a[1].total,a[1].vwap,
                   a[2].name,a[2].total,a[2].vwap));

   ObjectSetString(0,A_PREFIX+"CF3",OBJPROP_TEXT,
      StringFormat("%s:%+.0f VW%+.0f   %s:%+.0f VW%+.0f",
                   a[3].name,a[3].total,a[3].vwap,
                   a[4].name,a[4].total,a[4].vwap));

   double ema=0,vw=0,mac=0,rsi=0,dmi=0,bo=0;
   for(int i=0;i<5;i++)
   {
      ema+=a[i].ema/4.0*100*a[i].weight;
      vw+=a[i].vwap/2.0*100*a[i].weight;
      mac+=a[i].macd/2.0*100*a[i].weight;
      rsi+=a[i].rsi*100*a[i].weight;
      dmi+=a[i].dmi/2.0*100*a[i].weight;
      bo+=a[i].boll*100*a[i].weight;
   }
   if(ws>0)
   {
      ema/=ws; vw/=ws; mac/=ws; rsi/=ws; dmi/=ws; bo/=ws;
   }

   string inames[6]={"EMA","VWAP","MACD","RSI","DMI","BOLL"};
   double ivals[6]={ema,vw,mac,rsi,dmi,bo};

   for(int i=0;i<5;i++)
      for(int j=i+1;j<6;j++)
         if(MathAbs(ivals[j])>MathAbs(ivals[i]))
         {
            double tv=ivals[i]; ivals[i]=ivals[j]; ivals[j]=tv;
            string tn=inames[i]; inames[i]=inames[j]; inames[j]=tn;
         }

   ObjectSetString(0,A_PREFIX+"CF4",OBJPROP_TEXT,
      StringFormat("贡献1: %s%+.0f > %s%+.0f > %s%+.0f",
                   inames[0],ivals[0],inames[1],ivals[1],inames[2],ivals[2]));

   ObjectSetString(0,A_PREFIX+"CF5",OBJPROP_TEXT,
      StringFormat("贡献2: %s%+.0f > %s%+.0f > %s%+.0f",
                   inames[3],ivals[3],inames[4],ivals[4],inames[5],ivals[5]));

   ObjectSetString(0,A_PREFIX+"CF6",OBJPROP_TEXT,
      "VWAP: M5/M15=日内｜H1/H4=周｜D1=月");

   string suit="方向不一致，偏震荡/等待";
   if(overall>=StrongScoreThreshold && bull>=3)
      suit="多头共振较强";
   else if(overall>=DirectionScoreThreshold)
      suit="偏多，等待入场确认";
   else if(overall<=-StrongScoreThreshold && bear>=3)
      suit="空头共振较强";
   else if(overall<=-DirectionScoreThreshold)
      suit="偏空，等待入场确认";

   ObjectSetString(0,A_PREFIX+"CF7",OBJPROP_TEXT,"当前模型: "+suit);
   ObjectSetInteger(0,A_PREFIX+"CF1",OBJPROP_COLOR,
      overall>=DirectionScoreThreshold?clrLimeGreen:
      (overall<=-DirectionScoreThreshold?clrTomato:clrGold));
}

void RefreshHeatmap()
{
   if(!g_analytics_loaded || !EnableFloatingAnalyticsPanel) return;

   for(int i=0;i<15;i++)
   {
      string name=A_PREFIX+"CELL_"+IntegerToString(i);

      string mapped=g_heat_symbols[i];
      string tip=(mapped!="" ? (g_heat_keys[i]+" → "+mapped+"｜点击切换")
                             : (g_heat_keys[i]+" → 未映射"));
      if(ObjectGetString(0,name,OBJPROP_TOOLTIP)!=tip)
         ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);

      if(!ShowMarketHeatmap)
      {
         string offText=g_heat_keys[i]+" OFF";
         if(ObjectGetString(0,name,OBJPROP_TEXT)!=offText)
            ObjectSetString(0,name,OBJPROP_TEXT,offText);

         long oldbg=ObjectGetInteger(0,name,OBJPROP_BGCOLOR);
         if(oldbg!=(long)clrDarkSlateGray)
            ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrDarkSlateGray);
         continue;
      }

      double v=EMPTY_VALUE;
      bool ok=TryDayReturnCached(i,v,true);

      string newText;
      color newBg;

      if(!ok)
      {
         // 首次确实没有任何可用数据时才显示等待；之后缓存值不会消失。
         newText=g_heat_keys[i]+" 等待";
         newBg=clrDarkSlateGray;
      }
      else
      {
         newText=StringFormat("%s %+.2f%%",g_heat_keys[i],v);
         newBg=(v>0.05?clrDarkGreen:(v<-0.05?clrFireBrick:clrSlateGray));
      }

      if(ObjectGetString(0,name,OBJPROP_TEXT)!=newText)
         ObjectSetString(0,name,OBJPROP_TEXT,newText);

      long oldbg=ObjectGetInteger(0,name,OBJPROP_BGCOLOR);
      if(oldbg!=(long)newBg)
         ObjectSetInteger(0,name,OBJPROP_BGCOLOR,newBg);
   }
}

void RefreshAnalytics()
{
   if(!g_analytics_loaded || !EnableFloatingAnalyticsPanel || g_analytics_busy) return;

   g_analytics_busy=true;
   RefreshConfluence();
   RefreshHeatmap();

   datetime now=TimeCurrent();
   g_next_analytics_refresh=now+MathMax(30,ConfluenceRefreshSeconds);
   g_next_heat_refresh=now+MathMax(60,HeatmapRefreshSeconds);

   if(ObjectFind(0,A_PREFIX+"LOAD")>=0)
      ObjectSetString(0,A_PREFIX+"LOAD",OBJPROP_TEXT,"市场分析已加载");

   g_analytics_busy=false;
   ChartRedraw();
}
// =========================
// 成交事件：奇数循环 / 手工跟踪
// =========================
string OriginCommentByPositionId(ulong pos_id)
{
   if(!HistorySelectByPosition(pos_id)) return "";
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(en==DEAL_ENTRY_IN || en==DEAL_ENTRY_INOUT)
      {
         string c=HistoryDealGetString(d,DEAL_COMMENT); if(c!="") return c;
      }
   }
   return "";
}

double ClosedPositionNetById(ulong pos_id)
{
   if(!HistorySelectByPosition(pos_id)) return 0;
   double p=0; int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      p+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
   }
   return p;
}

// =========================
// v1.64.1 界面一键隐藏/恢复（修复黑板）
// 不再用 OBJPROP_TIMEFRAMES 隐藏对象；隐藏时直接删除UI对象，恢复时按原布局重建。
// 交易辅助线/吸筹框不删除，EA交易逻辑继续运行。
// =========================
void DeleteObjectsByPrefixSafe(const string prefix)
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StartsWith(name,prefix)) ObjectDelete(0,name);
   }
}

void ToggleUiHidden()
{
   g_ui_hidden=!g_ui_hidden;

   if(g_ui_hidden)
   {
      DeleteObjectsByPrefixSafe(UI_PREFIX);
      DeleteObjectsByPrefixSafe(A_PREFIX);

      // 隐藏后保留一个很小的恢复按钮，鼠标也能恢复；数字0/小键盘0仍然有效。
      Button(RESTORE_UI_OBJ,"显示面板 [0]",PanelLeftOffset,PanelTopOffset,118,26,clrDarkSlateGray);
      ObjectSetInteger(0,RESTORE_UI_OBJ,OBJPROP_HIDDEN,false);
      ChartRedraw();
      return;
   }

   ObjectDelete(0,RESTORE_UI_OBJ);

   // 恢复时从零重建，不复用被隐藏过的矩形背景，避免出现整块黑板。
   BuildMainPanel();

   // v1.67.4：市场热图/多周期共振已拆分为独立指标，本EA不再恢复分析面板。
   RefreshMainStats();
   ChartRedraw();
}

// =========================
// v1.67.4：Trading Core Lite
// 热图/多周期共振运行时已从EA拆分，建议配套加载 Jammy_Market_Heatmap_MTF_Lite_v1.00。
// =========================
// 生命周期
// =========================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   g_risk_usd=RiskUsd; g_fixed_lots=FixedLotsDefault; g_base_ratio=BasePositionRatioDefault; g_manual_orders=MathMax(1,ManualOrderCount); g_smart_orders=MathMax(2,SmartGridCount); g_even_rr=EvenRR; g_tp_mode=TakeProfitMode;
   LoadTrackingState();
   LoadStabilityState();
   // 每次加载EA都处于“未确认”状态：旧框可以保留，但绝不自动排单。
   g_smart_user_confirmed=false;
   g_running=false;
   g_paused=false;
   if(BoxExists())
   {
      JsaDirection d;
      if(InferSmartDirection(d)) g_direction=d;   // 有吸筹单时以实际单子方向为准
      g_direction_prepared=true; DrawSmartStop(); CacheBox();
   }
   else ObjectDelete(0,OBJ_SMART_STOP);   // 上次残留的孤立止损线
   ObjectDelete(0,RESTORE_UI_OBJ);
   BuildMainPanel(); // v1.67.4：热图/共振已拆分为独立指标，不在交易EA中加载

   // 统一TP/SL辅助线可跟随鼠标移动。
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);

   EventSetTimer(1);
   if(!IsHedgingAccount()) SetStatus("警告：当前MT5账户不是Hedging模式，多订单逻辑无法1:1工作；请使用对冲账户");
   else SetStatus("v1.55.2：吸金只管Jammy风险｜风险盈亏统计当前品种全部订单");
   SetStatus("v1.67.3：风险自适应单数｜底部信息可折叠｜状态文字自动分行｜面板可按钮隐藏/恢复");
   RecoverExistingTasksSafe();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   SaveRecoveryRuntimeState();
   EventKillTimer();
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);
   DeleteByPrefix(UI_PREFIX); DeleteByPrefix(A_PREFIX); ObjectDelete(0,RESTORE_UI_OBJ);
   // 交易线与吸金框刻意保留，方便重载后继续接管。
}

void OnTick()
{
   if(!IsHedgingAccount()) return;
   ApplyBaseProtection();
   ApplyOneKeyTrailing();
   if(g_smart_user_confirmed && g_running && !g_paused)
   {
      if(HardStopEnabled && HitHardStop()) { EmergencyStop(DynamicAccumulation?"触及动态退出边界":"触及初始止损边界"); return; }
      if(DynamicAccumulation)
      {
         UpdateDynamicBox();
         if(DynamicReverseExit && FollowMode==FOLLOW_H4_EMA8 && FollowEmaReversal()) { EmergencyStop("EMA趋势反转"); return; }
      }
      TightenSmartStops();
      ExpireSmartOrders();
   }
}


bool NeedDynamicRiskRefill()
{
   // v1.58：禁止Timer因为“排单数量减少”就整体重排。
   // 框内价格下跌/回撤时，原排单继续工作；奇数止盈只由 RearmOddSlot 原槽位补回。
   // 整体 RebuildPendingGrid 只允许由 UpdateDynamicBox 在趋势方向真正推进后触发。
   return false;
}

// v1.67.7：取消吸金计划。未确认运行时连同吸金框和止损线一起清除；
// 已在运行的吸金只取消待确认计划，不再顺带把运行中的策略静默停掉。
void CancelSmartPlanButton()
{
   g_smart_plan_ready=false;
   ArrayResize(g_smart_plan,0);
   if(g_smart_user_confirmed && g_running)
   {
      SetStatus("已取消待确认计划｜吸金仍在运行，如需结束请点“停止吸金”");
      return;
   }
   g_smart_user_confirmed=false;
   g_running=false;
   ClearSmartTaskContext();   // 删除吸金框 + 止损线
   SetStatus("已取消吸金计划：吸金框和止损线已清除，不会排单");
}

// 吸金框不在了（被手动删除等），止损线随之清除，避免留下删不掉的孤立虚线。
void CleanupOrphanSmartStop()
{
   if(BoxExists() || ObjectFind(0,OBJ_SMART_STOP)<0) return;
   ObjectDelete(0,OBJ_SMART_STOP);
   if(g_smart_user_confirmed && g_running)
   {
      g_paused=true;
      SetStatus("吸金框已被删除：吸金已暂停（持仓/挂单保持不动），请重新画框或点“停止吸金”");
   }
   ChartRedraw();
}

void OnTimer()
{
   CleanupOrphanSmartStop();
   NewsGuardTick();
   // v1.67.4 Trading Core Lite：只刷新交易主面板。
   // 市场热图/多周期共振由独立指标负责，避免CopyRates/多品种刷新占用交易EA线程。
   if(!g_ui_hidden)
      RefreshMainStats();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return; // v1.67.6：只选这一笔成交，不再每笔扫描30天历史
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   ulong posid=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(entry==DEAL_ENTRY_IN)
   {
      string in_comment=HistoryDealGetString(trans.deal,DEAL_COMMENT);
      TagPositionTask(posid,in_comment);
      return;
   }
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   if(ConsumeSuppressId(posid)) return;

   string c=OriginCommentByPositionId(posid);
   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(!(magic==MagicNumber || IsEaFamilyComment(c))) return;

   double net=ClosedPositionNetById(posid);
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON);
   bool tpExit=(reason==DEAL_REASON_TP);
   bool recycleAllowed=(!RecycleOnlyOnTakeProfit || tpExit);
   bool profitableOrTp=(tpExit || net>0);

   // v1.67.1：默认只有真正由TP成交退出，才允许自动补回。
   // 人工平仓、EA主动平仓、SL、Close By 等不再把订单“复活”。
   if(recycleAllowed && profitableOrTp && IsOddComment(c) && g_running && !g_paused && InfiniteOddRecycle)
      RearmOddSlot(c);

   if(recycleAllowed && profitableOrTp && c==StringFormat("%s1",MANUAL_SPLIT_PREFIX) && ManualSmartTracking && g_manual_tracking_active)
   {
      bool cycle_enabled=(g_manual_tracking_source_mode==1 ? (MarketCycleTracking && g_one_key_trailing) : PendingCycleTracking);
      if(cycle_enabled) RearmManualTracking();
   }

   if(!recycleAllowed && (IsOddComment(c) || c==StringFormat("%s1",MANUAL_SPLIT_PREFIX)))
      Print("JSA v1.67.1 循环未回挂：退出原因不是TP，reason=",(int)reason," comment=",c);

   string gv=BaseRiskGV(posid); if(GlobalVariableCheck(gv)) GlobalVariableDel(gv);
}

// 危险操作需在 HotkeyConfirmSeconds 秒内按两次同一个键。
bool HotkeyConfirmed(string action,string label)
{
   ulong now=GetTickCount64();
   ulong window=(ulong)MathMax(1,HotkeyConfirmSeconds)*1000;
   // 间隔太短（“00”键连发/双击过快）不算第二次确认，保留第一次的等待状态。
   if(g_hotkey_pending==action && now-g_hotkey_pending_ms<JSA_MIN_DOUBLE_PRESS_MS) return false;
   if(g_hotkey_pending==action && now-g_hotkey_pending_ms<=window)
   {
      g_hotkey_pending="";
      return true;
   }
   g_hotkey_pending=action;
   g_hotkey_pending_ms=now;
   SetStatus(StringFormat("%s：%d秒内再按一次确认",label,MathMax(1,HotkeyConfirmSeconds)));
   return false;
}

// 小键盘虚拟键码：Num0=96 … Num9=105，*=106，+=107，-=109，.=110，/=111
bool HandleNumpadHotkey(int key)
{
   if(!EnableNumpadHotkeys || g_ui_hidden || g_edit_focus) return false;
   if(key<97 || key>111 || key==108) return false;
   if(key!=106 && key!=111) g_hotkey_pending="";

   switch(key)
   {
      case 103: CreateDirectionalBox(DIR_LONG);  break;  // 7 建立多头框
      case 104: CreateDirectionalBox(DIR_SHORT); break;  // 8 建立空头框
      case 105: PrepareSmartPlan();              break;  // 9 计算吸金计划
      case 107: ConfirmSmartPlan();              break;  // + 确认开始吸金
      case 109: EndSmartStrategy();              break;  // - 停止吸金
      case 100: DrawManualStop();                break;  // 4 画线止损
      case 101: PrepareManualMarket();           break;  // 5 计算市价风险
      case 102: ConfirmManualMarket();           break;  // 6 确认市价开仓
      case 97:  DrawEntryLine();                 break;  // 1 设置排单线
      case 98:  PrepareManualPending();          break;  // 2 计算排单风险
      case 99:  ConfirmManualPending();          break;  // 3 确认排单入场
      case 110: CancelAllPending();              break;  // . 删除排单
      case 106: if(HotkeyConfirmed("CLOSEALL","一键清仓")) CloseAllStrategy(); break;  // * 一键清仓
      case 111: if(HotkeyConfirmed("LOCK","一键锁仓/解锁")) ToggleLock();       break;  // / 锁仓/解锁
   }
   RefreshMainStats();
   ChartRedraw();
   return true;
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   // 点进面板输入框开始打字时屏蔽快捷键；结束编辑(Enter/离开输入框)或点其他按钮后恢复。
   if(id==CHARTEVENT_OBJECT_CLICK)
      g_edit_focus=(StringFind(sparam,UI_PREFIX+"ED_")==0);
   else if(id==CHARTEVENT_OBJECT_ENDEDIT)
      g_edit_focus=false;

   // v1.66.3：统一TP/SL线在创建后跟随鼠标。
   if(id==CHARTEVENT_MOUSE_MOVE && g_unified_follow_active)
   {
      if(g_unified_follow_name!="" && ObjectFind(0,g_unified_follow_name)>=0)
      {
         int subwin=0;
         datetime tm=0;
         double price=0.0;
         if(ChartXYToTimePrice(0,(int)lparam,(int)dparam,subwin,tm,price) && subwin==0 && price>0)
         {
            ObjectSetDouble(0,g_unified_follow_name,OBJPROP_PRICE,NormalizePrice(price));
            ChartRedraw();
         }
      }
      return;
   }

   // 在图表空白处单击，固定当前统一线位置；之后仍可手工拖动微调。
   if(id==CHARTEVENT_CLICK && g_unified_follow_active)
   {
      string fixed_name=g_unified_follow_name;
      g_unified_follow_active=false;
      g_unified_follow_name="";
      if(fixed_name!="" && ObjectFind(0,fixed_name)>=0)
      {
         ObjectSetInteger(0,fixed_name,OBJPROP_SELECTED,true);
         SetStatus("统一线已固定：可继续拖动微调，确认后会自动消失");
      }
      return;
   }

   if(id==CHARTEVENT_OBJECT_DRAG)
   {
      if(sparam==OBJ_LONG_TP || sparam==OBJ_LONG_SL || sparam==OBJ_SHORT_TP || sparam==OBJ_SHORT_SL)
      {
         g_unified_follow_active=false;
         g_unified_follow_name="";
         SetStatus("统一线已手工拖动：位置已固定，确认后自动消失");
         return;
      }

      if(sparam==OBJ_BOX)
      {
         // v1.67.6：运行中把止损边界拖过现价，会在下一Tick直接触发硬止损清仓，撤销这次拖动。
         if(g_smart_user_confirmed && g_running && !BoxStopSafeNow())
         {
            RestoreCachedBox();
            ChartRedraw();
            SetStatus("拖框已撤销：止损边界不能越过现价（否则会立即触发硬止损清仓）");
            return;
         }
         CacheBox();
         DrawSmartStop(); g_smart_plan_ready=false; ArrayResize(g_smart_plan,0);
         if(g_smart_user_confirmed && g_running && !g_paused && DynamicRegridPendingOrders)
         {
            RebuildPendingGrid(true);
            SetStatus("吸金框已移动：已确认策略按新框动态重排");
         }
         else
         {
            g_smart_user_confirmed=false;
            g_running=false;
            SetStatus("吸金框已移动：请重新计算计划并点击确认后才会排单");
         }
      }
      else if(sparam==OBJ_MANUAL_STOP)
      {
         ObjectSetString(0,UI_PREFIX+"ED_STOP",OBJPROP_TEXT,DoubleToString(ManualStopPrice(),DigitsValue())); g_manual_plan_ready=false;
      }
      else if(sparam==OBJ_ENTRY)
      {
         ObjectSetString(0,UI_PREFIX+"ED_ENTRY",OBJPROP_TEXT,DoubleToString(EntryPriceLine(),DigitsValue())); g_manual_plan_ready=false;
      }
      else if(sparam==A_PREFIX+"BG")
      {
         int x=(int)ObjectGetInteger(0,A_PREFIX+"BG",OBJPROP_XDISTANCE);
         int y=(int)ObjectGetInteger(0,A_PREFIX+"BG",OBJPROP_YDISTANCE);
         MoveAnalyticsChildren(x,y);
         ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0,g_analytics_last_chart_w);
         ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0,g_analytics_last_chart_h);
         g_analytics_custom_moved=true;
      }
      return;
   }
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      // 只有图表尺寸真的变化时才重新计算右下角位置。
      // 对象自身移动/重绘引发的 CHART_CHANGE 不再重复搬动整个面板。
      if(EnableFloatingAnalyticsPanel && !g_analytics_custom_moved && !g_analytics_repositioning)
      {
         long cw=0,ch=0;
         ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0,cw);
         ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0,ch);

         if(cw!=g_analytics_last_chart_w || ch!=g_analytics_last_chart_h)
            MoveAnalyticsRightBottom();
      }
      return;
   }

   // v1.63：数字0 / 小键盘0 一键隐藏或恢复面板。
   // Windows虚拟键：'0'=48，NumPad0=96。
   if(id==CHARTEVENT_KEYDOWN)
   {
      int key=(int)lparam;
      // 按住不放的自动重复一律忽略：防止按住 * 或 / 被当成“按两次确认”。
      if(((int)StringToInteger(sparam) & JSA_KF_REPEAT)!=0) return;
      if(key==48 || key==96)
      {
         if(g_edit_focus) return;
         ToggleUiHidden();
         return;
      }
      HandleNumpadHotkey(key);
      return;
   }

   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   // 隐藏状态下的小恢复按钮不属于 UI_PREFIX，优先处理。
   if(sparam==RESTORE_UI_OBJ)
   {
      ToggleUiHidden();
      return;
   }

   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   if(sparam!=UI_PREFIX+"LOCK" && sparam!=UI_PREFIX+"CLOSEALL" && sparam!=UI_PREFIX+"ENDALL")
      g_hotkey_pending="";

   if(sparam==UI_PREFIX+"FOLDINFO") { ToggleInfoCollapsed(); return; }
   else if(sparam==UI_PREFIX+"HIDEUI") { ToggleUiHidden(); return; }
   // v1.67.6：清仓、结束+全平、锁仓/解锁都要在设定秒数内点两次。
   else if(sparam==UI_PREFIX+"LOCK") { if(HotkeyConfirmed("LOCK","一键锁仓/解锁")) ToggleLock(); }
   else if(sparam==UI_PREFIX+"CLOSEALL" || sparam==UI_PREFIX+"ENDALL") { if(HotkeyConfirmed("CLOSEALL","一键清仓/结束+全平")) CloseAllStrategy(); }
   else if(sparam==UI_PREFIX+"TRAIL") ToggleOneKeyTrailing();
   else if(sparam==UI_PREFIX+"SMARTCALC" || sparam==UI_PREFIX+"PLAN") PrepareSmartPlan();
   else if(sparam==UI_PREFIX+"LTP") PrepareUnifiedLine(true,true);
   else if(sparam==UI_PREFIX+"LSL") PrepareUnifiedLine(true,false);
   else if(sparam==UI_PREFIX+"LAPPLY")
   {
      g_unified_follow_active=false;
      g_unified_follow_name="";
      ApplyUnified(true);
   }
   else if(sparam==UI_PREFIX+"STP") PrepareUnifiedLine(false,true);
   else if(sparam==UI_PREFIX+"SSL") PrepareUnifiedLine(false,false);
   else if(sparam==UI_PREFIX+"SAPPLY")
   {
      g_unified_follow_active=false;
      g_unified_follow_name="";
      ApplyUnified(false);
   }
   else if(sparam==UI_PREFIX+"DEAN") SetStatus("修心悟道：预留按钮，不执行交易动作");
   else if(sparam==UI_PREFIX+"RISK") ShowCurrentSymbolRiskPopup();
   else if(sparam==UI_PREFIX+"BOXBUY") CreateDirectionalBox(DIR_LONG);
   else if(sparam==UI_PREFIX+"BOXSELL") CreateDirectionalBox(DIR_SHORT);
   else if(sparam==UI_PREFIX+"START") ConfirmSmartPlan();
   else if(sparam==UI_PREFIX+"CANCELPLAN") CancelSmartPlanButton();
   else if(sparam==UI_PREFIX+"DRAWSL") DrawManualStop();
   else if(sparam==UI_PREFIX+"CANCELORD") CancelAllPending();
   else if(sparam==UI_PREFIX+"CLOSELOSS") CloseByProfit(false);
   else if(sparam==UI_PREFIX+"CLOSEWIN") CloseByProfit(true);
   else if(sparam==UI_PREFIX+"MKTCALC") PrepareManualMarket();
   else if(sparam==UI_PREFIX+"MKTGO") ConfirmManualMarket();
   else if(sparam==UI_PREFIX+"ENTRY") DrawEntryLine();
   else if(sparam==UI_PREFIX+"PENDCALC") PrepareManualPending();
   else if(sparam==UI_PREFIX+"PENDGO") ConfirmManualPending();
   else if(sparam==UI_PREFIX+"CANCELMAN") CancelManualPlan();
   else if(sparam==UI_PREFIX+"TODAY") { LoadTodayPnL(); SetStatus(StringFormat("本EA CME盈亏(%s起)：%.2f",CmeOpenBeijingTimeText(),g_today_pnl_cache)); }
   else if(sparam==UI_PREFIX+"APPLY") ApplyPanelInputs();
   else if(sparam==UI_PREFIX+"TPMODE") ToggleTpMode();
   else if(sparam==UI_PREFIX+"PAUSE") { g_paused=!g_paused; SetStatus(g_paused?"吸金补单已暂停":"吸金补单已恢复"); }
   if(sparam==UI_PREFIX+"RECOVER"){ ResumeRecoveredTasks(); RefreshMainStats(); ChartRedraw(); return; }
   if(sparam==UI_PREFIX+"ABANDON"){ AbandonRecoveredTasks(); RefreshMainStats(); ChartRedraw(); return; }
   else if(sparam==UI_PREFIX+"STOPSMART") EndSmartStrategy();
   else if(sparam==A_PREFIX+"LEFT") MoveAnalyticsRightTop();
   else if(sparam==A_PREFIX+"RIGHT") MoveAnalyticsRightBottom();
   else if(sparam==A_PREFIX+"LOAD") LoadAnalytics();
   else if(sparam==A_PREFIX+"REFRESH")
   {
      if(!g_analytics_loaded) LoadAnalytics();
      else
      {
         if(!g_analytics_busy)
         {
            g_analytics_busy=true;
            WarmupHeatHistory();
            RefreshConfluence();
            RefreshHeatmap();
            datetime now=TimeCurrent();
            g_next_analytics_refresh=now+MathMax(30,ConfluenceRefreshSeconds);
            g_next_heat_refresh=now+MathMax(60,HeatmapRefreshSeconds);
            g_analytics_busy=false;
            SetStatus("市场分析已手动刷新｜缓存稳定显示");
         }
      }
   }
   else
   {
      int heat_idx=HeatCellIndex(sparam);
      if(heat_idx>=0)
      {
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         SwitchHeatmapSymbolByIndex(heat_idx);
         return;
      }
   }

   ChartRedraw();
}
