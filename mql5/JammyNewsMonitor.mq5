//+------------------------------------------------------------------+
//| Jammy 新闻监控服务 v1.00                                           |
//| 放在 MQL5\Services 里，在导航器"服务"中右键"添加服务"运行。          |
//| 后台常驻，不占图表：                                                |
//|  1) 金十快讯（非官方接口）按关键词 / 重要标记推送                    |
//|  2) MT5 经济日历：高影响美元数据 公布前倒计时 + 公布值               |
//|  3) 可选 RSS 新闻源（英文）                                         |
//| 通知方式：手机推送(MetaQuotes ID) / 弹窗 / 声音 / 邮件 / 日志文件     |
//+------------------------------------------------------------------+
#property service
#property copyright "Jammy"
#property version   "1.00"
#property description "Jammy 新闻监控：金十快讯 + 经济日历 + RSS，关键词命中即推送到手机"

input group "=== 轮询 ==="
input int    PollSeconds        = 15;     // 每隔多少秒抓取一次（建议 10~30）
input bool   NotifyBacklogOnStart = false; // 启动时是否推送已有的旧新闻（false=只推启动后的新新闻）

input group "=== 金十快讯（非官方接口，金十改版可能失效） ==="
input bool   EnableJin10        = true;
input string Jin10Url           = "https://flash-api.jin10.com/get_flash_list?channel=-8200&vip=1";
input string Jin10AppId         = "bVBF4FyRTn5NJF5n";
input bool   Jin10AllImportant  = true;   // 金十标红(重要)的快讯不看关键词也推送

input group "=== 关键词（逗号分隔，命中任意一个就推送） ==="
input string KeywordsCN = "黄金,金价,现货金,XAU,美联储,鲍威尔,利率,加息,降息,非农,CPI,PCE,通胀,伊朗,以色列,霍尔木兹,中东,原油,油价,特朗普,制裁,导弹,空袭,停火,战争,核";
input string KeywordsEN = "gold,XAU,Fed,Powell,FOMC,rate hike,rate cut,payroll,CPI,PCE,inflation,Iran,Israel,Hormuz,oil,crude,Trump,sanction,missile,strike,ceasefire,war";
input string ExcludeWords = "";           // 含这些词的不推送（逗号分隔）

input group "=== MT5 经济日历 ==="
input bool   EnableCalendar     = true;
input string CalendarCurrency   = "USD";
input bool   CalendarHighOnly   = true;   // 只看高影响（false=高+中）
input int    PreAlertMinutes    = 15;     // 公布前多少分钟提醒（0=不提前提醒）

input group "=== RSS 新闻源（可留空） ==="
input string RssUrl1 = "https://www.fxstreet.com/rss/news";
input string RssUrl2 = "";

input group "=== 通知方式 ==="
input bool   UsePush            = true;   // 手机推送：需在 MT5 选项→通知 填 MetaQuotes ID
input bool   UseAlert           = true;   // 电脑弹窗
input bool   UseSound           = true;
input bool   UseMail            = false;  // 需在 MT5 选项→邮箱 配置
input bool   WriteLogFile       = true;   // 记录到 MQL5\Files\JammyNews.log
input int    MaxPushPerPoll     = 4;      // 每轮最多单独推送几条，其余合并成一条

//+------------------------------------------------------------------+
string g_kw[];
string g_ex[];
string g_seen[];          // 已处理的快讯ID / RSS标题
ulong  g_calPre[];        // 已发提前提醒的日历值ID
ulong  g_calDone[];       // 已发公布值的日历值ID
bool   g_jinPrimed=false, g_rssPrimed1=false, g_rssPrimed2=false;
bool   g_warnedUrl=false;
string g_queue[];         // 本轮待推送

//+------------------------------------------------------------------+
//| 小工具                                                            |
//+------------------------------------------------------------------+
void SplitList(string s,string &out[])
{
   ArrayResize(out,0);
   string parts[];
   int n=StringSplit(s,',',parts);
   for(int i=0;i<n;i++)
   {
      string w=parts[i]; StringTrimLeft(w); StringTrimRight(w);
      if(w=="") continue;
      StringToUpper(w);
      int k=ArraySize(out); ArrayResize(out,k+1); out[k]=w;
   }
}

bool Contains(const string text,const string &words[])
{
   string up=text; StringToUpper(up);
   for(int i=0;i<ArraySize(words);i++)
      if(StringFind(up,words[i])>=0) return true;
   return false;
}

bool Seen(const string key)
{
   for(int i=ArraySize(g_seen)-1;i>=0;i--) if(g_seen[i]==key) return true;
   return false;
}
void MarkSeen(const string key)
{
   int n=ArraySize(g_seen);
   if(n>=600) { ArrayRemove(g_seen,0,100); n=ArraySize(g_seen); }
   ArrayResize(g_seen,n+1); g_seen[n]=key;
}
bool InList(ulong id,const ulong &a[]) { for(int i=0;i<ArraySize(a);i++) if(a[i]==id) return true; return false; }
void AddList(ulong id,ulong &a[]) { int n=ArraySize(a); if(n>=400){ArrayRemove(a,0,100);n=ArraySize(a);} ArrayResize(a,n+1); a[n]=id; }

string StripTags(string s)
{
   string out=""; bool tag=false;
   int n=StringLen(s);
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      if(c=='<') { tag=true; continue; }
      if(c=='>') { tag=false; continue; }
      if(!tag) out+=ShortToString(c);
   }
   StringReplace(out,"&nbsp;"," "); StringReplace(out,"&amp;","&");
   StringReplace(out,"&lt;","<");  StringReplace(out,"&gt;",">"); StringReplace(out,"&quot;","\"");
   StringReplace(out,"\r"," "); StringReplace(out,"\n"," ");
   return out;
}

int HexVal(ushort c)
{
   if(c>='0' && c<='9') return c-'0';
   if(c>='a' && c<='f') return c-'a'+10;
   if(c>='A' && c<='F') return c-'A'+10;
   return -1;
}

// 从 pos 处读取 JSON 字符串（pos 指向开头引号之后），处理转义
string ReadJsonString(const string s,int pos,int &endPos)
{
   string out=""; int n=StringLen(s); int i=pos;
   while(i<n)
   {
      ushort c=StringGetCharacter(s,i);
      if(c=='"') break;
      if(c=='\\' && i+1<n)
      {
         ushort e=StringGetCharacter(s,i+1);
         if(e=='u' && i+5<n)
         {
            int v=0; bool ok=true;
            for(int k=2;k<=5;k++){ int h=HexVal(StringGetCharacter(s,i+k)); if(h<0){ok=false;break;} v=v*16+h; }
            if(ok){ out+=ShortToString((ushort)v); i+=6; continue; }
         }
         if(e=='n' || e=='r' || e=='t') out+=" ";
         else if(e=='/') out+="/";
         else out+=ShortToString(e);
         i+=2; continue;
      }
      out+=ShortToString(c); i++;
   }
   endPos=i;
   return out;
}

// 在 [from,to) 范围里找 "key":" 的字符串值
string JsonStr(const string s,const string key,int from,int to)
{
   string pat="\""+key+"\":\"";
   int p=StringFind(s,pat,from);
   if(p<0 || (to>0 && p>=to)) return "";
   int e; return ReadJsonString(s,p+StringLen(pat),e);
}

int JsonInt(const string s,const string key,int from,int to)
{
   string pat="\""+key+"\":";
   int p=StringFind(s,pat,from);
   if(p<0 || (to>0 && p>=to)) return 0;
   return (int)StringToInteger(StringSubstr(s,p+StringLen(pat),6));
}

//+------------------------------------------------------------------+
//| 通知                                                              |
//+------------------------------------------------------------------+
void LogLine(const string msg)
{
   if(!WriteLogFile) return;
   int h=FileOpen("JammyNews.log",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+"  "+msg+"\r\n");
   FileClose(h);
}

void Queue(const string msg)
{
   int n=ArraySize(g_queue); ArrayResize(g_queue,n+1); g_queue[n]=msg;
   Print(msg);
   LogLine(msg);
   if(UseAlert) Alert(msg);
}

void FlushQueue()
{
   int n=ArraySize(g_queue);
   if(n==0) return;
   if(UseSound) PlaySound("news.wav");

   int single=MathMin(n,MathMax(1,MaxPushPerPoll));
   for(int i=0;i<n;i++)
   {
      string msg;
      if(i<single-1 || n==single) msg=g_queue[i];
      else
      {
         msg=StringFormat("另有%d条：",n-i);
         for(int j=i;j<n;j++) msg+=StringSubstr(g_queue[j],0,40)+"；";
         i=n;   // 合并后结束
      }
      if(UsePush && !SendNotification(StringSubstr(msg,0,250)))
         Print("手机推送失败 err=",GetLastError(),"（检查 选项→通知 的 MetaQuotes ID）");
      if(UseMail) SendMail("新闻提醒",msg);
      Sleep(1100);   // MT5 推送限速：每秒最多约 1~2 条
   }
   ArrayResize(g_queue,0);
}

//+------------------------------------------------------------------+
//| HTTP                                                              |
//+------------------------------------------------------------------+
bool HttpGet(const string url,const string headers,string &body)
{
   char req[],res[]; string resHeaders;
   ResetLastError();
   int code=WebRequest("GET",url,headers,8000,req,res,resHeaders);
   if(code==-1)
   {
      int err=GetLastError();
      if(err==4014 && !g_warnedUrl)
      {
         g_warnedUrl=true;
         string m="新闻监控：网址未被允许。请在 工具→选项→智能交易 勾选“允许WebRequest”，并添加：https://flash-api.jin10.com 以及RSS网址";
         Print(m); if(UseAlert) Alert(m);
      }
      else Print("WebRequest 失败 err=",err," url=",url);
      return false;
   }
   if(code!=200) { Print("HTTP ",code," url=",url); return false; }
   body=CharArrayToString(res,0,WHOLE_ARRAY,CP_UTF8);
   return true;
}

//+------------------------------------------------------------------+
//| 金十快讯                                                          |
//+------------------------------------------------------------------+
void PollJin10()
{
   if(!EnableJin10) return;
   string headers="x-app-id: "+Jin10AppId+"\r\nx-version: 1.0.0\r\n"
                  "Referer: https://www.jin10.com/\r\nOrigin: https://www.jin10.com\r\n"
                  "User-Agent: Mozilla/5.0\r\n";
   string body;
   if(!HttpGet(Jin10Url,headers,body)) return;

   // 逐条解析 {"id":"...","time":"...",...,"data":{...,"content":"..."},"important":0,...}
   string ids[],times[],texts[]; int imps[];
   string pat="\"id\":\"";
   int p=StringFind(body,pat);
   while(p>=0)
   {
      int e;
      string id=ReadJsonString(body,p+StringLen(pat),e);
      int next=StringFind(body,pat,e);
      string content=JsonStr(body,"content",e,next);
      if(content!="")
      {
         int k=ArraySize(ids);
         ArrayResize(ids,k+1); ArrayResize(times,k+1); ArrayResize(texts,k+1); ArrayResize(imps,k+1);
         ids[k]=id; times[k]=JsonStr(body,"time",e,next); texts[k]=StripTags(content);
         imps[k]=JsonInt(body,"important",e,next);
      }
      p=next;
   }

   if(ArraySize(ids)==0) { Print("金十：没有解析到快讯（接口可能改版或被拒绝）"); return; }

   // 接口按时间倒序返回：倒着处理，推送顺序从旧到新
   for(int i=ArraySize(ids)-1;i>=0;i--)
   {
      string key="J"+ids[i];
      if(Seen(key)) continue;
      MarkSeen(key);
      if(!g_jinPrimed && !NotifyBacklogOnStart) continue;

      string t=texts[i];
      if(ArraySize(g_ex)>0 && Contains(t,g_ex)) continue;
      bool hit=Contains(t,g_kw) || (Jin10AllImportant && imps[i]==1);
      if(!hit) continue;

      string hhmm=(StringLen(times[i])>=16 ? StringSubstr(times[i],11,5) : times[i]);
      Queue((imps[i]==1?"【重要】":"")+"金十 "+hhmm+"｜"+t);
   }
   g_jinPrimed=true;
}

//+------------------------------------------------------------------+
//| MT5 经济日历                                                      |
//+------------------------------------------------------------------+
string CalNum(long raw,int digits)
{
   if(raw==LONG_MIN) return "--";
   return DoubleToString((double)raw/1000000.0,MathMax(0,MathMin(3,digits)));
}

void PollCalendar()
{
   if(!EnableCalendar) return;
   datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
   MqlCalendarValue vals[];
   if(CalendarValueHistory(vals,now-6*3600,now+MathMax(1,PreAlertMinutes)*60+60,NULL,CalendarCurrency)<=0) return;

   for(int i=0;i<ArraySize(vals);i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev)) continue;
      bool imp=(ev.importance==CALENDAR_IMPORTANCE_HIGH) ||
               (!CalendarHighOnly && ev.importance==CALENDAR_IMPORTANCE_MODERATE);
      if(!imp) continue;

      ulong vid=vals[i].id;
      datetime t=vals[i].time;
      string tag=(ev.importance==CALENDAR_IMPORTANCE_HIGH?"【高影响】":"【中影响】");

      // 公布前提醒
      if(PreAlertMinutes>0 && t>now && t-now<=PreAlertMinutes*60 && !InList(vid,g_calPre))
      {
         AddList(vid,g_calPre);
         Queue(StringFormat("%s%d分钟后公布 %s %s｜预期 %s 前值 %s",tag,(int)((t-now+59)/60),
               CalendarCurrency,ev.name,CalNum(vals[i].forecast_value,(int)ev.digits),CalNum(vals[i].prev_value,(int)ev.digits)));
      }

      // 公布值
      if(vals[i].actual_value!=LONG_MIN && !InList(vid,g_calDone))
      {
         AddList(vid,g_calDone);
         if(now-t>30*60) continue;   // 启动时不补推半小时前的旧数据
         string dir="";
         if(vals[i].forecast_value!=LONG_MIN)
            dir=(vals[i].actual_value>vals[i].forecast_value?"（高于预期）":
                (vals[i].actual_value<vals[i].forecast_value?"（低于预期）":"（符合预期）"));
         Queue(StringFormat("%s已公布 %s %s｜公布 %s%s 预期 %s 前值 %s",tag,CalendarCurrency,ev.name,
               CalNum(vals[i].actual_value,(int)ev.digits),dir,
               CalNum(vals[i].forecast_value,(int)ev.digits),CalNum(vals[i].prev_value,(int)ev.digits)));
      }
   }
}

//+------------------------------------------------------------------+
//| RSS                                                               |
//+------------------------------------------------------------------+
string Between(const string s,const string a,const string b,int from,int &endPos)
{
   int p=StringFind(s,a,from); if(p<0) { endPos=-1; return ""; }
   p+=StringLen(a);
   int q=StringFind(s,b,p); if(q<0) { endPos=-1; return ""; }
   endPos=q+StringLen(b);
   return StringSubstr(s,p,q-p);
}

void PollRss(const string url,bool &primed)
{
   if(url=="") return;
   string body;
   if(!HttpGet(url,"User-Agent: Mozilla/5.0\r\n",body)) return;

   int pos=0,e=0;
   while(true)
   {
      string item=Between(body,"<item>","</item>",pos,e);
      if(e<0) break;
      pos=e;
      int x;
      string title=Between(item,"<title>","</title>",0,x);
      StringReplace(title,"<![CDATA[",""); StringReplace(title,"]]>","");
      title=StripTags(title);
      if(title=="") continue;

      string key="R"+title;
      if(Seen(key)) continue;
      MarkSeen(key);
      if(!primed && !NotifyBacklogOnStart) continue;
      if(ArraySize(g_ex)>0 && Contains(title,g_ex)) continue;
      if(!Contains(title,g_kw)) continue;
      Queue("RSS｜"+title);
   }
   primed=true;
}

//+------------------------------------------------------------------+
//| 主循环                                                            |
//+------------------------------------------------------------------+
void OnStart()
{
   string cn[],en[];
   SplitList(KeywordsCN,cn); SplitList(KeywordsEN,en);
   ArrayResize(g_kw,0);
   for(int i=0;i<ArraySize(cn);i++){ int n=ArraySize(g_kw); ArrayResize(g_kw,n+1); g_kw[n]=cn[i]; }
   for(int i=0;i<ArraySize(en);i++){ int n=ArraySize(g_kw); ArrayResize(g_kw,n+1); g_kw[n]=en[i]; }
   SplitList(ExcludeWords,g_ex);

   string hello=StringFormat("Jammy 新闻监控已启动：每%d秒检查｜关键词%d个｜金十%s 日历%s",
                             PollSeconds,ArraySize(g_kw),EnableJin10?"开":"关",EnableCalendar?"开":"关");
   Print(hello);
   if(UsePush) SendNotification(hello);

   while(!IsStopped())
   {
      PollJin10();
      PollCalendar();
      PollRss(RssUrl1,g_rssPrimed1);
      PollRss(RssUrl2,g_rssPrimed2);
      FlushQueue();

      for(int s=0;s<MathMax(5,PollSeconds) && !IsStopped();s++) Sleep(1000);
   }
   Print("Jammy 新闻监控已停止");
}
