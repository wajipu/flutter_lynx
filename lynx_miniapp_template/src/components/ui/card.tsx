import React from "@lynx-js/react";

export interface CardProps {
  title?: string;
  subtitle?: string;
  extra?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
  bordered?: boolean;
  hoverable?: boolean;
}

export function Card({
  title,
  subtitle,
  extra,
  children,
  className = "",
  bordered = true,
}: CardProps) {
  return (
    <view className={`ui-card ${bordered ? "ui-card-bordered" : ""} ${className}`}>
      {(title || extra) && (
        <view className="ui-card-header">
          <view className="ui-card-header-left">
            {title && <text className="ui-card-title">{title}</text>}
            {subtitle && <text className="ui-card-subtitle">{subtitle}</text>}
          </view>
          {extra && <view className="ui-card-extra">{extra}</view>}
        </view>
      )}
      <view className="ui-card-body">{children}</view>
    </view>
  );
}
