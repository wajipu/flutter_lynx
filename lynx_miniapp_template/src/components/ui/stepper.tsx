import React from "@lynx-js/react";

export interface StepperProps {
  value: number;
  min?: number;
  max?: number;
  step?: number;
  onChange?: (value: number) => void;
  className?: string;
}

export function Stepper({
  value = 0,
  min = 0,
  max = 999,
  step = 1,
  onChange,
  className = "",
}: StepperProps) {
  const handleMinus = () => {
    if (value > min) {
      onChange?.(Math.max(min, value - step));
    }
  };

  const handlePlus = () => {
    if (value < max) {
      onChange?.(Math.min(max, value + step));
    }
  };

  return (
    <view className={`ui-stepper ${className}`}>
      {value > min && (
        <view
          className={`ui-stepper-btn ui-stepper-btn-minus ${value <= min ? "ui-stepper-btn-disabled" : ""}`}
          bindtap={handleMinus}
        >
          <text className="ui-stepper-btn-icon">-</text>
        </view>
      )}
      {value > min && (
        <view className="ui-stepper-val-box">
          <text className="ui-stepper-val-text">{value}</text>
        </view>
      )}
      <view
        className={`ui-stepper-btn ui-stepper-btn-plus ${value >= max ? "ui-stepper-btn-disabled" : ""}`}
        bindtap={handlePlus}
      >
        <text className="ui-stepper-btn-icon">+</text>
      </view>
    </view>
  );
}
