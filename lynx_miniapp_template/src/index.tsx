import { useState, useEffect } from "@lynx-js/react";
import { LynxBridge, UserInfo, SystemInfo } from "./bridge";
import "./styles.css";

export default function App() {
  const [activeTab, setActiveTab] = useState<number>(0);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [lastActionResult, setLastActionResult] = useState<string>("尚未触发操作");

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

  return (
    <view className="container">
      {/* Top Header Card */}
      <view className="header-card">
        <text className="header-title">Lynx 动态小程序 (ReactLynx)</text>
        <text className="header-subtitle">双向 JSBridge 隧道已就绪 • 支持热更与秒开</text>
      </view>

      {/* Tabs */}
      <view className="tabs-bar">
        {["桌台看板", "扫码点餐", "会员中心", "宿主隧道"].map((t, idx) => (
          <view
            key={idx}
            className={`tab-item ${activeTab === idx ? "tab-active" : ""}`}
            bindtap={() => setActiveTab(idx)}
          >
            <text className={`tab-text ${activeTab === idx ? "tab-text-active" : ""}`}>{t}</text>
          </view>
        ))}
      </view>

      {/* Tab 0: 桌台看板 */}
      {activeTab === 0 && (
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

      {/* Tab 1: 扫码点餐 */}
      {activeTab === 1 && (
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

      {/* Tab 2: 会员中心 */}
      {activeTab === 2 && (
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

      {/* Tab 3: 宿主隧道 */}
      {activeTab === 3 && (
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
