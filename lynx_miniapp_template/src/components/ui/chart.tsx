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
  // Ceiling to nice round number
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
                {/* Value Label above Bar */}
                <view className="ui-chart-bar-value-wrapper">
                  <text className={`ui-chart-bar-value ${isSelected ? "ui-chart-bar-value-active" : ""}`}>
                    {item.value >= 1000 ? `${(item.value / 1000).toFixed(1)}k` : item.value}
                  </text>
                </view>

                {/* Animated Gradient Bar */}
                <view className="ui-chart-bar-track">
                  <view
                    className={`ui-chart-bar-fill ${isSelected ? "ui-chart-bar-fill-selected" : ""}`}
                    style={{ height: `${barHeightPct}%` }}
                  />
                </view>

                {/* X-Axis Label */}
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

      {/* Selected Indicator Card */}
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
      {/* Multi-segmented Bar */}
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

      {/* Legend List */}
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
