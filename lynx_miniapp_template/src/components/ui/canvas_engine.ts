/**
 * Lynx Mini-Program Dynamic Canvas 2D Engine
 *
 * Provides standard 2D Canvas drawing APIs in TSX/JS.
 * Drawing commands are serialized into a lightweight command stream and executed
 * directly on Flutter's Skia/Impeller GPU canvas at 60 FPS without WebView overhead.
 *
 * When mini-program developers create or modify charts (Radar, K-line, Funnel, Heatmap),
 * ONLY the mini-program bundle (.lynx.bundle) is published. The Flutter host NEVER needs
 * recompilation or App Store republication.
 */

export interface CanvasCommand {
  op: string;
  [key: string]: any;
}

export class LynxCanvasContext {
  private commands: CanvasCommand[] = [];
  private currentStrokeColor: string = "#000000";
  private currentFillColor: string = "#000000";
  private currentLineWidth: number = 1.0;

  get strokeStyle(): string {
    return this.currentStrokeColor;
  }
  set strokeStyle(color: string) {
    this.currentStrokeColor = color;
    this.commands.push({ op: "setStrokeColor", color });
  }

  get fillStyle(): string {
    return this.currentFillColor;
  }
  set fillStyle(color: string) {
    this.currentFillColor = color;
    this.commands.push({ op: "setFillColor", color });
  }

  get lineWidth(): number {
    return this.currentLineWidth;
  }
  set lineWidth(width: number) {
    this.currentLineWidth = width;
    this.commands.push({ op: "setLineWidth", width });
  }

  beginPath(): this {
    this.commands.push({ op: "beginPath" });
    return this;
  }

  closePath(): this {
    this.commands.push({ op: "closePath" });
    return this;
  }

  moveTo(x: number, y: number): this {
    this.commands.push({ op: "moveTo", x, y });
    return this;
  }

  lineTo(x: number, y: number): this {
    this.commands.push({ op: "lineTo", x, y });
    return this;
  }

  bezierCurveTo(cp1x: number, cp1y: number, cp2x: number, cp2y: number, x: number, y: number): this {
    this.commands.push({ op: "bezierCurveTo", cp1x, cp1y, cp2x, cp2y, x, y });
    return this;
  }

  quadraticCurveTo(cpx: number, cpy: number, x: number, y: number): this {
    this.commands.push({ op: "quadraticCurveTo", cpx, cpy, x, y });
    return this;
  }

  stroke(): this {
    this.commands.push({ op: "stroke" });
    return this;
  }

  fill(): this {
    this.commands.push({ op: "fill" });
    return this;
  }

  rect(x: number, y: number, w: number, h: number, isFill: boolean = true): this {
    this.commands.push({ op: "rect", x, y, w, h, isFill });
    return this;
  }

  roundRect(x: number, y: number, w: number, h: number, r: number = 4, isFill: boolean = true): this {
    this.commands.push({ op: "roundRect", x, y, w, h, r, isFill });
    return this;
  }

  arc(x: number, y: number, radius: number, startAngle: number, sweepAngle: number, isFill: boolean = false): this {
    this.commands.push({ op: "arc", x, y, radius, startAngle, sweepAngle, isFill });
    return this;
  }

  circle(x: number, y: number, radius: number, isFill: boolean = true): this {
    this.commands.push({ op: "circle", x, y, radius, isFill });
    return this;
  }

  setLinearGradient(x0: number, y0: number, x1: number, y1: number, colors: string[]): this {
    this.commands.push({ op: "setLinearGradient", x0, y0, x1, y1, colors });
    return this;
  }

  fillText(text: string, x: number, y: number, fontSize: number = 12, color?: string, isBold: boolean = false): this {
    this.commands.push({ op: "drawText", text, x, y, fontSize, color: color || this.currentFillColor, isBold });
    return this;
  }

  save(): this {
    this.commands.push({ op: "save" });
    return this;
  }

  restore(): this {
    this.commands.push({ op: "restore" });
    return this;
  }

  translate(x: number, y: number): this {
    this.commands.push({ op: "translate", x, y });
    return this;
  }

  rotate(angleDeg: number): this {
    this.commands.push({ op: "rotate", angle: angleDeg });
    return this;
  }

  scale(sx: number, sy: number): this {
    this.commands.push({ op: "scale", sx, sy });
    return this;
  }

  clear(): this {
    this.commands = [{ op: "clear" }];
    return this;
  }

  /**
   * Returns the recorded drawing command stream for Flutter to render.
   */
  getCommands(): CanvasCommand[] {
    return [...this.commands];
  }
}

/**
 * Factory to create a new canvas context in the mini-program
 */
export function createCanvasContext(): LynxCanvasContext {
  return new LynxCanvasContext();
}
