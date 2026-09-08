import React from "@lynx-js/react";

export interface TagProps {
  children: React.ReactNode;
  color?: "blue" | "green" | "gold" | "red" | "purple" | "cyan" | "default";
  size?: "small" | "middle";
  bordered?: boolean;
  className?: string;
}

export function Tag({
  children,
  color = "default",
  size = "small",
  bordered = true,
  className = "",
}: TagProps) {
  return (
    <view className={`ui-tag ui-tag-${color} ui-tag-${size} ${bordered ? "ui-tag-bordered" : ""} ${className}`}>
      <text className={`ui-tag-text ui-tag-text-${color}`}>{children}</text>
    </view>
  );
}

export interface BadgeProps {
  count?: number;
  dot?: boolean;
  overflowCount?: number;
  children?: React.ReactNode;
  className?: string;
}

export function Badge({ count, dot = false, overflowCount = 99, children, className = "" }: BadgeProps) {
  const displayCount = count !== undefined && count > overflowCount ? `${overflowCount}+` : count;

  return (
    <view className={`ui-badge-wrapper ${className}`}>
      {children}
      {dot && <view className="ui-badge-dot" />}
      {!dot && count !== undefined && count > 0 && (
        <view className="ui-badge-count">
          <text className="ui-badge-count-text">{displayCount}</text>
        </view>
      )}
    </view>
  );
}
