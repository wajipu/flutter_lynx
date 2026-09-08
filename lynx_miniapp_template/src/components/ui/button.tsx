import React from "@lynx-js/react";

export interface ButtonProps {
  type?: "primary" | "default" | "success" | "warning" | "danger" | "ghost";
  size?: "small" | "middle" | "large";
  block?: boolean;
  disabled?: boolean;
  loading?: boolean;
  icon?: string;
  onClick?: () => void;
  children?: React.ReactNode;
  className?: string;
}

export function Button({
  type = "default",
  size = "middle",
  block = false,
  disabled = false,
  loading = false,
  icon,
  onClick,
  children,
  className = "",
}: ButtonProps) {
  const handleClick = () => {
    if (!disabled && !loading && onClick) {
      onClick();
    }
  };

  const btnClass = `ui-btn ui-btn-${type} ui-btn-${size} ${block ? "ui-btn-block" : ""} ${disabled ? "ui-btn-disabled" : ""} ${className}`;

  return (
    <view className={btnClass} bindtap={handleClick}>
      {loading && <text className="ui-btn-spinner">⟳ </text>}
      {icon && !loading && <text className="ui-btn-icon">{icon} </text>}
      <text className={`ui-btn-text ui-btn-text-${type}`}>{children}</text>
    </view>
  );
}
