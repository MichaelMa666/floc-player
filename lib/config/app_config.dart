class AppConfig {
  const AppConfig._();

  // 主用域名；其它作为备用，按顺序故障切换。
  static const String apiBaseUrl = 'https://api.fb168168.com';
  static const List<String> apiBaseUrls = [
    apiBaseUrl,
    'https://api.iqiu888.com',
    'https://api.qhskq888.com',
    'https://api.ldty688.com',
    'https://api.ttzb888.com',
    'https://api.sq518.com',
  ];

  static const String defaultAccount = '13866668888';
  static const String loginChannel = 'phone';
  static const String defaultCode = '7202';

  // 接口必需的业务/设备头。服务端据此决定返回哪些字段（缺失会导致 hot_live 等为空）。
  // 暂时硬编码设备 id，后续可改为启动时生成并持久化。
  static const Map<String, String> defaultHeaders = {
    'Origin': 'https://fb168168.com',
    'Referer': 'https://fb168168.com/',
    'x-platform': 'H5',
    'x-device-id': '29d6fc5617dcdffcc0395b5a9efc15da',
    'x-brand': '',
    'x-channel': '',
  };
}
