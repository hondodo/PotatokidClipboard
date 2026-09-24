class SearchProviderModel {
  final String id;
  final String name;
  final String url;
  final String icon;
  final String tail;

  SearchProviderModel(
      {required this.id,
      required this.name,
      required this.url,
      required this.icon,
      this.tail = ''});
}
