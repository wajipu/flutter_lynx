#import "LynxUIInput.h"

#import <Lynx/LynxUIContext.h>

@interface LynxUIInput () <UITextFieldDelegate> {
  NSInteger _maxLength;
}
@end

LYNX_REGISTER_UI("input")

@implementation LynxUIInput

- (instancetype)initWithView:(UITextField*)view {
  if (self = [super initWithView:view]) {
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
  }
  return self;
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

#pragma mark - Props

LYNX_PROP_SETTER("default-value", setDefaultValue, NSString*)
- (void)setDefaultValue:(NSString*)value requestReset:(BOOL)requestReset {
  self.view.text = value;
  if (requestReset) {
    [self.view resignFirstResponder];
  }
}

LYNX_PROP_SETTER("placeholder", setPlaceholder, NSString*)
- (void)setPlaceholder:(NSString*)value requestReset:(BOOL)requestReset {
  self.view.placeholder = value;
}

LYNX_PROP_SETTER("maxlength", setMaxlength, NSInteger)
- (void)setMaxlength:(NSInteger)value requestReset:(BOOL)requestReset {
  _maxLength = value;
}

LYNX_PROP_SETTER("confirm-type", setConfirmType, NSString*)
- (void)setConfirmType:(NSString*)value requestReset:(BOOL)requestReset {
  NSDictionary* mapping = @{
    @"search" : @(UIReturnKeySearch),
    @"go" : @(UIReturnKeyGo),
    @"send" : @(UIReturnKeySend),
    @"next" : @(UIReturnKeyNext),
    @"done" : @(UIReturnKeyDone),
  };
  NSNumber* key = mapping[value.lowercaseString];
  self.view.returnKeyType = key ? (UIReturnKeyType)key.integerValue : UIReturnKeyDefault;
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
