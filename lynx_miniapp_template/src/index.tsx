import { useState, useEffect } from "@lynx-js/react";
import { LynxBridge, UserInfo, SystemInfo } from "./bridge";
import {
  Button,
  Card,
  Statistic,
  BarChart,
  CategoryComposition,
  Tag,
  Stepper,
} from "./components/ui";
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
    { label: "10:00", value: 1280, subValue: "18单" },
    { label: "12:00", value: 5640, subValue: "68单" },
    { label: "14:00", value: 2180, subValue: "26单" },
    { label: "16:00", value: 1650, subValue: "20单" },
    { label: "18:00", value: 6820, subValue: "82单" },
    { label: "20:00", value: 6120, subValue: "74单" },
    { label: "22:00", value: 3480, subValue: "32单" },
    { label: "24:00", value: 1280, subValue: "8单" },
  ];

  const categoryComposition = [
    { name: "招牌热菜与火锅", percent: 45, color: "#1677FF", amount: "¥12,802.50" },
    { name: "特色小吃与冷碟", percent: 25, color: "#52C41A", amount: "¥7,112.50" },
    { name: "鲜榨特饮与名酒", percent: 18, color: "#FAAD14", amount: "¥5,121.00" },
    { name: "经典主食与甜品", percent: 12, color: "#722ED1", amount: "¥3,414.00" },
  ];

  return (
    <view className="container">
      {/* Top Header Card */}
      <view className="header-card">
        <text className="header-title">Lynx 动态小程序 (ReactLynx TSX)</text>
        <text className="header-subtitle">组件库驱动 • Ant Design / Semi 规范 • 宿主双向通信</text>
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
        <view>
          {/* KPI Statistics Grid using UI Components */}
          <view className="kpi-grid">
            <Statistic
              title="今日营业总额"
              value="28,450.00"
              prefix="¥"
              trend={{ type: "up", value: "18.4% 环比昨日" }}
              color="#1677FF"
              icon="💰"
            />
            <Statistic
              title="有效订单总量"
              value="328"
              suffix="单"
              trend={{ type: "up", value: "12.6% 环比昨日" }}
              color="#52C41A"
              icon="📋"
            />
            <Statistic
              title="顾客平均客单价"
              value="86.74"
              prefix="¥"
              trend={{ type: "up", value: "5.2% 提升" }}
              color="#FAAD14"
              icon="🏷️"
            />
            <Statistic
              title="综合菜品毛利率"
              value="68.5"
              suffix="%"
              trend={{ type: "neutral", value: "优秀标准" }}
              color="#722ED1"
              icon="📈"
            />
          </view>

          {/* Professional BarChart Component */}
          <Card
            title="分时营收与订单走势图"
            subtitle="专业可视化图表组件库 • 含 Y 轴刻度与辅助网格线"
            extra={
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
            }
          >
            <BarChart
              data={hourlyData}
              selectedIndex={selectedHourIdx}
              onSelectIndex={setSelectedHourIdx}
              unit="¥"
              height={170}
            />
          </Card>

          {/* Category Composition Ring / Bar */}
          <Card title="营收品类结构占比" subtitle="基于各品类订单流水贡献比率分析">
            <CategoryComposition categories={categoryComposition} />
          </Card>

          {/* Top Sellers */}
          <Card title="爆款单品销量与毛利排行 Top 4" subtitle="今日累计点单频次与利润贡献">
            {[
              { rank: "1", name: "招牌秘制牛腩煲", sales: "142份", rev: "¥9,656", margin: "毛利 68%", color: "gold" as const },
              { rank: "2", name: "潮汕鲜手打牛肉丸", sales: "98份", rev: "¥3,724", margin: "毛利 72%", color: "blue" as const },
              { rank: "3", name: "生椰爆汁柠檬茶", sales: "86杯", rev: "¥1,548", margin: "毛利 81%", color: "green" as const },
              { rank: "4", name: "极佳级安格斯眼肉", sales: "45份", rev: "¥4,410", margin: "毛利 65%", color: "red" as const },
            ].map((t) => (
              <view key={t.rank} className="top-row">
                <view className="top-badge"><text className="badge-text">{t.rank}</text></view>
                <view className="top-info">
                  <text className="top-name">{t.name}</text>
                  <text className="top-sales">已售 {t.sales}</text>
                </view>
                <view className="top-money">
                  <text className="top-rev">{t.rev}</text>
                  <Tag color={t.color}>{t.margin}</Tag>
                </view>
              </view>
            ))}
          </Card>

          {/* Export Report Button Component */}
          <Button
            type="primary"
            block
            size="large"
            onClick={handleExportReport}
            icon="📊"
          >
            通过宿主隧道导出 Excel 报表 (exportReport)
          </Button>
        </view>
      )}

      {/* Tab 1: 桌台看板 */}
      {activeTab === 1 && (
        <Card title="餐饮桌台看板 (Grid 布局)" subtitle="实时桌位占用与翻台协同">
          <view className="desk-grid">
            {[
              { name: "大厅A01", cap: "4人", status: "就餐中", amount: "¥288", color: "gold" as const },
              { name: "大厅A02", cap: "4人", status: "空闲", amount: "-", color: "green" as const },
              { name: "靠窗A05", cap: "2人", status: "就餐中", amount: "¥168", color: "gold" as const },
              { name: "包厢B01", cap: "10人", status: "已预定", amount: "¥500", color: "blue" as const },
            ].map((d, i) => (
              <view key={i} className="desk-card" bindtap={() => handleToast(`已选择桌台: ${d.name}`)}>
                <view className="desk-header">
                  <text className="desk-name">{d.name}</text>
                  <Tag color={d.color}>{d.status}</Tag>
                </view>
                <text className="desk-cap">{d.cap}</text>
                <text className="desk-amt">{d.amount}</text>
              </view>
            ))}
          </view>
        </Card>
      )}

      {/* Tab 2: 扫码点餐 */}
      {activeTab === 2 && (
        <Card title="扫码点餐货架" subtitle="双列分类与 Stepper 步进器组件">
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
                { id: "p1", name: "招牌秘制牛腩煲", price: 68, tag: "爆品" },
                { id: "p2", name: "潮汕鲜手打牛肉丸", price: 38, tag: "推荐" },
                { id: "p3", name: "生椰爆汁柠檬茶", price: 18, tag: "人气" },
              ].map((p) => (
                <view key={p.id} className="product-row">
                  <view className="product-info">
                    <view className="product-name-row">
                      <text className="product-name">{p.name}</text>
                      <Tag color="red">{p.tag}</Tag>
                    </view>
                    <text className="product-price">¥{p.price}</text>
                  </view>
                  <Stepper
                    value={cart[p.id] || 0}
                    onChange={(val) => updateCart(p.id, val - (cart[p.id] || 0))}
                  />
                </view>
              ))}
            </view>
          </view>
        </Card>
      )}

      {/* Tab 3: 会员中心 */}
      {activeTab === 3 && (
        <view>
          <view className="vip-hero-card">
            <text className="vip-title">黑金尊享 VIP 会员</text>
            <text className="vip-sub">积分余额: 12,850 • 储值 ¥880.00</text>
          </view>
          <Card title="会员专属特惠券包">
            <view className="coupon-item" bindtap={() => handleToast("已领取 ¥30 堂食立减券")}>
              <text className="coupon-val">¥30</text>
              <view className="coupon-info">
                <text className="coupon-title">全场通用堂食无门槛立减券</text>
                <text className="coupon-sub">有效期至 2026-12-31</text>
              </view>
              <Button type="primary" size="small" onClick={() => handleToast("领取成功")}>领取</Button>
            </view>
          </Card>
        </view>
      )}

      {/* Tab 4: 宿主隧道 */}
      {activeTab === 4 && (
        <Card title="宿主能力桥接隧道 (JSBridge)" subtitle="调用宿主系统原生能力与安全硬件">
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
        </Card>
      )}
    </view>
  );
}
