import React from "@lynx-js/react";

export interface StatisticProps {
  title: string;
  value: string | number;
  prefix?: string;
  suffix?: string;
  trend?: {
    type: "up" | "down" | "neutral";
    value: string;
  };
  color?: string;
  icon?: string;
  className?: string;
}

export function Statistic({
  title,
  value,
  prefix,
  suffix,
  trend,
  color = "#1677ff",
  icon,
  className = "",
}: StatisticProps) {
  return (
    <view className={`ui-statistic ${className}`}>
      <view className="ui-statistic-header">
        <text className="ui-statistic-title">{title}</text>
        {icon && <text className="ui-statistic-icon">{icon}</text>}
      </view>
      <view className="ui-statistic-value-box">
        {prefix && <text className="ui-statistic-prefix">{prefix}</text>}
        <text className="ui-statistic-value" style={{ color }}>
          {value}
        </text>
        {suffix && <text className="ui-statistic-suffix">{suffix}</text>}
      </view>
      {trend && (
        <view className="ui-statistic-trend">
          <text className={`ui-statistic-trend-tag ui-statistic-trend-${trend.type}`}>
            {trend.type === "up" ? "↑ " : trend.type === "down" ? "↓ " : "• "}
            {trend.value}
          </text>
        </view>
      )}
    </view>
  );
}
