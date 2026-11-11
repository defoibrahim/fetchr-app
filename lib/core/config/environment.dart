enum Environment {
  prod('prod', 'https://jsonplaceholder.typicode.com/', 'Fetchr');

  const Environment(this.flavorName, this.baseUrl, this.appName);

  final String flavorName;
  final String baseUrl;
  final String appName;

  static Environment get current => prod;

  bool get isProd => this == prod;
}
