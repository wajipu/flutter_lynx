import React from "@lynx-js/react";

export interface BarChartDataItem {
  label: string;
  value: number;
  subValue?: string | number;
  highlight?: boolean;
}

export interface BarChartProps {
  data: BarChartDataItem[];
  selectedIndex?: number;
  onSelectIndex?: (index: number) => void;
  height?: number;
  unit?: string;
  className?: string;
}

export function BarChart({
  data,
  selectedIndex = 0,
  onSelectIndex,
  height = 180,
  unit = "¥",
  className = "",
}: BarChartProps) {
  const maxValue = Math.max(...data.map((d) => d.value), 100);
  const yTicks = [
    { label: `${unit}${(maxValue).toFixed(0)}`, ratio: 1.0 },
    { label: `${unit}${(maxValue * 0.75).toFixed(0)}`, ratio: 0.75 },
    { label: `${unit}${(maxValue * 0.5).toFixed(0)}`, ratio: 0.5 },
    { label: `${unit}${(maxValue * 0.25).toFixed(0)}`, ratio: 0.25 },
    { label: `${unit}0`, ratio: 0.0 },
  ];

  return (
    <view className={`ui-chart-container ${className}`}>
      {/* Chart Canvas Area with Y-axis and Gridlines */}
      <view className="ui-chart-canvas" style={{ height: `${height}px` }}>
        {/* Y-Axis Grid Lines & Ticks */}
        <view className="ui-chart-grid">
          {yTicks.map((tick, idx) => (
            <view key={idx} className="ui-chart-grid-row">
              <text className="ui-chart-y-label">{tick.label}</text>
              <view className="ui-chart-grid-line" />
            </view>
          ))}
        </view>

        {/* Bars Columns */}
        <view className="ui-chart-bars-layer">
          {data.map((item, idx) => {
            const isSelected = selectedIndex === idx;
            const barHeightPct = Math.max(4, Math.round((item.value / maxValue) * 100));

            return (
              <view
                key={idx}
                className={`ui-chart-col ${isSelected ? "ui-chart-col-selected" : ""}`}
                bindtap={() => onSelectIndex?.(idx)}
              >
                <view className="ui-chart-bar-value-wrapper">
                  <text className={`ui-chart-bar-value ${isSelected ? "ui-chart-bar-value-active" : ""}`}>
                    {item.value >= 1000 ? `${(item.value / 1000).toFixed(1)}k` : item.value}
                  </text>
                </view>

                <view className="ui-chart-bar-track">
                  <view
                    className={`ui-chart-bar-fill ${isSelected ? "ui-chart-bar-fill-selected" : ""}`}
                    style={{ height: `${barHeightPct}%` }}
                  />
                </view>

                <view className="ui-chart-x-wrapper">
                  <text className={`ui-chart-x-label ${isSelected ? "ui-chart-x-label-active" : ""}`}>
                    {item.label}
                  </text>
                </view>
              </view>
            );
          })}
        </view>
      </view>

      {data[selectedIndex] && (
        <view className="ui-chart-detail-pill">
          <view className="ui-chart-detail-dot" />
          <text className="ui-chart-detail-text">
            选中时段 {data[selectedIndex].label}：{unit}{data[selectedIndex].value}
            {data[selectedIndex].subValue ? ` (${data[selectedIndex].subValue})` : ""}
          </text>
        </view>
      )}
    </view>
  );
}

export interface ProgressCategoryItem {
  name: string;
  percent: number;
  color: string;
  amount?: string;
}

export interface CategoryCompositionProps {
  categories: ProgressCategoryItem[];
  className?: string;
}

export function CategoryComposition({ categories, className = "" }: CategoryCompositionProps) {
  return (
    <view className={`ui-composition-container ${className}`}>
      <view className="ui-composition-track">
        {categories.map((cat, idx) => (
          <view
            key={idx}
            className="ui-composition-segment"
            style={{
              flex: cat.percent,
              backgroundColor: cat.color,
            }}
          />
        ))}
      </view>

      <view className="ui-composition-legends">
        {categories.map((cat, idx) => (
          <view key={idx} className="ui-composition-legend-item">
            <view className="ui-composition-dot" style={{ backgroundColor: cat.color }} />
            <text className="ui-composition-legend-name">{cat.name}</text>
            <text className="ui-composition-legend-percent">{cat.percent}%</text>
            {cat.amount && <text className="ui-composition-legend-amount">{cat.amount}</text>}
          </view>
        ))}
      </view>
    </view>
  );
}

export interface LineChartItem {
  day: string;
  revenue: number;
  orders: number;
}

export interface LineTrendChartProps {
  data: LineChartItem[];
  selectedDayIdx?: number;
  onSelectDay?: (idx: number) => void;
  className?: string;
}

export function LineTrendChart({
  data,
  selectedDayIdx = 4,
  onSelectDay,
  className = "",
}: LineTrendChartProps) {
  const maxRev = Math.max(...data.map((d) => d.revenue), 100);

  return (
    <view className={`ui-line-chart-box ${className}`}>
      {/* Visual Line Curve Nodes */}
      <view className="ui-line-chart-body">
        {data.map((item, idx) => {
          const isSelected = selectedDayIdx === idx;
          const ratio = Math.max(0.1, item.revenue / maxRev);

          return (
            <view
              key={idx}
              className={`ui-line-node-col ${isSelected ? "ui-line-col-active" : ""}`}
              bindtap={() => onSelectDay?.(idx)}
            >
              <text className={`ui-line-val ${isSelected ? "ui-line-val-active" : ""}`}>
                ¥{(item.revenue / 1000).toFixed(1)}k
              </text>
              <view className="ui-line-track">
                <view
                  className={`ui-line-point ${isSelected ? "ui-line-point-active" : ""}`}
                  style={{ marginBottom: `${Math.round(ratio * 90)}px` }}
                />
              </view>
              <text className={`ui-line-label ${isSelected ? "ui-line-label-active" : ""}`}>
                {item.day}
              </text>
            </view>
          );
        })}
      </view>

      {data[selectedDayIdx] && (
        <view className="ui-chart-detail-pill">
          <view className="ui-chart-detail-dot" />
          <text className="ui-chart-detail-text">
            {data[selectedDayIdx].day}流水: ¥{data[selectedDayIdx].revenue} | 订单量: {data[selectedDayIdx].orders} 单
          </text>
        </view>
      )}
    </view>
  );
}

export interface GaugeChartProps {
  target: number;
  current: number;
  unit?: string;
  title?: string;
  className?: string;
}

export function GaugeChart({
  target,
  current,
  unit = "¥",
  title = "今日业绩目标达成度",
  className = "",
}: GaugeChartProps) {
  const percent = Math.min(100, Math.round((current / target) * 100));
  const diff = Math.max(0, target - current);

  return (
    <view className={`ui-gauge-card ${className}`}>
      <text className="ui-gauge-title">{title}</text>
      <view className="ui-gauge-meter-wrapper">
        <view className="ui-gauge-meter-bg">
          <view className="ui-gauge-meter-fill" style={{ width: `${percent}%` }} />
        </view>
        <view className="ui-gauge-percent-box">
          <text className="ui-gauge-percent-text">{percent}%</text>
          <text className="ui-gauge-status-chip">
            {percent >= 90 ? "🚀 冲刺就绪" : "持续推进"}
          </text>
        </view>
      </view>
      <view className="ui-gauge-stats-row">
        <view className="ui-gauge-stat">
          <text className="ui-gauge-stat-lbl">业绩目标</text>
          <text className="ui-gauge-stat-val">{unit}{target.toLocaleString()}</text>
        </view>
        <view className="ui-gauge-stat">
          <text className="ui-gauge-stat-lbl">当前已达</text>
          <text className="ui-gauge-stat-val ui-gauge-val-green">{unit}{current.toLocaleString()}</text>
        </view>
        <view className="ui-gauge-stat">
          <text className="ui-gauge-stat-lbl">距离目标</text>
          <text className="ui-gauge-stat-val ui-gauge-val-orange">{unit}{diff.toLocaleString()}</text>
        </view>
      </view>
    </view>
  );
}
