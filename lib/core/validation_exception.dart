/// 规则层只携带稳定错误代码和参数，展示层按当前应用语言生成文案。
class ValidationException extends FormatException {
  const ValidationException(this.code, [this.arguments = const {}])
    : super(code);

  final String code;
  final Map<String, Object> arguments;
}
