import { useState, useEffect } from "@lynx-js/react";
import { LynxBridge, UserInfo, SystemInfo } from "./bridge";
import "./styles.css";

export default function App() {
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [lastActionResult, setLastActionResult] = useState<string>("尚未触发操作");

  useEffect(() => {
    // Load current user info and system metrics
    LynxBridge.getUserInfo()
      .then((user) => setUserInfo(user))
      .catch((err) => console.error("Failed to load user info:", err));

    LynxBridge.getSystemInfo()
      .then((sys) => setSystemInfo(sys))
      .catch((err) => console.error("Failed to load system info:", err));
  }, []);

  const handleScanQR = async () => {
    try {
      setLastActionResult("正在唤起宿主扫码组件...");
      const result = await LynxBridge.scanQRCode();
      setLastActionResult(`扫码结果: \${result.code}`);
      LynxBridge.showToast("扫码成功", "success");
    } catch (e: any) {
      setLastActionResult(`扫码取消或失败: \${e.message}`);
    }
  };

  const handleRequest = async () => {
    try {
      setLastActionResult("正在通过宿主 DioClient 请求接口...");
      const res = await LynxBridge.request({
        url: "/api/v1/desk/list",
        method: "GET",
      });
      setLastActionResult(`请求成功: \${JSON.stringify(res)}`);
      LynxBridge.showToast("接口请求成功");
    } catch (e: any) {
      setLastActionResult(`请求失败: \${e.message}`);
    }
  };

  const handleShowModal = async () => {
    const res = await LynxBridge.showModal(
      "操作确认",
      "确定要在 Lynx 小程序中执行该操作吗？",
      true
    );
    setLastActionResult(`Modal 结果: \${res.confirm ? "点击了确定" : "点击了取消"}`);
  };

  const handleToast = () => {
    LynxBridge.showToast("Hello from Lynx Mini-Program!", "success");
    setLastActionResult("已触发宿主 KTips Toast");
  };

  return (
    <view className="container">
      {/* Header Banner */}
      <view className="header-card">
        <text className="header-title">Lynx 动态小程序</text>
        <text className="header-subtitle">驱动框架: LynxJS (https://lynxjs.org/)</text>
      </view>

      {/* User Info from KManager */}
      <view className="section-card">
        <text className="section-title">宿主当前登录信息</text>
        <view className="user-info-row">
          <text className="user-info-label">用户姓名:</text>
          <text className="user-info-value">{userInfo?.userName || "未登录"}</text>
        </view>
        <view className="user-info-row">
          <text className="user-info-label">手机号码:</text>
          <text className="user-info-value">{userInfo?.phone || "-"}</text>
        </view>
        <view className="user-info-row">
          <text className="user-info-label">运行平台:</text>
          <text className="user-info-value">{systemInfo?.platform || "-"}</text>
        </view>
      </view>

      {/* Quick Action Grid */}
      <view className="section-card">
        <text className="section-title">宿主能力桥接</text>
        <view className="actions-grid">
          <view className="action-btn" bindtap={handleScanQR}>
            <text className="action-icon">📷</text>
            <text className="action-label">宿主扫码</text>
          </view>
          <view className="action-btn" bindtap={handleRequest}>
            <text className="action-icon">🌐</text>
            <text className="action-label">网络代理</text>
          </view>
          <view className="action-btn" bindtap={handleShowModal}>
            <text className="action-icon">💬</text>
            <text className="action-label">原生弹窗</text>
          </view>
          <view className="action-btn" bindtap={handleToast}>
            <text className="action-icon">🔔</text>
            <text className="action-label">KTips Toast</text>
          </view>
        </view>

        {/* Operation Result */}
        <view className="result-card">
          <text className="result-title">最新执行结果:</text>
          <text className="result-text">{lastActionResult}</text>
        </view>
      </view>
    </view>
  );
}
