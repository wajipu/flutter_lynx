#import "LynxUIInput.h"

#import <Lynx/LynxUIContext.h>

@interface LynxUIInput () <UITextFieldDelegate> {
  NSInteger _maxLength;
}
@end

@implementation LynxUIInput

LYNX_REGISTER_UI("input")

// 群组宏只生成有方法体的 props 配置类方法，实例 setter 自由实现；
// 逐条 LYNX_PROP_SETTER 展开以无分号声明收尾，紧贴实现会被 clang 拒绝。
LYNX_PROPS_GROUP_DECLARE(LYNX_PROP_DECLARE("default-value", setDefaultValue, NSString*),
                         LYNX_PROP_DECLARE("placeholder", setPlaceholder, NSString*),
                         LYNX_PROP_DECLARE("maxlength", setMaxlength, NSInteger),
                         LYNX_PROP_DECLARE("confirm-type", setConfirmType, NSString*))

- (UITextField *)createView {
  // Lynx 的 initWithView:nil 会调用这里创建视图，监听必须绑定实际文本框。
  UITextField* view = [[UITextField alloc] init];
  view.delegate = self;
  view.borderStyle = UITextBorderStyleNone;
  view.backgroundColor = [UIColor clearColor];
  view.autocorrectionType = UITextAutocorrectionTypeNo;
  view.autocapitalizationType = UITextAutocapitalizationTypeNone;
  [view addTarget:self
           action:@selector(onTextChanged:)
 forControlEvents:UIControlEventEditingChanged];
  [view addTarget:self
           action:@selector(onConfirm:)
 forControlEvents:UIControlEventEditingDidEndOnExit];
  return view;
}

- (void)onTextChanged:(UITextField*)sender {
  if (_maxLength > 0 && sender.text.length > (NSUInteger)_maxLength) {
    sender.text = [sender.text substringToIndex:_maxLength];
  }
  [self emitCustomEvent:@"input" value:sender.text ?: @""];
}

- (void)onConfirm:(UITextField*)sender {
  [sender resignFirstResponder];
  [self emitCustomEvent:@"confirm" value:sender.text ?: @""];
}

- (void)emitCustomEvent:(NSString*)name value:(NSString*)value {
  LynxCustomEvent* event =
      [[LynxCustomEvent alloc] initWithName:name
                                 targetSign:self.sign
                                     params:@{@"value" : value ?: @""}];
  [self.context.eventEmitter sendCustomEvent:event];
}

- (void)setDefaultValue:(NSString*)value requestReset:(BOOL)requestReset {
  self.view.text = value;
  if (requestReset) {
    [self.view resignFirstResponder];
  }
}

- (void)setPlaceholder:(NSString*)value requestReset:(BOOL)requestReset {
  self.view.placeholder = value;
}

- (void)setMaxlength:(NSInteger)value requestReset:(BOOL)requestReset {
  _maxLength = value;
}

- (void)setConfirmType:(NSString*)value requestReset:(BOOL)requestReset {
  NSDictionary* mapping = @{
    @"search" : @(UIReturnKeySearch),
    @"go" : @(UIReturnKeyGo),
    @"send" : @(UIReturnKeySend),
    @"next" : @(UIReturnKeyNext),
    @"done" : @(UIReturnKeyDone),
  };
  NSNumber* key = mapping[value.lowercaseString];
  self.view.returnKeyType =
      key ? (UIReturnKeyType)key.integerValue : UIReturnKeyDefault;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField*)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString*)string {
  if (_maxLength <= 0 || [string isEqualToString:@""]) {
    return YES;
  }
  NSUInteger newLength = textField.text.length - range.length + string.length;
  return newLength <= (NSUInteger)_maxLength;
}

@end
