class ApiConfig {
  static const bool isProd = true;

  static String get baseUrl {
    if (isProd) {
      return "https://voxarena-server.onrender.com";
    } else {
      return "http://192.168.1.26:8090";
    }
  }
}
