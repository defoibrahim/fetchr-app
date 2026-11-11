abstract final class AppRoutes {
  static const home = '/home';
  static const downloads = '/downloads';
  static const library = '/library';
  static const settings = '/settings';
  static const player = '/player';
  static const playlist = '/playlist';
  static const gallery = '/gallery';

  static String playerLocation({required String uri, required String title}) =>
      Uri(
        path: player,
        queryParameters: {'uri': uri, 'title': title},
      ).toString();
}
