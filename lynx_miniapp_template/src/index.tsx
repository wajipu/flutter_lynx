import { useState, useEffect } from "@lynx-js/react";
import { LynxBridge, UserInfo, SystemInfo } from "./bridge";
import "./styles.css";

export default function App() {
  const [activeTab, setActiveTab] = useState<number>(0);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [lastActionResult, setLastActionResult] = useState<string>("尚未触发操作");

  // Report state
  const [reportPeriod, setReportPeriod] = useState<string>("今日实时");
  const [selectedHourIdx, setSelectedHourIdx] = useState<number>(4);

  // Order state
  const [selectedCat, setSelectedCat] = useState<number>(0);
  const [cart, setCart] = useState<Record<string, number>>({});

  useEffect(() => {
    LynxBridge.getUserInfo().then(setUserInfo).catch(console.error);
    LynxBridge.getSystemInfo().then(setSystemInfo).catch(console.error);
  }, []);

  const handleScanQR = async () => {
    try {
      setLastActionResult("正在唤起宿主扫码组件...");
      const result = await LynxBridge.scanQRCode();
      setLastActionResult(`扫码结果: ${result.code}`);
      LynxBridge.showToast("扫码成功", "success");
    } catch (e: any) {
      setLastActionResult(`扫码失败: ${e.message}`);
    }
  };

  const handleRequest = async (url: string) => {
    try {
      setLastActionResult(`正在通过宿主网络代理请求: ${url}...`);
      const res = await LynxBridge.request({ url, method: "GET" });
      setLastActionResult(`请求成功:\n${JSON.stringify(res, null, 2)}`);
      LynxBridge.showToast("接口请求成功");
    } catch (e: any) {
      setLastActionResult(`请求失败: ${e.message}`);
    }
  };

  const handleExportReport = async () => {
    try {
      setLastActionResult("正在通知宿主生成并导出 Excel 报表...");
      const res = await LynxBridge.invoke("exportReport", { range: reportPeriod, format: "xlsx" }, "report");
      setLastActionResult(`报表导出成功:\n${JSON.stringify(res, null, 2)}`);
      LynxBridge.showToast("Excel 导出完成", "success");
    } catch (e: any) {
      setLastActionResult(`导出失败: ${e.message}`);
    }
  };

  const handleShowModal = async () => {
    const res = await LynxBridge.showModal("宿主原生弹窗", "确定要在 Lynx 小程序中执行此操作吗？", true);
    setLastActionResult(`Modal 结果: ${res.confirm ? "点击了确定" : "点击了取消"}`);
  };

  const handleToast = (msg: string) => {
    LynxBridge.showToast(msg, "success");
    setLastActionResult(`已触发宿主 Toast: ${msg}`);
  };

  const updateCart = (id: string, delta: number) => {
    const next = { ...cart };
    const cur = next[id] || 0;
    const val = Math.max(0, cur + delta);
    if (val === 0) delete next[id];
    else next[id] = val;
    setCart(next);
  };

  const hourlyData = [
    { hour: "10:00", amount: 1280, orders: 18, height: 25 },
    { hour: "12:00", amount: 5640, orders: 68, height: 85 },
    { hour: "14:00", amount: 2180, orders: 26, height: 35 },
    { hour: "16:00", amount: 1650, orders: 20, height: 28 },
    { hour: "18:00", amount: 6820, orders: 82, height: 100 },
    { hour: "20:00", amount: 6120, orders: 74, height: 90 },
    { hour: "22:00", amount: 3480, orders: 32, height: 52 },
    { hour: "24:00", amount: 1280, orders: 8, height: 20 },
  ];

  const curHour = hourlyData[selectedHourIdx];

  return (
    <view className="container">
      {/* Top Header Card */}
      <view className="header-card">
        <text className="header-title">Lynx 动态小程序 (ReactLynx TSX)</text>
        <text className="header-subtitle">宿主纯容器化驱动 • 100% 独立 TSX / CSS 代码</text>
      </view>

      {/* Tabs */}
      <view className="tabs-bar">
        {["经营报表", "桌台看板", "扫码点餐", "会员中心", "宿主隧道"].map((t, idx) => (
          <view
            key={idx}
            className={`tab-item ${activeTab === idx ? "tab-active" : ""}`}
            bindtap={() => setActiveTab(idx)}
          >
            <text className={`tab-text ${activeTab === idx ? "tab-text-active" : ""}`}>{t}</text>
          </view>
        ))}
      </view>

      {/* Tab 0: 经营分析与多维报表图表 */}
      {activeTab === 0 && (
        <view className="section-card">
          <view className="report-header-row">
            <view className="period-selector">
              {["今日实时", "近7天", "本月"].map((p) => (
                <view
                  key={p}
                  className={`period-btn ${reportPeriod === p ? "period-active" : ""}`}
                  bindtap={() => setReportPeriod(p)}
                >
                  <text className="period-text">{p}</text>
                </view>
              ))}
            </view>
            <view className="export-btn" bindtap={handleExportReport}>
              <text className="export-text">📥 导出 Excel</text>
            </view>
          </view>

          {/* KPI Metrics */}
          <view className="kpi-grid">
            <view className="kpi-card">
              <text className="kpi-title">今日营业总额</text>
              <text className="kpi-val">¥28,450.00</text>
              <text className="kpi-sub kpi-green">同比 +14.8% ↑</text>
            </view>
            <view className="kpi-card">
              <text className="kpi-title">成交订单总量</text>
              <text className="kpi-val">328 单</text>
              <text className="kpi-sub">客单价 ¥86.7</text>
            </view>
            <view className="kpi-card">
              <text className="kpi-title">餐台综合翻台率</text>
              <text className="kpi-val">3.6 次/日</text>
              <text className="kpi-sub kpi-orange">满座率 94%</text>
            </view>
            <view className="kpi-card">
              <text className="kpi-title">会员消费贡献额</text>
              <text className="kpi-val">¥18,260.00</text>
              <text className="kpi-sub kpi-purple">占比 64.2%</text>
            </view>
          </view>

          {/* Hourly Revenue Bar Chart */}
          <view className="chart-card">
            <text className="chart-title">分时营收与出单趋势柱状图</text>
            <text className="chart-sub">单位: 元 (点击柱形查看时段详情)</text>
            <view className="bar-chart-container">
              {hourlyData.map((d, i) => (
                <view
                  key={d.hour}
                  className={`bar-col ${selectedHourIdx === i ? "bar-active" : ""}`}
                  bindtap={() => setSelectedHourIdx(i)}
                >
                  {selectedHourIdx === i && <text className="bar-tip">¥{d.amount}</text>}
                  <view className={`bar-pillar bar-h-${d.height} ${selectedHourIdx === i ? "pillar-active" : ""}`} />
                  <text className="bar-label">{d.hour}</text>
                </view>
              ))}
            </view>
            <view className="hour-detail-box">
              <text className="hour-detail-text">
                选中时段: {curHour.hour} | 营收: ¥{curHour.amount} | 出单: {curHour.orders} 单
              </text>
            </view>
          </view>

          {/* Category Donut / Progress Breakdown */}
          <view className="chart-card">
            <text className="chart-title">菜品类目营收结构占比</text>
            <view className="progress-stack-bar">
              <view className="bar-seg seg-blue" />
              <view className="bar-seg seg-cyan" />
              <view className="bar-seg seg-orange" />
              <view className="bar-seg seg-purple" />
            </view>
            <view className="legend-list">
              {[
                { name: "招牌锅底与主菜", amt: "¥11,949", pct: "42%", dot: "dot-blue" },
                { name: "特色小吃与凉菜", amt: "¥7,397", pct: "26%", dot: "dot-cyan" },
                { name: "鲜制特饮与酒水", amt: "¥5,121", pct: "18%", dot: "dot-orange" },
                { name: "经典主食与甜点", amt: "¥3,983", pct: "14%", dot: "dot-purple" },
              ].map((c) => (
                <view key={c.name} className="legend-row">
                  <view className={`legend-dot ${c.dot}`} />
                  <text className="legend-name">{c.name}</text>
                  <text className="legend-amt">{c.amt}</text>
                  <text className="legend-pct">{c.pct}</text>
                </view>
              ))}
            </view>
          </view>

          {/* Top Sellers */}
          <view className="chart-card">
            <text className="chart-title">爆款单品销量与毛利排行 Top 4</text>
            {[
              { rank: "1", name: "招牌秘制牛腩煲", sales: "142份", rev: "¥9,656", margin: "毛利 68%" },
              { rank: "2", name: "潮汕鲜手打牛肉丸", sales: "98份", rev: "¥3,724", margin: "毛利 72%" },
              { rank: "3", name: "生椰爆汁柠檬茶", sales: "86杯", rev: "¥1,548", margin: "毛利 81%" },
              { rank: "4", name: "极佳级安格斯眼肉", sales: "45份", rev: "¥4,410", margin: "毛利 65%" },
            ].map((t) => (
              <view key={t.rank} className="top-row">
                <view className="top-badge"><text className="badge-text">{t.rank}</text></view>
                <view className="top-info">
                  <text className="top-name">{t.name}</text>
                  <text className="top-sales">已售 {t.sales}</text>
                </view>
                <view className="top-money">
                  <text className="top-rev">{t.rev}</text>
                  <view className="margin-pill"><text className="margin-text">{t.margin}</text></view>
                </view>
              </view>
            ))}
          </view>
        </view>
      )}

      {/* Tab 1: 桌台看板 */}
      {activeTab === 1 && (
        <view className="section-card">
          <text className="section-title">餐饮桌台看板 (Grid 布局)</text>
          <view className="desk-grid">
            {[
              { name: "大厅A01", cap: "4人", status: "就餐中", amount: "¥288" },
              { name: "大厅A02", cap: "4人", status: "空闲", amount: "-" },
              { name: "靠窗A05", cap: "2人", status: "就餐中", amount: "¥168" },
              { name: "包厢B01", cap: "10人", status: "已预定", amount: "¥500" },
            ].map((d, i) => (
              <view key={i} className="desk-card" bindtap={() => handleToast(`已选择桌台: ${d.name}`)}>
                <text className="desk-name">{d.name}</text>
                <text className="desk-cap">{d.cap} • {d.status}</text>
                <text className="desk-amt">{d.amount}</text>
              </view>
            ))}
          </view>
        </view>
      )}

      {/* Tab 2: 扫码点餐 */}
      {activeTab === 2 && (
        <view className="section-card">
          <text className="section-title">扫码点餐货架 (双列菜单布局)</text>
          <view className="menu-container">
            <view className="cat-sidebar">
              {["热销榜", "精选主食", "特色小吃", "现调饮品"].map((c, i) => (
                <view
                  key={i}
                  className={`cat-btn ${selectedCat === i ? "cat-active" : ""}`}
                  bindtap={() => setSelectedCat(i)}
                >
                  <text className="cat-text">{c}</text>
                </view>
              ))}
            </view>
            <view className="product-list">
              {[
                { id: "p1", name: "招牌秘制牛腩煲", price: 68 },
                { id: "p2", name: "潮汕鲜手打牛肉丸", price: 38 },
                { id: "p3", name: "生椰爆汁柠檬茶", price: 18 },
              ].map((p) => (
                <view key={p.id} className="product-row">
                  <view className="product-info">
                    <text className="product-name">{p.name}</text>
                    <text className="product-price">¥{p.price}</text>
                  </view>
                  <view className="stepper">
                    <view className="step-btn" bindtap={() => updateCart(p.id, -1)}>
                      <text>-</text>
                    </view>
                    <text className="step-count">{cart[p.id] || 0}</text>
                    <view className="step-btn step-add" bindtap={() => updateCart(p.id, 1)}>
                      <text>+</text>
                    </view>
                  </view>
                </view>
              ))}
            </view>
          </view>
        </view>
      )}

      {/* Tab 3: 会员中心 */}
      {activeTab === 3 && (
        <view className="section-card">
          <view className="vip-hero-card">
            <text className="vip-title">黑金尊享 VIP 会员</text>
            <text className="vip-sub">积分余额: 3,580 • 储值 ¥1,280.00</text>
          </view>
          <view className="coupon-item" bindtap={() => handleToast("已领取 ¥30 堂食立减券")}>
            <text className="coupon-val">¥30</text>
            <view className="coupon-info">
              <text className="coupon-title">全场通用堂食无门槛立减券</text>
              <text className="coupon-sub">有效期至 2026-12-31</text>
            </view>
            <view className="coupon-action"><text>领取</text></view>
          </view>
        </view>
      )}

      {/* Tab 4: 宿主隧道 */}
      {activeTab === 4 && (
        <view className="section-card">
          <text className="section-title">宿主能力桥接隧道 (JSBridge)</text>
          <view className="actions-grid">
            <view className="action-btn" bindtap={handleScanQR}>
              <text className="action-icon">📷</text>
              <text className="action-label">宿主扫码</text>
            </view>
            <view className="action-btn" bindtap={() => handleRequest("/api/v1/desk/list")}>
              <text className="action-icon">🌐</text>
              <text className="action-label">网络代理</text>
            </view>
            <view className="action-btn" bindtap={handleShowModal}>
              <text className="action-icon">💬</text>
              <text className="action-label">原生弹窗</text>
            </view>
            <view className="action-btn" bindtap={() => handleToast("已成功调用宿主 Toast!")}>
              <text className="action-icon">🔔</text>
              <text className="action-label">KTips Toast</text>
            </view>
          </view>

          {/* Operation Result */}
          <view className="result-card">
            <text className="result-title">最新隧道执行结果:</text>
            <text className="result-text">{lastActionResult}</text>
          </view>
        </view>
      )}
    </view>
  );
}
